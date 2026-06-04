const std = @import("std");
const zigimg = @import("zigimg");
const palcommon = @import("palcommon.zig");
const palette = @import("palette.zig");
const yj1 = @import("yj1.zig");

const MkfFile = palcommon.MkfFile;
const Io = std.Io;
const Dir = Io.Dir;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator: std.mem.Allocator = init.arena.allocator();

    const chunk_num: u32 = 60;
    const palette_num: i32 = 0;

    const fbp_data = try Dir.readFileAlloc(.cwd(), io, "resources/pal/FBP.MKF", allocator, .unlimited);
    const pat_data = try Dir.readFileAlloc(.cwd(), io, "resources/pal/PAT.MKF", allocator, .unlimited);

    const fbp_mkf = MkfFile.fromMemory(fbp_data);

    // Initialize palette module
    palette.init(pat_data);

    // Read compressed FBP chunk and decompress
    const compressed = try fbp_mkf.getChunkData(chunk_num);
    var pixels: [320 * 200]u8 = undefined;
    _ = try yj1.decompress(compressed, &pixels);

    // Get palette
    const pal = palette.get(palette_num, false) orelse return error.PaletteNotFound;

    // Create RGB image using zigimg
    var image = try zigimg.Image.create(allocator, 320, 200, .rgb24);
    defer image.deinit(allocator);

    for (0..320 * 200) |i| {
        const color_idx = pixels[i];
        image.pixels.rgb24[i] = .{
            .r = pal[color_idx].r,
            .g = pal[color_idx].g,
            .b = pal[color_idx].b,
        };
    }

    // Save as PNG
    const out_file = try Dir.createFile(.cwd(), io, "output.png", .{});
    defer out_file.close(io);
    var write_buf: [4096]u8 = undefined;
    try image.writeToFile(allocator, io, out_file, &write_buf, .{ .png = .{} });

    std.debug.print("Written output.png (chunk {d}, palette {d})\n", .{ chunk_num, palette_num });
}
