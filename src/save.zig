// Copyright (c) 2009-2011, Wei Mingzhi <whistler_wmz@users.sf.net>.
// Copyright (c) 2011-2026, SDLPAL development team.
// All rights reserved.
//
// This file is part of SDLPAL.
//
// SDLPAL is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License, version 3
// as published by the Free Software Foundation.

// PAL_SaveGame / PAL_LoadGame — DOS-format save files (`<slot>.rpg`).
//
// Layout mirrors SDLPAL global.c's SAVEDGAME_DOS exactly: a fixed prefix
// followed by a variable-length EVENTOBJECT array. We always write the actual
// number of event objects (not the MAX_EVENT_OBJECTS-sized array), matching
// SDLPAL's `i = ChunkSize(0,SSS) + (size - MAX_EVENT_OBJECTS*sizeof(EO))`
// truncation. Files saved by SDLPAL DOS builds are byte-compatible.

const std = @import("std");
const global = @import("global.zig");

// std.c gives us libc bindings (open/read/write/close) without the C-import
// boilerplate. The libretro core links libc anyway.
const c = std.c;

// Compile-time sanity checks on the SDLPAL byte layout. Save files are
// byte-shared with SDLPAL DOS builds, so any drift in field order or struct
// padding would silently corrupt loads.
comptime {
    std.debug.assert(@sizeOf(global.Party) == 10);
    std.debug.assert(@sizeOf(global.Trail) == 6);
    std.debug.assert(@sizeOf(global.Experience) == 8);
    std.debug.assert(@sizeOf(global.Inventory) == 6);
    std.debug.assert(@sizeOf(global.Object) == 12);
    std.debug.assert(@sizeOf(global.Scene) == 8);
    std.debug.assert(@sizeOf(global.PoisonStatus) == 4);
}

// Header prefix — everything before the trailing rgEventObject[] in SAVEDGAME_DOS.
pub const SavedGameDosHeader = extern struct {
    saved_times: u16 align(1),
    viewport_x: u16 align(1),
    viewport_y: u16 align(1),
    n_party_member: u16 align(1),
    num_scene: u16 align(1),
    palette_offset: u16 align(1),
    party_direction: u16 align(1),
    num_music: u16 align(1),
    num_battle_music: u16 align(1),
    num_battle_field: u16 align(1),
    screen_wave: u16 align(1),
    battle_speed: u16 align(1),
    collect_value: u16 align(1),
    layer: u16 align(1),
    chase_range: u16 align(1),
    chase_speed_change_cycles: u16 align(1),
    n_follower: u16 align(1),
    reserved2: [3]u16 align(1),
    cash: u32 align(1),
    party: [global.MAX_PLAYABLE_PLAYER_ROLES]global.Party align(1),
    trail: [global.MAX_PLAYABLE_PLAYER_ROLES]global.Trail align(1),
    exp: global.AllExperience align(1),
    player_roles: global.PlayerRoles align(1),
    poison_status: [global.MAX_POISONS][global.MAX_PLAYABLE_PLAYER_ROLES]global.PoisonStatus align(1),
    inventory: [global.MAX_INVENTORY]global.Inventory align(1),
    scenes: [global.MAX_SCENES]global.Scene align(1),
    objects: [global.MAX_OBJECTS]global.Object align(1),
};

fn savePath(slot: u32, buf: *[4096]u8) ?[:0]const u8 {
    const sys_dir = @import("libretro_core.zig").system_dir orelse return null;
    const written = std.fmt.bufPrint(buf, "{s}/pal/{d}.rpg\x00", .{ sys_dir, slot }) catch return null;
    return buf[0 .. written.len - 1 :0];
}

// Read up to `dst.len` bytes from file fd. Returns the count actually read.
fn readAll(fd: c.fd_t, dst: []u8) usize {
    var total: usize = 0;
    while (total < dst.len) {
        const n = c.read(fd, dst.ptr + total, dst.len - total);
        if (n <= 0) break;
        total += @intCast(n);
    }
    return total;
}

fn writeAllOrErr(fd: c.fd_t, src: []const u8) !void {
    var total: usize = 0;
    while (total < src.len) {
        const n = c.write(fd, src.ptr + total, src.len - total);
        if (n <= 0) return error.WriteFailed;
        total += @intCast(n);
    }
}

// PAL_GetSavedTimes — read just the first WORD of the .rpg file. Used by
// PAL_SaveSlotMenu to show the play-count of each slot.
pub fn getSavedTimes(slot: u32) u16 {
    var path_buf: [4096]u8 = undefined;
    const path = savePath(slot, &path_buf) orelse return 0;
    const fd = c.open(path, .{ .ACCMODE = .RDONLY });
    if (fd < 0) return 0;
    defer _ = c.close(fd);
    var w_bytes: [2]u8 = undefined;
    if (readAll(fd, &w_bytes) != 2) return 0;
    return std.mem.readInt(u16, &w_bytes, .little);
}

// PAL_LoadGame_DOS / PAL_LoadGame_Common — read `<slot>.rpg` and populate the
// global game state. Returns true on success, false if the file is missing or
// truncated below the header.
pub fn loadGame(slot: u32) !bool {
    var path_buf: [4096]u8 = undefined;
    const path = savePath(slot, &path_buf) orelse return false;
    const fd = c.open(path, .{ .ACCMODE = .RDONLY });
    if (fd < 0) return false;
    defer _ = c.close(fd);

    var hdr: SavedGameDosHeader = undefined;
    const hdr_bytes = std.mem.asBytes(&hdr);
    if (readAll(fd, hdr_bytes) != hdr_bytes.len) return false;

    // Trailing event-object data — best effort. The file may have been written
    // with a different MAX_EVENT_OBJECTS, but as long as nEventObject matches
    // the SSS chunk we just loaded into `gpg.g.event_objects`, the read pulls
    // the right count out (short reads are silently tolerated).
    if (global.gpg.g.event_objects.len > 0) {
        const eo_bytes = std.mem.sliceAsBytes(global.gpg.g.event_objects);
        _ = readAll(fd, eo_bytes);
    }

    const vx: i16 = @bitCast(hdr.viewport_x);
    const vy: i16 = @bitCast(hdr.viewport_y);
    global.gpg.viewport = global.palXY(vx, vy);
    global.gpg.max_party_member_index = hdr.n_party_member;
    global.gpg.num_scene = hdr.num_scene;
    global.gpg.night_palette = (hdr.palette_offset != 0);
    global.gpg.party_direction = hdr.party_direction;
    global.gpg.num_music = hdr.num_music;
    global.gpg.num_battle_music = hdr.num_battle_music;
    global.gpg.num_battle_field = hdr.num_battle_field;
    global.gpg.screen_wave = hdr.screen_wave;
    global.gpg.wave_progression = 0;
    global.gpg.collect_value = hdr.collect_value;
    global.gpg.layer = hdr.layer;
    global.gpg.chase_range = hdr.chase_range;
    global.gpg.chase_speed_change_cycles = hdr.chase_speed_change_cycles;
    global.gpg.n_follower = hdr.n_follower;
    global.gpg.cash = hdr.cash;

    global.gpg.party = hdr.party;
    global.gpg.trail = hdr.trail;
    global.gpg.exp = hdr.exp;
    global.gpg.g.player_roles = hdr.player_roles;
    // SDLPAL zeroes poisons on load (matches DOS-classic behavior). Saved
    // poison_status bytes are read but discarded.
    @memset(std.mem.asBytes(&global.gpg.poison_status), 0);
    global.gpg.inventory = hdr.inventory;
    global.gpg.g.scenes = hdr.scenes;
    global.gpg.g.objects = hdr.objects;

    global.gpg.entering_scene = false;

    global.compressInventory();
    return true;
}

// PAL_SaveGame_DOS / PAL_SaveGame_Common — write the current game state to
// `<slot>.rpg`. Trailing event-object array is truncated to the actual count.
pub fn saveGame(slot: u32, saved_times: u16) !void {
    var hdr: SavedGameDosHeader = std.mem.zeroes(SavedGameDosHeader);

    hdr.saved_times = saved_times;
    hdr.viewport_x = @bitCast(global.palX(global.gpg.viewport));
    hdr.viewport_y = @bitCast(global.palY(global.gpg.viewport));
    hdr.n_party_member = global.gpg.max_party_member_index;
    hdr.num_scene = global.gpg.num_scene;
    hdr.palette_offset = if (global.gpg.night_palette) 0x180 else 0;
    hdr.party_direction = global.gpg.party_direction;
    hdr.num_music = global.gpg.num_music;
    hdr.num_battle_music = global.gpg.num_battle_music;
    hdr.num_battle_field = global.gpg.num_battle_field;
    hdr.screen_wave = global.gpg.screen_wave;
    hdr.battle_speed = 2; // PAL_CLASSIC defaults to 2
    hdr.collect_value = global.gpg.collect_value;
    hdr.layer = global.gpg.layer;
    hdr.chase_range = global.gpg.chase_range;
    hdr.chase_speed_change_cycles = global.gpg.chase_speed_change_cycles;
    hdr.n_follower = global.gpg.n_follower;
    hdr.cash = global.gpg.cash;

    hdr.party = global.gpg.party;
    hdr.trail = global.gpg.trail;
    hdr.exp = global.gpg.exp;
    hdr.player_roles = global.gpg.g.player_roles;
    hdr.poison_status = global.gpg.poison_status;
    hdr.inventory = global.gpg.inventory;
    hdr.scenes = global.gpg.g.scenes;
    hdr.objects = global.gpg.g.objects;

    var path_buf: [4096]u8 = undefined;
    const path = savePath(slot, &path_buf) orelse return error.NoSysDir;
    const fd = c.open(path, .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .TRUNC = true,
    }, @as(c.mode_t, 0o644));
    if (fd < 0) return error.OpenFailed;
    defer _ = c.close(fd);

    try writeAllOrErr(fd, std.mem.asBytes(&hdr));
    if (global.gpg.g.event_objects.len > 0) {
        try writeAllOrErr(fd, std.mem.sliceAsBytes(global.gpg.g.event_objects));
    }
}
