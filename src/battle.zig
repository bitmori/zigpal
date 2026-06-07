// Copyright (c) 2009-2011, Wei Mingzhi <whistler_wmz@users.sf.net>.
// Copyright (c) 2011-2026, SDLPAL development team.
// All rights reserved.
//
// This file is part of SDLPAL.
//
// SDLPAL is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License, version 3
// as published by the Free Software Foundation.

// Stage 7a — battle skeleton.
//
// Mirrors battle.h / battle.c. We follow PAL_CLASSIC (turn-based) and
// drop time-meter (#ifndef PAL_CLASSIC) fields. Sprites/background load,
// scene rendering, and a minimal main loop are wired so 0x0007 actually
// transitions into a battle screen. Combat logic (fight.c) lands in 7d.

const std = @import("std");
const global = @import("global.zig");
const palcommon = @import("palcommon.zig");
const video = @import("video.zig");
const ui = @import("ui.zig");
const input = @import("input.zig");
const util = @import("util.zig");
const yj1 = @import("yj1.zig");

// --- Constants ---

pub const MAX_BATTLE_MAGICSPRITE_ITEMS: u32 = 3;
pub const MAX_BATTLESPRITESEQ_ITEMS: u32 =
    global.MAX_ENEMIES_IN_TEAM + global.MAX_PLAYABLE_PLAYER_ROLES + MAX_BATTLE_MAGICSPRITE_ITEMS;

pub const MAX_BATTLE_ACTIONS: u32 = 256;
pub const MAX_KILLED_ENEMIES: u32 = 256;

// PAL_CLASSIC action queue.
pub const MAX_ACTIONQUEUE_ITEMS: u32 = global.MAX_PLAYERS_IN_PARTY + global.MAX_ENEMIES_IN_TEAM * 2;

// --- Enums ---

pub const BattleResult = enum(u16) {
    won = 3,
    lost = 1,
    fleed = 0xFFFF,
    terminated = 0,
    on_going = 1000,
    pre_battle = 1001,
    pause = 1002,
};

pub const FighterState = enum(u8) {
    wait,
    com,
    act,
};

pub const BattleActionType = enum(u8) {
    pass,
    defend,
    attack,
    magic,
    coop_magic,
    flee,
    throw_item,
    use_item,
    attack_mate,
};

pub const BattleSpriteType = enum(u8) {
    none,
    enemy,
    player,
    magic,
};

pub const BattlePhase = enum(u8) {
    select_action,
    perform_action,
};

pub const BattleUIState = enum(u8) {
    wait,
    select_move,
    select_target_enemy,
    select_target_player,
    select_target_enemy_all,
    select_target_player_all,
};

pub const BattleMenuState = enum(u8) {
    main,
    magic_select,
    use_item_select,
    throw_item_select,
    misc,
    misc_item_sub_menu,
};

// --- Records ---

pub const BattleAction = struct {
    action_type: BattleActionType = .pass,
    action_id: u16 = 0,
    target: i16 = 0,
};

pub const BattleEnemy = struct {
    object_id: u16 = 0,
    e: global.Enemy = undefined,
    status: [global.STATUS_ALL]u16 = [_]u16{0} ** global.STATUS_ALL,
    poisons: [global.MAX_POISONS]global.PoisonStatus =
        [_]global.PoisonStatus{.{ .poison_id = 0, .poison_script = 0 }} ** global.MAX_POISONS,
    sprite: ?[]u8 = null,
    pos: u32 = 0,
    pos_original: u32 = 0,
    current_frame: u16 = 0,
    state: FighterState = .wait,
    script_on_turn_start: u16 = 0,
    script_on_battle_end: u16 = 0,
    script_on_ready: u16 = 0,
    prev_hp: u16 = 0,
    color_shift: i32 = 0,
};

pub const BattlePlayer = struct {
    color_shift: i32 = 0,
    hiding_time: u16 = 0,
    sprite: ?[]u8 = null,
    pos: u32 = 0,
    pos_original: u32 = 0,
    current_frame: u16 = 0,
    state: FighterState = .wait,
    action: BattleAction = .{},
    prev_action: BattleAction = .{},
    defending: bool = false,
    second_attack: bool = false,
    prev_hp: u16 = 0,
    prev_mp: u16 = 0,
};

pub const BattleSpriteSeq = struct {
    type: BattleSpriteType = .none,
    object_index: i32 = 0,
    pos: u32 = 0,
    layer_offset: i16 = 0,
    has_color_shift: bool = false,
};

pub const ShowNum = struct {
    num: u16 = 0,
    pos: u32 = 0,
    time: u32 = 0,
    color: ui.NumColorEx = .yellow,
};

pub const BATTLEUI_MAX_SHOWNUM: u32 = 16;

pub const BattleUI = struct {
    state: BattleUIState = .wait,
    menu_state: BattleMenuState = .main,
    msg: [256]u8 = [_]u8{0} ** 256,
    next_msg: [256]u8 = [_]u8{0} ** 256,
    msg_show_time: u32 = 0,
    next_msg_duration: u16 = 0,
    cur_player_index: u16 = 0,
    selected_action: u16 = 0,
    selected_index: i32 = 0,
    prev_enemy_target: i32 = -1,
    action_type: u16 = 0,
    object_id: u16 = 0,
    auto_attack: bool = false,
    show_num: [BATTLEUI_MAX_SHOWNUM]ShowNum = [_]ShowNum{.{}} ** BATTLEUI_MAX_SHOWNUM,
};

pub const ActionQueue = struct {
    is_enemy: bool = false,
    dexterity: u16 = 0,
    index: u16 = 0,
    is_second: bool = false,
};

pub const Battle = struct {
    players: [global.MAX_PLAYERS_IN_PARTY]BattlePlayer = [_]BattlePlayer{.{}} ** global.MAX_PLAYERS_IN_PARTY,
    enemies: [global.MAX_ENEMIES_IN_TEAM]BattleEnemy = [_]BattleEnemy{.{}} ** global.MAX_ENEMIES_IN_TEAM,
    max_enemy_index: i32 = 0,

    // Background and scene buffers (gpScreen-compatible 8bpp surfaces).
    scene_buf_pixels: [video.SCREEN_WIDTH * video.SCREEN_HEIGHT]u8 =
        [_]u8{0} ** (video.SCREEN_WIDTH * video.SCREEN_HEIGHT),
    background_pixels: [video.SCREEN_WIDTH * video.SCREEN_HEIGHT]u8 =
        [_]u8{0} ** (video.SCREEN_WIDTH * video.SCREEN_HEIGHT),

    background_color_shift: i16 = 0,

    summon_sprite: ?[]u8 = null,
    pos_summon: u32 = 0,
    summon_frame: i32 = 0,
    summon_color_shift: bool = false,

    exp_gained: i32 = 0,
    cash_gained: i32 = 0,

    is_boss: bool = false,
    enemy_cleared: bool = false,
    result: BattleResult = .pre_battle,

    ui: BattleUI = .{},

    effect_sprite: ?[]u8 = null,

    enemy_moving: bool = false,
    hiding_time: i32 = 0,
    moving_player_index: u16 = 0,
    blow: i32 = 0,

    magic_bitmap: ?[]const u8 = null,

    sprite_draw_seq: [MAX_BATTLESPRITESEQ_ITEMS]BattleSpriteSeq = [_]BattleSpriteSeq{.{}} ** MAX_BATTLESPRITESEQ_ITEMS,
    max_sprite_draw_seq_index: u16 = 0,
    sprite_add_lock: bool = false,

    // PAL_CLASSIC fields.
    phase: BattlePhase = .select_action,
    action_queue: [MAX_ACTIONQUEUE_ITEMS]ActionQueue = [_]ActionQueue{.{}} ** MAX_ACTIONQUEUE_ITEMS,
    cur_action: i32 = 0,
    repeat: bool = false,
    force: bool = false,
    flee: bool = false,
    prev_auto_atk: bool = false,
    prev_player_auto_atk: bool = false,
    coop_contributors: [global.MAX_PLAYERS_IN_PARTY]u16 = [_]u16{0} ** global.MAX_PLAYERS_IN_PARTY,
    this_turn_coop: bool = false,
};

pub var g_battle: Battle = .{};

// Default player positions per party size — copied from battle.c g_rgPlayerPos.
const PLAYER_POS: [3][3][2]u16 = .{
    .{ .{ 240, 170 }, .{ 0, 0 }, .{ 0, 0 } }, // one player
    .{ .{ 200, 176 }, .{ 256, 152 }, .{ 0, 0 } }, // two players
    .{ .{ 180, 180 }, .{ 234, 170 }, .{ 270, 146 } }, // three players
};

pub const PLAYER_POS_PUB = PLAYER_POS;

// --- Sprite loading ---

// PAL_GetPlayerBattleSprite — base sprite + equipment overrides.
pub fn getPlayerBattleSprite(player_role: u16) u16 {
    var w: u16 = global.gpg.g.player_roles.sprite_num_in_battle[player_role];
    var i: u32 = 0;
    while (i <= global.MAX_PLAYER_EQUIPMENTS) : (i += 1) {
        const v = global.gpg.equipment_effect[i].sprite_num_in_battle[player_role];
        if (v != 0) w = v;
    }
    return w;
}

fn freeBattleSprites() void {
    for (&g_battle.players) |*p| {
        if (p.sprite) |buf| global.allocator.free(buf);
        p.sprite = null;
    }
    for (&g_battle.enemies) |*e| {
        if (e.sprite) |buf| global.allocator.free(buf);
        e.sprite = null;
    }
    if (g_battle.summon_sprite) |buf| {
        global.allocator.free(buf);
        g_battle.summon_sprite = null;
    }
}

fn decompressMkfChunk(mkf: palcommon.MkfFile, chunk_num: u32) ?[]u8 {
    const compressed = mkf.getChunkData(chunk_num) catch return null;
    const sz = mkf.getDecompressedSize(chunk_num, false) catch return null;
    const buf = global.allocator.alloc(u8, sz) catch return null;
    _ = yj1.decompress(compressed, buf) catch {
        global.allocator.free(buf);
        return null;
    };
    return buf;
}

// PAL_LoadBattleSprites — players from F.MKF, enemies from ABC.MKF.
pub fn loadBattleSprites() void {
    freeBattleSprites();

    const f = global.gpg.f.f orelse return;
    const abc = global.gpg.f.abc orelse return;

    // Players.
    var i: u32 = 0;
    while (i <= global.gpg.max_party_member_index) : (i += 1) {
        const role = global.gpg.party[i].player_role;
        const s = getPlayerBattleSprite(role);
        g_battle.players[i].sprite = decompressMkfChunk(f, s);

        const party_size = @as(u32, global.gpg.max_party_member_index);
        const pos = PLAYER_POS[party_size][i];
        const x: i16 = @intCast(pos[0]);
        const y: i16 = @intCast(pos[1]);
        g_battle.players[i].pos_original = global.palXY(x, y);
        g_battle.players[i].pos = global.palXY(x, y);
    }

    // Enemies.
    i = 0;
    while (i < global.MAX_ENEMIES_IN_TEAM) : (i += 1) {
        if (g_battle.enemies[i].object_id == 0) continue;
        const enemy_id = global.gpg.g.objects[g_battle.enemies[i].object_id].data[0];
        g_battle.enemies[i].sprite = decompressMkfChunk(abc, enemy_id);

        const max_idx: u32 = @intCast(g_battle.max_enemy_index);
        const ep = global.gpg.g.enemy_pos.pos[i][max_idx];
        const x: i16 = @bitCast(ep.x);
        const y: i32 = @as(i32, @bitCast(@as(u32, ep.y))) + @as(i32, g_battle.enemies[i].e.y_pos_offset);
        const y16: i16 = @intCast(y);
        g_battle.enemies[i].pos_original = global.palXY(x, y16);
        g_battle.enemies[i].pos = global.palXY(x, y16);
    }
}

// PAL_LoadBattleBackground — decompress wNumBattleField from FBP.MKF.
fn loadBattleBackground() void {
    const fbp = global.gpg.f.fbp orelse return;
    const compressed = fbp.getChunkData(global.gpg.num_battle_field) catch return;
    const buf = global.allocator.alloc(u8, video.SCREEN_WIDTH * video.SCREEN_HEIGHT) catch return;
    defer global.allocator.free(buf);
    _ = yj1.decompress(compressed, buf) catch return;
    @memcpy(&g_battle.background_pixels, buf);
}

// --- Battle initialization (PAL_StartBattle prefix) ---

fn initBattle(enemy_team: u16, is_boss: bool) void {
    // Make sure everyone in the party is alive; clear hidden EXP counts.
    var i: u32 = 0;
    while (i <= global.gpg.max_party_member_index) : (i += 1) {
        const w = global.gpg.party[i].player_role;
        if (global.gpg.g.player_roles.hp[w] == 0) {
            global.gpg.g.player_roles.hp[w] = 1;
            global.gpg.player_status[w][global.STATUS_PUPPET] = 0;
        }
        global.gpg.exp.health[w].count = 0;
        global.gpg.exp.magic_exp[w].count = 0;
        global.gpg.exp.attack[w].count = 0;
        global.gpg.exp.magic_power[w].count = 0;
        global.gpg.exp.defense[w].count = 0;
        global.gpg.exp.dexterity[w].count = 0;
        global.gpg.exp.flee[w].count = 0;
    }

    // Clear in-use counts.
    for (&global.gpg.inventory) |*it| it.amount_in_use = 0;

    // Store enemies.
    var j: u32 = 0;
    i = 0;
    while (j < global.MAX_ENEMIES_IN_TEAM) : (j += 1) {
        g_battle.enemies[j] = .{};
        const obj = global.gpg.g.enemy_teams[enemy_team].enemy[j];
        if (obj == 0xFFFF) continue;
        if (obj != 0) {
            const enemy_id = global.gpg.g.objects[obj].data[0]; // wEnemyID
            g_battle.enemies[i].e = global.gpg.g.enemies[enemy_id];
            g_battle.enemies[i].state = .wait;
            // OBJECT_ENEMY layout: data[0]=wEnemyID, data[1]=resistance, data[2]=on_turn_start,
            //                     data[3]=on_battle_end, data[4]=on_ready
            g_battle.enemies[i].script_on_turn_start = global.gpg.g.objects[obj].data[2];
            g_battle.enemies[i].script_on_battle_end = global.gpg.g.objects[obj].data[3];
            g_battle.enemies[i].script_on_ready = global.gpg.g.objects[obj].data[4];
            g_battle.enemies[i].color_shift = 0;
        }
        g_battle.enemies[i].object_id = obj;
        i += 1;
    }
    g_battle.max_enemy_index = @as(i32, @intCast(i)) - 1;

    // Reset players.
    i = 0;
    while (i <= global.gpg.max_party_member_index) : (i += 1) {
        g_battle.players[i].hiding_time = 0;
        g_battle.players[i].state = .wait;
        g_battle.players[i].defending = false;
        g_battle.players[i].current_frame = 0;
        g_battle.players[i].color_shift = 0;
    }

    loadBattleSprites();
    loadBattleBackground();

    // battle.c L1754: re-apply every equipment's script_on_equip so per-
    // battle bonuses (atk/def, status, etc.) take effect.
    global.updateEquipments();

    g_battle.exp_gained = 0;
    g_battle.cash_gained = 0;
    g_battle.is_boss = is_boss;
    g_battle.enemy_cleared = false;
    g_battle.enemy_moving = false;
    g_battle.hiding_time = 0;
    g_battle.moving_player_index = 0;

    g_battle.ui = .{};
    g_battle.ui.prev_enemy_target = -1;

    g_battle.summon_sprite = null;
    g_battle.background_color_shift = 0;

    global.gpg.in_battle = true;
    g_battle.result = .pre_battle;
    g_battle.sprite_add_lock = true;

    // battle.c L1782: refresh fighter positions/frames before main loop.
    @import("fight.zig").updateFighters();

    // Battle effect sprite (DATA chunk 10).
    if (global.gpg.f.data) |data| {
        if (data.getChunkData(10)) |bytes| {
            const buf = global.allocator.alloc(u8, bytes.len) catch null;
            if (buf) |b| {
                @memcpy(b, bytes);
                g_battle.effect_sprite = b;
            }
        } else |_| {}
    }

    // PAL_CLASSIC.
    g_battle.phase = .select_action;
    g_battle.repeat = false;
    g_battle.force = false;
    g_battle.flee = false;
    g_battle.prev_auto_atk = false;
    g_battle.this_turn_coop = false;
}

fn freeBattle() void {
    freeBattleSprites();
    if (g_battle.effect_sprite) |buf| {
        global.allocator.free(buf);
        g_battle.effect_sprite = null;
    }
    global.gpg.in_battle = false;
}

// --- Main battle loop (Stage 7a stub) ---

fn battleStartFrame() void {
    if (util.shouldQuit()) {
        g_battle.result = .fleed;
        return;
    }
    @import("fight.zig").startFrame();
    @import("battleui.zig").update();
}

// Called by fight.zig when the player commits a flee action.
pub fn flagPlayerFleeing() void {
    g_battle.flee = true;
}

fn battleMain() BattleResult {
    // SDLPAL battle.c:706 — back up the world-view screen, paint the freshly
    // composed battle scene, then run VIDEO_SwitchScreen(5) to do the 6-step
    // pixel-stride transition that visually swaps from world to battle.
    video.backupScreen();
    battleMakeScene();
    @memcpy(&video.screen_pixels, &g_battle.scene_buf_pixels);
    video.switchScreen(5);

    // Honour the pending fade-in flag so a battle started during a faded-out
    // scene reveals through PAL_FadeIn instead of jump-cutting.
    if (global.gpg.need_to_fade_in) {
        @import("palette.zig").fadeIn(@intCast(global.gpg.num_palette), global.gpg.night_palette, 1);
        global.gpg.need_to_fade_in = false;
    }

    // Pre-battle scripts.
    var i: u32 = 0;
    while (g_battle.max_enemy_index >= 0 and i <= @as(u32, @intCast(g_battle.max_enemy_index))) : (i += 1) {
        g_battle.enemies[i].script_on_turn_start =
            @import("script.zig").runTriggerScript(g_battle.enemies[i].script_on_turn_start, @intCast(i));
        if (g_battle.result != .pre_battle) break;
    }
    if (g_battle.result == .pre_battle) g_battle.result = .on_going;

    var dw_time = util.getTicks();
    input.clearKeyState();

    while (g_battle.result == .on_going) {
        if (util.shouldQuit()) {
            g_battle.result = .fleed;
            break;
        }
        while (util.getTicks() < dw_time) {
            input.processEvent();
            std.Thread.yield() catch {};
            if (util.shouldQuit()) {
                g_battle.result = .fleed;
                break;
            }
        }
        dw_time = util.getTicks() + global.BATTLE_FRAME_TIME;

        // Scene first (background + sprites into screen), then UI overlays.
        battleMakeScene();
        @memcpy(&video.screen_pixels, &g_battle.scene_buf_pixels);
        battleStartFrame();
        video.updateScreen(null);
    }

    return g_battle.result;
}

// PAL_BattleDrawBackground — copy the precomputed background into the scene
// buffer with a per-pixel low-nibble color shift, then apply screen wave. The
// 0x80/0x70 saturation comes straight from battle.c.
fn battleDrawBackground() void {
    const shift = g_battle.background_color_shift;
    var i: usize = 0;
    while (i < video.SCREEN_WIDTH * video.SCREEN_HEIGHT) : (i += 1) {
        const src = g_battle.background_pixels[i];
        const lo: i32 = @as(i32, src & 0x0F) + shift;
        const out_lo: u8 = if (lo & 0x80 != 0)
            0
        else if (lo & 0x70 != 0)
            0x0F
        else
            @intCast(lo & 0x0F);
        g_battle.scene_buf_pixels[i] = (src & 0xF0) | out_lo;
    }

    // PAL_ApplyWave operates on video.screen — apply on the scene buffer
    // by swapping the screen pointer-style. We instead memcpy then wave.
    @memcpy(&video.screen_pixels, &g_battle.scene_buf_pixels);
    @import("scene.zig").applyWave();
    @memcpy(&g_battle.scene_buf_pixels, &video.screen_pixels);
}

// PAL_BattleDrawEnemySprites — center the sprite bitmap on enemy.pos.
fn drawEnemySprites(idx: u32, dst: *palcommon.Surface) void {
    const e = &g_battle.enemies[idx];
    if (e.object_id == 0) return;
    const sprite = e.sprite orelse return;
    const frame = palcommon.spriteGetFrame(sprite, @intCast(e.current_frame)) orelse return;

    var pos = e.pos;
    if (e.status[global.STATUS_CONFUSED] > 0 and
        e.status[global.STATUS_SLEEP] == 0 and
        e.status[global.STATUS_PARALYZED] == 0)
    {
        const dx = util.randomLong(-1, 1);
        pos = global.palXY(@truncate(@as(i32, global.palX(pos)) + dx), global.palY(pos));
    }

    const w: i32 = palcommon.rleGetWidth(frame);
    const h: i32 = palcommon.rleGetHeight(frame);
    const top_left = global.palXY(
        @truncate(@as(i32, global.palX(pos)) - @divTrunc(w, 2)),
        @truncate(@as(i32, global.palY(pos)) - h),
    );

    if (e.color_shift != 0) {
        _ = palcommon.rleBlitWithColorShift(frame, dst, top_left, e.color_shift);
    } else {
        _ = palcommon.rleBlitToSurface(frame, dst, top_left);
    }
}

// PAL_BattleDrawPlayerSprites — index 0xFFFF means draw the summoned god.
fn drawPlayerSprites(idx: i32, dst: *palcommon.Surface) void {
    if (idx == -1 or idx == 0xFFFF) {
        const sprite = g_battle.summon_sprite orelse return;
        const frame = palcommon.spriteGetFrame(sprite, g_battle.summon_frame) orelse return;
        const w: i32 = palcommon.rleGetWidth(frame);
        const h: i32 = palcommon.rleGetHeight(frame);
        const top_left = global.palXY(
            @truncate(@as(i32, global.palX(g_battle.pos_summon)) - @divTrunc(w, 2)),
            @truncate(@as(i32, global.palY(g_battle.pos_summon)) - h),
        );
        _ = palcommon.rleBlitToSurface(frame, dst, top_left);
        return;
    }

    const u: u32 = @intCast(idx);
    const p = &g_battle.players[u];
    const sprite = p.sprite orelse return;
    const frame = palcommon.spriteGetFrame(sprite, @intCast(p.current_frame)) orelse return;

    const role = global.gpg.party[u].player_role;
    var pos = p.pos;
    if (global.gpg.player_status[role][global.STATUS_CONFUSED] != 0 and
        global.gpg.player_status[role][global.STATUS_SLEEP] == 0 and
        global.gpg.player_status[role][global.STATUS_PARALYZED] == 0 and
        global.gpg.g.player_roles.hp[role] > 0 and
        !isPlayerDying(role))
    {
        const dy = util.randomLong(-1, 1);
        pos = global.palXY(global.palX(pos), @truncate(@as(i32, global.palY(pos)) + dy));
    }

    const w: i32 = palcommon.rleGetWidth(frame);
    const h: i32 = palcommon.rleGetHeight(frame);
    const top_left = global.palXY(
        @truncate(@as(i32, global.palX(pos)) - @divTrunc(w, 2)),
        @truncate(@as(i32, global.palY(pos)) - h),
    );

    if (p.color_shift != 0) {
        _ = palcommon.rleBlitWithColorShift(frame, dst, top_left, p.color_shift);
    } else if (g_battle.hiding_time == 0) {
        _ = palcommon.rleBlitToSurface(frame, dst, top_left);
    }
}

fn drawMagicSprite(seq: BattleSpriteSeq, dst: *palcommon.Surface) void {
    const bmp = g_battle.magic_bitmap orelse return;
    const w: i32 = palcommon.rleGetWidth(bmp);
    const h: i32 = palcommon.rleGetHeight(bmp);
    const top_left = global.palXY(
        @truncate(@as(i32, global.palX(seq.pos)) - @divTrunc(w, 2)),
        @truncate(@as(i32, global.palY(seq.pos)) - h),
    );
    _ = palcommon.rleBlitToSurface(bmp, dst, top_left);
}

// PAL_IsPlayerDying — fight.c L46-48. hp < min(maxhp/5, 100).
pub fn isPlayerDying(role: u16) bool {
    const hp = global.gpg.g.player_roles.hp[role];
    const max = global.gpg.g.player_roles.max_hp[role];
    const threshold: u32 = @min(@as(u32, 100), @as(u32, max) / 5);
    return hp < threshold;
}

// PAL_BattleClearSpriteObject.
pub fn clearSpriteObject() void {
    g_battle.sprite_draw_seq = [_]BattleSpriteSeq{.{}} ** MAX_BATTLESPRITESEQ_ITEMS;
    g_battle.max_sprite_draw_seq_index = 0;
}

// PAL_BattleSpriteAddUnlock.
pub fn spriteAddUnlock() void {
    g_battle.sprite_add_lock = false;
    clearSpriteObject();
}

// PAL_BattleAddSpriteObject.
pub fn addSpriteObject(t: BattleSpriteType, object_index: i32, pos: u32, layer_offset: i16, has_color_shift: bool) void {
    if (g_battle.max_sprite_draw_seq_index + 1 < MAX_BATTLESPRITESEQ_ITEMS) {
        const seq = &g_battle.sprite_draw_seq[g_battle.max_sprite_draw_seq_index];
        seq.* = .{
            .type = t,
            .object_index = object_index,
            .pos = pos,
            .layer_offset = layer_offset,
            .has_color_shift = has_color_shift,
        };
        g_battle.max_sprite_draw_seq_index += 1;
    }
}

// PAL_BattleAddFighterSpriteObject.
fn addFighterSpriteObject() void {
    var i: i32 = 0;
    while (i <= g_battle.max_enemy_index) : (i += 1) {
        const u: u32 = @intCast(i);
        addSpriteObject(.enemy, i, g_battle.enemies[u].pos, 0, g_battle.enemies[u].color_shift != 0);
    }

    if (g_battle.summon_sprite != null) {
        addSpriteObject(.player, -1, g_battle.pos_summon, 0, g_battle.summon_color_shift);
    } else {
        i = 0;
        while (i <= @as(i32, global.gpg.max_party_member_index)) : (i += 1) {
            const u: u32 = @intCast(i);
            addSpriteObject(.player, i, g_battle.players[u].pos, 0, g_battle.players[u].color_shift != 0);
        }
    }
}

// PAL_BattleSortSpriteObjecByPos — bubble-sort by Y, ties broken by descending X.
fn sortSpriteObjectByPos() void {
    if (g_battle.max_sprite_draw_seq_index == 0) return;
    const n: usize = g_battle.max_sprite_draw_seq_index;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        var j: usize = i + 1;
        while (j <= n - 1) : (j += 1) {
            const a = &g_battle.sprite_draw_seq[i];
            const b = &g_battle.sprite_draw_seq[j];
            const ay: i32 = @as(i32, global.palY(a.pos)) + a.layer_offset;
            const by: i32 = @as(i32, global.palY(b.pos)) + b.layer_offset;
            if (ay > by) {
                const tmp = a.*;
                a.* = b.*;
                b.* = tmp;
            } else if (ay == by) {
                const ax: i32 = global.palX(a.pos);
                const bx: i32 = global.palX(b.pos);
                if (ax < bx) {
                    const tmp = a.*;
                    a.* = b.*;
                    b.* = tmp;
                }
            }
        }
    }
}

fn drawAllSpritesWithColorShift(only_color_shift: bool) void {
    sortSpriteObjectByPos();
    var i: u32 = 0;
    while (i <= @as(u32, g_battle.max_sprite_draw_seq_index)) : (i += 1) {
        const seq = g_battle.sprite_draw_seq[i];
        if (only_color_shift and !seq.has_color_shift) continue;
        switch (seq.type) {
            .none => {},
            .enemy => drawEnemySprites(@intCast(seq.object_index), &video.screen),
            .player => drawPlayerSprites(seq.object_index, &video.screen),
            .magic => drawMagicSprite(seq, &video.screen),
        }
    }
}

// PAL_BattleFadeScene — battle.c L608. Blend scene_buf into gpScreenBak over
// 12*6 = 72 frames, with a 6-pixel-stride dither pattern. The low nibble (the
// palette-shifted color index) is stepped one notch per outer iteration; the
// high nibble (palette page) is taken straight from scene_buf. After the loop
// the final frame is just scene_buf copied verbatim.
pub fn battleFadeScene() void {
    const rg_index = [_]usize{ 0, 3, 1, 5, 2, 4 };
    const total: usize = video.SCREEN_WIDTH * video.SCREEN_HEIGHT;
    var time: u32 = util.getTicks();

    var i: u32 = 0;
    while (i < 12) : (i += 1) {
        var j: u32 = 0;
        while (j < 6) : (j += 1) {
            while (util.getTicks() < time) {
                input.processEvent();
                std.Thread.yield() catch {};
                if (util.shouldQuit()) return;
            }
            time = util.getTicks() + 16;

            // Blend the pixels in the 2 buffers, and put the result into bak.
            var k: usize = rg_index[j];
            while (k < total) : (k += 6) {
                const a = g_battle.scene_buf_pixels[k];
                var b = video.screen_bak_pixels[k];
                if (i > 0) {
                    if ((a & 0x0F) > (b & 0x0F)) {
                        b +%= 1;
                    } else if ((a & 0x0F) < (b & 0x0F)) {
                        b -%= 1;
                    }
                }
                video.screen_bak_pixels[k] = (a & 0xF0) | (b & 0x0F);
            }

            // Draw bak to screen, then UI overlay.
            video.restoreScreen();
            @import("battleui.zig").update();
            video.updateScreen(null);
        }
    }

    // Final step: scene_buf as-is.
    @memcpy(&video.screen_pixels, &g_battle.scene_buf_pixels);
    @import("battleui.zig").update();
    video.updateScreen(null);
}

// PAL_BattleMakeScene.
pub fn battleMakeScene() void {
    battleDrawBackground();
    if (g_battle.sprite_add_lock) {
        clearSpriteObject();
    } else {
        g_battle.sprite_add_lock = true;
    }
    addFighterSpriteObject();

    // Draw to scene_buf via screen.
    @memcpy(&video.screen_pixels, &g_battle.scene_buf_pixels);
    drawAllSpritesWithColorShift(false);
    drawAllSpritesWithColorShift(true);
    @memcpy(&g_battle.scene_buf_pixels, &video.screen_pixels);
}

// PAL_StartBattle — entry point.
pub fn startBattle(enemy_team: u16, is_boss: bool) BattleResult {
    const palette = @import("palette.zig");

    const prev_wave_level = global.gpg.screen_wave;
    const prev_wave_progression = global.gpg.wave_progression;

    global.gpg.wave_progression = 0;
    global.gpg.screen_wave = global.gpg.g.battlefields[global.gpg.num_battle_field].screen_wave;

    initBattle(enemy_team, is_boss);

    // Battle music — fade out current BGM, then start the battle track.
    // Mirrors SDLPAL battle.c:717,728. wNumBattleMusic is set by script
    // op 0x0045 before battle is triggered.
    @import("audio.zig").stopMusic(1.0);
    util.delay(200);
    @import("audio.zig").playMusic(@intCast(global.gpg.num_battle_music), true, 0);

    if (global.gpg.need_to_fade_in) {
        palette.fadeIn(@intCast(global.gpg.num_palette), global.gpg.night_palette, 1);
        global.gpg.need_to_fade_in = false;
    }

    const result = battleMain();

    // Stage 7f: post-battle resolution. SDLPAL's PAL_StartBattle only handles
    // .won here; .fleed already played PlayerEscape inside the .flee action.
    if (result == .won) {
        @import("fight.zig").battleWon();
    }

    for (&global.gpg.inventory) |*it| it.amount_in_use = 0;

    // battle.c L1822-L1830: clear status (preserving equipment-granted),
    // cure low-level poisons, drop the kBodyPartExtra equipment effects
    // (temporary stat boosts from spells like 御靈靈感).
    global.clearAllPlayerStatus();
    var w: u32 = 0;
    while (w < global.MAX_PLAYER_ROLES) : (w += 1) {
        global.curePoisonByLevel(@intCast(w), global.EX_MAX_VISIBLE_POISON_LEVEL);
        global.removeEquipmentEffect(@intCast(w), global.BODYPART_EXTRA);
    }

    freeBattle();

    // Restore screen wave.
    global.gpg.wave_progression = prev_wave_progression;
    global.gpg.screen_wave = prev_wave_level;

    // Restore field BGM (SDLPAL battle.c:1849).
    @import("audio.zig").playMusic(@intCast(global.gpg.num_music), true, 1.0);

    return result;
}
