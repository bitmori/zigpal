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
const global = @import("global.zig");
const video = @import("video.zig");
const input = @import("input.zig");
const util = @import("util.zig");
const palcommon = @import("palcommon.zig");
const palette_mod = @import("palette.zig");
const libretro_core = @import("libretro_core.zig");
const res = @import("res.zig");
const play = @import("play.zig");


// PAL_GameMain — the game thread entry point.
//
// Mirrors game.c PAL_GameMain():
//   bCurrentSaveSlot = PAL_OpeningMenu();
//   PAL_ReloadInNextTick(bCurrentSaveSlot);
//   while (TRUE) {
//     PAL_LoadResources();
//     PAL_ClearKeyState();
//     PAL_DelayUntil(dwTime);
//     dwTime = SDL_GetTicks() + FRAME_TIME;
//     PAL_StartFrame();
//   }
pub fn gameMain() !void {
    try palInit();

    // PAL_TrademarkScreen / PAL_SplashScreen — both honour `pal/NO_SPLASH` to
    // short-circuit the intro for fast boot during dev.
    @import("splash.zig").trademarkScreen();
    @import("splash.zig").splashScreen();

    // PAL_OpeningMenu — present new game / load game choice. Stage 6e-7.
    const slot_choice = @import("uigame.zig").openingMenu();
    const save_slot: u8 = if (slot_choice <= 0) 0 else @intCast(slot_choice);
    global.gpg.current_save_slot = save_slot;
    global.gpg.in_main_game = true;

    // PAL_ReloadInNextTick — schedule data load on next frame.
    global.reloadInNextTick(save_slot);

    var dw_time = util.getTicks();
    while (!libretro_core.quit_flag.load(.monotonic)) {
        // PAL_LoadResources
        res.loadResources() catch |err| {
            std.log.err("PAL_LoadResources failed: {}", .{err});
            return;
        };

        input.clearKeyState();

        // PAL_DelayUntil + PAL_ProcessEvent on each tick.
        while (util.getTicks() < dw_time) {
            input.processEvent();
            std.Thread.yield() catch {};
            if (libretro_core.quit_flag.load(.monotonic)) return;
        }

        dw_time = util.getTicks() + global.FRAME_TIME;

        // PAL_StartFrame — gameUpdate inside already increments frame_num.
        play.startFrame();
    }
}

// PAL_Init — port of main.c PAL_Init (only the parts we need).
fn palInit() !void {
    input.initInput();
    res.initResources();

    const sys_dir = libretro_core.system_dir orelse {
        std.log.err("system directory not set", .{});
        return error.NoSystemDir;
    };

    var pal_dir_buf: [4096]u8 = undefined;
    const pal_dir = try std.fmt.bufPrint(&pal_dir_buf, "{s}/pal", .{sys_dir});

    try loadAllResourceFiles(pal_dir);

    // Order matters: SSS chunk 3 (msg index) needs gpg.f.sss already populated
    // by loadAllResourceFiles, and ui.zig needs DATA.MKF chunk 9.
    try @import("ui.zig").initUI();
    try @import("text.zig").initText();
    @import("objectdesc.zig").load();
}

fn loadAllResourceFiles(base_dir: []const u8) !void {
    const alloc = global.allocator;

    const Pair = struct { name: []const u8, dst: *?[]u8, mkf: ?*?palcommon.MkfFile };
    const pairs = [_]Pair{
        .{ .name = "PAT.MKF", .dst = &global.res_buffers.pat, .mkf = &global.gpg.f.pat },
        .{ .name = "FBP.MKF", .dst = &global.res_buffers.fbp, .mkf = &global.gpg.f.fbp },
        .{ .name = "MGO.MKF", .dst = &global.res_buffers.mgo, .mkf = &global.gpg.f.mgo },
        .{ .name = "BALL.MKF", .dst = &global.res_buffers.ball, .mkf = &global.gpg.f.ball },
        .{ .name = "DATA.MKF", .dst = &global.res_buffers.data, .mkf = &global.gpg.f.data },
        .{ .name = "F.MKF", .dst = &global.res_buffers.f, .mkf = &global.gpg.f.f },
        .{ .name = "FIRE.MKF", .dst = &global.res_buffers.fire, .mkf = &global.gpg.f.fire },
        .{ .name = "RGM.MKF", .dst = &global.res_buffers.rgm, .mkf = &global.gpg.f.rgm },
        .{ .name = "SSS.MKF", .dst = &global.res_buffers.sss, .mkf = &global.gpg.f.sss },
        .{ .name = "ABC.MKF", .dst = &global.res_buffers.abc, .mkf = &global.gpg.f.abc },
        .{ .name = "MAP.MKF", .dst = &global.res_buffers.map, .mkf = &global.gpg.f.map },
        .{ .name = "GOP.MKF", .dst = &global.res_buffers.gop, .mkf = &global.gpg.f.gop },
        .{ .name = "RNG.MKF", .dst = &global.res_buffers.rng, .mkf = &global.gpg.f.rng },
        .{ .name = "WORD.DAT", .dst = &global.res_buffers.word, .mkf = null },
        .{ .name = "M.MSG", .dst = &global.res_buffers.msg, .mkf = null },
        .{ .name = "WOR16.ASC", .dst = &global.res_buffers.asc, .mkf = null },
        .{ .name = "WOR16.FON", .dst = &global.res_buffers.fon, .mkf = null },
    };

    inline for (pairs) |p| {
        if (try readFile(alloc, base_dir, p.name)) |buf| {
            p.dst.* = buf;
            if (p.mkf) |slot| slot.* = palcommon.MkfFile.fromMemory(buf);
        }
    }

    if (global.res_buffers.pat) |buf| {
        palette_mod.init(buf);
    } else {
        return error.PatMkfMissing;
    }

    @import("font.zig").init(global.res_buffers.asc, global.res_buffers.fon);
}

fn readFile(alloc: std.mem.Allocator, base_dir: []const u8, name: []const u8) !?[]u8 {
    var path_buf: [4096]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/{s}\x00", .{ base_dir, name });
    const path_z: [*:0]const u8 = path_buf[0 .. path.len - 1 :0];
    return util.readFileFully(path_z, alloc);
}
