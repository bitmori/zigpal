const std = @import("std");
const font = @import("font.zig");

const Io = std.Io;
const Dir = Io.Dir;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator: std.mem.Allocator = init.arena.allocator();

    const wor16_asc = Dir.readFileAlloc(.cwd(), io, "resources/pal/WOR16.ASC", allocator, .unlimited) catch null;
    const wor16_fon = Dir.readFileAlloc(.cwd(), io, "resources/pal/WOR16.FON", allocator, .unlimited) catch null;
    font.init(wor16_asc, wor16_fon);

    // 仙劍奇俠傳 in BIG5
    const big5_codes = [_]u16{ 0xA550, 0xBC43, 0xA95F, 0xAB4C, 0xB6C7 };

    for (big5_codes) |code| {
        printBig5Glyph(code);
        std.debug.print("\n", .{});
    }
}

fn printBig5Glyph(code: u16) void {
    const glyph = font.lookupBig5(code) orelse {
        std.debug.print("[missing: {x:0>4}]\n", .{code});
        return;
    };

    for (0..15) |row| {
        // Left 8 pixels
        for (0..8) |col| {
            if (glyph[row * 2] & (@as(u8, 1) << @intCast(7 - col)) != 0) {
                std.debug.print("##", .{});
            } else {
                std.debug.print("  ", .{});
            }
        }
        // Right 8 pixels
        for (0..8) |col| {
            if (glyph[row * 2 + 1] & (@as(u8, 1) << @intCast(7 - col)) != 0) {
                std.debug.print("##", .{});
            } else {
                std.debug.print("  ", .{});
            }
        }
        std.debug.print("\n", .{});
    }
}
