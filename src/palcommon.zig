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

// --- Types ---

pub const Pos = u32;

pub fn palXY(x: i16, y: i16) Pos {
    return (@as(u32, @bitCast(@as(i32, y))) << 16) | (@as(u32, @bitCast(@as(i32, x))) & 0xFFFF);
}

pub fn palX(xy: Pos) i16 {
    return @bitCast(@as(u16, @intCast(xy & 0xFFFF)));
}

pub fn palY(xy: Pos) i16 {
    return @bitCast(@as(u16, @intCast((xy >> 16) & 0xFFFF)));
}

pub const Direction = enum {
    south,
    west,
    north,
    east,
    unknown,
};

pub const MusicType = enum {
    midi,
    rix,
    mp3,
    ogg,
    opus,
};

pub const CdType = enum {
    none,
    mp3,
    ogg,
    opus,
    sdl_cd,
};

pub const MidiSynthType = enum {
    native,
    timidity,
    tiny_soundfont,
};

pub const CodePage = enum {
    big5,
    gbk,
    utf8,
    ucs,
};

pub const Surface = struct {
    w: i32,
    h: i32,
    pitch: i32,
    pixels: []u8,
};

// --- Constants ---

// 魔改 — 4-person party support (fork bumps from 3 to 4).
pub const MAX_PLAYERS_IN_PARTY = 4;
pub const MAX_PLAYER_ROLES = 6;
pub const MAX_PLAYABLE_PLAYER_ROLES = 5;
pub const MAX_INVENTORY = 256;
pub const MAX_STORE_ITEM = 9;
pub const NUM_MAGIC_ELEMENTAL = 5;
pub const MAX_ENEMIES_IN_TEAM = 5;
pub const MAX_PLAYER_EQUIPMENTS = 6;
pub const MAX_PLAYER_MAGICS = 32;
pub const MAX_SCENES = 300;
pub const MAX_OBJECTS = 600;
pub const MAX_EVENT_OBJECTS = 5500;
pub const MAX_POISONS = 16;
pub const MAX_LEVELS = 99;
pub const MINIMAL_WORD_COUNT = MAX_OBJECTS + 13;
pub const PAL_CDTRACK_BASE = 10000;
pub const PAL_RLEBUFSIZE = 64000;

// --- Helper functions ---

inline fn calcShadowColor(source: u8) u8 {
    return (source & 0xF0) | ((source & 0x0F) >> 1);
}

fn skipRleHeader(data: []const u8) []const u8 {
    if (data.len >= 4 and data[0] == 0x02 and data[1] == 0x00 and data[2] == 0x00 and data[3] == 0x00) {
        return data[4..];
    }
    return data;
}

fn rleGetDimensions(data: []const u8) struct { width: u32, height: u32 } {
    return .{
        .width = std.mem.readInt(u16, data[0..2], .little),
        .height = std.mem.readInt(u16, data[2..4], .little),
    };
}

// --- RLE Blit functions ---

const BlitMode = union(enum) {
    normal: void,
    shadow: void,
    color_shift: i32,
    mono_color: struct { base_color: u8, color_shift: i32 },
    // 魔改 — horizontal flip; only normal pixel copy (no shadow / color
    // shift). Source column x maps to destination column dx + width-1 - x.
    mirror: void,
};

fn rleBlitGeneric(bitmap_rle: []const u8, surface: *Surface, pos: Pos, mode: BlitMode) i32 {
    var rle = skipRleHeader(bitmap_rle);
    const dims = rleGetDimensions(rle);
    const ui_width: u32 = dims.width;
    const ui_height: u32 = dims.height;

    const dx: i32 = palX(pos);
    var dy: i32 = palY(pos);

    if (@as(i32, @intCast(ui_width)) + dx <= 0 or dx >= surface.w or
        @as(i32, @intCast(ui_height)) + dy <= 0 or dy >= surface.h)
    {
        return 0;
    }

    if (mode == .mirror) {
        return rleBlitMirror(rle, surface, dx, dy, ui_width, ui_height);
    }

    const ui_len = ui_width * ui_height;
    rle = rle[4..];

    var i: u32 = 0;
    var ui_src_x: u32 = 0;
    var rle_offset: usize = 0;

    while (i < ui_len) {
        const T = rle[rle_offset];
        rle_offset += 1;

        if ((T & 0x80) != 0 and T <= 0x80 + @as(u8, @intCast(@min(ui_width, 0x7F)))) {
            const skip = @as(u32, T) - 0x80;
            i += skip;
            ui_src_x += skip;
            if (ui_src_x >= ui_width) {
                ui_src_x -= ui_width;
                dy += 1;
            }
        } else {
            var j: u32 = 0;
            var sx: u32 = ui_src_x;
            var x: i32 = dx + @as(i32, @intCast(ui_src_x));
            var y: i32 = dy;

            if (y < 0) {
                j += @as(u32, @intCast(-y)) * ui_width;
                y = 0;
            } else if (y >= surface.h) {
                return 0;
            }

            while (j < T) {
                if (x < 0) {
                    const neg_x: u32 = @intCast(-x);
                    j += neg_x;
                    if (j >= T) break;
                    sx += neg_x;
                    x = 0;
                } else if (x >= surface.w) {
                    j += ui_width - sx;
                    x -= @as(i32, @intCast(sx));
                    sx = 0;
                    y += 1;
                    if (y >= surface.h) return 0;
                    continue;
                }

                var k: u32 = @as(u32, T) - j;
                const remaining_w: u32 = @intCast(surface.w - x);
                if (remaining_w < k) k = remaining_w;
                if (ui_width - sx < k) k = ui_width - sx;
                sx += k;

                const row_start: usize = @intCast(y * surface.pitch);
                var xi: usize = @intCast(x);
                var ki = k;

                switch (mode) {
                    .shadow => {
                        j += k;
                        while (ki != 0) : (ki -= 1) {
                            surface.pixels[row_start + xi] = calcShadowColor(surface.pixels[row_start + xi]);
                            xi += 1;
                        }
                    },
                    .normal => {
                        while (ki != 0) : (ki -= 1) {
                            surface.pixels[row_start + xi] = rle[rle_offset + j];
                            j += 1;
                            xi += 1;
                        }
                    },
                    .color_shift => |shift| {
                        while (ki != 0) : (ki -= 1) {
                            var b: i32 = @as(i32, rle[rle_offset + j] & 0x0F);
                            b += shift;
                            if (b > 0x0F) b = 0x0F else if (b < 0) b = 0;
                            surface.pixels[row_start + xi] = @as(u8, @intCast(b)) | (rle[rle_offset + j] & 0xF0);
                            j += 1;
                            xi += 1;
                        }
                    },
                    .mono_color => |mc| {
                        while (ki != 0) : (ki -= 1) {
                            var b: i32 = @as(i32, rle[rle_offset + j] & 0x0F);
                            b += mc.color_shift;
                            if (b > 0x0F) b = 0x0F else if (b < 0) b = 0;
                            surface.pixels[row_start + xi] = @as(u8, @intCast(b)) | mc.base_color;
                            j += 1;
                            xi += 1;
                        }
                    },
                    // mirror takes the early branch in rleBlitGeneric — never reaches here.
                    .mirror => unreachable,
                }
                x += @intCast(k);

                if (sx >= ui_width) {
                    sx -= ui_width;
                    x -= @as(i32, @intCast(ui_width));
                    y += 1;
                    if (y >= surface.h) return 0;
                }
            }
            rle_offset += T;
            i += T;
            ui_src_x += T;
            while (ui_src_x >= ui_width) {
                ui_src_x -= ui_width;
                dy += 1;
            }
        }
    }

    return 0;
}

// 魔改 — fork PAL_RLEBlitToSurfaceInMirror, ported segment-for-segment.
// Caller has already skipped the file header and the 4-byte width/height
// prefix is still on `rle` (we strip it here). dx0/dy0 are pre-clipped only
// for the trivial off-screen rejection in rleBlitGeneric; the inner loop
// does its own per-segment clipping just like the C version.
fn rleBlitMirror(rle_in: []const u8, surface: *Surface, dx0: i32, dy0: i32, ui_w: u32, ui_h: u32) i32 {
    const rle = rle_in[4..];
    const total_len: u32 = ui_w * ui_h;

    var i: u32 = 0;
    var src_x: u32 = 0;
    var src_y: u32 = 0;
    var off: usize = 0;

    while (i < total_len) {
        const T = rle[off];
        off += 1;

        if ((T & 0x80) != 0 and T <= 0x80 + @as(u8, @intCast(@min(ui_w, 0x7F)))) {
            const skip = @as(u32, T) - 0x80;
            i += skip;
            src_x += skip;
            while (src_x >= ui_w) {
                src_x -= ui_w;
                src_y += 1;
            }
            continue;
        }

        // Skip rows entirely outside the surface up-front.
        var y: i32 = dy0 + @as(i32, @intCast(src_y));
        if (y < 0 or y >= surface.h) {
            off += T;
            i += T;
            src_x += T;
            while (src_x >= ui_w) {
                src_x -= ui_w;
                src_y += 1;
            }
            continue;
        }

        var row_start: usize = @intCast(y * surface.pitch);
        var processed: u32 = 0;
        var cur_src_x: u32 = src_x;

        while (processed < T) {
            const pixels_in_row: u32 = @min(@as(u32, T) - processed, ui_w - cur_src_x);

            // Mirror-mapped destination column range for this row segment.
            const dst_x_start: i32 = dx0 + @as(i32, @intCast(ui_w)) - 1 - @as(i32, @intCast(cur_src_x));
            const dst_x_end: i32 = dx0 + @as(i32, @intCast(ui_w)) - 1 - @as(i32, @intCast(cur_src_x + pixels_in_row - 1));

            const clip_left: i32 = @max(0, dst_x_end);
            const clip_right: i32 = @min(surface.w - 1, dst_x_start);

            if (clip_left <= clip_right) {
                const px_clipped_left: i32 = clip_left - dst_x_end;
                const px_to_draw: u32 = @intCast(clip_right - clip_left + 1);

                var k: u32 = 0;
                while (k < px_to_draw) : (k += 1) {
                    const src_idx: usize = off + processed + @as(u32, @intCast(px_clipped_left)) + k;
                    const dst_x: usize = @intCast(clip_right - @as(i32, @intCast(k)));
                    surface.pixels[row_start + dst_x] = rle[src_idx];
                }
            }

            processed += pixels_in_row;
            cur_src_x += pixels_in_row;
            if (cur_src_x >= ui_w) {
                cur_src_x = 0;
                y += 1;
                if (y >= surface.h) break;
                row_start = @intCast(y * surface.pitch);
            }
        }

        off += T;
        i += T;
        src_x += T;
        while (src_x >= ui_w) {
            src_x -= ui_w;
            src_y += 1;
        }
    }

    return 0;
}

pub fn rleBlitToSurface(bitmap_rle: []const u8, surface: *Surface, pos: Pos) i32 {
    return rleBlitGeneric(bitmap_rle, surface, pos, .normal);
}

pub fn rleBlitToSurfaceWithShadow(bitmap_rle: []const u8, surface: *Surface, pos: Pos, shadow: bool) i32 {
    return rleBlitGeneric(bitmap_rle, surface, pos, if (shadow) .shadow else .normal);
}

pub fn rleBlitWithColorShift(bitmap_rle: []const u8, surface: *Surface, pos: Pos, color_shift: i32) i32 {
    return rleBlitGeneric(bitmap_rle, surface, pos, .{ .color_shift = color_shift });
}

pub fn rleBlitMonoColor(bitmap_rle: []const u8, surface: *Surface, pos: Pos, color: u8, color_shift: i32) i32 {
    return rleBlitGeneric(bitmap_rle, surface, pos, .{ .mono_color = .{ .base_color = color & 0xF0, .color_shift = color_shift } });
}

// 魔改 — horizontally-flipped RLE blit. Decodes the RLE as usual but maps
// source column x to destination column (dx + width - 1 - x). Used by the
// magic-render Mirror mode (Magic.render_mode & MAGIC_RENDER_MIRROR).
pub fn rleBlitToSurfaceInMirror(bitmap_rle: []const u8, surface: *Surface, pos: Pos) i32 {
    return rleBlitGeneric(bitmap_rle, surface, pos, .mirror);
}

pub fn fbpBlitToSurface(bitmap_fbp: []const u8, surface: *Surface) i32 {
    if (surface.w != 320 or surface.h != 200) {
        return -1;
    }

    for (0..200) |y| {
        const row_start: usize = @intCast(@as(i32, @intCast(y)) * surface.pitch);
        for (0..320) |x| {
            surface.pixels[row_start + x] = bitmap_fbp[y * 320 + x];
        }
    }

    return 0;
}

// --- RLE dimension queries ---

pub fn rleGetWidth(bitmap_rle: []const u8) u16 {
    const rle = skipRleHeader(bitmap_rle);
    return std.mem.readInt(u16, rle[0..2], .little);
}

pub fn rleGetHeight(bitmap_rle: []const u8) u16 {
    const rle = skipRleHeader(bitmap_rle);
    return std.mem.readInt(u16, rle[2..4], .little);
}

// --- Sprite functions ---

pub fn spriteGetNumFrames(sprite: []const u8) u16 {
    return std.mem.readInt(u16, sprite[0..2], .little) -% 1;
}

pub fn spriteGetFrame(sprite: []const u8, frame_num: i32) ?[]const u8 {
    const image_count: i32 = std.mem.readInt(u16, sprite[0..2], .little);

    if (frame_num < 0 or frame_num >= image_count) {
        return null;
    }

    const idx: usize = @intCast(frame_num * 2);
    var offset: u32 = @as(u32, std.mem.readInt(u16, sprite[idx..][0..2], .little)) << 1;
    if (offset == 0x18444) offset = offset & 0xFFFF;
    return sprite[@intCast(offset)..];
}

// --- MKF archive functions ---
// MkfFile operates on an in-memory buffer of the whole MKF file.

pub const MkfFile = struct {
    data: []const u8,

    pub fn fromMemory(data: []const u8) MkfFile {
        return .{ .data = data };
    }

    fn readU32(self: *const MkfFile, offset: usize) !u32 {
        if (offset + 4 > self.data.len) return error.UnexpectedEof;
        return std.mem.readInt(u32, self.data[offset..][0..4], .little);
    }

    pub fn getChunkCount(self: *const MkfFile) !u32 {
        const first_offset = try self.readU32(0);
        return (first_offset - 4) >> 2;
    }

    pub fn getChunkSize(self: *const MkfFile, chunk_num: u32) !u32 {
        const chunk_count = try self.getChunkCount();
        if (chunk_num >= chunk_count) return error.InvalidChunk;

        const offset = try self.readU32(4 * chunk_num);
        const next_offset = try self.readU32(4 * chunk_num + 4);
        return next_offset - offset;
    }

    pub fn readChunk(self: *const MkfFile, buffer: []u8, chunk_num: u32) !usize {
        const chunk_count = try self.getChunkCount();
        if (chunk_num >= chunk_count) return error.InvalidChunk;

        const offset = try self.readU32(4 * chunk_num);
        const next_offset = try self.readU32(4 * chunk_num + 4);

        const chunk_len = next_offset - offset;
        if (chunk_len > buffer.len) return error.BufferTooSmall;
        if (chunk_len == 0) return error.EmptyChunk;
        if (offset + chunk_len > self.data.len) return error.UnexpectedEof;

        @memcpy(buffer[0..chunk_len], self.data[offset..][0..chunk_len]);
        return chunk_len;
    }

    pub fn getChunkData(self: *const MkfFile, chunk_num: u32) ![]const u8 {
        const chunk_count = try self.getChunkCount();
        if (chunk_num >= chunk_count) return error.InvalidChunk;

        const offset = try self.readU32(4 * chunk_num);
        const next_offset = try self.readU32(4 * chunk_num + 4);

        const chunk_len = next_offset - offset;
        if (chunk_len == 0) return error.EmptyChunk;
        if (offset + chunk_len > self.data.len) return error.UnexpectedEof;

        return self.data[offset..][0..chunk_len];
    }

    pub fn getDecompressedSize(self: *const MkfFile, chunk_num: u32, is_win95: bool) !u32 {
        const chunk_count = try self.getChunkCount();
        if (chunk_num >= chunk_count) return error.InvalidChunk;

        const offset = try self.readU32(4 * chunk_num);

        if (is_win95) {
            return try self.readU32(offset);
        } else {
            const signature = try self.readU32(offset);
            const size = try self.readU32(offset + 4);
            if (signature != 0x315f4a59) return error.InvalidSignature;
            return size;
        }
    }
};
