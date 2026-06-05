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
// PAL_SplashScreen — port of main.c:206. Cranes flying across a sliding
// upper/lower bitmap pair, with the title sliding down on the right and a
// 15-second palette fade-in. Press SEARCH/MENU to skip; the rest of the
// fade-in runs in fast-forward (the standard SDLPAL behaviour) before fading
// out to the opening menu.
//
// Audio is omitted in this port. NO_SPLASH file in the resource directory
// also short-circuits the entire splash to a no-op (handy for dev iteration).

const std = @import("std");
const c = std.c;
const global = @import("global.zig");
const palcommon = @import("palcommon.zig");
const video = @import("video.zig");
const palette = @import("palette.zig");
const util = @import("util.zig");
const input = @import("input.zig");
const yj1 = @import("yj1.zig");

// DOS resource indices — main.c:42-45.
const BITMAPNUM_SPLASH_UP: u32 = 0x26;
const BITMAPNUM_SPLASH_DOWN: u32 = 0x27;
const SPRITENUM_SPLASH_TITLE: u32 = 0x47;
const SPRITENUM_SPLASH_CRANE: u32 = 0x49;

// Decompress an FBP/MGO chunk into an owned buffer. The MKF chunks are
// YJ1-compressed; we allocate `out_len` bytes and return them on success.
fn decompressChunk(mkf: palcommon.MkfFile, chunk_num: u32, out_len: usize) ?[]u8 {
    const compressed = mkf.getChunkData(chunk_num) catch return null;
    const buf = global.allocator.alloc(u8, out_len) catch return null;
    _ = yj1.decompress(compressed, buf) catch {
        global.allocator.free(buf);
        return null;
    };
    return buf;
}

// True when a NO_SPLASH file exists in the resource directory.
fn noSplashFlagSet() bool {
    const sys_dir = @import("libretro_core.zig").system_dir orelse return false;
    var path_buf: [4096]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/pal/NO_SPLASH\x00", .{sys_dir}) catch return false;
    const path_z: [*:0]const u8 = path_buf[0 .. path.len - 1 :0];

    const fd = c.open(path_z, .{ .ACCMODE = .RDONLY });
    if (fd < 0) return false;
    _ = c.close(fd);
    return true;
}

// Apply a palette scaled by `factor` ∈ [0, 1] for fade-in. SDLPAL multiplies
// each channel by `dwTime / 15000` directly, which produces values in
// 0..255 when the source palette is already 0..255.
fn applyScaledPalette(base: *const palette.Palette, factor: f32) void {
    var p: palette.Palette = undefined;
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        p[i] = .{
            .r = @intFromFloat(@as(f32, @floatFromInt(base[i].r)) * factor),
            .g = @intFromFloat(@as(f32, @floatFromInt(base[i].g)) * factor),
            .b = @intFromFloat(@as(f32, @floatFromInt(base[i].b)) * factor),
        };
    }
    video.setPalette(p);
}

// PAL_TrademarkScreen — port of main.c:179. Plays RNG.MKF chunk 6 (the
// Softstar/Domo logos) on top of palette 3, holds for a second, fades out.
// PAL_PlayAVI("1.avi") is intentionally skipped — DOS data has no AVI and
// the Win95 path is out of scope for this port.
pub fn trademarkScreen() void {
    if (noSplashFlagSet()) return;
    palette.setPalette(3, false);
    @import("rngplay.zig").rngPlay(6, 0, -1, 25);
    util.delay(1000);
    palette.fadeOut(1);
}

pub fn splashScreen() void {
    if (noSplashFlagSet()) return;

    // PAL_SplashScreen plays the title RIX (track 5) on entry — matches
    // SDLPAL's main.c:293. Do this first so init delay overlaps the load.
    @import("audio.zig").playMusic(5, true, 2.0);

    const fbp = global.gpg.f.fbp orelse return;
    const mgo = global.gpg.f.mgo orelse return;
    const base_pal = palette.get(1, false) orelse return;

    // Decompressed pixel buffers. SDLPAL hardcodes 320*200 for the bg pair
    // and 32000 for the sprites.
    const bg_up = decompressChunk(fbp, BITMAPNUM_SPLASH_UP, 320 * 200) orelse return;
    defer global.allocator.free(bg_up);
    const bg_down = decompressChunk(fbp, BITMAPNUM_SPLASH_DOWN, 320 * 200) orelse return;
    defer global.allocator.free(bg_down);
    const title_sprite = decompressChunk(mgo, SPRITENUM_SPLASH_TITLE, 32000) orelse return;
    defer global.allocator.free(title_sprite);
    const crane_sprite = decompressChunk(mgo, SPRITENUM_SPLASH_CRANE, 32000) orelse return;
    defer global.allocator.free(crane_sprite);

    // Compose the bg pair into 8bpp surfaces (320×200). SDLPAL uses
    // VIDEO_CreateCompatibleSurface; we just need raw pixel arrays.
    var bg_up_pix: [320 * 200]u8 = undefined;
    var bg_down_pix: [320 * 200]u8 = undefined;
    var bg_up_surf: palcommon.Surface = .{ .w = 320, .h = 200, .pitch = 320, .pixels = &bg_up_pix };
    var bg_down_surf: palcommon.Surface = .{ .w = 320, .h = 200, .pitch = 320, .pixels = &bg_down_pix };
    _ = palcommon.fbpBlitToSurface(bg_up, &bg_up_surf);
    _ = palcommon.fbpBlitToSurface(bg_down, &bg_down_surf);

    // The title sprite's first frame; SDLPAL hacks the height word to 0 so
    // the bitmap reveals row-by-row each frame. Make a mutable copy of the
    // RLE so we can patch its header inline. The sprite blob is structured
    // as `spriteGetFrame` expects — frame 0 is at offset given by the table
    // at the head of the sprite blob.
    const title_frame_const = palcommon.spriteGetFrame(title_sprite, 0) orelse return;
    const title_frame = global.allocator.dupe(u8, title_frame_const) catch return;
    defer global.allocator.free(title_frame);

    const title_height_full: u16 = palcommon.rleGetHeight(title_frame);
    // Slot the height to 0 — SDLPAL writes lpBitmapTitle[2..3]. The RLE has
    // a 4-byte signature 02 00 00 00 prefix before width/height; check it.
    const rle_off: usize = if (title_frame.len >= 4 and
        title_frame[0] == 0x02 and title_frame[1] == 0x00 and
        title_frame[2] == 0x00 and title_frame[3] == 0x00) 4 else 0;
    const height_lo = rle_off + 2;
    const height_hi = rle_off + 3;
    title_frame[height_lo] = 0;
    title_frame[height_hi] = 0;

    // Random crane positions. SDLPAL uses RandomLong; use the same RNG so
    // the visuals match and runs are reproducible.
    var crane_pos: [9][3]i32 = undefined;
    var ci: usize = 0;
    while (ci < 9) : (ci += 1) {
        crane_pos[ci][0] = util.randomLong(300, 600);
        crane_pos[ci][1] = util.randomLong(0, 80);
        crane_pos[ci][2] = util.randomLong(0, 8);
    }

    // Animation state.
    var img_pos: i32 = 200;
    var crane_frame: u32 = 0;
    const FADE_DURATION_MS: u32 = 15000;
    const FRAME_INTERVAL_MS: u32 = 85;

    input.processEvent();
    input.clearKeyState();

    const begin_time = util.getTicks();

    while (true) {
        if (util.shouldQuit()) break;

        input.processEvent();
        var dw_time: u32 = util.getTicks() -% begin_time;

        // Palette scale for fade-in. After 15s, full palette.
        if (dw_time < FADE_DURATION_MS) {
            const factor: f32 = @as(f32, @floatFromInt(dw_time)) / @as(f32, @floatFromInt(FADE_DURATION_MS));
            applyScaledPalette(base_pal, factor);
        } else {
            video.setPalette(base_pal.*);
        }

        // Slide the bg pair. img_pos counts down from 200 toward 1, splitting
        // the upper bitmap (visible above the seam) from the lower bitmap
        // (visible below).
        if (img_pos > 1) img_pos -= 1;

        // Upper part: copy rows [img_pos, 200) of bg_up to rows [0, 200-img_pos).
        const upper_h: i32 = 200 - img_pos;
        if (upper_h > 0) {
            var row: i32 = 0;
            while (row < upper_h) : (row += 1) {
                const src_row = img_pos + row;
                @memcpy(
                    video.screen_pixels[@as(usize, @intCast(row * 320))..][0..320],
                    bg_up_pix[@as(usize, @intCast(src_row * 320))..][0..320],
                );
            }
        }

        // Lower part: copy rows [0, img_pos) of bg_down to rows [200-img_pos, 200).
        if (img_pos > 0) {
            var row: i32 = 0;
            while (row < img_pos) : (row += 1) {
                const dst_row = 200 - img_pos + row;
                @memcpy(
                    video.screen_pixels[@as(usize, @intCast(dst_row * 320))..][0..320],
                    bg_down_pix[@as(usize, @intCast(row * 320))..][0..320],
                );
            }
        }

        // Draw the cranes.
        var k: usize = 0;
        while (k < 9) : (k += 1) {
            crane_pos[k][2] = @mod(crane_pos[k][2] + @as(i32, @intCast(crane_frame & 1)), 8);
            const frame_bmp = palcommon.spriteGetFrame(crane_sprite, crane_pos[k][2]) orelse continue;
            // Sink the cranes when the bg is still sliding.
            if (img_pos > 1 and (img_pos & 1) != 0) crane_pos[k][1] += 1;
            _ = palcommon.rleBlitToSurface(
                frame_bmp,
                &video.screen,
                global.palXY(@truncate(crane_pos[k][0]), @truncate(crane_pos[k][1])),
            );
            crane_pos[k][0] -= 1;
        }
        crane_frame += 1;

        // Title slide: increment the patched height word until it reaches the
        // real height — the RLE blit then progressively reveals more rows.
        const cur_title_h: u16 = palcommon.rleGetHeight(title_frame);
        if (cur_title_h < title_height_full) {
            const new_h: u16 = cur_title_h + 1;
            title_frame[height_lo] = @truncate(new_h);
            title_frame[height_hi] = @truncate(new_h >> 8);
        }
        _ = palcommon.rleBlitToSurface(title_frame, &video.screen, global.palXY(255, 10));

        video.updateScreen(null);

        // Skip on key press: snap to full palette and break out.
        const k_press = input.state.key_press;
        if ((k_press & (input.KEY_MENU | input.KEY_SEARCH)) != 0) {
            // Restore the full title height before final flush so the user
            // sees a clean title for ~500ms before the fade-out.
            title_frame[height_lo] = @truncate(title_height_full);
            title_frame[height_hi] = @truncate(title_height_full >> 8);
            _ = palcommon.rleBlitToSurface(title_frame, &video.screen, global.palXY(255, 10));
            video.updateScreen(null);

            // If we cut the fade short, finish it quickly so the screen is
            // fully bright before the fade-out begins.
            if (dw_time < FADE_DURATION_MS) {
                while (dw_time < FADE_DURATION_MS) {
                    if (util.shouldQuit()) break;
                    const factor: f32 = @as(f32, @floatFromInt(dw_time)) / @as(f32, @floatFromInt(FADE_DURATION_MS));
                    applyScaledPalette(base_pal, factor);
                    util.delay(8);
                    dw_time += 250;
                }
                util.delay(500);
            }
            input.clearKeyState();
            break;
        }

        // Sleep until the next 85ms tick.
        input.processEvent();
        const target = begin_time +% dw_time +% FRAME_INTERVAL_MS;
        while (util.getTicks() -% begin_time < dw_time +% FRAME_INTERVAL_MS) {
            if (util.shouldQuit()) break;
            util.delay(1);
            input.processEvent();
        }
        _ = target;
    }

    palette.fadeOut(1);
}
