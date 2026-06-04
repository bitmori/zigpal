const std = @import("std");
const zigimg = @import("zigimg");
const palcommon = @import("palcommon.zig");
const palette = @import("palette.zig");
const bdf = @import("bdf.zig");

const Io = std.Io;
const Dir = Io.Dir;

const cell_w = 48;
const cell_h = 24;
const cols = 16;
const rows = 16;
const img_w = cols * cell_w;
const img_h = rows * cell_h;

fn drawChar(pixels: []u8, img_width: u32, codepoint: u32, x: i32, y: i32, color: zigimg.color.Rgb24, font: *const bdf.BdfFont) i32 {
    const glyph = font.lookup(codepoint) orelse return 0;
    const w: usize = glyph.bbx_w;

    for (0..glyph.height) |row| {
        const dest_y = y + @as(i32, @intCast(row));
        if (dest_y < 0 or dest_y >= @as(i32, @intCast(img_h))) continue;
        const hi = glyph.data[row * 2];
        const lo = glyph.data[row * 2 + 1];
        const word: u16 = (@as(u16, hi) << 8) | @as(u16, lo);

        for (0..w) |col| {
            const dest_x = x + @as(i32, @intCast(col));
            if (dest_x < 0 or dest_x >= @as(i32, @intCast(img_width))) continue;
            if (word & (@as(u16, 1) << @intCast(15 - col)) != 0) {
                const idx: usize = @intCast(@as(u32, @intCast(dest_y)) * img_width + @as(u32, @intCast(dest_x)));
                pixels[idx * 3] = color.r;
                pixels[idx * 3 + 1] = color.g;
                pixels[idx * 3 + 2] = color.b;
            }
        }
    }
    return glyph.dwidth;
}

fn drawHexString(pixels: []u8, img_width: u32, hex_val: u8, x: i32, y: i32, color: zigimg.color.Rgb24, font: *const bdf.BdfFont) void {
    const hex_chars = "0123456789ABCDEF";
    const hi: u32 = hex_chars[hex_val >> 4];
    const lo: u32 = hex_chars[hex_val & 0x0F];

    var cur_x = x;
    cur_x += drawChar(pixels, img_width, hi, cur_x, y, color, font);
    _ = drawChar(pixels, img_width, lo, cur_x, y, color, font);
}

fn contrastColor(r: u8, g: u8, b: u8) zigimg.color.Rgb24 {
    const luma: u32 = @as(u32, r) * 299 + @as(u32, g) * 587 + @as(u32, b) * 114;
    if (luma > 128000) {
        return .{ .r = 0, .g = 0, .b = 0 };
    } else {
        return .{ .r = 255, .g = 255, .b = 255 };
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator: std.mem.Allocator = init.arena.allocator();

    const pat_data = try Dir.readFileAlloc(.cwd(), io, "resources/pal/PAT.MKF", allocator, .unlimited);
    const bdf_data = try Dir.readFileAlloc(.cwd(), io, "resources/zpix.bdf", allocator, .unlimited);

    palette.init(pat_data);
    const pal = palette.get(0, false) orelse return error.PaletteNotFound;
    const font = try bdf.load(bdf_data, allocator);

    var image = try zigimg.Image.create(allocator, img_w, img_h, .rgb24);
    defer image.deinit(allocator);

    // Fill cells with palette colors
    for (0..256) |i| {
        const col: u32 = @intCast(i % cols);
        const row: u32 = @intCast(i / cols);
        const color = pal[i];

        const x0 = col * cell_w;
        const y0 = row * cell_h;

        for (y0..y0 + cell_h) |py| {
            for (x0..x0 + cell_w) |px| {
                image.pixels.rgb24[py * img_w + px] = .{
                    .r = color.r,
                    .g = color.g,
                    .b = color.b,
                };
            }
        }

        // Draw hex label centered in cell
        const text_color = contrastColor(color.r, color.g, color.b);
        const tx: i32 = @intCast(x0 + (cell_w - 12) / 2);
        const ty: i32 = @intCast(y0 + (cell_h - 12) / 2);

        const raw_pixels: [*]u8 = @ptrCast(image.pixels.rgb24.ptr);
        const pixel_slice = raw_pixels[0 .. img_w * img_h * 3];
        drawHexString(pixel_slice, img_w, @intCast(i), tx, ty, text_color, &font);
    }

    const out_file = try Dir.createFile(.cwd(), io, "palette_output.png", .{});
    defer out_file.close(io);
    var write_buf: [4096]u8 = undefined;
    try image.writeToFile(allocator, io, out_file, &write_buf, .{ .png = .{} });

    std.debug.print("Written palette_output.png ({d}x{d}, 256 colors)\n", .{ img_w, img_h });
}
