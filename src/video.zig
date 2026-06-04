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

pub const SCREEN_WIDTH: u32 = 320;
pub const SCREEN_HEIGHT: u32 = 200;

// 8-bit indexed surfaces (gpScreen, gpScreenBak in SDLPAL)
pub var screen_pixels: [SCREEN_WIDTH * SCREEN_HEIGHT]u8 = [_]u8{0} ** (SCREEN_WIDTH * SCREEN_HEIGHT);
pub var screen_bak_pixels: [SCREEN_WIDTH * SCREEN_HEIGHT]u8 = [_]u8{0} ** (SCREEN_WIDTH * SCREEN_HEIGHT);

pub var screen: palcommon.Surface = .{
    .w = @intCast(SCREEN_WIDTH),
    .h = @intCast(SCREEN_HEIGHT),
    .pitch = @intCast(SCREEN_WIDTH),
    .pixels = &screen_pixels,
};

pub var screen_bak: palcommon.Surface = .{
    .w = @intCast(SCREEN_WIDTH),
    .h = @intCast(SCREEN_HEIGHT),
    .pitch = @intCast(SCREEN_WIDTH),
    .pixels = &screen_bak_pixels,
};

// Current palette in RGB888 (used for fade/anime computation)
pub const Color = struct { r: u8 = 0, g: u8 = 0, b: u8 = 0, a: u8 = 0xff };
pub var current_palette: [256]Color = [_]Color{.{}} ** 256;

// Pre-computed RGB565 palette (used by retro_run to avoid per-pixel conversion)
pub var palette565: [256]u16 = [_]u16{0} ** 256;

// Final framebuffer in RGB565 — read by retro_run.
pub var framebuffer: [SCREEN_WIDTH * SCREEN_HEIGHT]u16 = [_]u16{0} ** (SCREEN_WIDTH * SCREEN_HEIGHT);

// Shake state (set by VIDEO_ShakeScreen, applied in VIDEO_UpdateScreen)
var g_w_shake_time: u16 = 0;
var g_w_shake_level: u16 = 0;

inline fn rgb565(r: u8, g: u8, b: u8) u16 {
    return (@as(u16, r >> 3) << 11) | (@as(u16, g >> 2) << 5) | @as(u16, b >> 3);
}

// VIDEO_SetPalette — install a new RGB888 palette and recompute the RGB565 LUT.
pub fn setPalette(palette: [256]Color) void {
    current_palette = palette;
    for (0..256) |i| {
        palette565[i] = rgb565(palette[i].r, palette[i].g, palette[i].b);
    }
}

// VIDEO_UpdateScreen — convert the indexed `screen` to RGB565 framebuffer.
// SDLPAL uses lpRect to limit the dirty region; we always do full conversion.
// Shake offset applies if g_wShakeTime != 0.
pub fn updateScreen(_: ?*const anyopaque) void {
    if (g_w_shake_time != 0) {
        const level: u32 = g_w_shake_level;
        const visible_h: u32 = SCREEN_HEIGHT - level;
        if ((g_w_shake_time & 1) != 0) {
            // Top half visible at offset 0..visible_h, with src offset = level
            for (0..visible_h) |y| {
                const sy = y + level;
                for (0..SCREEN_WIDTH) |x| {
                    framebuffer[y * SCREEN_WIDTH + x] = palette565[screen_pixels[sy * SCREEN_WIDTH + x]];
                }
            }
            // Black band at the bottom
            for (visible_h..SCREEN_HEIGHT) |y| {
                for (0..SCREEN_WIDTH) |x| {
                    framebuffer[y * SCREEN_WIDTH + x] = 0;
                }
            }
        } else {
            // Black band at top, then content shifted down by level
            for (0..level) |y| {
                for (0..SCREEN_WIDTH) |x| {
                    framebuffer[y * SCREEN_WIDTH + x] = 0;
                }
            }
            for (level..SCREEN_HEIGHT) |y| {
                const sy = y - level;
                for (0..SCREEN_WIDTH) |x| {
                    framebuffer[y * SCREEN_WIDTH + x] = palette565[screen_pixels[sy * SCREEN_WIDTH + x]];
                }
            }
        }
        g_w_shake_time -%= 1;
    } else {
        for (0..SCREEN_WIDTH * SCREEN_HEIGHT) |i| {
            framebuffer[i] = palette565[screen_pixels[i]];
        }
    }
}

// VIDEO_BackupScreen / VIDEO_RestoreScreen
pub fn backupScreen() void {
    @memcpy(&screen_bak_pixels, &screen_pixels);
}

pub fn restoreScreen() void {
    @memcpy(&screen_pixels, &screen_bak_pixels);
}

// VIDEO_ShakeScreen — schedule wShakeTime frames of vertical shaking with wShakeLevel pixels.
pub fn shakeScreen(shake_time: u16, shake_level: u16) void {
    g_w_shake_time = shake_time;
    g_w_shake_level = shake_level;
}

// VIDEO_FadeScreen — video.c L1130. Cross-fade from screen_bak (backup) to
// screen (current) over 12 × 6 steps using the SDLPAL low-nibble blend.
// Destroys screen_bak. Assumes the caller already populated screen with the
// new content and screen_bak with the old.
pub fn fadeScreen(speed_in: u16) void {
    const util = @import("util.zig");
    const input = @import("input.zig");

    const rg_index = [_]usize{ 0, 3, 1, 5, 2, 4 };

    var speed: u32 = @as(u32, speed_in) + 1;
    speed *= 10;

    var time = util.getTicks();
    var i: u32 = 0;
    while (i < 12) : (i += 1) {
        var j: u32 = 0;
        while (j < 6) : (j += 1) {
            input.processEvent();
            while (util.getTicks() < time) {
                input.processEvent();
                util.delay(5);
            }
            time = util.getTicks() + speed;

            var k: usize = rg_index[j];
            while (k < SCREEN_WIDTH * SCREEN_HEIGHT) : (k += 6) {
                const a = screen_pixels[k];
                var b = screen_bak_pixels[k];
                if (i > 0) {
                    if ((a & 0x0F) > (b & 0x0F)) {
                        b +%= 1;
                    } else if ((a & 0x0F) < (b & 0x0F)) {
                        b -%= 1;
                    }
                }
                screen_bak_pixels[k] = (a & 0xF0) | (b & 0x0F);
            }

            // Push the blended buffer to display via the public path.
            const saved = screen_pixels;
            @memcpy(&screen_pixels, &screen_bak_pixels);
            updateScreen(null);
            @memcpy(&screen_pixels, &saved);
        }
    }

    // Final state: screen contains the target.
    updateScreen(null);
}

// VIDEO_SwitchScreen — video.c:1056. 6-step pixel-stride replacement from
// screen_bak (old) to screen (new). Each step copies every 6th pixel from
// the new buffer into the backup along the index sequence {0,3,1,5,2,4} so
// the transition feels like a sparse fade. Each step waits (speed+1)*10 ms.
// Destroys screen_bak. Used at battle entry to swap world view → battle.
pub fn switchScreen(speed_in: u16) void {
    const util = @import("util.zig");

    const rg_index = [_]usize{ 0, 3, 1, 5, 2, 4 };
    const wait_ms: u32 = (@as(u32, speed_in) + 1) * 10;

    var i: u32 = 0;
    while (i < 6) : (i += 1) {
        var k: usize = rg_index[i];
        while (k < SCREEN_WIDTH * SCREEN_HEIGHT) : (k += 6) {
            screen_bak_pixels[k] = screen_pixels[k];
        }

        const saved = screen_pixels;
        @memcpy(&screen_pixels, &screen_bak_pixels);
        updateScreen(null);
        @memcpy(&screen_pixels, &saved);

        util.delay(wait_ms);
    }

    updateScreen(null);
}
