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

pub const Direction = palcommon.Direction;

// PALKEY bit flags from input.h
pub const KEY_NONE: u32 = 0;
pub const KEY_MENU: u32 = 1 << 0;
pub const KEY_SEARCH: u32 = 1 << 1;
pub const KEY_DOWN: u32 = 1 << 2;
pub const KEY_LEFT: u32 = 1 << 3;
pub const KEY_UP: u32 = 1 << 4;
pub const KEY_RIGHT: u32 = 1 << 5;
pub const KEY_PGUP: u32 = 1 << 6;
pub const KEY_PGDN: u32 = 1 << 7;
pub const KEY_REPEAT: u32 = 1 << 8;
pub const KEY_AUTO: u32 = 1 << 9;
pub const KEY_DEFEND: u32 = 1 << 10;
pub const KEY_USEITEM: u32 = 1 << 11;
pub const KEY_THROWITEM: u32 = 1 << 12;
pub const KEY_FLEE: u32 = 1 << 13;
pub const KEY_STATUS: u32 = 1 << 14;
pub const KEY_FORCE: u32 = 1 << 15;
pub const KEY_HOME: u32 = 1 << 16;
pub const KEY_END: u32 = 1 << 17;
// 魔改 — Z key in SDLPAL fork. On the world map opens the same status
// screen as KEY_STATUS; in battle it opens 《情報》(enemyinfo.show).
pub const KEY_INFO: u32 = 1 << 18;

// PALINPUTSTATE
pub const InputState = struct {
    dir: Direction = .unknown,
    prev_dir: Direction = .unknown,
    key_press: u32 = 0,
    key_order: [4]u32 = [_]u32{0} ** 4,
    key_max_count: u32 = 0,
};

pub var state: InputState = .{};

// Raw button state injected by libretro main thread (atomic).
// Bit layout matches PALKEY.
pub var raw_keys: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);

// Per-key last time for repeat detection.
var key_last_time: [32]u32 = [_]u32{0} ** 32;

// PAL_ClearKeyState
pub fn clearKeyState() void {
    state.key_press = 0;
}

// Forget any held direction. Used after scene transitions so the party doesn't
// take a stray step in the direction the player held while triggering the
// scene-change event. SDLPAL gets away without this because of how its event
// pump fires per OS key event; our raw-keys polling keeps dir set as long as
// the key is held, which would otherwise walk one tile on the new scene.
pub fn forgetDirection() void {
    state.dir = .unknown;
    state.prev_dir = .unknown;
    state.key_order = [_]u32{0} ** 4;
    state.key_max_count = 0;
    // Force key-down logic to re-fire when the key next polls as pressed —
    // otherwise key_last_time != 0 means we never call keyDown again.
    for (&key_last_time) |*t| t.* = 0;
}

// PAL_InitInput
pub fn initInput() void {
    state = .{};
    state.dir = .unknown;
    state.prev_dir = .unknown;
}

// PAL_ShutdownInput
pub fn shutdownInput() void {}

fn getCurrDirection() Direction {
    var curr_dir: usize = @intFromEnum(Direction.south);
    var i: usize = 1;
    while (i < state.key_order.len) : (i += 1) {
        if (state.key_order[curr_dir] < state.key_order[i]) curr_dir = i;
    }
    if (state.key_order[curr_dir] == 0) return .unknown;
    return @enumFromInt(curr_dir);
}

fn keyDown(key: u32, repeat: bool) void {
    var curr_dir: ?Direction = null;

    if (!repeat) {
        if ((key & KEY_DOWN) != 0) curr_dir = .south
        else if ((key & KEY_LEFT) != 0) curr_dir = .west
        else if ((key & KEY_UP) != 0) curr_dir = .north
        else if ((key & KEY_RIGHT) != 0) curr_dir = .east;

        if (curr_dir) |dir| {
            state.key_max_count += 1;
            state.key_order[@intFromEnum(dir)] = state.key_max_count;
            state.dir = getCurrDirection();
        }
    }

    state.key_press |= key;
}

fn keyUp(key: u32) void {
    var curr_dir: ?Direction = null;
    if ((key & KEY_DOWN) != 0) curr_dir = .south
    else if ((key & KEY_LEFT) != 0) curr_dir = .west
    else if ((key & KEY_UP) != 0) curr_dir = .north
    else if ((key & KEY_RIGHT) != 0) curr_dir = .east;

    if (curr_dir) |dir| {
        state.key_order[@intFromEnum(dir)] = 0;
        const new_dir = getCurrDirection();
        state.key_max_count = if (new_dir == .unknown) 0 else state.key_order[@intFromEnum(new_dir)];
        state.dir = new_dir;
    }
}

// All keys we listen to (bit index → mask).
const all_keys = [_]u32{
    KEY_MENU, KEY_SEARCH, KEY_DOWN, KEY_LEFT, KEY_UP, KEY_RIGHT,
    KEY_PGUP, KEY_PGDN, KEY_REPEAT, KEY_AUTO, KEY_DEFEND, KEY_USEITEM,
    KEY_THROWITEM, KEY_FLEE, KEY_STATUS, KEY_FORCE, KEY_HOME, KEY_END,
    KEY_INFO,
};

// PAL_ProcessEvent — translate raw_keys bitmap into InputState updates.
// Implements key repeat similar to PAL_UpdateKeyboardState.
pub fn processEvent() void {
    const util = @import("util.zig");
    const cur_keys = raw_keys.load(.monotonic);
    const now = util.getTicks();
    const REPEAT_DELAY: u32 = 200;
    const REPEAT_INTERVAL: u32 = 75;

    for (all_keys, 0..) |mask, i| {
        const pressed = (cur_keys & mask) != 0;
        if (pressed) {
            if (now > key_last_time[i]) {
                const repeat = key_last_time[i] != 0;
                keyDown(mask, repeat);
                key_last_time[i] = now + (if (key_last_time[i] == 0) REPEAT_DELAY else REPEAT_INTERVAL);
            }
        } else {
            if (key_last_time[i] != 0) {
                keyUp(mask);
                key_last_time[i] = 0;
            }
        }
    }
}
