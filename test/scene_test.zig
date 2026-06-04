const std = @import("std");
const palcommon = @import("palcommon.zig");
const palette = @import("palette.zig");
const map_mod = @import("map.zig");
const scene_mod = @import("scene.zig");
const text = @import("text.zig");
const game_context = @import("game_context.zig");
const zigimg = @import("zigimg");

comptime {
    _ = text;
}

const MkfFile = palcommon.MkfFile;
const Io = std.Io;
const Dir = Io.Dir;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator: std.mem.Allocator = init.arena.allocator();

    const map_data = try Dir.readFileAlloc(.cwd(), io, "resources/pal/MAP.MKF", allocator, .unlimited);
    const gop_data = try Dir.readFileAlloc(.cwd(), io, "resources/pal/GOP.MKF", allocator, .unlimited);
    const pat_data = try Dir.readFileAlloc(.cwd(), io, "resources/pal/PAT.MKF", allocator, .unlimited);
    const sss_data = try Dir.readFileAlloc(.cwd(), io, "resources/pal/SSS.MKF", allocator, .unlimited);
    const data_data = try Dir.readFileAlloc(.cwd(), io, "resources/pal/DATA.MKF", allocator, .unlimited);

    palette.init(pat_data);
    const pal = palette.get(0, false) orelse return error.PaletteNotFound;

    const map_mkf = MkfFile.fromMemory(map_data);
    const gop_mkf = MkfFile.fromMemory(gop_data);

    // Initialize game context to get scene info
    var globals = game_context.GlobalVars{};
    globals.init(sss_data, data_data);
    try globals.initGameData(allocator);
    try globals.loadDefaultGame();

    // Create scene and load the first scene's map
    var scene = scene_mod.Scene.init(allocator);
    defer scene.deinit();

    scene.setLoadFlags(.{ .scene = true });
    scene.loadResources(&globals, map_mkf, gop_mkf, map_mkf); // pass map_mkf as placeholder for mgo

    const pal_map = scene.getCurrentMap() orelse {
        std.debug.print("[scene_test] failed to load map\n", .{});
        return;
    };

    // Render the full map
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
    map_mod.blitToSurface(pal_map, &surface, src_rect, 0);
    map_mod.blitToSurface(pal_map, &surface, src_rect, 1);

    // Convert to RGB and save
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

    const out_file = try Dir.createFile(.cwd(), io, "scene_output.png", .{});
    defer out_file.close(io);
    var write_buf: [4096]u8 = undefined;
    try image.writeToFile(allocator, io, out_file, &write_buf, .{ .png = .{} });

    std.debug.print("Written scene_output.png (scene {d}, map {d}, {d}x{d})\n", .{
        globals.num_scene,
        globals.g.scenes[@as(usize, globals.num_scene) -| 1].map_num,
        full_w,
        full_h,
    });
}
