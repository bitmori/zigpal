// Copyright (c) 2009-2011, Wei Mingzhi <whistler_wmz@users.sf.net>.
// Copyright (c) 2011-2026, SDLPAL development team.
// All rights reserved.
//
// This file is part of SDLPAL.
//
// SDLPAL is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License, version 3
// as published by the Free Software Foundation.

const std = @import("std");
const palcommon = @import("palcommon.zig");
const yj1 = @import("yj1.zig");
const MkfFile = palcommon.MkfFile;

pub const PalMap = struct {
    tiles: [128][64][2]u32,
    tile_sprite: []const u8,
    map_num: u32,
};

pub fn loadMap(map_num: u32, map_mkf: MkfFile, gop_mkf: MkfFile, _: std.mem.Allocator) !PalMap {
    const map_chunk_count = try map_mkf.getChunkCount();
    const gop_chunk_count = try gop_mkf.getChunkCount();

    if (map_num == 0 or map_num >= map_chunk_count or map_num >= gop_chunk_count) {
        return error.InvalidMapNum;
    }

    const compressed = try map_mkf.getChunkData(map_num);

    var tile_bytes: [@sizeOf([128][64][2]u32)]u8 = undefined;
    _ = try yj1.decompress(compressed, &tile_bytes);

    var tiles: [128][64][2]u32 = undefined;
    for (0..128) |y| {
        for (0..64) |x| {
            for (0..2) |h| {
                const offset = (y * 64 * 2 + x * 2 + h) * 4;
                tiles[y][x][h] = std.mem.readInt(u32, tile_bytes[offset..][0..4], .little);
            }
        }
    }

    const tile_sprite = try gop_mkf.getChunkData(map_num);

    return .{
        .tiles = tiles,
        .tile_sprite = tile_sprite,
        .map_num = map_num,
    };
}

pub fn getTileBitmap(map: *const PalMap, x: u8, y: u8, h: u8, layer: u8) ?[]const u8 {
    if (x >= 64 or y >= 128 or h > 1) return null;

    var d = map.tiles[y][x][h];

    if (layer == 0) {
        const idx: i32 = @intCast((d & 0xFF) | ((d >> 4) & 0x100));
        return palcommon.spriteGetFrame(map.tile_sprite, idx);
    } else {
        d >>= 16;
        const raw: i32 = @intCast((d & 0xFF) | ((d >> 4) & 0x100));
        if (raw == 0) return null;
        return palcommon.spriteGetFrame(map.tile_sprite, raw - 1);
    }
}

pub fn tileIsBlocked(map: *const PalMap, x: u8, y: u8, h: u8) bool {
    if (x >= 64 or y >= 128 or h > 1) return true;
    return (map.tiles[y][x][h] & 0x2000) != 0;
}

pub fn getTileHeight(map: *const PalMap, x: u8, y: u8, h: u8, layer: u8) u8 {
    if (x >= 64 or y >= 128 or h > 1) return 0;

    var d = map.tiles[y][x][h];
    if (layer != 0) {
        d >>= 16;
    }
    d >>= 8;
    return @intCast(d & 0xF);
}

pub const Rect = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,
};

pub fn blitToSurface(map: *const PalMap, surface: *palcommon.Surface, src_rect: Rect, layer: u8) void {
    const sy: i32 = @divTrunc(src_rect.y, 16) - 1;
    const dy: i32 = @divTrunc(src_rect.y + src_rect.h, 16) + 2;
    const sx: i32 = @divTrunc(src_rect.x, 32) - 1;
    const dx: i32 = @divTrunc(src_rect.x + src_rect.w, 32) + 2;

    var y_pos: i32 = sy * 16 - 8 - src_rect.y;
    var y: i32 = sy;
    while (y < dy) : (y += 1) {
        var h: i32 = 0;
        while (h < 2) : (h += 1) {
            var x_pos: i32 = sx * 32 + h * 16 - 16 - src_rect.x;
            var x: i32 = sx;
            while (x < dx) : (x += 1) {
                var bitmap = getTileBitmap(map, @intCast(@as(u32, @bitCast(x)) & 0xFF), @intCast(@as(u32, @bitCast(y)) & 0xFF), @intCast(@as(u32, @bitCast(h)) & 0xFF), layer);
                if (bitmap == null) {
                    if (layer != 0) {
                        x_pos += 32;
                        continue;
                    }
                    bitmap = getTileBitmap(map, 0, 0, 0, layer);
                }
                if (bitmap) |bmp| {
                    _ = palcommon.rleBlitToSurface(bmp, surface, palcommon.palXY(@intCast(x_pos), @intCast(y_pos)));
                }
                x_pos += 32;
            }
            y_pos += 8;
        }
    }
}
