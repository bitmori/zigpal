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
const palcommon = @import("palcommon.zig");
const map_mod = @import("map.zig");
const yj1 = @import("yj1.zig");

pub const PalMap = map_mod.PalMap;

// RESOURCES — global resource manager (gpResources in SDLPAL).
pub const Resources = struct {
    map: ?PalMap = null,
    event_object_sprites: []?[]u8 = &.{},
    n_event_object: u32 = 0,
    player_sprites: [global.MAX_PLAYABLE_PLAYER_ROLES]?[]u8 =
        [_]?[]u8{null} ** global.MAX_PLAYABLE_PLAYER_ROLES,
};

pub var resources: Resources = .{};

// PAL_InitResources
pub fn initResources() void {
    resources = .{};
}

// PAL_FreeResources
pub fn freeResources() void {
    freePlayerSprites();
    freeEventObjectSprites();
    if (resources.map) |_| {
        // Map borrows from gop_data — nothing to free explicitly.
        resources.map = null;
    }
}

fn freeEventObjectSprites() void {
    for (resources.event_object_sprites) |maybe| {
        if (maybe) |buf| global.allocator.free(buf);
    }
    if (resources.event_object_sprites.len != 0) {
        global.allocator.free(resources.event_object_sprites);
    }
    resources.event_object_sprites = &.{};
    resources.n_event_object = 0;
}

fn freePlayerSprites() void {
    for (&resources.player_sprites) |*slot| {
        if (slot.*) |buf| {
            global.allocator.free(buf);
            slot.* = null;
        }
    }
}

// PAL_LoadResources — port of res.c PAL_LoadResources.
pub fn loadResources() !void {
    if (global.gpg.load_flags == 0) return;

    // Load global data
    if ((global.gpg.load_flags & global.LOAD_GLOBAL_DATA) != 0) {
        try initGameData(global.gpg.current_save_slot);
        // AUDIO_PlayMusic skipped — no audio support.
    }

    // Load scene
    if ((global.gpg.load_flags & global.LOAD_SCENE) != 0) {
        if (global.gpg.entering_scene) {
            global.gpg.screen_wave = 0;
            global.gpg.wave_progression = 0;
        }

        freeEventObjectSprites();

        const scene_idx = @as(usize, global.gpg.num_scene) - 1;
        const map_num = global.gpg.g.scenes[scene_idx].map_num;

        const map_mkf = global.gpg.f.map orelse return error.NoMapFile;
        const gop_mkf = global.gpg.f.gop orelse return error.NoGopFile;
        resources.map = try map_mod.loadMap(map_num, map_mkf, gop_mkf, global.allocator);

        // Load event-object sprites for the scene.
        const start_index: u32 = global.gpg.g.scenes[scene_idx].event_object_index;
        const end_index: u32 = global.gpg.g.scenes[scene_idx + 1].event_object_index;
        const n: u32 = end_index - start_index;
        resources.n_event_object = n;

        if (n > 0) {
            resources.event_object_sprites = try global.allocator.alloc(?[]u8, n);
            @memset(resources.event_object_sprites, null);

            const mgo_mkf = global.gpg.f.mgo orelse return error.NoMgoFile;
            var i: u32 = 0;
            while (i < n) : (i += 1) {
                const eo = &global.gpg.g.event_objects[start_index + i];
                if (eo.sprite_num == 0) {
                    resources.event_object_sprites[i] = null;
                    continue;
                }
                const sprite = try decompressMkfChunk(mgo_mkf, eo.sprite_num);
                resources.event_object_sprites[i] = sprite;
                eo.sprite_frames_auto = palcommon.spriteGetNumFrames(sprite);
            }
        } else {
            resources.event_object_sprites = &.{};
        }

        global.gpg.party_offset = global.palXY(160, 112);
    }

    // Load player sprites
    if ((global.gpg.load_flags & global.LOAD_PLAYER_SPRITE) != 0) {
        freePlayerSprites();

        const mgo_mkf = global.gpg.f.mgo orelse return error.NoMgoFile;
        var i: usize = 0;
        while (i <= global.gpg.max_party_member_index) : (i += 1) {
            const player_id = global.gpg.party[i].player_role;
            const sprite_num = global.gpg.g.player_roles.sprite_num[player_id];
            const sprite = try decompressMkfChunk(mgo_mkf, sprite_num);
            resources.player_sprites[i] = sprite;
        }

        var f: u32 = 1;
        while (f <= global.gpg.n_follower) : (f += 1) {
            const idx = global.gpg.max_party_member_index + f;
            const sprite_num = global.gpg.party[idx].player_role;
            const sprite = try decompressMkfChunk(mgo_mkf, sprite_num);
            resources.player_sprites[idx] = sprite;
        }
    }

    global.gpg.load_flags = 0;
}

// PAL_GetCurrentMap
pub fn getCurrentMap() ?*const PalMap {
    if (resources.map) |*m| return m;
    return null;
}

// PAL_GetPlayerSprite
pub fn getPlayerSprite(player_index: u8) ?[]const u8 {
    if (player_index >= global.MAX_PLAYABLE_PLAYER_ROLES) return null;
    return resources.player_sprites[player_index];
}

// PAL_GetEventObjectSprite
pub fn getEventObjectSprite(event_object_id: u16) ?[]const u8 {
    const scene_idx = @as(usize, global.gpg.num_scene) - 1;
    const start_index: u32 = global.gpg.g.scenes[scene_idx].event_object_index;
    if (event_object_id <= start_index) return null;
    const idx: usize = event_object_id - start_index - 1;
    if (idx >= resources.n_event_object) return null;
    return resources.event_object_sprites[idx];
}

// Decompress a YJ1 chunk and return a heap-allocated buffer.
fn decompressMkfChunk(mkf: palcommon.MkfFile, chunk_num: u32) ![]u8 {
    const compressed = try mkf.getChunkData(chunk_num);
    const decompressed_size = try mkf.getDecompressedSize(chunk_num, false);
    const buf = try global.allocator.alloc(u8, decompressed_size);
    _ = try yj1.decompress(compressed, buf);
    return buf;
}

// --- Game data initialization (PAL_InitGameData / PAL_LoadDefaultGame from global.c) ---

fn initGameData(save_slot: u8) !void {
    try initGlobalGameData();
    global.gpg.current_save_slot = save_slot;

    if (save_slot == 0 or !try loadSavedGame(save_slot)) {
        try loadDefaultGame();
    }

    global.gpg.cur_inv_menu_item = 0;
    global.gpg.in_battle = false;
    global.gpg.player_status = [_][global.STATUS_ALL]u16{[_]u16{0} ** global.STATUS_ALL} ** global.MAX_PLAYER_ROLES;
    global.updateEquipments();
}

// PAL_InitGlobalGameData — allocate and read the static tables shared across saves.
fn initGlobalGameData() !void {
    if (global.gpg.g.event_objects.len != 0) return; // already initialized

    const sss = global.gpg.f.sss orelse return error.NoSss;
    const data = global.gpg.f.data orelse return error.NoData;

    // SSS chunk 0 — event objects
    {
        const eo_data = try sss.getChunkData(0);
        const n = eo_data.len / @sizeOf(global.EventObject);
        global.gpg.g.event_objects = try global.allocator.alloc(global.EventObject, n);
        @memcpy(std.mem.sliceAsBytes(global.gpg.g.event_objects), eo_data[0 .. n * @sizeOf(global.EventObject)]);
    }
    // SSS chunk 4 — script entries
    {
        const se_data = try sss.getChunkData(4);
        const n = se_data.len / @sizeOf(global.ScriptEntry);
        global.gpg.g.script_entries = try global.allocator.alloc(global.ScriptEntry, n);
        @memcpy(std.mem.sliceAsBytes(global.gpg.g.script_entries), se_data[0 .. n * @sizeOf(global.ScriptEntry)]);
    }
    // DATA chunk 0 — stores
    {
        const d = try data.getChunkData(0);
        const n = d.len / @sizeOf(global.Store);
        global.gpg.g.stores = try global.allocator.alloc(global.Store, n);
        @memcpy(std.mem.sliceAsBytes(global.gpg.g.stores), d[0 .. n * @sizeOf(global.Store)]);
    }
    // DATA chunk 1 — enemies
    {
        const d = try data.getChunkData(1);
        const n = d.len / @sizeOf(global.Enemy);
        global.gpg.g.enemies = try global.allocator.alloc(global.Enemy, n);
        @memcpy(std.mem.sliceAsBytes(global.gpg.g.enemies), d[0 .. n * @sizeOf(global.Enemy)]);
    }
    // DATA chunk 2 — enemy teams
    {
        const d = try data.getChunkData(2);
        const n = d.len / @sizeOf(global.EnemyTeam);
        global.gpg.g.enemy_teams = try global.allocator.alloc(global.EnemyTeam, n);
        @memcpy(std.mem.sliceAsBytes(global.gpg.g.enemy_teams), d[0 .. n * @sizeOf(global.EnemyTeam)]);
    }
    // DATA chunk 4 — magics
    {
        const d = try data.getChunkData(4);
        const n = d.len / @sizeOf(global.Magic);
        global.gpg.g.magics = try global.allocator.alloc(global.Magic, n);
        @memcpy(std.mem.sliceAsBytes(global.gpg.g.magics), d[0 .. n * @sizeOf(global.Magic)]);
    }
    // DATA chunk 5 — battlefields
    {
        const d = try data.getChunkData(5);
        const n = d.len / @sizeOf(global.Battlefield);
        global.gpg.g.battlefields = try global.allocator.alloc(global.Battlefield, n);
        @memcpy(std.mem.sliceAsBytes(global.gpg.g.battlefields), d[0 .. n * @sizeOf(global.Battlefield)]);
    }
    // DATA chunk 6 — level-up magics
    {
        const d = try data.getChunkData(6);
        const n = d.len / @sizeOf(global.LevelUpMagicAll);
        global.gpg.g.level_up_magics = try global.allocator.alloc(global.LevelUpMagicAll, n);
        @memcpy(std.mem.sliceAsBytes(global.gpg.g.level_up_magics), d[0 .. n * @sizeOf(global.LevelUpMagicAll)]);
    }
    // DATA chunk 11 — battle effect index
    {
        const d = try data.getChunkData(11);
        @memcpy(std.mem.asBytes(&global.gpg.g.battle_effect_index), d[0..@sizeOf(@TypeOf(global.gpg.g.battle_effect_index))]);
    }
    // DATA chunk 13 — enemy positions
    {
        const d = try data.getChunkData(13);
        @memcpy(std.mem.asBytes(&global.gpg.g.enemy_pos), d[0..@sizeOf(global.EnemyPos)]);
    }
    // DATA chunk 14 — level-up exp
    {
        const d = try data.getChunkData(14);
        @memcpy(std.mem.asBytes(&global.gpg.g.level_up_exp), d[0..@sizeOf(@TypeOf(global.gpg.g.level_up_exp))]);
    }
}

// PAL_LoadDefaultGame
fn loadDefaultGame() !void {
    const sss = global.gpg.f.sss orelse return error.NoSss;
    const data = global.gpg.f.data orelse return error.NoData;

    // SSS chunk 0 — event objects (overwrite default state).
    {
        const eo_data = try sss.getChunkData(0);
        const bytes = @min(eo_data.len, global.gpg.g.event_objects.len * @sizeOf(global.EventObject));
        @memcpy(std.mem.sliceAsBytes(global.gpg.g.event_objects)[0..bytes], eo_data[0..bytes]);
    }

    // SSS chunk 1 — scenes
    {
        const d = try sss.getChunkData(1);
        const bytes = @min(d.len, @sizeOf(@TypeOf(global.gpg.g.scenes)));
        @memcpy(std.mem.asBytes(&global.gpg.g.scenes)[0..bytes], d[0..bytes]);
    }

    // SSS chunk 2 — objects (DOS format = 6 words per object).
    {
        const d = try sss.getChunkData(2);
        const bytes = @min(d.len, @sizeOf(@TypeOf(global.gpg.g.objects)));
        @memcpy(std.mem.asBytes(&global.gpg.g.objects)[0..bytes], d[0..bytes]);
    }

    // DATA chunk 3 — player roles
    {
        const d = try data.getChunkData(3);
        const bytes = @min(d.len, @sizeOf(global.PlayerRoles));
        @memcpy(std.mem.asBytes(&global.gpg.g.player_roles)[0..bytes], d[0..bytes]);
    }

    // Defaults
    global.gpg.cash = 0;
    global.gpg.num_music = 0;
    global.gpg.num_palette = 0;
    global.gpg.num_scene = 1;
    global.gpg.collect_value = 0;
    global.gpg.night_palette = false;
    global.gpg.max_party_member_index = 0;
    global.gpg.viewport = 0;
    global.gpg.layer = 0;
    global.gpg.n_follower = 0;
    global.gpg.chase_range = 1;

    @memset(&global.gpg.inventory, .{ .item = 0, .amount = 0, .amount_in_use = 0 });
    @memset(std.mem.asBytes(&global.gpg.poison_status), 0);
    @memset(std.mem.asBytes(&global.gpg.party), 0);
    @memset(std.mem.asBytes(&global.gpg.trail), 0);
    @memset(std.mem.asBytes(&global.gpg.exp), 0);

    for (0..global.MAX_PLAYER_ROLES) |i| {
        const lvl = global.gpg.g.player_roles.level[i];
        global.gpg.exp.primary[i].level = lvl;
        global.gpg.exp.health[i].level = lvl;
        global.gpg.exp.magic_exp[i].level = lvl;
        global.gpg.exp.attack[i].level = lvl;
        global.gpg.exp.magic_power[i].level = lvl;
        global.gpg.exp.defense[i].level = lvl;
        global.gpg.exp.dexterity[i].level = lvl;
        global.gpg.exp.flee[i].level = lvl;
    }

    global.gpg.entering_scene = true;
}

fn loadSavedGame(slot: u8) !bool {
    return @import("save.zig").loadGame(slot);
}
