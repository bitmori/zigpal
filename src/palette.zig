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
const video = @import("video.zig");
const util = @import("util.zig");
const MkfFile = palcommon.MkfFile;

pub const Color = video.Color;
pub const Palette = [256]Color;

var pat_mkf: ?MkfFile = null;

pub fn init(pat_data: []const u8) void {
    pat_mkf = MkfFile.fromMemory(pat_data);
}

// PAL_GetPalette
pub fn get(palette_num: i32, night: bool) ?*const Palette {
    const S = struct {
        var palette: Palette = [_]Color{.{ .r = 0xff, .g = 0xff, .b = 0xff }} ** 256;
    };

    const mkf = pat_mkf orelse return null;

    var buf: [1536]u8 = undefined;
    const bytes_read = mkf.readChunk(&buf, @intCast(palette_num)) catch return null;

    var use_night = night;
    if (bytes_read <= 256 * 3) use_night = false;

    const offset: usize = if (use_night) 256 * 3 else 0;
    for (0..256) |i| {
        S.palette[i].r = buf[offset + i * 3] << 2;
        S.palette[i].g = buf[offset + i * 3 + 1] << 2;
        S.palette[i].b = buf[offset + i * 3 + 2] << 2;
    }
    return &S.palette;
}

// PAL_SetPalette — install palette by number.
pub fn setPalette(palette_num: i32, night: bool) void {
    if (get(palette_num, night)) |p| video.setPalette(p.*);
}

// PAL_FadeOut — fade screen palette to black.
// SDLPAL relies on SDL's 8-bit surface to live-render with the new palette;
// our RGB565 framebuffer needs an explicit updateScreen each step so the user
// can actually see the gradient.
pub fn fadeOut(delay_in: i32) void {
    var delay = delay_in;
    if (delay == 0) delay = 1;

    const palette: Palette = video.current_palette;

    const total: u32 = @as(u32, @intCast(delay)) * 10 * 60;
    const start = util.getTicks();
    const target = start +% total;

    while (true) {
        const now = util.getTicks();
        const elapsed = now -% start;
        if (elapsed >= total) break;
        const remaining = target -% now;
        const j: i32 = @intCast(remaining / @as(u32, @intCast(delay)) / 10);
        if (j < 0) break;

        var newpalette: Palette = undefined;
        for (0..256) |i| {
            newpalette[i] = .{
                .r = @intCast((@as(u32, palette[i].r) * @as(u32, @intCast(j))) >> 6),
                .g = @intCast((@as(u32, palette[i].g) * @as(u32, @intCast(j))) >> 6),
                .b = @intCast((@as(u32, palette[i].b) * @as(u32, @intCast(j))) >> 6),
            };
        }
        video.setPalette(newpalette);
        video.updateScreen(null);
        util.delay(10);
    }

    var black: Palette = [_]Color{.{}} ** 256;
    _ = &black;
    video.setPalette(black);
    video.updateScreen(null);
}

// PAL_FadeIn — fade screen palette in to the specified palette.
pub fn fadeIn(palette_num: i32, night: bool, delay_in: i32) void {
    var delay = delay_in;
    if (delay == 0) delay = 1;

    const target_pal = get(palette_num, night) orelse return;

    const total: u32 = @as(u32, @intCast(delay)) * 10 * 60;
    const start = util.getTicks();
    const target = start +% total;

    while (true) {
        const now = util.getTicks();
        if (now -% start >= total) break;
        const remaining = target -% now;
        var j: i32 = @intCast(remaining / @as(u32, @intCast(delay)) / 10);
        if (j < 0) break;
        j = 60 - j;

        var newpalette: Palette = undefined;
        for (0..256) |i| {
            newpalette[i] = .{
                .r = @intCast((@as(u32, target_pal[i].r) * @as(u32, @intCast(j))) >> 6),
                .g = @intCast((@as(u32, target_pal[i].g) * @as(u32, @intCast(j))) >> 6),
                .b = @intCast((@as(u32, target_pal[i].b) * @as(u32, @intCast(j))) >> 6),
            };
        }
        video.setPalette(newpalette);
        video.updateScreen(null);
        util.delay(10);
    }

    video.setPalette(target_pal.*);
    video.updateScreen(null);
}

// PAL_FadeToRed — palette.c L595. Fade the screen to a red-tinted version of
// the current palette over 32 steps. SDLPAL also rewrites pixel value 0x4F
// to 0x4E in the framebuffer (so palette index 0x4F can be reserved for text
// that survives the fade).
pub fn fadeToRed() void {
    const palette = video.current_palette;
    var newpalette: Palette = palette;

    // HACKHACK: SDLPAL: rewrite 0x4F → 0x4E so 0x4F can stay legible.
    for (&video.screen_pixels) |*p| {
        if (p.* == 0x4F) p.* = 0x4E;
    }
    video.updateScreen(null);

    var i: u32 = 0;
    while (i < 32) : (i += 1) {
        var j: usize = 0;
        while (j < 256) : (j += 1) {
            if (j == 0x4F) continue;

            const r: i32 = palette[j].r;
            const g: i32 = palette[j].g;
            const b: i32 = palette[j].b;
            const target_r: i32 = @divTrunc(r + g + b, 4) + 64;

            if (newpalette[j].r > target_r) {
                const diff = @as(i32, newpalette[j].r) - target_r;
                newpalette[j].r -= @intCast(if (diff > 8) 8 else diff);
            } else if (newpalette[j].r < target_r) {
                const diff = target_r - @as(i32, newpalette[j].r);
                const add: u8 = @intCast(if (diff > 8) 8 else diff);
                if (255 - newpalette[j].r >= add) newpalette[j].r += add else newpalette[j].r = 255;
            }

            if (newpalette[j].g > 0) {
                newpalette[j].g -= @intCast(if (newpalette[j].g > 8) @as(u8, 8) else newpalette[j].g);
            }
            if (newpalette[j].b > 0) {
                newpalette[j].b -= @intCast(if (newpalette[j].b > 8) @as(u8, 8) else newpalette[j].b);
            }
        }
        video.setPalette(newpalette);
        video.updateScreen(null);
        util.delay(75);
    }
}

// PAL_PaletteFade — cross-fade from current to target palette.
pub fn paletteFade(palette_num: i32, night: bool, update_scene: bool) void {
    const newpalette = get(palette_num, night) orelse return;
    const oldpalette = video.current_palette;
    const global = @import("global.zig");
    const play = @import("play.zig");
    const scene_mod = @import("scene.zig");
    const input = @import("input.zig");

    var i: i32 = 0;
    while (i < 32) : (i += 1) {
        const time_target = util.getTicks() + (if (update_scene) global.FRAME_TIME else global.FRAME_TIME / 4);

        var t: Palette = undefined;
        for (0..256) |k| {
            t[k] = .{
                .r = @intCast(@divTrunc(@as(i32, oldpalette[k].r) * (31 - i) + @as(i32, newpalette[k].r) * i, 31)),
                .g = @intCast(@divTrunc(@as(i32, oldpalette[k].g) * (31 - i) + @as(i32, newpalette[k].g) * i, 31)),
                .b = @intCast(@divTrunc(@as(i32, oldpalette[k].b) * (31 - i) + @as(i32, newpalette[k].b) * i, 31)),
            };
        }
        video.setPalette(t);

        if (update_scene) {
            input.clearKeyState();
            input.state.dir = .unknown;
            input.state.prev_dir = .unknown;
            play.gameUpdate(false);
            scene_mod.makeScene();
            video.updateScreen(null);
        }

        util.delayUntil(time_target);
    }
}

// PAL_SceneFade — fade in or fade out the screen, updating the scene each step.
pub fn sceneFade(palette_num: i32, night: bool, step_in: i32) void {
    const palette = get(palette_num, night) orelse return;
    var step = step_in;
    if (step == 0) step = 1;

    const global = @import("global.zig");
    const play = @import("play.zig");
    const scene_mod = @import("scene.zig");
    const input = @import("input.zig");

    global.gpg.need_to_fade_in = false;

    if (step > 0) {
        var i: i32 = 0;
        while (i < 64) : (i += step) {
            const time_target = util.getTicks() + 100;

            input.clearKeyState();
            input.state.dir = .unknown;
            input.state.prev_dir = .unknown;
            play.gameUpdate(false);
            scene_mod.makeScene();
            video.updateScreen(null);

            var newp: Palette = undefined;
            for (0..256) |k| {
                newp[k] = .{
                    .r = @intCast((@as(i32, palette[k].r) * i) >> 6),
                    .g = @intCast((@as(i32, palette[k].g) * i) >> 6),
                    .b = @intCast((@as(i32, palette[k].b) * i) >> 6),
                };
            }
            video.setPalette(newp);

            util.delayUntil(time_target);
        }
    } else {
        var i: i32 = 63;
        while (i >= 0) : (i += step) {
            const time_target = util.getTicks() + 100;

            input.clearKeyState();
            input.state.dir = .unknown;
            input.state.prev_dir = .unknown;
            play.gameUpdate(false);
            scene_mod.makeScene();
            video.updateScreen(null);

            var newp: Palette = undefined;
            for (0..256) |k| {
                newp[k] = .{
                    .r = @intCast((@as(i32, palette[k].r) * i) >> 6),
                    .g = @intCast((@as(i32, palette[k].g) * i) >> 6),
                    .b = @intCast((@as(i32, palette[k].b) * i) >> 6),
                };
            }
            video.setPalette(newp);

            util.delayUntil(time_target);
        }
    }
}

// PAL_ColorFade — fade palette from/to the specified color.
pub fn colorFade(delay_in: i32, color: u8, from_color: bool) void {
    const global = @import("global.zig");
    const palette = get(@intCast(global.gpg.num_palette), global.gpg.night_palette) orelse return;
    var delay: i32 = delay_in * 10;
    if (delay == 0) delay = 10;

    var newp: Palette = undefined;

    if (from_color) {
        for (0..256) |i| newp[i] = palette[color];

        var step: i32 = 0;
        while (step < 64) : (step += 1) {
            for (0..256) |j| {
                if (newp[j].r > palette[j].r) newp[j].r -= 4
                else if (newp[j].r < palette[j].r) newp[j].r += 4;
                if (newp[j].g > palette[j].g) newp[j].g -= 4
                else if (newp[j].g < palette[j].g) newp[j].g += 4;
                if (newp[j].b > palette[j].b) newp[j].b -= 4
                else if (newp[j].b < palette[j].b) newp[j].b += 4;
            }
            video.setPalette(newp);
            video.updateScreen(null);
            util.delay(@intCast(delay));
        }
        video.setPalette(palette.*);
        video.updateScreen(null);
    } else {
        newp = palette.*;
        var step: i32 = 0;
        while (step < 64) : (step += 1) {
            for (0..256) |j| {
                if (newp[j].r > palette[color].r) newp[j].r -= 4
                else if (newp[j].r < palette[color].r) newp[j].r += 4;
                if (newp[j].g > palette[color].g) newp[j].g -= 4
                else if (newp[j].g < palette[color].g) newp[j].g += 4;
                if (newp[j].b > palette[color].b) newp[j].b -= 4
                else if (newp[j].b < palette[color].b) newp[j].b += 4;
            }
            video.setPalette(newp);
            video.updateScreen(null);
            util.delay(@intCast(delay));
        }
        for (0..256) |i| newp[i] = palette[color];
        video.setPalette(newp);
        video.updateScreen(null);
    }
}
