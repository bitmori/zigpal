// PAL_LoadObjectDesc / PAL_GetObjectDesc — DOS-style object descriptions.
// SDLPAL reads a `desc.dat` BIG5 text file and parses `id=text` lines. We use
// a UTF-8 JSON file (`{"3d|M": "...", "3e|I": "...", ...}`) so we can render
// with the zpix font (Unicode-encoded) without any codepage conversion. `*`
// in the source maps to `\n`.
//
// Key format: "<hex_id>|<type>" where type is one of:
//   M = Magic (仙术)   I = Item (道具)   ? = Other / unknown
// The type tag drives the debug "灵汇" / "进宝" pickers.
//
// Usage:
//   const objectdesc = @import("objectdesc.zig");
//   try objectdesc.load();         // once at boot, locates desc.json in system/pal/
//   const lines = objectdesc.get(item_id) orelse "";
//   objectdesc.drawAt(lines, x, y, color);

const std = @import("std");
const global = @import("global.zig");
const palcommon = @import("palcommon.zig");
const video = @import("video.zig");
const bdf = @import("bdf.zig");

const util = @import("util.zig");

pub const ObjectType = enum(u8) { magic, item, other };

var entries: std.AutoHashMap(u16, []const u8) = undefined;
var types: std.AutoHashMap(u16, ObjectType) = undefined;
var entries_inited: bool = false;
// Owns the parsed JSON value tree; its arena keeps the string slices alive
// for the lifetime of the program.
var parsed: ?std.json.Parsed(std.json.Value) = null;
var loaded: bool = false;

var font: ?bdf.BdfFont = null;
var font_loaded: bool = false;

// Load `desc.json` from the libretro system directory. Idempotent: returns
// early if already loaded. Missing or malformed files are silently treated
// as empty so menu rendering still works without descriptions.
pub fn load() void {
    if (loaded) return;
    loaded = true;

    if (!entries_inited) {
        entries = std.AutoHashMap(u16, []const u8).init(global.allocator);
        types = std.AutoHashMap(u16, ObjectType).init(global.allocator);
        entries_inited = true;
    }

    const sys_dir = @import("libretro_core.zig").system_dir orelse return;

    var path_buf: [4096]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/pal/desc.json\x00", .{sys_dir}) catch return;
    const path_z: [*:0]const u8 = path_buf[0 .. path.len - 1 :0];

    const buf = util.readFileFully(path_z, global.allocator) orelse return;
    defer global.allocator.free(buf);

    var p = std.json.parseFromSlice(std.json.Value, global.allocator, buf, .{}) catch return;
    if (p.value != .object) {
        p.deinit();
        return;
    }

    var it = p.value.object.iterator();
    while (it.next()) |kv| {
        if (kv.value_ptr.* != .string) continue;
        const key = kv.key_ptr.*;
        // Split on '|'. Old format ("3d") still works → type = .other.
        const id_part = if (std.mem.indexOfScalar(u8, key, '|')) |bar| key[0..bar] else key;
        const type_part = if (std.mem.indexOfScalar(u8, key, '|')) |bar| key[bar + 1 ..] else "";
        const id = std.fmt.parseInt(u16, id_part, 16) catch continue;
        const t: ObjectType = if (type_part.len == 0) .other else switch (type_part[0]) {
            'M', 'm' => .magic,
            'I', 'i' => .item,
            else => .other,
        };
        entries.put(id, kv.value_ptr.string) catch continue;
        types.put(id, t) catch {};
    }

    parsed = p;
}

pub fn getType(id: u16) ?ObjectType {
    if (!entries_inited) return null;
    return types.get(id);
}

pub fn get(id: u16) ?[]const u8 {
    if (!entries_inited) return null;
    return entries.get(id);
}

// True if a desc.json was successfully loaded (even if it had zero entries).
// Used by menus that change layout based on whether descriptions are available
// (mirrors SDLPAL's `gpGlobals->lpObjectDesc != NULL` toggle).
pub fn hasDescTable() bool {
    if (!entries_inited) return false;
    return entries.count() > 0;
}

fn ensureFont() void {
    if (font_loaded) return;
    font_loaded = true;
    const sys_dir = @import("libretro_core.zig").system_dir orelse return;
    var path_buf: [4096]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/pal/zpix.bdf\x00", .{sys_dir}) catch return;
    const path_z: [*:0]const u8 = path_buf[0 .. path.len - 1 :0];
    const buf = util.readFileFully(path_z, global.allocator) orelse return;
    defer global.allocator.free(buf);

    const f = bdf.load(buf, global.allocator) catch return;
    font = f;
}

// Decode one UTF-8 codepoint at `text[i]`. Returns (codepoint, bytes_consumed).
// Malformed sequences are surfaced as '?' so a corrupt byte never aborts a draw.
pub fn decodeUtf8(text: []const u8, i: usize) struct { cp: u32, n: usize } {
    const n = std.unicode.utf8ByteSequenceLength(text[i]) catch return .{ .cp = '?', .n = 1 };
    if (i + n > text.len) return .{ .cp = '?', .n = 1 };
    const cp = std.unicode.utf8Decode(text[i .. i + n]) catch return .{ .cp = '?', .n = n };
    return .{ .cp = cp, .n = n };
}

// Render a multi-line UTF-8 string with zpix at (x, y), 12px line height.
// `\n` advances to the next line. Returns the y after the last line.
pub fn drawSingleCodepoint(cp: u32, x: i32, y: i32, color: u8) void {
    ensureFont();
    const f = if (font) |*p| p else return;
    _ = f.drawCodepoint(cp, &video.screen, x + 1, y + 1, 0);
    _ = f.drawCodepoint(cp, &video.screen, x, y, color);
}

pub fn drawAt(text: []const u8, x: i32, y: i32, color: u8) i32 {
    ensureFont();
    const f = if (font) |*p| p else return y;

    var cx = x;
    var cy = y;
    const line_h: i32 = @intCast(f.font_height);
    var i: usize = 0;
    while (i < text.len) {
        if (text[i] == '\n') {
            cx = x;
            cy += line_h;
            i += 1;
            continue;
        }
        const r = decodeUtf8(text, i);
        // Shadow for legibility on busy menu backgrounds.
        _ = f.drawCodepoint(r.cp, &video.screen, cx + 1, cy + 1, 0);
        cx += f.drawCodepoint(r.cp, &video.screen, cx, cy, color);
        i += r.n;
    }
    return cy + line_h;
}
