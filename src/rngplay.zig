// Copyright (c) 2009-2011, Wei Mingzhi <whistler_wmz@users.sf.net>.
// Copyright (c) 2011-2026, SDLPAL development team.
// All rights reserved.
//
// This file is part of SDLPAL.
//
// SDLPAL is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License, version 3
// as published by the Free Software Foundation.
//
// PAL_RNGPlay — port of rngplay.c. RNG.MKF stores cutscene animations as a
// two-level chunked archive: outer chunks are individual movies, inner chunks
// are YJ1-compressed delta frames. Each frame's blit script paints onto the
// previous frame's buffer (320×200 8bpp), so we keep a persistent surface
// across frames and only commit to gpScreen at the end of each step.

const std = @import("std");
const global = @import("global.zig");
const palcommon = @import("palcommon.zig");
const video = @import("video.zig");
const palette = @import("palette.zig");
const util = @import("util.zig");
const yj1 = @import("yj1.zig");

// Read one inner frame from RNG.MKF[uiRngNum][uiFrameNum] into `out`.
// Returns the byte length on success, error otherwise.
fn rngReadFrame(out: []u8, rng_num: u32, frame_num: u32) !usize {
    const mkf = global.gpg.f.rng orelse return error.NoRng;
    const data = mkf.data;

    const chunk_count = try mkf.getChunkCount();
    if (rng_num >= chunk_count) return error.InvalidChunk;

    // Outer chunk offset/length.
    const outer_off: u32 = std.mem.readInt(u32, data[4 * rng_num ..][0..4], .little);
    const outer_next: u32 = std.mem.readInt(u32, data[4 * rng_num + 4 ..][0..4], .little);
    const outer_len: u32 = outer_next - outer_off;
    if (outer_len == 0) return error.EmptyChunk;
    if (outer_off + outer_len > data.len) return error.UnexpectedEof;

    const outer = data[outer_off..][0..outer_len];

    // First u32 of the outer chunk is the offset of the first sub-chunk
    // (counts implicitly the size of the offset table itself). The number of
    // sub-chunks = (first_offset - 4) / 4 — same encoding scheme as MkfFile.
    const first_inner_off: u32 = std.mem.readInt(u32, outer[0..4], .little);
    const sub_count: u32 = (first_inner_off - 4) >> 2;
    if (frame_num >= sub_count) return error.InvalidFrame;

    const sub_off: u32 = std.mem.readInt(u32, outer[4 * frame_num ..][0..4], .little);
    const sub_next: u32 = std.mem.readInt(u32, outer[4 * frame_num + 4 ..][0..4], .little);
    const sub_len: u32 = sub_next - sub_off;
    if (sub_len == 0) return error.EmptyFrame;
    if (sub_off + sub_len > outer.len) return error.UnexpectedEof;
    if (sub_len > out.len) return error.BufferTooSmall;

    @memcpy(out[0..sub_len], outer[sub_off..][0..sub_len]);
    return sub_len;
}

// Apply one decoded frame's delta opcodes to `surface` (320×200 8bpp).
// Mirrors PAL_RNGBlitToSurface in rngplay.c — the case fall-throughs for
// opcodes 0x06..0x0a are intentional in the upstream code (each writes 2
// bytes, then falls through to write 2 more, etc.). Preserve them exactly
// so the original RNG data renders correctly.
fn rngBlitToSurface(rng: []const u8, surface: *palcommon.Surface) void {
    var ptr: usize = 0;
    var dst_ptr: usize = 0;
    const w: usize = @intCast(surface.w);
    const pitch: usize = @intCast(surface.pitch);

    const writePair = struct {
        fn f(s: *palcommon.Surface, ww: usize, pp: usize, dp: *usize, b0: u8, b1: u8) void {
            var x = dp.* % ww;
            var y = dp.* / ww;
            s.pixels[y * pp + x] = b0;
            x += 1;
            if (x >= ww) { x = 0; y += 1; }
            if (y * pp + x < s.pixels.len) s.pixels[y * pp + x] = b1;
            dp.* += 2;
        }
    }.f;

    while (ptr < rng.len) {
        const data = rng[ptr];
        ptr += 1;
        switch (data) {
            0x00, 0x13 => return, // end
            0x02 => dst_ptr += 2,
            0x03 => {
                if (ptr >= rng.len) return;
                const n = rng[ptr];
                ptr += 1;
                dst_ptr += (@as(usize, n) + 1) * 2;
            },
            0x04 => {
                if (ptr + 2 > rng.len) return;
                const wd: u16 = @as(u16, rng[ptr]) | (@as(u16, rng[ptr + 1]) << 8);
                ptr += 2;
                dst_ptr += (@as(usize, wd) + 1) * 2;
            },
            // Opcodes 0x06..0x0a fall through cumulatively in the C source —
            // each writes a 2-byte pair, then drops into the next case to
            // write another. 0x0a writes 5 pairs (10 bytes), 0x09 writes 4,
            // 0x08 writes 3, 0x07 writes 2, 0x06 writes 1 (with break).
            0x0a, 0x09, 0x08, 0x07, 0x06 => {
                const pair_count: u32 = switch (data) {
                    0x0a => 5,
                    0x09 => 4,
                    0x08 => 3,
                    0x07 => 2,
                    0x06 => 1,
                    else => unreachable,
                };
                var p: u32 = 0;
                while (p < pair_count) : (p += 1) {
                    if (ptr + 2 > rng.len) return;
                    writePair(surface, w, pitch, &dst_ptr, rng[ptr], rng[ptr + 1]);
                    ptr += 2;
                }
            },
            0x0b => {
                if (ptr >= rng.len) return;
                const n = rng[ptr];
                ptr += 1;
                var i: u32 = 0;
                while (i <= n) : (i += 1) {
                    if (ptr + 2 > rng.len) return;
                    writePair(surface, w, pitch, &dst_ptr, rng[ptr], rng[ptr + 1]);
                    ptr += 2;
                }
            },
            0x0c => {
                if (ptr + 2 > rng.len) return;
                const wd: u16 = @as(u16, rng[ptr]) | (@as(u16, rng[ptr + 1]) << 8);
                ptr += 2;
                var i: u32 = 0;
                while (i <= wd) : (i += 1) {
                    if (ptr + 2 > rng.len) return;
                    writePair(surface, w, pitch, &dst_ptr, rng[ptr], rng[ptr + 1]);
                    ptr += 2;
                }
            },
            // 0x0d..0x10 — repeat the same 2-byte pair (data - 0x0b) times.
            // SDLPAL's "data - (0x0d - 2)" simplifies to data - 0x0b, giving
            // counts 2,3,4,5 for 0x0d,0x0e,0x0f,0x10.
            0x0d, 0x0e, 0x0f, 0x10 => {
                if (ptr + 2 > rng.len) return;
                const reps: u32 = data - 0x0b;
                var i: u32 = 0;
                while (i < reps) : (i += 1) {
                    writePair(surface, w, pitch, &dst_ptr, rng[ptr], rng[ptr + 1]);
                }
                ptr += 2;
            },
            0x11 => {
                if (ptr + 1 > rng.len) return;
                const n = rng[ptr];
                ptr += 1;
                if (ptr + 2 > rng.len) return;
                var i: u32 = 0;
                while (i <= n) : (i += 1) {
                    writePair(surface, w, pitch, &dst_ptr, rng[ptr], rng[ptr + 1]);
                }
                ptr += 2;
            },
            0x12 => {
                if (ptr + 2 > rng.len) return;
                const n: u32 = (@as(u32, rng[ptr]) | (@as(u32, rng[ptr + 1]) << 8)) + 1;
                ptr += 2;
                if (ptr + 2 > rng.len) return;
                var i: u32 = 0;
                while (i < n) : (i += 1) {
                    writePair(surface, w, pitch, &dst_ptr, rng[ptr], rng[ptr + 1]);
                }
                ptr += 2;
            },
            else => {
                // Unknown opcode — skip rather than abort so a corrupt frame
                // doesn't kill the entire cutscene.
            },
        }
    }
}

// PAL_RNGPlay — play a range of frames from RNG.MKF[num_rng].
// iSpeed=0 is treated as 16 by SDLPAL; we use a fixed 16ms-tick step that
// matches SDLPAL's `1/iSpeed second` cadence by reusing util.delayUntil.
pub fn rngPlay(num_rng: i32, start_frame_in: i32, end_frame_in: i32, speed_in: i32) void {
    if (global.gpg.f.rng == null) return;

    const speed: u32 = if (speed_in == 0) 16 else @intCast(speed_in);
    // Frame interval in virtual milliseconds (SDLPAL: 1 second / speed).
    // Our virtual clock is in ms, advanced by retro_run.
    const delay_ms: u32 = @max(@as(u32, 1), 1000 / speed);

    // Two scratch buffers — one for the YJ1-compressed payload, one for the
    // decoded delta script. SDLPAL hardcodes 65000 here.
    const BUF_SIZE: usize = 65000;
    const compressed = global.allocator.alloc(u8, BUF_SIZE) catch return;
    defer global.allocator.free(compressed);
    const decoded = global.allocator.alloc(u8, BUF_SIZE) catch return;
    defer global.allocator.free(decoded);

    var start_frame: i32 = start_frame_in;
    var end_frame: i32 = end_frame_in;
    if (end_frame > 0) end_frame += 1;

    var t = util.getTicks();
    while (start_frame != end_frame) : (start_frame += 1) {
        if (util.shouldQuit()) break;
        t += delay_ms;

        const compressed_len = rngReadFrame(compressed, @intCast(num_rng), @intCast(start_frame)) catch break;
        const decoded_len = yj1.decompress(compressed[0..compressed_len], decoded) catch break;

        rngBlitToSurface(decoded[0..decoded_len], &video.screen);
        video.updateScreen(null);

        if (global.gpg.need_to_fade_in) {
            palette.fadeIn(@intCast(global.gpg.num_palette), global.gpg.night_palette, 1);
            global.gpg.need_to_fade_in = false;
        }

        util.delayUntil(t);
    }
}
