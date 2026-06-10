//! 外典 — JSON-driven cheat menu.
//!
//! Loads system/pal/zigpal_hacks.json once on first open. Each entry has a
//! `name` (UTF-8, rendered with zpix BDF), an optional `desc` (UTF-8 multiline,
//! shown on the right pane), and a `code` array of DSL lines.
//!
//! DSL is whitespace-tokenised, one statement per line:
//!
//!   ADD_CASH <int>                          # add to gpg.cash, clamped to u32
//!   CHANGE_MAGIC_DATA <id> <off> <val>      # poke Magic[id] field at u16 offset
//!   CHANGE_OBJ <obj_id> <off> <val>         # poke Object[obj_id].data[off]
//!   EDIT_SCRIPT <entry> <op> <a1> <a2> <a3> # rewrite script_entries[entry]
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

// --- Command implementations ---

fn cmdAddCash(rest: *[]const u8) void {
    const v_tok = nextToken(rest) orelse {
        logErr("ADD_CASH needs an integer argument", .{});
        return;
    };
    const v = parseI64(v_tok) orelse {
        logErr("ADD_CASH: bad integer '{s}'", .{v_tok});
        return;
    };
    const cur: i64 = @intCast(global.gpg.cash);
    const new = cur + v;
    global.gpg.cash = if (new < 0) 0 else if (new > 0xFFFFFFFF) 0xFFFFFFFF else @intCast(new);
}

fn cmdChangeMagicData(rest: *[]const u8) void {
    const id_tok = nextToken(rest) orelse {
        logErr("CHANGE_MAGIC_DATA needs <id> <offset> <value>", .{});
        return;
    };
    const off_tok = nextToken(rest) orelse {
        logErr("CHANGE_MAGIC_DATA needs <id> <offset> <value>", .{});
        return;
    };
    const val_tok = nextToken(rest) orelse {
        logErr("CHANGE_MAGIC_DATA needs <id> <offset> <value>", .{});
        return;
    };
    const id = parseI64(id_tok) orelse {
        logErr("CHANGE_MAGIC_DATA: bad id '{s}'", .{id_tok});
        return;
    };
    const off = parseI64(off_tok) orelse {
        logErr("CHANGE_MAGIC_DATA: bad offset '{s}'", .{off_tok});
        return;
    };
    const val = parseI64(val_tok) orelse {
        logErr("CHANGE_MAGIC_DATA: bad value '{s}'", .{val_tok});
        return;
    };
    const n_magics: i64 = @intCast(global.gpg.g.magics.len);
    if (id < 0 or id >= n_magics) {
        logErr("CHANGE_MAGIC_DATA: id {} out of range [0,{})", .{ id, n_magics });
        return;
    }
    const n_fields: usize = @sizeOf(global.Magic) / 2;
    if (off < 0 or off >= n_fields) {
        logErr("CHANGE_MAGIC_DATA: offset {} out of range [0,{})", .{ off, n_fields });
        return;
    }
    if (val < std.math.minInt(i16) or val > std.math.maxInt(u16)) {
        logErr("CHANGE_MAGIC_DATA: value {} doesn't fit in 16 bits", .{val});
        return;
    }
    const raw: *align(1) [n_fields]u16 = @ptrCast(&global.gpg.g.magics[@intCast(id)]);
    raw[@intCast(off)] = @truncate(@as(u64, @bitCast(val)));
}

fn cmdChangeObj(rest: *[]const u8) void {
    const oid_tok = nextToken(rest) orelse {
        logErr("CHANGE_OBJ needs <obj_id> <offset> <value>", .{});
        return;
    };
    const off_tok = nextToken(rest) orelse {
        logErr("CHANGE_OBJ needs <obj_id> <offset> <value>", .{});
        return;
    };
    const val_tok = nextToken(rest) orelse {
        logErr("CHANGE_OBJ needs <obj_id> <offset> <value>", .{});
        return;
    };
    const oid = parseI64(oid_tok) orelse {
        logErr("CHANGE_OBJ: bad obj_id '{s}'", .{oid_tok});
        return;
    };
    const off = parseI64(off_tok) orelse {
        logErr("CHANGE_OBJ: bad offset '{s}'", .{off_tok});
        return;
    };
    const val = parseI64(val_tok) orelse {
        logErr("CHANGE_OBJ: bad value '{s}'", .{val_tok});
        return;
    };
    if (oid < 0 or oid >= global.MAX_OBJECTS) {
        logErr("CHANGE_OBJ: obj_id {} out of range [0,{})", .{ oid, global.MAX_OBJECTS });
        return;
    }
    if (off < 0 or off >= 6) {
        logErr("CHANGE_OBJ: offset {} out of range [0,6)", .{off});
        return;
    }
    if (val < std.math.minInt(i16) or val > std.math.maxInt(u16)) {
        logErr("CHANGE_OBJ: value {} doesn't fit in 16 bits", .{val});
        return;
    }
    global.gpg.g.objects[@intCast(oid)].data[@intCast(off)] = @truncate(@as(u64, @bitCast(val)));
}

fn cmdEditScript(rest: *[]const u8) void {
    const entry_tok = nextToken(rest) orelse {
        logErr("EDIT_SCRIPT needs <entry> <op> <a1> <a2> <a3>", .{});
        return;
    };
    const op_tok = nextToken(rest) orelse {
        logErr("EDIT_SCRIPT needs <entry> <op> <a1> <a2> <a3>", .{});
        return;
    };
    const a1_tok = nextToken(rest) orelse {
        logErr("EDIT_SCRIPT needs <entry> <op> <a1> <a2> <a3>", .{});
        return;
    };
    const a2_tok = nextToken(rest) orelse {
        logErr("EDIT_SCRIPT needs <entry> <op> <a1> <a2> <a3>", .{});
        return;
    };
    const a3_tok = nextToken(rest) orelse {
        logErr("EDIT_SCRIPT needs <entry> <op> <a1> <a2> <a3>", .{});
        return;
    };
    const entry = parseI64(entry_tok) orelse {
        logErr("EDIT_SCRIPT: bad entry '{s}'", .{entry_tok});
        return;
    };
    const op = parseI64(op_tok) orelse {
        logErr("EDIT_SCRIPT: bad op '{s}'", .{op_tok});
        return;
    };
    const a1 = parseI64(a1_tok) orelse {
        logErr("EDIT_SCRIPT: bad arg1 '{s}'", .{a1_tok});
        return;
    };
    const a2 = parseI64(a2_tok) orelse {
        logErr("EDIT_SCRIPT: bad arg2 '{s}'", .{a2_tok});
        return;
    };
    const a3 = parseI64(a3_tok) orelse {
        logErr("EDIT_SCRIPT: bad arg3 '{s}'", .{a3_tok});
        return;
    };
    const n_entries: i64 = @intCast(global.gpg.g.script_entries.len);
    if (entry < 0 or entry >= n_entries) {
        logErr("EDIT_SCRIPT: entry {} out of range [0,{})", .{ entry, n_entries });
        return;
    }
    const raws = [_]i64{ op, a1, a2, a3 };
    for (raws) |w| {
        if (w < std.math.minInt(i16) or w > std.math.maxInt(u16)) {
            logErr("EDIT_SCRIPT: word {} doesn't fit in 16 bits", .{w});
            return;
        }
    }
    const e = &global.gpg.g.script_entries[@intCast(entry)];
    e.operation = @truncate(@as(u64, @bitCast(op)));
    e.operand[0] = @truncate(@as(u64, @bitCast(a1)));
    e.operand[1] = @truncate(@as(u64, @bitCast(a2)));
    e.operand[2] = @truncate(@as(u64, @bitCast(a3)));
}

// --- Dispatcher ---

fn execLine(line: []const u8) void {
    var rest = line;
    const cmd = nextToken(&rest) orelse return;

    if (std.mem.eql(u8, cmd, "ADD_CASH")) {
        cmdAddCash(&rest);
    } else if (std.mem.eql(u8, cmd, "CHANGE_MAGIC_DATA")) {
        cmdChangeMagicData(&rest);
    } else if (std.mem.eql(u8, cmd, "CHANGE_OBJ")) {
        cmdChangeObj(&rest);
    } else if (std.mem.eql(u8, cmd, "EDIT_SCRIPT")) {
        cmdEditScript(&rest);
    } else {
        logErr("unknown command: '{s}'", .{cmd});
    }
}

pub fn runCode(code: []const []const u8) void {
    for (code) |line| execLine(line);
}

// --- Auto-hacks: run once after every save/new-game load ---

var auto_hacks_loaded: bool = false;
var auto_hacks_code: [][]const u8 = &.{};

pub fn runAutoHacks() void {
    if (!auto_hacks_loaded) {
        auto_hacks_loaded = true;
        loadAutoHacks();
    }
    for (auto_hacks_code) |line| execLine(line);
}

fn loadAutoHacks() void {
    const sys_dir = @import("libretro_core.zig").system_dir orelse return;
    var path_buf: [4096]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/pal/auto_hacks.json\x00", .{sys_dir}) catch return;
    const path_z: [*:0]const u8 = path_buf[0 .. path.len - 1 :0];
    const buf = util.readFileFully(path_z, global.allocator) orelse return;
    defer global.allocator.free(buf);

    if (arena_state == null) {
        arena_state = std.heap.ArenaAllocator.init(global.allocator);
    }
    const arena = arena_state.?.allocator();

    const parsed = std.json.parseFromSlice(std.json.Value, arena, buf, .{}) catch |err| {
        std.log.err("auto_hacks: parse failed: {}", .{err});
        return;
    };

    if (parsed.value != .array) {
        std.log.err("auto_hacks: top-level JSON must be an array of strings", .{});
        return;
    }

    const items = parsed.value.array.items;
    var lines = arena.alloc([]const u8, items.len) catch return;
    var n: usize = 0;
    for (items) |item| {
        if (item == .string) {
            lines[n] = item.string;
            n += 1;
        }
    }
    auto_hacks_code = lines[0..n];
    std.log.info("auto_hacks: loaded {d} commands", .{n});
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

    // Grid of hack names.
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

    // Description panel.
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
/// and run the chosen hack's code.
pub fn runMenu() void {
    loadFromDisk();
    if (hacks.len == 0) return;
    g_current = 0;

    video.backupScreen();
    defer {
        video.restoreScreen();
        video.updateScreen(null);
    }

    input.clearKeyState();
    var dw_time = util.getTicks();

    while (true) {
        if (util.shouldQuit()) return;

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
