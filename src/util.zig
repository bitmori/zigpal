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

// Virtual time, advanced by frame_time_callback in libretro_core.zig.
// Emulates SDL_GetTicks().
var ticks_atomic: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);

// Quit flag — libretro_core.retro_unload_game sets this to true. Lives here
// (rather than libretro_core.zig) so util.delay can check it without creating
// a circular import.
pub var quit_flag: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

pub fn getTicks() u32 {
    return ticks_atomic.load(.monotonic);
}

pub fn advanceTicks(delta_ms: u32) void {
    _ = ticks_atomic.fetchAdd(delta_ms, .monotonic);
}

pub fn shouldQuit() bool {
    return quit_flag.load(.monotonic);
}

// UTIL_Delay - busy wait for ms milliseconds of virtual time.
// Yields the thread to allow main thread to advance ticks. Returns early if
// the core is being unloaded so the game thread can exit promptly.
pub fn delay(ms: u32) void {
    const target = getTicks() + ms;
    while (getTicks() < target) {
        if (shouldQuit()) return;
        std.Thread.yield() catch {};
    }
}

// PAL_DelayUntil - wait until virtual time reaches `target`.
pub fn delayUntil(target: u32) void {
    while (getTicks() < target) {
        if (shouldQuit()) return;
        std.Thread.yield() catch {};
    }
}

// RandomLong: returns a pseudo-random integer in [from, to] inclusive.
// PCG-like LCG. Only the game thread calls this, so no synchronization needed.
var rng_state: u64 = 0xdeadbeefcafe;

fn nextRand() u32 {
    rng_state = rng_state *% 6364136223846793005 +% 1442695040888963407;
    return @truncate(rng_state >> 33);
}

pub fn randomLong(from: i32, to: i32) i32 {
    const range: u32 = @intCast(to - from + 1);
    return from + @as(i32, @intCast(nextRand() % range));
}

pub fn randomFloat() f32 {
    return @as(f32, @floatFromInt(nextRand() % 0x10000)) / @as(f32, 0x10000);
}

// SDLPAL's RandomFloat(min, max) — uniform float in [min, max].
pub fn randomFloatRange(min: f32, max: f32) f32 {
    return min + (max - min) * randomFloat();
}

// Logging
pub fn logInfo(comptime fmt: []const u8, args: anytype) void {
    std.log.info(fmt, args);
}

pub fn logError(comptime fmt: []const u8, args: anytype) void {
    std.log.err(fmt, args);
}

// File I/O — slurp a file at the given absolute zero-terminated path into an
// allocator-owned buffer. Returns null on any error. We use std.c (libc) here
// because Zig 0.16's std.fs API requires an Io instance that's awkward to
// thread through a libretro core; libc is already linked.
pub fn readFileFully(path_z: [*:0]const u8, alloc: std.mem.Allocator) ?[]u8 {
    const c = std.c;
    const fd = c.open(path_z, .{ .ACCMODE = .RDONLY });
    if (fd < 0) return null;
    defer _ = c.close(fd);

    const end_off = c.lseek(fd, 0, c.SEEK.END);
    if (end_off <= 0) return null;
    const size: usize = @intCast(end_off);
    if (c.lseek(fd, 0, c.SEEK.SET) < 0) return null;

    const buf = alloc.alloc(u8, size) catch return null;

    var total: usize = 0;
    while (total < size) {
        const n = c.read(fd, buf.ptr + total, size - total);
        if (n <= 0) {
            alloc.free(buf);
            return null;
        }
        total += @intCast(n);
    }
    return buf;
}
