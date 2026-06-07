//! 外典 — JSON-driven cheat menu.
//!
//! Loads system/pal/zigpal_hacks.json once on first open. Each entry has a
//! `name` (UTF-8, rendered with zpix BDF), an optional `desc` (UTF-8 multiline,
//! shown on the right pane), and a `code` array of DSL lines.
//!
//! DSL is whitespace-tokenised, one statement per line. MVP supports a single
//! command:
//!
//!   ADD_CASH <int>     # add to gpg.cash, clamped to u32 range
//!
//! The selection UI mirrors magic_menu.magicSelectionMenuUpdate so the hack
//! menu inherits the same chrome (cash box on the left, grid in the centre,
//! description on the right). Confirm runs every line in `code` sequentially
//! via runCode(); errors append to system/pal/zigpal_hacks.log and don't
//! interrupt the rest of the script.

const std = @import("std");
const global = @import("global.zig");
const palcommon = @import("palcommon.zig");
const video = @import("video.zig");
const ui = @import("ui.zig");
const text = @import("text.zig");
const input = @import("input.zig");
const util = @import("util.zig");
const objectdesc = @import("objectdesc.zig");
const bdf = @import("bdf.zig");

const SPRITENUM_CURSOR: i32 = 69;
const CASH_LABEL: u16 = 21;

pub const Hack = struct {
    name: []const u8, // UTF-8
    desc: []const u8, // UTF-8 (may be empty)
    code: [][]const u8,
};

var hacks: []Hack = &.{};
var loaded: bool = false;

// Owned strings/arrays from std.json.parseFromSlice — kept alive for the
// lifetime of the core (we never free; the JSON is tiny and the user re-runs
// the core to pick up edits anyway).
var arena_state: ?std.heap.ArenaAllocator = null;

// --- Loader -------------------------------------------------------------

fn loadFromDisk() void {
    if (loaded) return;
    loaded = true;

    const sys_dir = @import("libretro_core.zig").system_dir orelse return;
    var path_buf: [4096]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/pal/zigpal_hacks.json\x00", .{sys_dir}) catch return;
    const path_z: [*:0]const u8 = path_buf[0 .. path.len - 1 :0];
    const buf = util.readFileFully(path_z, global.allocator) orelse return;
    defer global.allocator.free(buf);

    arena_state = std.heap.ArenaAllocator.init(global.allocator);
    const arena = arena_state.?.allocator();

    // Parse as a generic JSON value first, then transcribe into our struct
    // so we keep arena ownership of every byte. std.json.parseFromSlice into
    // []Hack would need a different lifetime for the source bytes.
    const parsed = std.json.parseFromSlice(std.json.Value, arena, buf, .{}) catch |err| {
        std.log.err("hack: parse failed: {}", .{err});
        return;
    };

    if (parsed.value != .array) {
        std.log.err("hack: top-level JSON must be an array", .{});
        return;
    }

    const items = parsed.value.array.items;
    var out = arena.alloc(Hack, items.len) catch return;
    var n_out: usize = 0;

    for (items) |item| {
        if (item != .object) continue;
        const obj = item.object;

        const name_v = obj.get("name") orelse continue;
        if (name_v != .string) continue;

        const desc_v = obj.get("desc");
        const desc_str: []const u8 = if (desc_v) |d|
            (if (d == .string) d.string else "")
        else
            "";

        const code_v = obj.get("code") orelse continue;
        if (code_v != .array) continue;

        var code_lines = arena.alloc([]const u8, code_v.array.items.len) catch continue;
        var nl: usize = 0;
        for (code_v.array.items) |line_v| {
            if (line_v != .string) continue;
            code_lines[nl] = line_v.string;
            nl += 1;
        }
        code_lines = code_lines[0..nl];

        out[n_out] = .{
            .name = name_v.string,
            .desc = desc_str,
            .code = code_lines,
        };
        n_out += 1;
    }

    hacks = out[0..n_out];
}

pub fn count() usize {
    loadFromDisk();
    return hacks.len;
}

pub fn get(i: usize) ?*const Hack {
    if (i >= hacks.len) return null;
    return &hacks[i];
}

// --- DSL ----------------------------------------------------------------

fn logErr(comptime fmt: []const u8, args: anytype) void {
    std.log.err("hack: " ++ fmt, args);
}

fn nextToken(s: *[]const u8) ?[]const u8 {
    while (s.len > 0 and (s.*[0] == ' ' or s.*[0] == '\t')) s.* = s.*[1..];
    if (s.len == 0) return null;
    var end: usize = 0;
    while (end < s.len and s.*[end] != ' ' and s.*[end] != '\t') end += 1;
    const tok = s.*[0..end];
    s.* = s.*[end..];
    return tok;
}

fn parseI64(tok: []const u8) ?i64 {
    return std.fmt.parseInt(i64, tok, 0) catch null;
}

fn execLine(line: []const u8) void {
    var rest = line;
    const cmd = nextToken(&rest) orelse return;

    if (std.mem.eql(u8, cmd, "ADD_CASH")) {
        const v_tok = nextToken(&rest) orelse {
            logErr("ADD_CASH needs an integer argument", .{});
            return;
        };
        const v = parseI64(v_tok) orelse {
            logErr("ADD_CASH: bad integer '{s}'", .{v_tok});
            return;
        };
        const cur: i64 = @intCast(global.gpg.cash);
        const new = cur + v;
        const clamped: u32 = if (new < 0) 0 else if (new > 0xFFFFFFFF) 0xFFFFFFFF else @intCast(new);
        global.gpg.cash = clamped;
    } else {
        logErr("unknown command: '{s}'", .{cmd});
    }
}

pub fn runCode(code: []const []const u8) void {
    for (code) |line| execLine(line);
}

// --- Menu UI (mirrors magicmenu.magicSelectionMenuUpdate) ---------------

const ITEMS_PER_LINE: i32 = 3;
const LINES_PER_PAGE: i32 = 5;
const ITEM_TEXT_WIDTH: i32 = 87; // matches magic menu word_length=10
const BOX_X: i16 = 10;
const BOX_Y: i16 = 42;
const BOX_W: i32 = 16;
const ITEM_X0: i32 = 35;
const ITEM_Y0: i32 = 54;
const ROW_H: i32 = 18;

var g_current: i32 = 0;

// Render a UTF-8 label with zpix at the standard menu-item position.
fn drawLabel(s: []const u8, px: i32, py: i32, color: u8) void {
    _ = objectdesc.drawAt(s, px, py, color);
}

/// One frame of the hack-selection menu. Returns the index of the chosen
/// hack, -1 if the user cancelled, or -2 to signal "still showing".
pub fn updateOnce() i32 {
    const k_press = input.state.key_press;
    const n: i32 = @intCast(hacks.len);

    var delta: i32 = 0;
    if ((k_press & input.KEY_UP) != 0) {
        delta = -ITEMS_PER_LINE;
    } else if ((k_press & input.KEY_DOWN) != 0) {
        delta = ITEMS_PER_LINE;
    } else if ((k_press & input.KEY_LEFT) != 0) {
        delta = -1;
    } else if ((k_press & input.KEY_RIGHT) != 0) {
        delta = 1;
    } else if ((k_press & input.KEY_PGUP) != 0) {
        delta = -(ITEMS_PER_LINE * LINES_PER_PAGE);
    } else if ((k_press & input.KEY_PGDN) != 0) {
        delta = ITEMS_PER_LINE * LINES_PER_PAGE;
    } else if ((k_press & input.KEY_MENU) != 0) {
        return -1;
    }

    if (n > 0) {
        if (g_current + delta < 0) g_current = 0
        else if (g_current + delta >= n) g_current = n - 1
        else g_current += delta;
    }

    _ = ui.createBoxWithShadow(global.palXY(BOX_X, BOX_Y), LINES_PER_PAGE - 1, BOX_W, 1, false, 0);

    // Cash box (top-left), same as magic menu has-desc layout.
    _ = ui.createSingleLineBox(global.palXY(0, 0), 5, false);
    text.drawText(text.getWord(CASH_LABEL), global.palXY(10, 10), 0, false, false);
    ui.drawNumber(global.gpg.cash, 6, global.palXY(49, 14), .yellow, .right);

    // Grid of hack names. Use the magic menu's paging maths (start so the
    // current item is roughly mid-page).
    const page_offset: i32 = @divTrunc(LINES_PER_PAGE, 2);
    var i: i32 = @divTrunc(g_current, ITEMS_PER_LINE) * ITEMS_PER_LINE - ITEMS_PER_LINE * page_offset;
    if (i < 0) i = 0;

    var j: i32 = 0;
    outer: while (j < LINES_PER_PAGE) : (j += 1) {
        var k: i32 = 0;
        while (k < ITEMS_PER_LINE) : (k += 1) {
            if (i >= n) break :outer;
            const color: u8 = if (i == g_current) ui.menuItemColorSelected() else ui.MENUITEM_COLOR;
            const px: i32 = ITEM_X0 + k * ITEM_TEXT_WIDTH;
            const py: i32 = ITEM_Y0 + j * ROW_H;
            drawLabel(hacks[@intCast(i)].name, px, py, color);

            if (i == g_current) {
                if (palcommon.spriteGetFrame(ui.sprite_ui, SPRITENUM_CURSOR)) |bmp| {
                    _ = palcommon.rleBlitToSurface(
                        bmp,
                        &video.screen,
                        global.palXY(@intCast(px + 25), @intCast(py + 10)),
                    );
                }
            }
            i += 1;
        }
    }

    // Description in the same spot magicmenu uses (magicmenu.zig:209) —
    // top-centre area, just left of the cash box on the right.
    if (n > 0) {
        const desc = hacks[@intCast(g_current)].desc;
        if (desc.len > 0) {
            _ = objectdesc.drawAt(desc, 102, 3, 0x3C);
        }
    }

    if (n > 0 and (k_press & input.KEY_SEARCH) != 0) {
        return g_current;
    }
    return -2;
}

/// Top-level: open the hack menu, block until the user picks or cancels,
/// and run the chosen hack's code. Caller is responsible for backup/restore
/// of the framebuffer.
pub fn runMenu() void {
    loadFromDisk();
    if (hacks.len == 0) {
        // Nothing to show.
        return;
    }
    g_current = 0;

    // Snapshot the framebuffer once so each frame can restore it before
    // redrawing — otherwise the BDF text overlays on top of the previous
    // frame's text and the description area smears. magicmenu does the
    // same thing via scene.makeScene + restoreScreen (magicmenu.zig:392).
    video.backupScreen();
    defer {
        video.restoreScreen();
        video.updateScreen(null);
    }

    input.clearKeyState();
    var dw_time = util.getTicks();

    while (true) {
        if (util.shouldQuit()) return;

        // Wipe to the saved background each frame.
        video.restoreScreen();

        const r = updateOnce();
        input.clearKeyState();

        if (r == -1) return;
        if (r >= 0) {
            runCode(hacks[@intCast(r)].code);
            return;
        }

        video.updateScreen(null);

        while (util.getTicks() < dw_time) {
            input.processEvent();
            if (input.state.key_press != 0) break;
            util.delay(5);
            if (util.shouldQuit()) return;
        }
        dw_time = util.getTicks() + global.FRAME_TIME;
    }
}
