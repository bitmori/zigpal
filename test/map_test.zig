const std = @import("std");
const zigimg = @import("zigimg");
const palcommon = @import("palcommon.zig");
const palette = @import("palette.zig");
const map_mod = @import("map.zig");

const MkfFile = palcommon.MkfFile;
const Io = std.Io;
const Dir = Io.Dir;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator: std.mem.Allocator = init.arena.allocator();

    const map_num: u32 = 2;
    const palette_num: i32 = 0;

    const map_data = try Dir.readFileAlloc(.cwd(), io, "resources/pal/MAP.MKF", allocator, .unlimited);
    const gop_data = try Dir.readFileAlloc(.cwd(), io, "resources/pal/GOP.MKF", allocator, .unlimited);
    const pat_data = try Dir.readFileAlloc(.cwd(), io, "resources/pal/PAT.MKF", allocator, .unlimited);

    const map_mkf = MkfFile.fromMemory(map_data);
    const gop_mkf = MkfFile.fromMemory(gop_data);

    palette.init(pat_data);
    const pal = palette.get(palette_num, false) orelse return error.PaletteNotFound;

    const pal_map = try map_mod.loadMap(map_num, map_mkf, gop_mkf, allocator);

    // Full map pixel dimensions:
    // x: 64 tiles * 32px + 16 (h=1 offset) = 2064, plus margin
    // y: 128 rows * 16px + 8 (h=1 offset) = 2056, plus margin
    const full_w: i32 = 64 * 32 + 32;
    const full_h: i32 = 128 * 16 + 16;

    const pixel_count: usize = @intCast(full_w * full_h);
    const pixels = try allocator.alloc(u8, pixel_count);
    @memset(pixels, 0);

    var surface = palcommon.Surface{
        .w = full_w,
        .h = full_h,
        .pitch = full_w,
        .pixels = pixels,
    };

    const src_rect = map_mod.Rect{ .x = 0, .y = 0, .w = full_w, .h = full_h };

    map_mod.blitToSurface(&pal_map, &surface, src_rect, 0);
    map_mod.blitToSurface(&pal_map, &surface, src_rect, 1);

    // Convert indexed pixels to RGB using palette
    const img_w: u32 = @intCast(full_w);
    const img_h: u32 = @intCast(full_h);
    var image = try zigimg.Image.create(allocator, img_w, img_h, .rgb24);
    defer image.deinit(allocator);

    for (0..pixel_count) |i| {
        const color_idx = pixels[i];
        image.pixels.rgb24[i] = .{
            .r = pal[color_idx].r,
            .g = pal[color_idx].g,
            .b = pal[color_idx].b,
        };
    }

    const out_file = try Dir.createFile(.cwd(), io, "map_output.png", .{});
    defer out_file.close(io);
    var write_buf: [4096]u8 = undefined;
    try image.writeToFile(allocator, io, out_file, &write_buf, .{ .png = .{} });

    std.debug.print("Written map_output.png (map {d}, palette {d}, {d}x{d})\n", .{ map_num, palette_num, full_w, full_h });
}
