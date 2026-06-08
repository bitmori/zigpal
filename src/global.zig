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
const MkfFile = palcommon.MkfFile;

// --- Constants (re-exported for convenience) ---
pub const MAX_PLAYERS_IN_PARTY = palcommon.MAX_PLAYERS_IN_PARTY;
pub const MAX_PLAYER_ROLES = palcommon.MAX_PLAYER_ROLES;
pub const MAX_PLAYABLE_PLAYER_ROLES = palcommon.MAX_PLAYABLE_PLAYER_ROLES;
pub const MAX_INVENTORY = palcommon.MAX_INVENTORY;
pub const MAX_STORE_ITEM = palcommon.MAX_STORE_ITEM;
pub const NUM_MAGIC_ELEMENTAL = palcommon.NUM_MAGIC_ELEMENTAL;
pub const MAX_ENEMIES_IN_TEAM = palcommon.MAX_ENEMIES_IN_TEAM;
pub const MAX_PLAYER_EQUIPMENTS = palcommon.MAX_PLAYER_EQUIPMENTS;
pub const MAX_PLAYER_MAGICS = palcommon.MAX_PLAYER_MAGICS;
pub const MAX_SCENES = palcommon.MAX_SCENES;
pub const MAX_OBJECTS = palcommon.MAX_OBJECTS;
pub const MAX_EVENT_OBJECTS = palcommon.MAX_EVENT_OBJECTS;
pub const MAX_POISONS = palcommon.MAX_POISONS;
pub const MAX_LEVELS = palcommon.MAX_LEVELS;

// 魔改 — extended limits, mirroring SDLPAL fork's palcommon.h.
// Stat cap raised from the vanilla 999 to allow late-game character
// builds that would otherwise be clamped (level-up, equipment, magic
// boosts all clip here).
pub const MAX_PROPERTY_VALUE: u16 = 9999;
// Poisons with level >= this bypass resistance rolls (sure-hit).
pub const EX_POISON_CAN_PIERCE_LEVEL: u16 = 10;
// Highest poison level that survives revive / cure-by-level after death.
pub const EX_POISON_PERSIST_AFTER_REVIVE: u16 = 97;
// Highest poison level that the status panel will list. Vanilla was 3;
// raising this surfaces the new "permanent" poisons (寿虫蠱 etc.).
pub const EX_MAX_VISIBLE_POISON_LEVEL: u16 = 98;

// FRAME_TIME (game.h: FPS=10)
pub const FPS: u32 = 10;
pub const FRAME_TIME: u32 = 1000 / FPS;
pub const BATTLE_FPS: u32 = 25;
pub const BATTLE_FRAME_TIME: u32 = 1000 / BATTLE_FPS;

// --- Enums ---

// STATUS
pub const STATUS_CONFUSED: u16 = 0;
pub const STATUS_PARALYZED: u16 = 1;
pub const STATUS_SLEEP: u16 = 2;
pub const STATUS_SILENCE: u16 = 3;
pub const STATUS_PUPPET: u16 = 4;
pub const STATUS_BRAVERY: u16 = 5;
pub const STATUS_PROTECT: u16 = 6;
pub const STATUS_HASTE: u16 = 7;
pub const STATUS_DUAL_ATTACK: u16 = 8;
pub const STATUS_ALL: u16 = 9;

// BODYPART
pub const BODYPART_HEAD: u16 = 0;
pub const BODYPART_BODY: u16 = 1;
pub const BODYPART_SHOULDER: u16 = 2;
pub const BODYPART_HAND: u16 = 3;
pub const BODYPART_FEET: u16 = 4;
pub const BODYPART_WEAR: u16 = 5;
pub const BODYPART_EXTRA: u16 = 6;

// OBJECTSTATE
pub const OBJ_STATE_HIDDEN: i16 = 0;
pub const OBJ_STATE_NORMAL: i16 = 1;
pub const OBJ_STATE_BLOCKER: i16 = 2;

// TRIGGERMODE
pub const TRIGGER_NONE: u16 = 0;
pub const TRIGGER_SEARCH_NEAR: u16 = 1;
pub const TRIGGER_SEARCH_NORMAL: u16 = 2;
pub const TRIGGER_SEARCH_FAR: u16 = 3;
pub const TRIGGER_TOUCH_NEAR: u16 = 4;
pub const TRIGGER_TOUCH_NORMAL: u16 = 5;
pub const TRIGGER_TOUCH_FAR: u16 = 6;
pub const TRIGGER_TOUCH_FARTHER: u16 = 7;
pub const TRIGGER_TOUCH_FARTHEST: u16 = 8;

// MAGIC TYPE
pub const MAGIC_TYPE_NORMAL: u16 = 0;
pub const MAGIC_TYPE_ATTACK_ALL: u16 = 1;
pub const MAGIC_TYPE_ATTACK_WHOLE: u16 = 2;
pub const MAGIC_TYPE_ATTACK_FIELD: u16 = 3;
pub const MAGIC_TYPE_APPLY_TO_PLAYER: u16 = 4;
pub const MAGIC_TYPE_APPLY_TO_PARTY: u16 = 5;
pub const MAGIC_TYPE_TRANCE: u16 = 8;
pub const MAGIC_TYPE_SUMMON: u16 = 9;

// 魔改 — Magic.render_mode flags (field offset 11, was wUnknown in vanilla).
// Multiple flags may combine via bitwise OR.
//
//  val  flag                     effect
//  ---  -----------------------  ------------------------------------
//    1  REVERSE                  帧倒序播放 (双方)
//    2  REVERSE_HERO_OFF         帧倒序 (仅我方释放)
//    4  REVERSE_ENEMY_OFF        帧倒序 (仅敌方释放)
//    8  MIRROR                   水平翻转 (双方)
//   16  MIRROR_HERO_OFF          水平翻转 (仅我方释放)
//   32  MIRROR_ENEMY_OFF         水平翻转 (仅敌方释放)
//   64  TRIPLE_PARALLEL          attack-all 时三帧平行错位
//
pub const MAGIC_RENDER_REVERSE: u16 = 1;
pub const MAGIC_RENDER_REVERSE_HERO_OFF: u16 = 2;
pub const MAGIC_RENDER_REVERSE_ENEMY_OFF: u16 = 4;
pub const MAGIC_RENDER_MIRROR: u16 = 8;
pub const MAGIC_RENDER_MIRROR_HERO_OFF: u16 = 16;
pub const MAGIC_RENDER_MIRROR_ENEMY_OFF: u16 = 32;
pub const MAGIC_RENDER_TRIPLE_PARALLEL: u16 = 64;

// LoadFlags
pub const LOAD_NONE: u32 = 0;
pub const LOAD_SCENE: u32 = 1 << 0;
pub const LOAD_PLAYER_SPRITE: u32 = 1 << 1;
pub const LOAD_GLOBAL_DATA: u32 = 1 << 2;

// --- Helper for PAL_POS ---

pub inline fn palXY(x: i16, y: i16) u32 {
    return (@as(u32, @bitCast(@as(i32, y))) << 16) | (@as(u32, @bitCast(@as(i32, x))) & 0xFFFF);
}

pub inline fn palX(xy: u32) i16 {
    return @bitCast(@as(u16, @intCast(xy & 0xFFFF)));
}

pub inline fn palY(xy: u32) i16 {
    return @bitCast(@as(u16, @intCast((xy >> 16) & 0xFFFF)));
}

pub inline fn palXyOffset(xy: u32, dx: i32, dy: i32) u32 {
    const x: i32 = @as(i32, palX(xy)) + dx;
    const y: i32 = @as(i32, palY(xy)) + dy;
    return palXY(@truncate(x), @truncate(y));
}

// --- Data Structures (mirroring SDLPAL global.h) ---

pub const EventObject = extern struct {
    vanish_time: i16 align(1),
    x: u16 align(1),
    y: u16 align(1),
    layer: i16 align(1),
    trigger_script: u16 align(1),
    auto_script: u16 align(1),
    state: i16 align(1),
    trigger_mode: u16 align(1),
    sprite_num: u16 align(1),
    sprite_frames: u16 align(1),
    direction: u16 align(1),
    current_frame_num: u16 align(1),
    script_idle_frame: u16 align(1),
    sprite_ptr_offset: u16 align(1),
    sprite_frames_auto: u16 align(1),
    script_idle_frame_count_auto: u16 align(1),
};

pub const Scene = extern struct {
    map_num: u16 align(1),
    script_on_enter: u16 align(1),
    script_on_teleport: u16 align(1),
    event_object_index: u16 align(1),
};

pub const Object = extern struct {
    data: [6]u16 align(1),

    // OBJECT_ITEM_DOS view (data[0]=bitmap, data[1]=price, ...).
    pub fn item(self: *const Object) struct {
        bitmap: u16,
        price: u16,
        script_on_use: u16,
        script_on_equip: u16,
        script_on_throw: u16,
        flags: u16,
    } {
        return .{
            .bitmap = self.data[0],
            .price = self.data[1],
            .script_on_use = self.data[2],
            .script_on_equip = self.data[3],
            .script_on_throw = self.data[4],
            .flags = self.data[5],
        };
    }

    // OBJECT_MAGIC_DOS view.
    pub fn magic(self: *const Object) struct {
        magic_number: u16,
        reserved1: u16,
        script_on_success: u16,
        script_on_use: u16,
        reserved2: u16,
        flags: u16,
    } {
        return .{
            .magic_number = self.data[0],
            .reserved1 = self.data[1],
            .script_on_success = self.data[2],
            .script_on_use = self.data[3],
            .reserved2 = self.data[4],
            .flags = self.data[5],
        };
    }

    // OBJECT_PLAYER view (system strings + party leaders share this slot).
    // data[0..1] reserved (always 0); SDLPAL global.h tagOBJECT_PLAYER.
    pub fn player(self: *const Object) struct {
        script_on_friend_death: u16,
        script_on_dying: u16,
    } {
        return .{
            .script_on_friend_death = self.data[2],
            .script_on_dying = self.data[3],
        };
    }

    // OBJECT_ENEMY view — global.h tagOBJECT_ENEMY.
    pub fn enemy(self: *const Object) struct {
        enemy_id: u16,
        resistance_to_sorcery: u16,
        script_on_turn_start: u16,
        script_on_battle_end: u16,
        script_on_ready: u16,
    } {
        return .{
            .enemy_id = self.data[0],
            .resistance_to_sorcery = self.data[1],
            .script_on_turn_start = self.data[2],
            .script_on_battle_end = self.data[3],
            .script_on_ready = self.data[4],
        };
    }

    // OBJECT_POISON view.
    pub fn poison(self: *const Object) struct {
        poison_level: u16,
        color: u16,
        player_script: u16,
        reserved: u16,
        enemy_script: u16,
    } {
        return .{
            .poison_level = self.data[0],
            .color = self.data[1],
            .player_script = self.data[2],
            .reserved = self.data[3],
            .enemy_script = self.data[4],
        };
    }
};

// Item flags from ITEMFLAG.
pub const ITEM_FLAG_USABLE: u16 = 1 << 0;
pub const ITEM_FLAG_EQUIPABLE: u16 = 1 << 1;
pub const ITEM_FLAG_THROWABLE: u16 = 1 << 2;
pub const ITEM_FLAG_CONSUMING: u16 = 1 << 3;
pub const ITEM_FLAG_APPLY_TO_ALL: u16 = 1 << 4;
pub const ITEM_FLAG_SELLABLE: u16 = 1 << 5;
pub const ITEM_FLAG_EQUIPABLE_BY_PLAYER_ROLE_FIRST: u16 = 1 << 6;

// Magic flags from MAGICFLAG.
pub const MAGIC_FLAG_USABLE_OUTSIDE_BATTLE: u16 = 1 << 0;
pub const MAGIC_FLAG_USABLE_IN_BATTLE: u16 = 1 << 1;
pub const MAGIC_FLAG_USABLE_TO_ENEMY: u16 = 1 << 3;
pub const MAGIC_FLAG_APPLY_TO_ALL: u16 = 1 << 4;

pub const ScriptEntry = extern struct {
    operation: u16 align(1),
    operand: [3]u16 align(1),
};

pub const Inventory = extern struct {
    item: u16 align(1),
    amount: u16 align(1),
    amount_in_use: u16 align(1),
};

pub const Store = extern struct {
    items: [MAX_STORE_ITEM]u16 align(1),
};

pub const Enemy = extern struct {
    idle_frames: u16 align(1),
    magic_frames: u16 align(1),
    attack_frames: u16 align(1),
    idle_anim_speed: u16 align(1),
    act_wait_frames: u16 align(1),
    y_pos_offset: u16 align(1),
    attack_sound: i16 align(1),
    action_sound: i16 align(1),
    magic_sound: i16 align(1),
    death_sound: i16 align(1),
    call_sound: i16 align(1),
    health: u16 align(1),
    exp: u16 align(1),
    cash: u16 align(1),
    level: u16 align(1),
    magic: u16 align(1),
    magic_rate: u16 align(1),
    attack_equiv_item: u16 align(1),
    attack_equiv_item_rate: u16 align(1),
    steal_item: u16 align(1),
    n_steal_item: u16 align(1),
    attack_strength: u16 align(1),
    magic_strength: u16 align(1),
    defense: u16 align(1),
    dexterity: u16 align(1),
    flee_rate: u16 align(1),
    poison_resistance: u16 align(1),
    elem_resistance: [NUM_MAGIC_ELEMENTAL]u16 align(1),
    physical_resistance: u16 align(1),
    dual_move: u16 align(1),
    collect_value: u16 align(1),
};

pub const EnemyTeam = extern struct {
    enemy: [MAX_ENEMIES_IN_TEAM]u16 align(1),
};

pub const PlayerRoles = extern struct {
    avatar: [MAX_PLAYER_ROLES]u16 align(1),
    sprite_num_in_battle: [MAX_PLAYER_ROLES]u16 align(1),
    sprite_num: [MAX_PLAYER_ROLES]u16 align(1),
    name: [MAX_PLAYER_ROLES]u16 align(1),
    attack_all: [MAX_PLAYER_ROLES]u16 align(1),
    unknown1: [MAX_PLAYER_ROLES]u16 align(1),
    level: [MAX_PLAYER_ROLES]u16 align(1),
    max_hp: [MAX_PLAYER_ROLES]u16 align(1),
    max_mp: [MAX_PLAYER_ROLES]u16 align(1),
    hp: [MAX_PLAYER_ROLES]u16 align(1),
    mp: [MAX_PLAYER_ROLES]u16 align(1),
    equipment: [MAX_PLAYER_EQUIPMENTS][MAX_PLAYER_ROLES]u16 align(1),
    attack_strength: [MAX_PLAYER_ROLES]u16 align(1),
    magic_strength: [MAX_PLAYER_ROLES]u16 align(1),
    defense: [MAX_PLAYER_ROLES]u16 align(1),
    dexterity: [MAX_PLAYER_ROLES]u16 align(1),
    flee_rate: [MAX_PLAYER_ROLES]u16 align(1),
    poison_resistance: [MAX_PLAYER_ROLES]u16 align(1),
    elemental_resistance: [NUM_MAGIC_ELEMENTAL][MAX_PLAYER_ROLES]u16 align(1),
    unknown2: [MAX_PLAYER_ROLES]u16 align(1),
    unknown3: [MAX_PLAYER_ROLES]u16 align(1),
    unknown4: [MAX_PLAYER_ROLES]u16 align(1),
    covered_by: [MAX_PLAYER_ROLES]u16 align(1),
    magic: [MAX_PLAYER_MAGICS][MAX_PLAYER_ROLES]u16 align(1),
    walk_frames: [MAX_PLAYER_ROLES]u16 align(1),
    cooperative_magic: [MAX_PLAYER_ROLES]u16 align(1),
    unknown5: [MAX_PLAYER_ROLES]u16 align(1),
    unknown6: [MAX_PLAYER_ROLES]u16 align(1),
    death_sound: [MAX_PLAYER_ROLES]u16 align(1),
    attack_sound: [MAX_PLAYER_ROLES]u16 align(1),
    weapon_sound: [MAX_PLAYER_ROLES]u16 align(1),
    critical_sound: [MAX_PLAYER_ROLES]u16 align(1),
    magic_sound: [MAX_PLAYER_ROLES]u16 align(1),
    cover_sound: [MAX_PLAYER_ROLES]u16 align(1),
    dying_sound: [MAX_PLAYER_ROLES]u16 align(1),
};

pub const Magic = extern struct {
    effect: u16 align(1),
    magic_type: u16 align(1),
    x_offset: u16 align(1),
    y_offset: u16 align(1),
    specific: u16 align(1),
    speed: i16 align(1),
    keep_effect: u16 align(1),
    fire_delay: u16 align(1),
    effect_times: u16 align(1),
    shake: u16 align(1),
    wave: u16 align(1),
    // 魔改 — repurposed from wUnknown. See MAGIC_RENDER_* flag constants.
    render_mode: u16 align(1),
    cost_mp: u16 align(1),
    base_damage: u16 align(1),
    elemental: u16 align(1),
    sound: i16 align(1),
};

pub const Battlefield = extern struct {
    screen_wave: u16 align(1),
    magic_effect: [NUM_MAGIC_ELEMENTAL]i16 align(1),
};

pub const LevelUpMagic = extern struct {
    level: u16 align(1),
    magic: u16 align(1),
};

pub const LevelUpMagicAll = extern struct {
    m: [MAX_PLAYABLE_PLAYER_ROLES]LevelUpMagic align(1),
};

pub const PalPos = extern struct {
    x: u16 align(1),
    y: u16 align(1),
};

pub const EnemyPos = extern struct {
    pos: [MAX_ENEMIES_IN_TEAM][MAX_ENEMIES_IN_TEAM]PalPos align(1),
};

pub const Party = extern struct {
    player_role: u16 align(1),
    x: i16 align(1),
    y: i16 align(1),
    frame: u16 align(1),
    image_offset: u16 align(1),
};

pub const Trail = extern struct {
    x: u16 align(1),
    y: u16 align(1),
    direction: u16 align(1),
};

pub const Experience = extern struct {
    exp: u16 align(1),
    reserved: u16 align(1),
    level: u16 align(1),
    count: u16 align(1),
};

pub const AllExperience = extern struct {
    primary: [MAX_PLAYER_ROLES]Experience align(1),
    health: [MAX_PLAYER_ROLES]Experience align(1),
    magic_exp: [MAX_PLAYER_ROLES]Experience align(1),
    attack: [MAX_PLAYER_ROLES]Experience align(1),
    magic_power: [MAX_PLAYER_ROLES]Experience align(1),
    defense: [MAX_PLAYER_ROLES]Experience align(1),
    dexterity: [MAX_PLAYER_ROLES]Experience align(1),
    flee: [MAX_PLAYER_ROLES]Experience align(1),
};

pub const PoisonStatus = extern struct {
    poison_id: u16 align(1),
    poison_script: u16 align(1),
};

// LPFILES — file pointers in SDLPAL. We use MkfFile views into pre-loaded buffers.
pub const Files = struct {
    fbp: ?MkfFile = null,
    mgo: ?MkfFile = null,
    ball: ?MkfFile = null,
    data: ?MkfFile = null,
    f: ?MkfFile = null,
    fire: ?MkfFile = null,
    rgm: ?MkfFile = null,
    sss: ?MkfFile = null,
    abc: ?MkfFile = null,
    map: ?MkfFile = null,
    gop: ?MkfFile = null,
    pat: ?MkfFile = null,
    rng: ?MkfFile = null,
    // mus.mkf is the RIX music bank fed into pal-adplug; the audio module
    // keeps a long-lived view of res_buffers.mus so we don't expose MkfFile
    // here — the bytes go directly to pal_rix_create.
};

// LPGAMEDATA — game data loaded from data files.
pub const GameData = struct {
    event_objects: []EventObject = &.{},
    scenes: [MAX_SCENES]Scene = undefined,
    objects: [MAX_OBJECTS]Object = undefined,

    script_entries: []ScriptEntry = &.{},
    stores: []Store = &.{},
    enemies: []Enemy = &.{},
    enemy_teams: []EnemyTeam = &.{},
    player_roles: PlayerRoles = undefined,
    magics: []Magic = &.{},
    battlefields: []Battlefield = &.{},
    level_up_magics: []LevelUpMagicAll = &.{},

    enemy_pos: EnemyPos = undefined,
    level_up_exp: [MAX_LEVELS + 1]u16 = undefined,
    battle_effect_index: [10][2]u16 = undefined,
};

// GLOBALVARS
pub const GlobalVars = struct {
    f: Files = .{},
    g: GameData = .{},

    cur_main_menu_item: i32 = 0,
    cur_system_menu_item: i32 = 0,
    cur_inv_menu_item: i32 = 0,
    cur_playing_rng: i32 = 0,
    current_save_slot: u8 = 1,
    in_main_game: bool = false,
    entering_scene: bool = false,
    need_to_fade_in: bool = false,
    in_battle: bool = false,
    auto_battle: bool = false,

    last_unequipped_item: u16 = 0,

    equipment_effect: [MAX_PLAYER_EQUIPMENTS + 1]PlayerRoles = undefined,
    player_status: [MAX_PLAYER_ROLES][STATUS_ALL]u16 = [_][STATUS_ALL]u16{[_]u16{0} ** STATUS_ALL} ** MAX_PLAYER_ROLES,

    viewport: u32 = 0,
    party_offset: u32 = 0,
    layer: u16 = 0,
    max_party_member_index: u16 = 0,
    party: [MAX_PLAYABLE_PLAYER_ROLES]Party = undefined,
    trail: [MAX_PLAYABLE_PLAYER_ROLES]Trail = undefined,
    party_direction: u16 = 0,
    num_scene: u16 = 1,
    num_palette: u16 = 0,
    night_palette: bool = false,
    num_music: u16 = 0,
    num_battle_music: u16 = 0,
    num_battle_field: u16 = 0,
    collect_value: u16 = 0,
    screen_wave: u16 = 0,
    wave_progression: i16 = 0,
    chase_range: u16 = 1,
    chase_speed_change_cycles: u16 = 0,
    n_follower: u16 = 0,

    cash: u32 = 0,

    exp: AllExperience = undefined,
    poison_status: [MAX_POISONS][MAX_PLAYABLE_PLAYER_ROLES]PoisonStatus =
        [_][MAX_PLAYABLE_PLAYER_ROLES]PoisonStatus{[_]PoisonStatus{.{ .poison_id = 0, .poison_script = 0 }} ** MAX_PLAYABLE_PLAYER_ROLES} ** MAX_POISONS,
    inventory: [MAX_INVENTORY]Inventory =
        [_]Inventory{.{ .item = 0, .amount = 0, .amount_in_use = 0 }} ** MAX_INVENTORY,

    frame_num: u32 = 0,

    // load flags (kLoad...)
    load_flags: u32 = 0,
};

// The single global GLOBALVARS (gpGlobals in SDLPAL).
pub var gpg: GlobalVars = .{};

// --- Resource buffers — own the file data so MkfFile views remain valid. ---
pub const ResourceBuffers = struct {
    pat: ?[]u8 = null,
    fbp: ?[]u8 = null,
    rgm: ?[]u8 = null,
    data: ?[]u8 = null,
    sss: ?[]u8 = null,
    map: ?[]u8 = null,
    gop: ?[]u8 = null,
    mgo: ?[]u8 = null,
    ball: ?[]u8 = null,
    f: ?[]u8 = null,
    fire: ?[]u8 = null,
    abc: ?[]u8 = null,
    word: ?[]u8 = null,
    msg: ?[]u8 = null,
    asc: ?[]u8 = null,
    fon: ?[]u8 = null,
    desc: ?[]u8 = null,
    rng: ?[]u8 = null,
    mus: ?[]u8 = null,
    voc: ?[]u8 = null,
};

pub var res_buffers: ResourceBuffers = .{};

pub var allocator: std.mem.Allocator = std.heap.page_allocator;

// --- PAL_SetLoadFlags ---
pub fn setLoadFlags(flags: u32) void {
    gpg.load_flags |= flags;
}

// --- PAL_ReloadInNextTick ---
pub fn reloadInNextTick(save_slot: i32) void {
    gpg.current_save_slot = @intCast(save_slot);
    setLoadFlags(LOAD_GLOBAL_DATA | LOAD_SCENE | LOAD_PLAYER_SPRITE);
    gpg.entering_scene = true;
    gpg.need_to_fade_in = true;
    gpg.frame_num = 0;
}

// --- PAL_GetItemAmount ---
pub fn getItemAmount(item: u16) u16 {
    var i: usize = 0;
    while (i < MAX_INVENTORY) : (i += 1) {
        if (gpg.inventory[i].item == 0) break;
        if (gpg.inventory[i].item == item) return gpg.inventory[i].amount;
    }
    return 0;
}

// --- PAL_GetItemIndexToInventory ---
pub fn getItemIndexToInventory(object_id: u16) struct { found: bool, index: usize } {
    var index: usize = 0;
    while (index < MAX_INVENTORY) : (index += 1) {
        if (gpg.inventory[index].item == object_id) {
            return .{ .found = true, .index = index };
        }
        if (gpg.inventory[index].item == 0) {
            return .{ .found = false, .index = index };
        }
    }
    return .{ .found = false, .index = MAX_INVENTORY };
}

// --- PAL_AddItemToInventory ---
pub fn addItemToInventory(object_id: u16, num_in: i32) i32 {
    if (object_id == 0) return 0;
    const num: i32 = if (num_in == 0) 1 else num_in;

    const r = getItemIndexToInventory(object_id);
    const found = r.found;
    var index = r.index;

    if (num > 0) {
        if (index >= MAX_INVENTORY) return 0;
        if (found) {
            gpg.inventory[index].amount = @intCast(@min(@as(i32, gpg.inventory[index].amount) + num, 99));
        } else {
            gpg.inventory[index].item = object_id;
            gpg.inventory[index].amount = @intCast(@min(num, 99));
        }
        return 1;
    } else {
        if (!found) return 0;
        var n: i32 = -num;
        if (gpg.inventory[index].amount < n) {
            n -= @as(i32, gpg.inventory[index].amount);
            gpg.inventory[index].amount = 0;
            return -n;
        }
        gpg.inventory[index].amount -= @intCast(n);
        if (gpg.inventory[index].amount == 0 and index == @as(usize, @intCast(gpg.cur_inv_menu_item)) and index + 1 < MAX_INVENTORY and gpg.inventory[index + 1].amount == 0) {
            if (gpg.cur_inv_menu_item > 0) gpg.cur_inv_menu_item -= 1;
        }
        _ = &index;
        return 1;
    }
}

// --- PAL_CompressInventory ---
pub fn compressInventory() void {
    var j: usize = 0;
    var i: usize = 0;
    while (i < MAX_INVENTORY) : (i += 1) {
        if (gpg.inventory[i].amount > 0) {
            gpg.inventory[j] = gpg.inventory[i];
            j += 1;
        }
    }
    while (j < MAX_INVENTORY) : (j += 1) {
        gpg.inventory[j] = .{ .item = 0, .amount = 0, .amount_in_use = 0 };
    }
}

// --- PAL_CountItem ---
pub fn countItem(object_id: u16) i32 {
    if (object_id == 0) return 0;
    var index: usize = 0;
    var count: i32 = 0;
    while (index < MAX_INVENTORY) : (index += 1) {
        if (gpg.inventory[index].item == object_id) {
            count = gpg.inventory[index].amount;
            break;
        }
        if (gpg.inventory[index].item == 0) break;
    }
    var i: usize = 0;
    while (i <= gpg.max_party_member_index) : (i += 1) {
        const w = gpg.party[i].player_role;
        for (0..MAX_PLAYER_EQUIPMENTS) |j| {
            if (gpg.g.player_roles.equipment[j][w] == object_id) count += 1;
        }
    }
    return count;
}

// --- PAL_IncreaseHPMP ---
pub fn increaseHPMP(role: u16, hp: i16, mp: i16) bool {
    var success: bool = false;
    const orig_hp = gpg.g.player_roles.hp[role];
    const orig_mp = gpg.g.player_roles.mp[role];

    if (orig_hp == 0) return false;

    var new_hp: i32 = @as(i32, orig_hp) + hp;
    if (new_hp < 0) new_hp = 0;
    if (new_hp > gpg.g.player_roles.max_hp[role]) new_hp = gpg.g.player_roles.max_hp[role];
    gpg.g.player_roles.hp[role] = @intCast(new_hp);

    var new_mp: i32 = @as(i32, orig_mp) + mp;
    if (new_mp < 0) new_mp = 0;
    if (new_mp > gpg.g.player_roles.max_mp[role]) new_mp = gpg.g.player_roles.max_mp[role];
    gpg.g.player_roles.mp[role] = @intCast(new_mp);

    if (orig_hp != gpg.g.player_roles.hp[role] or orig_mp != gpg.g.player_roles.mp[role]) {
        success = true;
    }
    return success;
}

// --- PAL_GetPlayerAttackStrength / Magic / Defense / Dexterity / FleeRate / PoisonResistance ---
pub fn getPlayerAttackStrength(role: u16) u16 {
    var w: u32 = gpg.g.player_roles.attack_strength[role];
    var i: u32 = 0;
    while (i <= MAX_PLAYER_EQUIPMENTS) : (i += 1) {
        w +%= gpg.equipment_effect[i].attack_strength[role];
    }
    return @truncate(w);
}

pub fn getPlayerMagicStrength(role: u16) u16 {
    var w: u32 = gpg.g.player_roles.magic_strength[role];
    var i: u32 = 0;
    while (i <= MAX_PLAYER_EQUIPMENTS) : (i += 1) {
        w +%= gpg.equipment_effect[i].magic_strength[role];
    }
    return @truncate(w);
}

pub fn getPlayerDefense(role: u16) u16 {
    var w: u32 = gpg.g.player_roles.defense[role];
    var i: u32 = 0;
    while (i <= MAX_PLAYER_EQUIPMENTS) : (i += 1) {
        w +%= gpg.equipment_effect[i].defense[role];
    }
    return @truncate(w);
}

pub fn getPlayerDexterity(role: u16) u16 {
    var w: u32 = gpg.g.player_roles.dexterity[role];
    var i: u32 = 0;
    while (i <= MAX_PLAYER_EQUIPMENTS) : (i += 1) {
        w +%= gpg.equipment_effect[i].dexterity[role];
    }
    return @truncate(w);
}

pub fn getPlayerFleeRate(role: u16) u16 {
    var w: u32 = gpg.g.player_roles.flee_rate[role];
    var i: u32 = 0;
    while (i <= MAX_PLAYER_EQUIPMENTS) : (i += 1) {
        w +%= gpg.equipment_effect[i].flee_rate[role];
    }
    return @truncate(w);
}

pub fn getPlayerPoisonResistance(role: u16) u16 {
    var w: u32 = gpg.g.player_roles.poison_resistance[role];
    var i: u32 = 0;
    while (i <= MAX_PLAYER_EQUIPMENTS) : (i += 1) {
        w +%= gpg.equipment_effect[i].poison_resistance[role];
    }
    if (w > 100) w = 100;
    return @truncate(w);
}

// PAL_GetPlayerCooperativeMagic — base + equipment overrides.
pub fn getPlayerCooperativeMagic(role: u16) u16 {
    var w: u16 = gpg.g.player_roles.cooperative_magic[role];
    var i: u32 = 0;
    while (i <= MAX_PLAYER_EQUIPMENTS) : (i += 1) {
        const v = gpg.equipment_effect[i].cooperative_magic[role];
        if (v != 0) w = v;
    }
    return w;
}

// PAL_AddMagic — append a magic to the player's spell list. Returns true on success.
pub fn addMagic(role: u16, magic: u16) bool {
    var i: u32 = 0;
    while (i < MAX_PLAYER_MAGICS) : (i += 1) {
        if (gpg.g.player_roles.magic[i][role] == magic) return false;
    }
    i = 0;
    while (i < MAX_PLAYER_MAGICS) : (i += 1) {
        if (gpg.g.player_roles.magic[i][role] == 0) break;
    }
    if (i >= MAX_PLAYER_MAGICS) return false;
    gpg.g.player_roles.magic[i][role] = magic;
    return true;
}

// PAL_PlayerLevelUp — bump level by `n_levels` and roll the per-level deltas.
pub fn playerLevelUp(role: u16, n_levels: u32) void {
    const util = @import("util.zig");
    gpg.g.player_roles.level[role] +%= @intCast(n_levels);
    if (gpg.g.player_roles.level[role] > MAX_LEVELS) {
        gpg.g.player_roles.level[role] = MAX_LEVELS;
    }
    var i: u32 = 0;
    while (i < n_levels) : (i += 1) {
        gpg.g.player_roles.max_hp[role] +%= @intCast(10 + util.randomLong(0, 7));
        gpg.g.player_roles.max_mp[role] +%= @intCast(8 + util.randomLong(0, 5));
        gpg.g.player_roles.attack_strength[role] +%= @intCast(4 + util.randomLong(0, 1));
        gpg.g.player_roles.magic_strength[role] +%= @intCast(4 + util.randomLong(0, 1));
        gpg.g.player_roles.defense[role] +%= @intCast(2 + util.randomLong(0, 1));
        gpg.g.player_roles.dexterity[role] +%= @intCast(2 + util.randomLong(0, 1));
        gpg.g.player_roles.flee_rate[role] +%= 2;
    }
    if (gpg.g.player_roles.max_hp[role] > MAX_PROPERTY_VALUE) gpg.g.player_roles.max_hp[role] = MAX_PROPERTY_VALUE;
    if (gpg.g.player_roles.max_mp[role] > MAX_PROPERTY_VALUE) gpg.g.player_roles.max_mp[role] = MAX_PROPERTY_VALUE;
    if (gpg.g.player_roles.attack_strength[role] > MAX_PROPERTY_VALUE) gpg.g.player_roles.attack_strength[role] = MAX_PROPERTY_VALUE;
    if (gpg.g.player_roles.magic_strength[role] > MAX_PROPERTY_VALUE) gpg.g.player_roles.magic_strength[role] = MAX_PROPERTY_VALUE;
    if (gpg.g.player_roles.defense[role] > MAX_PROPERTY_VALUE) gpg.g.player_roles.defense[role] = MAX_PROPERTY_VALUE;
    if (gpg.g.player_roles.dexterity[role] > MAX_PROPERTY_VALUE) gpg.g.player_roles.dexterity[role] = MAX_PROPERTY_VALUE;
    if (gpg.g.player_roles.flee_rate[role] > MAX_PROPERTY_VALUE) gpg.g.player_roles.flee_rate[role] = MAX_PROPERTY_VALUE;
    gpg.exp.primary[role].exp = 0;
    gpg.exp.primary[role].level = gpg.g.player_roles.level[role];
}

// PAL_GetPlayerElementalResistance — base + equipment additive.
pub fn getPlayerElementalResistance(role: u16, elem: u32) u16 {
    var w: u32 = gpg.g.player_roles.elemental_resistance[elem][role];
    var i: u32 = 0;
    while (i <= MAX_PLAYER_EQUIPMENTS) : (i += 1) {
        w +%= gpg.equipment_effect[i].elemental_resistance[elem][role];
    }
    return @truncate(w);
}

// PAL_PlayerCanAttackAll — true if any equipment slot grants attack-all.
pub fn playerCanAttackAll(role: u16) bool {
    var i: u32 = 0;
    while (i <= MAX_PLAYER_EQUIPMENTS) : (i += 1) {
        if (gpg.equipment_effect[i].attack_all[role] != 0) return true;
    }
    return false;
}

// Resolve a player_role into a party slot index, or null if not in party.
fn partySlotOf(role: u16) ?u32 {
    var i: u32 = 0;
    while (i <= gpg.max_party_member_index) : (i += 1) {
        if (gpg.party[i].player_role == role) return i;
    }
    return null;
}

// PAL_AddPoisonForPlayer — global.c L1459 (魔改 two-pass version).
// Vanilla bailed out of one loop on either dedup match OR empty slot,
// which meant a free slot before an existing duplicate would re-add the
// poison. Pass 1 walks every slot to dedup; pass 2 finds the empty slot.
pub fn addPoisonForPlayer(role: u16, poison_id: u16) void {
    const idx = partySlotOf(role) orelse return;

    var i: u32 = 0;
    while (i < MAX_POISONS) : (i += 1) {
        if (gpg.poison_status[i][idx].poison_id == poison_id) return;
    }
    i = 0;
    while (i < MAX_POISONS) : (i += 1) {
        if (gpg.poison_status[i][idx].poison_id == 0) break;
    }
    if (i < MAX_POISONS) {
        gpg.poison_status[i][idx].poison_id = poison_id;
        gpg.poison_status[i][idx].poison_script =
            @import("script.zig").runTriggerScript(gpg.g.objects[poison_id].poison().player_script, role);
    }
}

// PAL_CurePoisonByKind — global.c L1520.
pub fn curePoisonByKind(role: u16, poison_id: u16) void {
    const idx = partySlotOf(role) orelse return;
    var i: u32 = 0;
    while (i < MAX_POISONS) : (i += 1) {
        if (gpg.poison_status[i][idx].poison_id == poison_id) {
            gpg.poison_status[i][idx].poison_id = 0;
            gpg.poison_status[i][idx].poison_script = 0;
        }
    }
}

// PAL_CurePoisonByLevel — global.c L1567.
pub fn curePoisonByLevel(role: u16, max_level: u16) void {
    const idx = partySlotOf(role) orelse return;
    var i: u32 = 0;
    while (i < MAX_POISONS) : (i += 1) {
        const w = gpg.poison_status[i][idx].poison_id;
        if (gpg.g.objects[w].poison().poison_level <= max_level) {
            gpg.poison_status[i][idx].poison_id = 0;
            gpg.poison_status[i][idx].poison_script = 0;
        }
    }
}

// PAL_IsPlayerPoisonedByLevel — global.c L1617.
pub fn isPlayerPoisonedByLevel(role: u16, min_level: u16) bool {
    const idx = partySlotOf(role) orelse return false;
    var i: u32 = 0;
    while (i < MAX_POISONS) : (i += 1) {
        const w = gpg.poison_status[i][idx].poison_id;
        if (w == 0) continue;
        const lvl = gpg.g.objects[w].poison().poison_level;
        if (lvl >= 99) continue; // equipment effects ignored
        if (lvl >= min_level) return true;
    }
    return false;
}

// PAL_IsPlayerPoisonedByKind — global.c L1687.
pub fn isPlayerPoisonedByKind(role: u16, poison_id: u16) bool {
    const idx = partySlotOf(role) orelse return false;
    var i: u32 = 0;
    while (i < MAX_POISONS) : (i += 1) {
        if (gpg.poison_status[i][idx].poison_id == poison_id) return true;
    }
    return false;
}

// PAL_SetPlayerStatus — global.c L2173. Returns false if puppet on alive player.
pub fn setPlayerStatus(role: u16, status_id: u16, num_round: u16) bool {
    var success = true;
    switch (status_id) {
        STATUS_CONFUSED, STATUS_SLEEP, STATUS_SILENCE, STATUS_PARALYZED => {
            // Bad statuses: don't overwrite if already present.
            if (gpg.player_status[role][status_id] == 0) {
                gpg.player_status[role][status_id] = num_round;
            }
        },
        STATUS_PUPPET => {
            if (gpg.g.player_roles.hp[role] == 0) {
                if (gpg.player_status[role][status_id] < num_round) {
                    gpg.player_status[role][status_id] = num_round;
                }
            } else {
                success = false;
            }
        },
        STATUS_BRAVERY, STATUS_PROTECT, STATUS_DUAL_ATTACK, STATUS_HASTE => {
            // Good statuses: refresh if longer.
            if (gpg.g.player_roles.hp[role] != 0 and
                gpg.player_status[role][status_id] < num_round)
            {
                gpg.player_status[role][status_id] = num_round;
            }
        },
        else => unreachable,
    }
    return success;
}

// PAL_SetPlayerStatusAll — apply a status to every active party member.
// Used by 魔改 opcode 0x002D when operand[2] is set, so a single script
// instruction can grant party-wide haste / bravery etc.
pub fn setPlayerStatusAll(status_id: u16, num_round: u16) bool {
    var success = true;
    var i: u32 = 0;
    while (i <= gpg.max_party_member_index) : (i += 1) {
        const w = gpg.party[i].player_role;
        if (!setPlayerStatus(w, status_id, num_round)) success = false;
    }
    return success;
}

// PAL_UpdateEquipments — global.c L1333. Reset all equipment effects to
// zero, then re-run each equipped item's script_on_equip so they re-grant
// their bonuses. Called whenever the party / equipment changes and at
// battle start.
pub fn updateEquipments() void {
    @memset(std.mem.asBytes(&gpg.equipment_effect), 0);

    var i: u16 = 0;
    while (i < MAX_PLAYER_ROLES) : (i += 1) {
        var j: u32 = 0;
        while (j < MAX_PLAYER_EQUIPMENTS) : (j += 1) {
            const w = gpg.g.player_roles.equipment[j][i];
            if (w != 0) {
                const new_eq = @import("script.zig").runTriggerScript(gpg.g.objects[w].item().script_on_equip, i);
                gpg.g.objects[w].data[3] = new_eq; // OBJECT_ITEM.script_on_equip
            }
        }
    }
}

// PAL_RemovePlayerStatus — global.c L2280. Don't clear equipment-granted
// statuses (those have value > 999).
pub fn removePlayerStatus(role: u16, status_id: u16) void {
    if (gpg.player_status[role][status_id] <= 999) {
        gpg.player_status[role][status_id] = 0;
    }
}

// PAL_ClearAllPlayerStatus — global.c L2311. Like removePlayerStatus but for
// every role × status, preserving equipment-granted (>999) entries.
pub fn clearAllPlayerStatus() void {
    var i: usize = 0;
    while (i < MAX_PLAYER_ROLES) : (i += 1) {
        var j: usize = 0;
        while (j < STATUS_ALL) : (j += 1) {
            if (gpg.player_status[i][j] <= 999) {
                gpg.player_status[i][j] = 0;
            }
        }
    }
}

// PAL_RemoveEquipmentEffect — global.c L1372. Zero the per-role columns of
// gpg.equipment_effect[part]. Hand resets DUAL_ATTACK; wear strips poisons
// with level >= 99 (equipment-granted).
pub fn removeEquipmentEffect(role: u16, equip_part: u16) void {
    const p: [*]u16 = @ptrCast(@alignCast(&gpg.equipment_effect[equip_part]));
    const n_fields = @sizeOf(PlayerRoles) / (2 * MAX_PLAYER_ROLES);
    var i: usize = 0;
    while (i < n_fields) : (i += 1) {
        p[i * MAX_PLAYER_ROLES + role] = 0;
    }

    if (equip_part == BODYPART_HAND) {
        gpg.player_status[role][STATUS_DUAL_ATTACK] = 0;
    } else if (equip_part == BODYPART_WEAR) {
        const idx = partySlotOf(role) orelse return;
        var j: usize = 0;
        var k: usize = 0;
        while (k < MAX_POISONS) : (k += 1) {
            const w = gpg.poison_status[k][idx].poison_id;
            if (w == 0) break;
            if (gpg.g.objects[w].poison().poison_level < 99) {
                gpg.poison_status[j][idx] = gpg.poison_status[k][idx];
                j += 1;
            }
        }
        while (j < MAX_POISONS) : (j += 1) {
            gpg.poison_status[j][idx].poison_id = 0;
            gpg.poison_status[j][idx].poison_script = 0;
        }
    }
}
