// Copyright (c) 2009-2011, Wei Mingzhi <whistler_wmz@users.sf.net>.
// Copyright (c) 2011-2026, SDLPAL development team.
// All rights reserved.
//
// This file is part of SDLPAL.
//
// SDLPAL is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License, version 3
// as published by the Free Software Foundation.

// Stage 7c — battle UI state machine.
//
// Mirrors uibattle.c PAL_BattleUIUpdate and friends. PAL_CLASSIC layout:
//   bottom-row icons:  Attack(40) Magic(41) CoopMagic(42) MiscMenu(43)
//   misc submenu:      Auto / Inventory / Defend / Flee / Status
//   item submenu:      Use / Throw

const std = @import("std");
const global = @import("global.zig");
const palcommon = @import("palcommon.zig");
const video = @import("video.zig");
const ui = @import("ui.zig");
const text = @import("text.zig");
const input = @import("input.zig");
const util = @import("util.zig");
const battle = @import("battle.zig");
const uibattle = @import("uibattle.zig");
const itemmenu = @import("itemmenu.zig");
const magicmenu = @import("magicmenu.zig");
const fight = @import("fight.zig");

// Sprite numbers from uibattle.h.
const SPR_BATTLEICON_ATTACK: i32 = 40;
const SPR_BATTLEICON_MAGIC: i32 = 41;
const SPR_BATTLEICON_COOPMAGIC: i32 = 42;
const SPR_BATTLEICON_MISCMENU: i32 = 43;
const SPR_ARROW_CURPLAYER: i32 = 69;
const SPR_ARROW_CURPLAYER_RED: i32 = 68;
const SPR_ARROW_SELPLAYER: i32 = 67;
const SPR_ARROW_SELPLAYER_RED: i32 = 66;

const BATTLEUI_LABEL_AUTO: u16 = 56;
const BATTLEUI_LABEL_INVENTORY: u16 = 57;
const BATTLEUI_LABEL_DEFEND: u16 = 58;
const BATTLEUI_LABEL_FLEE: u16 = 59;
const BATTLEUI_LABEL_STATUS: u16 = 60;
const BATTLEUI_LABEL_USEITEM: u16 = 23;
const BATTLEUI_LABEL_THROWITEM: u16 = 24;

// Frame counter — drives the alternating arrow/highlight blink.
var s_iframe: u32 = 0;
// Misc/sub menu cursor positions (preserved across enter/exit, like SDLPAL).
var g_cur_misc_menu_item: i32 = 0;
var g_cur_sub_menu_item: i32 = 0;

// PAL_BattleUIIsActionValid (PAL_CLASSIC subset).
fn isActionValid(action: u16) bool {
    const role = global.gpg.party[battle.g_battle.ui.cur_player_index].player_role;
    switch (action) {
        // Attack / Misc — always valid.
        0, 3 => return true,
        1 => return global.gpg.player_status[role][global.STATUS_SILENCE] == 0,
        2 => {
            // CoopMagic — needs >1 healthy party members and the current is healthy.
            if (global.gpg.max_party_member_index == 0) return false;
            var healthy: u32 = 0;
            var i: u32 = 0;
            while (i <= global.gpg.max_party_member_index) : (i += 1) {
                if (fight.isPlayerHealthy(global.gpg.party[i].player_role)) healthy += 1;
            }
            return fight.isPlayerHealthy(role) and healthy > 1;
        },
        else => return true,
    }
}

// 魔改 — 6th misc item (情報) opens enemyinfo.zig. The label has no
// WORD.DAT entry, so we feed text.drawText the BIG5 bytes directly to
// match the chrome of the other rows. (情=B1A1, 報=B3F8.)
const BATTLEUI_MISC_ITEMS: i32 = 6;
const MISC_LABEL_INFO_BIG5 = "\xB1\xA1\xB3\xF8";

// PAL_BattleUIDrawMiscMenu (PAL_CLASSIC).
fn drawMiscMenu(current: u16, confirmed: bool) void {
    const items = [_]ui.MenuItem{
        .{ .value = 0, .num_word = BATTLEUI_LABEL_AUTO, .enabled = true, .pos = global.palXY(16, 32) },
        .{ .value = 1, .num_word = BATTLEUI_LABEL_INVENTORY, .enabled = true, .pos = global.palXY(16, 50) },
        .{ .value = 2, .num_word = BATTLEUI_LABEL_DEFEND, .enabled = true, .pos = global.palXY(16, 68) },
        .{ .value = 3, .num_word = BATTLEUI_LABEL_FLEE, .enabled = true, .pos = global.palXY(16, 86) },
        .{ .value = 4, .num_word = BATTLEUI_LABEL_STATUS, .enabled = true, .pos = global.palXY(16, 104) },
    };
    _ = ui.createBox(global.palXY(2, 20), BATTLEUI_MISC_ITEMS - 1, ui.menuTextMaxWidth(&items) - 1, 0, false);
    var i: u16 = 0;
    while (i < 5) : (i += 1) {
        var color: u8 = ui.MENUITEM_COLOR;
        if (i == current) {
            color = if (confirmed) ui.MENUITEM_COLOR_CONFIRMED else ui.menuItemColorSelected();
        }
        text.drawText(text.getWord(items[i].num_word), items[i].pos, color, true, false);
    }
    // 6th item — 情報. Drawn through text.drawText with raw BIG5 so the
    // glyph hinting / shadow matches the rest of the menu.
    const info_color: u8 = blk: {
        if (current == 5) break :blk if (confirmed) ui.MENUITEM_COLOR_CONFIRMED else ui.menuItemColorSelected();
        break :blk ui.MENUITEM_COLOR;
    };
    text.drawText(MISC_LABEL_INFO_BIG5, global.palXY(16, 122), info_color, true, false);
}

// PAL_BattleUIMiscMenuUpdate.
fn miscMenuUpdate() u16 {
    drawMiscMenu(@intCast(g_cur_misc_menu_item), false);

    const k = input.state.key_press;
    if ((k & (input.KEY_UP | input.KEY_LEFT)) != 0) {
        g_cur_misc_menu_item -= 1;
        if (g_cur_misc_menu_item < 0) g_cur_misc_menu_item = BATTLEUI_MISC_ITEMS - 1;
    } else if ((k & (input.KEY_DOWN | input.KEY_RIGHT)) != 0) {
        g_cur_misc_menu_item += 1;
        if (g_cur_misc_menu_item > BATTLEUI_MISC_ITEMS - 1) g_cur_misc_menu_item = 0;
    } else if ((k & input.KEY_SEARCH) != 0) {
        return @as(u16, @intCast(g_cur_misc_menu_item)) + 1;
    } else if ((k & input.KEY_MENU) != 0) {
        return 0;
    }
    return 0xFFFF;
}

// PAL_BattleUIMiscItemSubMenuUpdate — Use / Throw.
fn miscItemSubMenuUpdate() u16 {
    drawMiscMenu(1, true); // PAL_CLASSIC: highlights the Inventory row
    const items = [_]ui.MenuItem{
        .{ .value = 0, .num_word = BATTLEUI_LABEL_USEITEM, .enabled = true, .pos = global.palXY(44, 62) },
        .{ .value = 1, .num_word = BATTLEUI_LABEL_THROWITEM, .enabled = true, .pos = global.palXY(44, 80) },
    };
    _ = ui.createBox(global.palXY(30, 50), 1, ui.menuTextMaxWidth(&items) - 1, 0, false);

    var i: u16 = 0;
    while (i < 2) : (i += 1) {
        const color: u8 = if (i == g_cur_sub_menu_item) ui.menuItemColorSelected() else ui.MENUITEM_COLOR;
        text.drawText(text.getWord(items[i].num_word), items[i].pos, color, true, false);
    }

    const k = input.state.key_press;
    if ((k & (input.KEY_UP | input.KEY_LEFT)) != 0) {
        g_cur_sub_menu_item = 0;
    } else if ((k & (input.KEY_DOWN | input.KEY_RIGHT)) != 0) {
        g_cur_sub_menu_item = 1;
    } else if ((k & input.KEY_SEARCH) != 0) {
        return @as(u16, @intCast(g_cur_sub_menu_item)) + 1;
    } else if ((k & input.KEY_MENU) != 0) {
        return 0;
    }
    return 0xFFFF;
}

// PAL_BattleUIPlayerReady — start the action selection menu for player N.
pub fn playerReady(player_index: u16) void {
    battle.g_battle.ui.cur_player_index = player_index;
    battle.g_battle.ui.state = .select_move;
    battle.g_battle.ui.selected_action = 0;
    battle.g_battle.ui.menu_state = .main;
}

// PAL_BattleUIShowNum — schedule a damage/heal number to float upward.
pub fn showNum(num: u16, pos: u32, color: ui.NumColorEx) void {
    var i: u32 = 0;
    while (i < battle.BATTLEUI_MAX_SHOWNUM) : (i += 1) {
        if (battle.g_battle.ui.show_num[i].num == 0) {
            battle.g_battle.ui.show_num[i] = .{
                .num = num,
                .pos = global.palXY(@truncate(@as(i32, global.palX(pos)) - 15), global.palY(pos)),
                .color = color,
                .time = util.getTicks(),
            };
            return;
        }
    }
}

// Draw the four player info boxes along the bottom — battles always show all
// active party members regardless of UI state.
fn drawPlayerInfoBoxes() void {
    var i: u32 = 0;
    while (i <= global.gpg.max_party_member_index) : (i += 1) {
        const role = global.gpg.party[i].player_role;
        uibattle.playerInfoBox(global.palXY(@intCast(91 + 77 * @as(i32, @intCast(i))), 165), role);
    }
}

// Highlight the selected enemy (alternates frames for blink).
fn drawEnemyHighlight(idx: u32) void {
    if ((s_iframe & 1) == 0) return;
    const e = &battle.g_battle.enemies[idx];
    if (e.object_id == 0) return;
    const sprite = e.sprite orelse return;
    const frame = palcommon.spriteGetFrame(sprite, @intCast(e.current_frame)) orelse return;
    const w: i32 = palcommon.rleGetWidth(frame);
    const h: i32 = palcommon.rleGetHeight(frame);
    const top_left = global.palXY(
        @truncate(@as(i32, global.palX(e.pos)) - @divTrunc(w, 2)),
        @truncate(@as(i32, global.palY(e.pos)) - h),
    );
    _ = palcommon.rleBlitWithColorShift(frame, &video.screen, top_left, 7);
}

fn drawCurrentPlayerArrow() void {
    const idx = battle.g_battle.ui.cur_player_index;
    const party_size: u32 = global.gpg.max_party_member_index;
    const px = battle.PLAYER_POS_PUB[party_size][idx];
    const x: i32 = @as(i32, @intCast(px[0])) - 8;
    const y: i32 = @as(i32, @intCast(px[1])) - 74;
    const sprite_num: i32 = if ((s_iframe & 1) != 0) SPR_ARROW_CURPLAYER else SPR_ARROW_CURPLAYER_RED;
    if (palcommon.spriteGetFrame(ui.sprite_ui, sprite_num)) |bmp| {
        _ = palcommon.rleBlitToSurface(bmp, &video.screen, global.palXY(@truncate(x), @truncate(y)));
    }
}

fn drawSelectedPlayerArrow(idx: u32) void {
    const party_size: u32 = global.gpg.max_party_member_index;
    const px = battle.PLAYER_POS_PUB[party_size][idx];
    const x: i32 = @as(i32, @intCast(px[0])) - 8;
    const y: i32 = @as(i32, @intCast(px[1])) - 67;
    const sprite_num: i32 = if ((s_iframe & 1) != 0) SPR_ARROW_SELPLAYER_RED else SPR_ARROW_SELPLAYER;
    if (palcommon.spriteGetFrame(ui.sprite_ui, sprite_num)) |bmp| {
        _ = palcommon.rleBlitToSurface(bmp, &video.screen, global.palXY(@truncate(x), @truncate(y)));
    }
}

// Draw the four bottom-row action icons — one highlighted, others mono.
fn drawActionIcons() void {
    const items = [_]struct { sprite: i32, pos: u32, action: u16 }{
        .{ .sprite = SPR_BATTLEICON_ATTACK, .pos = global.palXY(27, 140), .action = 0 },
        .{ .sprite = SPR_BATTLEICON_MAGIC, .pos = global.palXY(0, 155), .action = 1 },
        .{ .sprite = SPR_BATTLEICON_COOPMAGIC, .pos = global.palXY(54, 155), .action = 2 },
        .{ .sprite = SPR_BATTLEICON_MISCMENU, .pos = global.palXY(27, 170), .action = 3 },
    };

    if (battle.g_battle.ui.menu_state == .main) {
        switch (input.state.dir) {
            .north => battle.g_battle.ui.selected_action = 0,
            .south => battle.g_battle.ui.selected_action = 3,
            .west => if (isActionValid(1)) {
                battle.g_battle.ui.selected_action = 1;
            },
            .east => if (isActionValid(2)) {
                battle.g_battle.ui.selected_action = 2;
            },
            .unknown => {},
        }
    }

    if (!isActionValid(items[battle.g_battle.ui.selected_action].action)) {
        battle.g_battle.ui.selected_action = 0;
    }

    for (items, 0..) |it, i| {
        const frame = palcommon.spriteGetFrame(ui.sprite_ui, it.sprite) orelse continue;
        if (battle.g_battle.ui.selected_action == i) {
            _ = palcommon.rleBlitToSurface(frame, &video.screen, it.pos);
        } else if (isActionValid(it.action)) {
            _ = palcommon.rleBlitMonoColor(frame, &video.screen, it.pos, 0, -4);
        } else {
            _ = palcommon.rleBlitMonoColor(frame, &video.screen, it.pos, 0x10, -4);
        }
    }
}

// Helpers from fight.c — moved out so battleui doesn't fight ordering.
fn pickAutoMagic(role: u16, random_range: i32) u16 {
    if (global.gpg.player_status[role][global.STATUS_SILENCE] != 0) return 0;
    var best: u16 = 0;
    var best_power: i32 = 0;
    var i: u32 = 0;
    while (i < global.MAX_PLAYER_MAGICS) : (i += 1) {
        const w = global.gpg.g.player_roles.magic[i][role];
        if (w == 0) continue;
        const mn = global.gpg.g.objects[w].magic().magic_number;
        const m = global.gpg.g.magics[mn];
        const base: i16 = @bitCast(m.base_damage);
        if (m.cost_mp == 1 or m.cost_mp > global.gpg.g.player_roles.mp[role] or base <= 0) continue;
        const power: i32 = @as(i32, base) + util.randomLong(0, random_range);
        if (power > best_power) {
            best_power = power;
            best = w;
        }
    }
    return best;
}

// PAL_BattleUIUpdate — the per-frame state-machine body.
pub fn update() void {
    s_iframe +%= 1;

    // Auto-attack toggle hint.
    if (battle.g_battle.ui.auto_attack and !global.gpg.auto_battle) {
        if ((input.state.key_press & input.KEY_MENU) != 0) {
            battle.g_battle.ui.auto_attack = false;
        } else {
            const t = text.getWord(BATTLEUI_LABEL_AUTO);
            const tw: i32 = ui.textWidth(t);
            text.drawText(t, global.palXY(@truncate(312 - tw), 10), ui.MENUITEM_COLOR_CONFIRMED, true, false);
        }
    }

    // PAL_CLASSIC: during PerformAction, hide the player info boxes — the
    // attack/magic/throw animations own the screen (uibattle.c L888-L892
    // `goto end` skips the box draw block).
    if (battle.g_battle.phase == .perform_action) {
        drawShowNumbers();
        input.clearKeyState();
        return;
    }

    if ((input.state.key_press & input.KEY_AUTO) != 0) {
        battle.g_battle.ui.auto_attack = !battle.g_battle.ui.auto_attack;
        battle.g_battle.ui.menu_state = .main;
    }

    if (!battle.g_battle.ui.auto_attack) {
        drawPlayerInfoBoxes();
    }

    if ((input.state.key_press & input.KEY_STATUS) != 0) {
        @import("playerstatus.zig").playerStatus();
        drawShowNumbers();
        input.clearKeyState();
        return;
    }
    if ((input.state.key_press & input.KEY_INFO) != 0) {
        @import("enemyinfo.zig").show();
        drawShowNumbers();
        input.clearKeyState();
        return;
    }

    // While we're not in the SELECT_MOVE state we still keep the UI alive.
    if (battle.g_battle.ui.state == .wait) {
        // Pre-7d: no fighter-ready logic. UI just idles. Pressing menu = flee.
        if ((input.state.key_press & input.KEY_MENU) != 0) {
            battle.g_battle.result = .fleed;
        }
        drawShowNumbers();
        input.clearKeyState();
        return;
    }

    // ----- kBattleUISelectMove -----
    if (battle.g_battle.ui.state == .select_move) {
        const role = global.gpg.party[battle.g_battle.ui.cur_player_index].player_role;

        // Hard-fail if the current player can't act.
        if (global.gpg.g.player_roles.hp[role] == 0 and global.gpg.player_status[role][global.STATUS_PUPPET] != 0) {
            battle.g_battle.ui.action_type = @intFromEnum(battle.BattleActionType.attack);
            battle.g_battle.ui.selected_index = if (global.playerCanAttackAll(role)) -1 else fight.battleSelectAutoTarget();
            fight.commitAction(false);
            drawShowNumbers();
            input.clearKeyState();
            return;
        }
        if (global.gpg.g.player_roles.hp[role] == 0 or
            global.gpg.player_status[role][global.STATUS_SLEEP] != 0 or
            global.gpg.player_status[role][global.STATUS_PARALYZED] != 0)
        {
            battle.g_battle.ui.action_type = @intFromEnum(battle.BattleActionType.pass);
            fight.commitAction(false);
            drawShowNumbers();
            input.clearKeyState();
            return;
        }
        if (global.gpg.player_status[role][global.STATUS_CONFUSED] != 0) {
            battle.g_battle.ui.action_type = @intFromEnum(battle.BattleActionType.attack_mate);
            fight.commitAction(false);
            drawShowNumbers();
            input.clearKeyState();
            return;
        }
        if (battle.g_battle.ui.auto_attack) {
            battle.g_battle.ui.action_type = @intFromEnum(battle.BattleActionType.attack);
            battle.g_battle.ui.selected_index = if (global.playerCanAttackAll(role)) -1 else fight.battleSelectAutoTarget();
            fight.commitAction(false);
            drawShowNumbers();
            input.clearKeyState();
            return;
        }
        // fight.c L1797: once any player commits flee, every later player in
        // the SelectAction phase auto-commits flee too. SDLPAL implements this
        // by injecting kKeyFlee from fStartFrame; we just hop straight to the
        // flee commit.
        if (battle.g_battle.flee) {
            battle.g_battle.ui.action_type = @intFromEnum(battle.BattleActionType.flee);
            fight.commitAction(false);
            drawShowNumbers();
            input.clearKeyState();
            return;
        }

        drawCurrentPlayerArrow();
        drawActionIcons();

        switch (battle.g_battle.ui.menu_state) {
            .main => handleMainMenuKeys(role),
            .magic_select => {
                const w = magicmenu.magicSelectionMenuUpdate();
                if (w != 0xFFFF) {
                    battle.g_battle.ui.menu_state = .main;
                    if (w != 0) handleMagicSelected(w);
                }
            },
            .use_item_select => uiUseItem(),
            .throw_item_select => uiThrowItem(),
            .misc => {
                const w = miscMenuUpdate();
                if (w != 0xFFFF) handleMiscSelection(w);
            },
            .misc_item_sub_menu => {
                const w = miscItemSubMenuUpdate();
                if (w != 0xFFFF) handleMiscItemSubSelection(w);
            },
        }
    } else if (battle.g_battle.ui.state == .select_target_enemy) {
        targetEnemyState();
    } else if (battle.g_battle.ui.state == .select_target_player) {
        targetPlayerState();
    } else if (battle.g_battle.ui.state == .select_target_enemy_all) {
        // PAL_CLASSIC: don't ask, commit immediately.
        battle.g_battle.ui.selected_index = -1;
        fight.commitAction(false);
    } else if (battle.g_battle.ui.state == .select_target_player_all) {
        battle.g_battle.ui.selected_index = -1;
        fight.commitAction(false);
    }

    drawShowNumbers();
    input.clearKeyState();
}

// True if `idx` points at an alive enemy slot. Used to decide whether the
// "remember last target" path can reuse a stored index.
fn isEnemyTargetable(idx: i32) bool {
    if (idx < 0) return false;
    if (battle.g_battle.max_enemy_index < 0) return false;
    if (idx > battle.g_battle.max_enemy_index) return false;
    return battle.g_battle.enemies[@intCast(idx)].object_id != 0;
}

fn handleMainMenuKeys(role: u16) void {
    const k = input.state.key_press;
    if ((k & input.KEY_SEARCH) != 0) {
        switch (battle.g_battle.ui.selected_action) {
            0 => { // Attack
                battle.g_battle.ui.action_type = @intFromEnum(battle.BattleActionType.attack);
                if (global.playerCanAttackAll(role)) {
                    battle.g_battle.ui.state = .select_target_enemy_all;
                } else {
                    // Default to last picked target if it's still alive,
                    // else fall back to slot 0. (Earlier code reset to 0
                    // unconditionally after restoring, which was a bug.)
                    battle.g_battle.ui.selected_index =
                        if (battle.g_battle.ui.prev_enemy_target != -1 and
                            isEnemyTargetable(@intCast(battle.g_battle.ui.prev_enemy_target)))
                            battle.g_battle.ui.prev_enemy_target
                        else
                            0;
                    battle.g_battle.ui.state = .select_target_enemy;
                }
            },
            1 => { // Magic
                battle.g_battle.ui.menu_state = .magic_select;
                magicmenu.magicSelectionMenuInit(role, true, 0);
            },
            2 => { // Coop magic
                const w = global.getPlayerCooperativeMagic(role);
                battle.g_battle.ui.action_type = @intFromEnum(battle.BattleActionType.coop_magic);
                battle.g_battle.ui.object_id = w;
                const flags = global.gpg.g.objects[w].magic().flags;
                if ((flags & global.MAGIC_FLAG_USABLE_TO_ENEMY) != 0) {
                    if ((flags & global.MAGIC_FLAG_APPLY_TO_ALL) != 0) {
                        battle.g_battle.ui.state = .select_target_enemy_all;
                    } else {
                        battle.g_battle.ui.selected_index =
                            if (battle.g_battle.ui.prev_enemy_target != -1 and
                                isEnemyTargetable(@intCast(battle.g_battle.ui.prev_enemy_target)))
                                battle.g_battle.ui.prev_enemy_target
                            else
                                0;
                        battle.g_battle.ui.state = .select_target_enemy;
                    }
                } else {
                    if ((flags & global.MAGIC_FLAG_APPLY_TO_ALL) != 0) {
                        battle.g_battle.ui.state = .select_target_player_all;
                    } else {
                        battle.g_battle.ui.selected_index = 0;
                        battle.g_battle.ui.state = .select_target_player;
                    }
                }
            },
            3 => battle.g_battle.ui.menu_state = .misc,
            else => {},
        }
    } else if ((k & input.KEY_DEFEND) != 0) {
        battle.g_battle.ui.action_type = @intFromEnum(battle.BattleActionType.defend);
        fight.commitAction(false);
    } else if ((k & input.KEY_FORCE) != 0) {
        const w = pickAutoMagic(role, 60);
        if (w == 0) {
            battle.g_battle.ui.action_type = @intFromEnum(battle.BattleActionType.attack);
            battle.g_battle.ui.selected_index = if (global.playerCanAttackAll(role)) -1 else fight.battleSelectAutoTarget();
        } else {
            battle.g_battle.ui.action_type = @intFromEnum(battle.BattleActionType.magic);
            battle.g_battle.ui.object_id = w;
            const flags = global.gpg.g.objects[w].magic().flags;
            battle.g_battle.ui.selected_index = if ((flags & global.MAGIC_FLAG_APPLY_TO_ALL) != 0) -1 else fight.battleSelectAutoTarget();
        }
        fight.commitAction(false);
    } else if ((k & input.KEY_FLEE) != 0) {
        battle.g_battle.ui.action_type = @intFromEnum(battle.BattleActionType.flee);
        fight.commitAction(false);
    } else if ((k & input.KEY_USEITEM) != 0) {
        battle.g_battle.ui.menu_state = .use_item_select;
        itemmenu.itemSelectMenuInit(global.ITEM_FLAG_USABLE);
    } else if ((k & input.KEY_THROWITEM) != 0) {
        battle.g_battle.ui.menu_state = .throw_item_select;
        itemmenu.itemSelectMenuInit(global.ITEM_FLAG_THROWABLE);
    } else if ((k & input.KEY_REPEAT) != 0) {
        // fight.c L1778-L1782: R key starts a chain-repeat across the whole
        // round. Restore the auto-atk flag from the snapshot taken at round
        // start so the repeat sees the same UI mode the player chose.
        battle.g_battle.repeat = true;
        battle.g_battle.ui.auto_attack = battle.g_battle.prev_auto_atk;
        fight.commitAction(true);
    } else if ((k & input.KEY_MENU) != 0) {
        // Revert to previous player.
        battle.g_battle.players[battle.g_battle.ui.cur_player_index].state = .wait;
        battle.g_battle.ui.state = .wait;
        if (battle.g_battle.ui.cur_player_index > 0) {
            // Walk back through unusable players (asleep / paralyzed / etc).
            while (true) {
                battle.g_battle.ui.cur_player_index -= 1;
                battle.g_battle.players[battle.g_battle.ui.cur_player_index].state = .wait;
                fight.refundUiActionConsumables(battle.g_battle.ui.cur_player_index);
                if (battle.g_battle.ui.cur_player_index == 0) break;
                const r = global.gpg.party[battle.g_battle.ui.cur_player_index].player_role;
                if (global.gpg.g.player_roles.hp[r] != 0 and
                    global.gpg.player_status[r][global.STATUS_CONFUSED] == 0 and
                    global.gpg.player_status[r][global.STATUS_SLEEP] == 0 and
                    global.gpg.player_status[r][global.STATUS_PARALYZED] == 0)
                    break;
            }
        }
    }
}

fn handleMagicSelected(w: u16) void {
    battle.g_battle.ui.action_type = @intFromEnum(battle.BattleActionType.magic);
    battle.g_battle.ui.object_id = w;
    const flags = global.gpg.g.objects[w].magic().flags;
    if ((flags & global.MAGIC_FLAG_USABLE_TO_ENEMY) != 0) {
        if ((flags & global.MAGIC_FLAG_APPLY_TO_ALL) != 0) {
            battle.g_battle.ui.state = .select_target_enemy_all;
        } else {
            if (battle.g_battle.ui.prev_enemy_target != -1) {
                battle.g_battle.ui.selected_index = battle.g_battle.ui.prev_enemy_target;
            }
            battle.g_battle.ui.state = .select_target_enemy;
            battle.g_battle.ui.selected_index = 0;
        }
    } else {
        if ((flags & global.MAGIC_FLAG_APPLY_TO_ALL) != 0) {
            battle.g_battle.ui.state = .select_target_player_all;
        } else {
            battle.g_battle.ui.selected_index = 0;
            battle.g_battle.ui.state = .select_target_player;
        }
    }
}

fn uiUseItem() void {
    const w = itemmenu.itemSelectMenuUpdate();
    if (w != 0xFFFF) {
        if (w != 0) {
            battle.g_battle.ui.action_type = @intFromEnum(battle.BattleActionType.use_item);
            battle.g_battle.ui.object_id = w;
            const flags = global.gpg.g.objects[w].item().flags;
            if ((flags & global.ITEM_FLAG_APPLY_TO_ALL) != 0) {
                battle.g_battle.ui.state = .select_target_player_all;
            } else {
                battle.g_battle.ui.selected_index = 0;
                battle.g_battle.ui.state = .select_target_player;
            }
        } else {
            battle.g_battle.ui.menu_state = .main;
        }
    }
}

fn uiThrowItem() void {
    const w = itemmenu.itemSelectMenuUpdate();
    if (w != 0xFFFF) {
        if (w != 0) {
            battle.g_battle.ui.action_type = @intFromEnum(battle.BattleActionType.throw_item);
            battle.g_battle.ui.object_id = w;
            const flags = global.gpg.g.objects[w].item().flags;
            if ((flags & global.ITEM_FLAG_APPLY_TO_ALL) != 0) {
                battle.g_battle.ui.state = .select_target_enemy_all;
            } else {
                if (battle.g_battle.ui.prev_enemy_target != -1) {
                    battle.g_battle.ui.selected_index = battle.g_battle.ui.prev_enemy_target;
                }
                battle.g_battle.ui.state = .select_target_enemy;
                battle.g_battle.ui.selected_index = 0;
            }
        } else {
            battle.g_battle.ui.menu_state = .main;
        }
    }
}

fn handleMiscSelection(w: u16) void {
    battle.g_battle.ui.menu_state = .main;
    switch (w) {
        // PAL_CLASSIC ordering: 1=auto, 2=item, 3=defend, 4=flee, 5=status.
        1 => battle.g_battle.ui.auto_attack = true,
        2 => battle.g_battle.ui.menu_state = .misc_item_sub_menu,
        3 => {
            battle.g_battle.ui.action_type = @intFromEnum(battle.BattleActionType.defend);
            fight.commitAction(false);
        },
        4 => {
            battle.g_battle.ui.action_type = @intFromEnum(battle.BattleActionType.flee);
            fight.commitAction(false);
        },
        5 => @import("playerstatus.zig").playerStatus(),
        6 => @import("enemyinfo.zig").show(),
        else => {},
    }
}

fn handleMiscItemSubSelection(w: u16) void {
    battle.g_battle.ui.menu_state = .main;
    switch (w) {
        1 => {
            battle.g_battle.ui.menu_state = .use_item_select;
            itemmenu.itemSelectMenuInit(global.ITEM_FLAG_USABLE);
        },
        2 => {
            battle.g_battle.ui.menu_state = .throw_item_select;
            itemmenu.itemSelectMenuInit(global.ITEM_FLAG_THROWABLE);
        },
        else => {},
    }
}

fn targetEnemyState() void {
    var last: i32 = -1;
    var alive: u32 = 0;
    var i: u32 = 0;
    while (i < global.MAX_ENEMIES_IN_TEAM) : (i += 1) {
        if (battle.g_battle.enemies[i].object_id != 0) {
            last = @intCast(i);
            alive += 1;
        }
    }
    if (last == -1) {
        battle.g_battle.ui.state = .select_move;
        return;
    }
    if (battle.g_battle.ui.action_type == @intFromEnum(battle.BattleActionType.coop_magic) and !isActionValid(2)) {
        battle.g_battle.ui.state = .select_move;
        return;
    }
    // PAL_CLASSIC: only one enemy left → auto-commit.
    if (alive == 1) {
        if (battle.g_battle.ui.selected_index == -1) {
            battle.g_battle.ui.selected_index = last;
        } else {
            var k: i32 = 0;
            while (k < global.MAX_ENEMIES_IN_TEAM) : (k += 1) {
                if (battle.g_battle.enemies[@intCast(k)].object_id != 0) {
                    battle.g_battle.ui.selected_index = k;
                    break;
                }
            }
        }
        fight.commitAction(false);
        return;
    }

    if (battle.g_battle.ui.selected_index > last) battle.g_battle.ui.selected_index = last;
    if (battle.g_battle.ui.selected_index < 0) battle.g_battle.ui.selected_index = 0;

    // Skip to the next live enemy if the current slot is empty.
    var step: i32 = 0;
    while (step <= last) : (step += 1) {
        if (battle.g_battle.enemies[@intCast(battle.g_battle.ui.selected_index)].object_id != 0) break;
        battle.g_battle.ui.selected_index += 1;
        battle.g_battle.ui.selected_index = @mod(battle.g_battle.ui.selected_index, last + 1);
    }

    drawEnemyHighlight(@intCast(battle.g_battle.ui.selected_index));

    const k = input.state.key_press;
    if ((k & input.KEY_MENU) != 0) {
        battle.g_battle.ui.state = .select_move;
    } else if ((k & input.KEY_SEARCH) != 0) {
        fight.commitAction(false);
    } else if ((k & (input.KEY_LEFT | input.KEY_DOWN)) != 0) {
        battle.g_battle.ui.selected_index -= 1;
        if (battle.g_battle.ui.selected_index < 0) battle.g_battle.ui.selected_index = global.MAX_ENEMIES_IN_TEAM - 1;
        while (battle.g_battle.ui.selected_index != 0 and
            battle.g_battle.enemies[@intCast(battle.g_battle.ui.selected_index)].object_id == 0)
        {
            battle.g_battle.ui.selected_index -= 1;
            if (battle.g_battle.ui.selected_index < 0) battle.g_battle.ui.selected_index = global.MAX_ENEMIES_IN_TEAM - 1;
        }
    } else if ((k & (input.KEY_RIGHT | input.KEY_UP)) != 0) {
        battle.g_battle.ui.selected_index += 1;
        if (battle.g_battle.ui.selected_index >= global.MAX_ENEMIES_IN_TEAM) battle.g_battle.ui.selected_index = 0;
        while (battle.g_battle.ui.selected_index < global.MAX_ENEMIES_IN_TEAM and
            battle.g_battle.enemies[@intCast(battle.g_battle.ui.selected_index)].object_id == 0)
        {
            battle.g_battle.ui.selected_index += 1;
            if (battle.g_battle.ui.selected_index >= global.MAX_ENEMIES_IN_TEAM) battle.g_battle.ui.selected_index = 0;
        }
    }
}

fn targetPlayerState() void {
    if (global.gpg.max_party_member_index == 0) {
        battle.g_battle.ui.selected_index = 0;
        fight.commitAction(false);
        return;
    }

    // Mute the action icons so the arrow can be seen clearly.
    const items = [_]struct { sprite: i32, pos: u32 }{
        .{ .sprite = SPR_BATTLEICON_ATTACK, .pos = global.palXY(27, 140) },
        .{ .sprite = SPR_BATTLEICON_MAGIC, .pos = global.palXY(0, 155) },
        .{ .sprite = SPR_BATTLEICON_COOPMAGIC, .pos = global.palXY(54, 155) },
        .{ .sprite = SPR_BATTLEICON_MISCMENU, .pos = global.palXY(27, 170) },
    };
    for (items) |it| {
        const frame = palcommon.spriteGetFrame(ui.sprite_ui, it.sprite) orelse continue;
        _ = palcommon.rleBlitMonoColor(frame, &video.screen, it.pos, 0, -4);
    }

    drawSelectedPlayerArrow(@intCast(battle.g_battle.ui.selected_index));

    const k = input.state.key_press;
    if ((k & input.KEY_MENU) != 0) {
        battle.g_battle.ui.state = .select_move;
    } else if ((k & input.KEY_SEARCH) != 0) {
        fight.commitAction(false);
    } else if ((k & (input.KEY_LEFT | input.KEY_DOWN)) != 0) {
        if (battle.g_battle.ui.selected_index != 0) {
            battle.g_battle.ui.selected_index -= 1;
        } else {
            battle.g_battle.ui.selected_index = global.gpg.max_party_member_index;
        }
    } else if ((k & (input.KEY_RIGHT | input.KEY_UP)) != 0) {
        if (battle.g_battle.ui.selected_index < global.gpg.max_party_member_index) {
            battle.g_battle.ui.selected_index += 1;
        } else {
            battle.g_battle.ui.selected_index = 0;
        }
    }
}

fn drawShowNumbers() void {
    var i: u32 = 0;
    while (i < battle.BATTLEUI_MAX_SHOWNUM) : (i += 1) {
        const sn = &battle.g_battle.ui.show_num[i];
        if (sn.num == 0) continue;
        const elapsed = util.getTicks() -% sn.time;
        const frames = elapsed / global.BATTLE_FRAME_TIME;
        if (frames > 10) {
            sn.num = 0;
        } else {
            ui.drawNumberEx(
                sn.num,
                5,
                global.palXY(global.palX(sn.pos), @truncate(@as(i32, global.palY(sn.pos)) - @as(i32, @intCast(frames)))),
                sn.color,
                .right,
            );
        }
    }
}
