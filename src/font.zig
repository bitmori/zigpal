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
const Surface = palcommon.Surface;
const Pos = palcommon.Pos;
const palX = palcommon.palX;
const palY = palcommon.palY;

const font_height = 15;

const iso_font_raw = @embedFile("ascii_font.bin");
const iso_font_chars = iso_font_raw.len / 15;

// BIG5 font: wor16.fon contains 30-byte glyphs (15 rows x 16 pixels wide)
// indexed by character order in wor16.asc
var big5_font: []const [30]u8 = &.{};
var big5_chars: []const u8 = &.{}; // raw BIG5 bytes (2 per char)

// ASCII font: 8x15, one byte per row, pre-reversed at comptime
const ascii_font: [iso_font_chars][15]u8 = blk: {
    @setEvalBranchQuota(100_000);
    var result: [iso_font_chars][15]u8 = undefined;
    for (0..iso_font_chars) |i| {
        for (0..15) |j| {
            result[i][j] = comptime_reverseBits(iso_font_raw[i * 15 + j]);
        }
    }
    break :blk result;
};

fn comptime_reverseBits(x: u8) u8 {
    var val = x;
    var y: u8 = 0;
    for (0..8) |_| {
        y <<= 1;
        y |= (val & 1);
        val >>= 1;
    }
    return y;
}

const glyph_offset = 0x682;
const glyph_size = 30;

pub fn init(wor16_asc: ?[]const u8, wor16_fon: ?[]const u8) void {
    const asc = wor16_asc orelse return;
    const fon = wor16_fon orelse return;

    const char_count = asc.len / 2;
    if (fon.len < glyph_offset + char_count * glyph_size) return;

    big5_chars = asc;
    const glyph_data = fon[glyph_offset..];
    big5_font = @as([*]const [30]u8, @ptrCast(glyph_data.ptr))[0..char_count];
}

pub fn lookupBig5(code: u16) ?*const [30]u8 {
    const hi: u8 = @intCast(code >> 8);
    const lo: u8 = @intCast(code & 0xFF);
    const char_count = big5_chars.len / 2;
    for (0..char_count) |i| {
        if (big5_chars[i * 2] == hi and big5_chars[i * 2 + 1] == lo) {
            return &big5_font[i];
        }
    }
    return null;
}

pub fn getAsciiGlyph(ch: u8) *const [15]u8 {
    if (ch < iso_font_chars) return &ascii_font[ch];
    return &ascii_font[0];
}

pub fn drawAscii(ch: u8, surface: *Surface, pos: Pos, color: u8) void {
    const x = palX(pos);
    const y = palY(pos);
    const glyph = &ascii_font[ch];

    for (0..font_height) |row| {
        const dest_y = y + @as(i32, @intCast(row));
        if (dest_y < 0 or dest_y >= surface.h) continue;
        const row_start: usize = @intCast(dest_y * surface.pitch);

        for (0..8) |col| {
            const dest_x = x + @as(i32, @intCast(col));
            if (dest_x < 0 or dest_x >= surface.w) continue;
            if (glyph[row] & (@as(u8, 1) << @intCast(7 - col)) != 0) {
                surface.pixels[row_start + @as(usize, @intCast(dest_x))] = color;
            }
        }
    }
}

pub fn drawBig5(code: u16, surface: *Surface, pos: Pos, color: u8) void {
    const glyph = lookupBig5(code) orelse return;
    const x = palX(pos);
    const y = palY(pos);

    for (0..font_height) |row| {
        const dest_y = y + @as(i32, @intCast(row));
        if (dest_y < 0 or dest_y >= surface.h) continue;
        const row_start: usize = @intCast(dest_y * surface.pitch);

        // Left 8 pixels
        for (0..8) |col| {
            const dest_x = x + @as(i32, @intCast(col));
            if (dest_x < 0 or dest_x >= surface.w) continue;
            if (glyph[row * 2] & (@as(u8, 1) << @intCast(7 - col)) != 0) {
                surface.pixels[row_start + @as(usize, @intCast(dest_x))] = color;
            }
        }
        // Right 8 pixels
        for (0..8) |col| {
            const dest_x = x + 8 + @as(i32, @intCast(col));
            if (dest_x < 0 or dest_x >= surface.w) continue;
            if (glyph[row * 2 + 1] & (@as(u8, 1) << @intCast(7 - col)) != 0) {
                surface.pixels[row_start + @as(usize, @intCast(dest_x))] = color;
            }
        }
    }
}

pub fn charWidth(code: u16) i32 {
    if (code < 0x80) return 8;
    return 16;
}

pub fn height() i32 {
    return font_height;
}
