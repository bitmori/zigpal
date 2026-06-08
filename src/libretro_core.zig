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
const video = @import("video.zig");
const input = @import("input.zig");
const util = @import("util.zig");
const audio = @import("audio.zig");

const c = @cImport({
    @cInclude("libretro.h");
});

const SCREEN_WIDTH = video.SCREEN_WIDTH;
const SCREEN_HEIGHT = video.SCREEN_HEIGHT;

var video_cb: c.retro_video_refresh_t = null;
var audio_cb: c.retro_audio_sample_t = null;
var audio_batch_cb: c.retro_audio_sample_batch_t = null;
var input_poll_cb: c.retro_input_poll_t = null;
var input_state_cb: c.retro_input_state_t = null;
var environ_cb: c.retro_environment_t = null;

var game_thread: ?std.Thread = null;
// Quit flag now lives in util.zig (so util.delay can poll it). Re-export here
// for any caller that already imports libretro_core.
pub const quit_flag = &util.quit_flag;
var loaded: bool = false;
pub var system_dir: ?[]const u8 = null;

// --- libretro API exports ---

export fn retro_set_environment(cb: c.retro_environment_t) void {
    environ_cb = cb;
    var no_content: bool = true;
    if (cb) |env| {
        _ = env(c.RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME, @ptrCast(&no_content));
    }
}

export fn retro_set_video_refresh(cb: c.retro_video_refresh_t) void {
    video_cb = cb;
}

export fn retro_set_audio_sample(cb: c.retro_audio_sample_t) void {
    audio_cb = cb;
}

export fn retro_set_audio_sample_batch(cb: c.retro_audio_sample_batch_t) void {
    audio_batch_cb = cb;
}

export fn retro_set_input_poll(cb: c.retro_input_poll_t) void {
    input_poll_cb = cb;
}

export fn retro_set_input_state(cb: c.retro_input_state_t) void {
    input_state_cb = cb;
}

export fn retro_init() void {}
export fn retro_deinit() void {}

export fn retro_api_version() c_uint {
    return c.RETRO_API_VERSION;
}

export fn retro_get_system_info(info: *c.retro_system_info) void {
    info.library_name = "zigpal";
    info.library_version = "0.3.0";
    info.need_fullpath = true;
    info.valid_extensions = "mkf|MKF";
    info.block_extract = false;
}

export fn retro_get_system_av_info(info: *c.retro_system_av_info) void {
    info.geometry.base_width = SCREEN_WIDTH;
    info.geometry.base_height = SCREEN_HEIGHT;
    info.geometry.max_width = SCREEN_WIDTH;
    info.geometry.max_height = SCREEN_HEIGHT;
    info.geometry.aspect_ratio = 320.0 / 200.0;
    info.timing.fps = 60.0;
    info.timing.sample_rate = 44100.0;
}

export fn retro_set_controller_port_device(_: c_uint, _: c_uint) void {}

export fn retro_reset() void {}

// --- Frame time callback (advances virtual ticks) ---
// libretro's frame_time_callback is optional and not all frontends call it
// (RetroArch only does so when explicitly requested by the core's environment
// negotiation, and even then not always). We use it if available, else fall
// back to a fixed 1000/60 ms advance per retro_run call.

var frame_time_cb_active: bool = false;

fn frameTimeCallback(usec: c.retro_usec_t) callconv(.c) void {
    frame_time_cb_active = true;
    const ms: i64 = @divTrunc(usec, 1000);
    if (ms > 0) util.advanceTicks(@intCast(ms));
}

// --- Main frame ---

export fn retro_run() void {
    if (input_poll_cb) |poll| poll();

    pumpJoypadInput();
    pumpDebugKeys();

    // If the frontend isn't driving frame_time_callback, advance ticks ourselves.
    if (!frame_time_cb_active) {
        util.advanceTicks(1000 / 60);
    }

    if (video_cb) |cb| {
        cb(&video.framebuffer, SCREEN_WIDTH, SCREEN_HEIGHT, SCREEN_WIDTH * 2);
    }

    audio.produce(audio_batch_cb);
}

fn pumpJoypadInput() void {
    const sf = input_state_cb orelse return;

    var keys: u32 = 0;
    // D-pad — movement / menu cursor. Same on every screen.
    if (sf(0, c.RETRO_DEVICE_JOYPAD, 0, c.RETRO_DEVICE_ID_JOYPAD_UP) != 0) keys |= input.KEY_UP;
    if (sf(0, c.RETRO_DEVICE_JOYPAD, 0, c.RETRO_DEVICE_ID_JOYPAD_DOWN) != 0) keys |= input.KEY_DOWN;
    if (sf(0, c.RETRO_DEVICE_JOYPAD, 0, c.RETRO_DEVICE_ID_JOYPAD_LEFT) != 0) keys |= input.KEY_LEFT;
    if (sf(0, c.RETRO_DEVICE_JOYPAD, 0, c.RETRO_DEVICE_ID_JOYPAD_RIGHT) != 0) keys |= input.KEY_RIGHT;
    // Face buttons.
    if (sf(0, c.RETRO_DEVICE_JOYPAD, 0, c.RETRO_DEVICE_ID_JOYPAD_A) != 0) keys |= input.KEY_SEARCH;
    if (sf(0, c.RETRO_DEVICE_JOYPAD, 0, c.RETRO_DEVICE_ID_JOYPAD_B) != 0) keys |= input.KEY_MENU;
    if (sf(0, c.RETRO_DEVICE_JOYPAD, 0, c.RETRO_DEVICE_ID_JOYPAD_X) != 0) keys |= input.KEY_DEFEND;
    if (sf(0, c.RETRO_DEVICE_JOYPAD, 0, c.RETRO_DEVICE_ID_JOYPAD_Y) != 0) keys |= input.KEY_USEITEM;
    // Start / Select.
    if (sf(0, c.RETRO_DEVICE_JOYPAD, 0, c.RETRO_DEVICE_ID_JOYPAD_START) != 0) keys |= input.KEY_STATUS;
    if (sf(0, c.RETRO_DEVICE_JOYPAD, 0, c.RETRO_DEVICE_ID_JOYPAD_SELECT) != 0) keys |= input.KEY_INFO;
    // Shoulders + triggers + sticks.
    if (sf(0, c.RETRO_DEVICE_JOYPAD, 0, c.RETRO_DEVICE_ID_JOYPAD_L) != 0) keys |= input.KEY_PGUP;
    if (sf(0, c.RETRO_DEVICE_JOYPAD, 0, c.RETRO_DEVICE_ID_JOYPAD_R) != 0) keys |= input.KEY_PGDN;
    if (sf(0, c.RETRO_DEVICE_JOYPAD, 0, c.RETRO_DEVICE_ID_JOYPAD_L2) != 0) keys |= input.KEY_THROWITEM;
    if (sf(0, c.RETRO_DEVICE_JOYPAD, 0, c.RETRO_DEVICE_ID_JOYPAD_R2) != 0) keys |= input.KEY_REPEAT;
    if (sf(0, c.RETRO_DEVICE_JOYPAD, 0, c.RETRO_DEVICE_ID_JOYPAD_L3) != 0) keys |= input.KEY_AUTO;
    if (sf(0, c.RETRO_DEVICE_JOYPAD, 0, c.RETRO_DEVICE_ID_JOYPAD_R3) != 0) keys |= input.KEY_FLEE;

    input.raw_keys.store(keys, .monotonic);
}

// Backslash opens the debug menu (RetroArch doesn't grab it as a hotkey).
// Everything else — battle trigger, battlefield cycle, etc — has moved into
// the menu itself so we only need one global key.
var debug_key_prev: bool = false;
fn pumpDebugKeys() void {
    const sf = input_state_cb orelse return;
    const now = sf(0, c.RETRO_DEVICE_KEYBOARD, 0, c.RETROK_BACKSLASH) != 0;
    if (now and !debug_key_prev) {
        @import("debug.zig").requestMenu();
    }
    debug_key_prev = now;
}

export fn zigpalKeyboardEvent(down: bool, keycode: c_uint, character: u32, key_modifiers: u16) void {
    _ = character;
    _ = key_modifiers;
    if (!down) return;
    if (keycode == c.RETROK_BACKSLASH) {
        @import("debug.zig").requestMenu();
    }
}

// --- Load/Unload ---

export fn retro_load_game(info: ?*const c.retro_game_info) bool {
    _ = info;

    var fmt: c_uint = c.RETRO_PIXEL_FORMAT_RGB565;
    if (environ_cb) |env| {
        _ = env(c.RETRO_ENVIRONMENT_SET_PIXEL_FORMAT, @ptrCast(&fmt));
    }

    // Register frame time callback to drive virtual ticks.
    var ftc: c.retro_frame_time_callback = .{
        .callback = frameTimeCallback,
        .reference = 1000000 / 60, // 60fps reference
    };
    if (environ_cb) |env| {
        _ = env(c.RETRO_ENVIRONMENT_SET_FRAME_TIME_CALLBACK, @ptrCast(&ftc));
    }

    // Keyboard callback — receives raw key events even when RetroArch's hotkey
    // filter would otherwise eat them. Used for the debug overlay toggle.
    var kbc: c.retro_keyboard_callback = .{ .callback = zigpalKeyboardEvent };
    if (environ_cb) |env| {
        _ = env(c.RETRO_ENVIRONMENT_SET_KEYBOARD_CALLBACK, @ptrCast(&kbc));
    }

    // Locate the system directory (RetroArch system dir).
    var sys_dir_ptr: [*:0]const u8 = undefined;
    if (environ_cb) |env| {
        if (env(c.RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY, @ptrCast(&sys_dir_ptr))) {
            system_dir = std.mem.span(sys_dir_ptr);
        }
    }

    quit_flag.store(false, .monotonic);
    loaded = true;

    // Audio init must happen after the game thread loads MUS.MKF, but the
    // game thread runs asynchronously — instead we let init() be lazy and
    // pick up res_buffers.mus the first time it's called. The first
    // playMusic() from script will trigger init via produce()'s null check.
    // Spawn the game thread. The thread runs PAL_GameMain (in main.zig),
    // which loops indefinitely on virtual ticks.
    game_thread = std.Thread.spawn(.{}, gameThreadEntry, .{}) catch return false;

    return true;
}

fn gameThreadEntry() void {
    const main_mod = @import("main.zig");
    main_mod.gameMain() catch |err| {
        std.log.err("game thread crashed: {}", .{err});
    };
}

export fn retro_load_game_special(_: c_uint, _: [*]const c.retro_game_info, _: usize) bool {
    return false;
}

export fn retro_unload_game() void {
    quit_flag.store(true, .monotonic);
    if (game_thread) |t| {
        t.join();
        game_thread = null;
    }
    audio.deinit();
    loaded = false;
}

export fn retro_get_region() c_uint {
    return c.RETRO_REGION_NTSC;
}

export fn retro_serialize_size() usize {
    return 0;
}

export fn retro_serialize(_: ?*anyopaque, _: usize) bool {
    return false;
}

export fn retro_unserialize(_: ?*const anyopaque, _: usize) bool {
    return false;
}

export fn retro_cheat_reset() void {}
export fn retro_cheat_set(_: c_uint, _: bool, _: ?[*:0]const u8) void {}

export fn retro_get_memory_data(_: c_uint) ?*anyopaque {
    return null;
}

export fn retro_get_memory_size(_: c_uint) usize {
    return 0;
}
