const std = @import("std");
const bdf = @import("bdf.zig");

const Io = std.Io;
const Dir = Io.Dir;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator: std.mem.Allocator = init.arena.allocator();

    const data = try Dir.readFileAlloc(.cwd(), io, "resources/zpix.bdf", allocator, .unlimited);
    const font = try bdf.load(data, allocator);

    std.debug.print("Loaded {d} glyphs, height={d}\n", .{ font.count, font.font_height });

    // 仙劍奇俠傳: U+4ED9 U+528D U+5947 U+4FE0 U+50B3
    const title = [_]u32{ 0x4ED9, 0x528D, 0x5947, 0x4FE0, 0x50B3 };

    for (title) |cp| {
        printGlyph(&font, cp);
        std.debug.print("\n", .{});
    }
}

fn printGlyph(font: *const bdf.BdfFont, codepoint: u32) void {
    const glyph = font.lookup(codepoint) orelse {
        std.debug.print("[missing U+{X:0>4}]\n", .{codepoint});
        return;
    };

    const w: usize = glyph.bbx_w;
    for (0..glyph.height) |row| {
        const hi = glyph.data[row * 2];
        const lo = glyph.data[row * 2 + 1];
        const word: u16 = (@as(u16, hi) << 8) | @as(u16, lo);

        for (0..w) |col| {
            if (word & (@as(u16, 1) << @intCast(15 - col)) != 0) {
                std.debug.print("##", .{});
            } else {
                std.debug.print("  ", .{});
            }
        }
        std.debug.print("\n", .{});
    }
}
