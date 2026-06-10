// Copyright (c) 2009-2011, Wei Mingzhi <whistler_wmz@users.sf.net>.
// Copyright (c) 2011-2026, SDLPAL development team.
// All rights reserved.
//
// This file is part of SDLPAL.
//
// SDLPAL is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License, version 3
// as published by the Free Software Foundation.

// fight.c port — PAL_CLASSIC only.
//
// Stage 7d: action queue + select/perform two-phase main loop.
// Currently implements physical attack, defend, flee, attack-mate, pass
// for both players and enemies. Magic / use_item / throw_item / coop_magic
// are stubbed to a basic damage path so the loop terminates; the full
// animation pipeline (showPlayerOffMagicAnim, summon, throw arc, etc) lands
// in a follow-up step.

const std = @import("std");
const global = @import("global.zig");
const battle = @import("battle.zig");
const palcommon = @import("palcommon.zig");
const video = @import("video.zig");
const ui = @import("ui.zig");
const text = @import("text.zig");
const input = @import("input.zig");
const util = @import("util.zig");
const script = @import("script.zig");

// PAL_IsPlayerDying — fight.c L33-49.
pub fn isPlayerDying(role: u16) bool {
    const max = global.gpg.g.player_roles.max_hp[role];
    const threshold = if (max / 5 < 100) max / 5 else 100;
    return global.gpg.g.player_roles.hp[role] < threshold;
}

// PAL_IsPlayerHealthy — fight.c L52-76.
pub fn isPlayerHealthy(role: u16) bool {
    if (isPlayerDying(role)) return false;
    return global.gpg.player_status[role][global.STATUS_SLEEP] == 0 and
        global.gpg.player_status[role][global.STATUS_CONFUSED] == 0 and
        global.gpg.player_status[role][global.STATUS_SILENCE] == 0 and
        global.gpg.player_status[role][global.STATUS_PARALYZED] == 0 and
        global.gpg.player_status[role][global.STATUS_PUPPET] == 0;
}

// PAL_BattleSelectAutoTargetFrom + PAL_BattleSelectAutoTarget — fight.c L78-128.
pub fn battleSelectAutoTargetFrom(begin: i32) i32 {
    const prev: i32 = battle.g_battle.ui.prev_enemy_target;
    if (prev >= 0 and prev <= battle.g_battle.max_enemy_index and
        battle.g_battle.enemies[@intCast(prev)].object_id != 0 and
        battle.g_battle.enemies[@intCast(prev)].e.health > 0)
    {
        return prev;
    }

    const max_idx = battle.g_battle.max_enemy_index;
    if (max_idx < 0) return -1;
    var idx: i32 = if (begin >= 0) begin else 0;
    var count: u32 = 0;
    while (count < global.MAX_ENEMIES_IN_TEAM) : (count += 1) {
        const u: usize = @intCast(idx);
        if (battle.g_battle.enemies[u].object_id != 0 and battle.g_battle.enemies[u].e.health > 0) {
            return idx;
        }
        idx = @mod(idx + 1, max_idx + 1);
    }
    return -1;
}

pub fn battleSelectAutoTarget() i32 {
    return battleSelectAutoTargetFrom(0);
}

// --- Damage formulas (PAL_CalcBaseDamage / PhysicalAttack / Magic) ---

fn calcBaseDamage(attack_strength: i32, defense: i32) i32 {
    if (attack_strength > defense) {
        // (atk*2 - def*1.6 + 0.5)
        const v: f32 = @as(f32, @floatFromInt(attack_strength)) * 2.0 -
            @as(f32, @floatFromInt(defense)) * 1.6 + 0.5;
        return @intFromFloat(v);
    } else if (@as(f32, @floatFromInt(attack_strength)) > @as(f32, @floatFromInt(defense)) * 0.6) {
        const v: f32 = @as(f32, @floatFromInt(attack_strength)) -
            @as(f32, @floatFromInt(defense)) * 0.6 + 0.5;
        return @intFromFloat(v);
    }
    return 0;
}

// PAL_CalcMagicDamage — fight.c L173. The strength gets a 1.0..1.1 jitter,
// then base damage / 4, plus the magic's wBaseDamage; if the spell has an
// element field, the result is scaled by (10 - resistance/multiplier)/5 and
// the battlefield's per-element multiplier.
fn calcMagicDamage(
    magic_strength_in: u16,
    defense: i32,
    elem_resist: *align(1) const [global.NUM_MAGIC_ELEMENTAL]u16,
    poison_resist: u16,
    resistance_multiplier: u16,
    magic_object_id: u16,
) i32 {
    const magic_id = global.gpg.g.objects[magic_object_id].magic().magic_number;

    // Strength jitter.
    var ms_f: f32 = @as(f32, @floatFromInt(magic_strength_in)) * util.randomFloatRange(10.0, 11.0);
    ms_f /= 10.0;

    var s_damage: f32 = @floatFromInt(calcBaseDamage(@intFromFloat(ms_f), defense));
    s_damage /= 4.0;
    s_damage += @floatFromInt(global.gpg.g.magics[magic_id].base_damage);

    const elem = global.gpg.g.magics[magic_id].elemental;
    if (elem != 0) {
        if (elem > global.NUM_MAGIC_ELEMENTAL) {
            s_damage *= 10.0 - @as(f32, @floatFromInt(poison_resist)) / @as(f32, @floatFromInt(resistance_multiplier));
        } else if (elem == 0) {
            // unreachable from the outer if, but mirrors SDLPAL.
            s_damage *= 5.0;
        } else {
            s_damage *= 10.0 - @as(f32, @floatFromInt(elem_resist[elem - 1])) / @as(f32, @floatFromInt(resistance_multiplier));
        }
        s_damage /= 5.0;

        if (elem <= global.NUM_MAGIC_ELEMENTAL) {
            const me: i32 = global.gpg.g.battlefields[global.gpg.num_battle_field].magic_effect[elem - 1];
            s_damage *= 10.0 + @as(f32, @floatFromInt(me));
            s_damage /= 10.0;
        }
    }
    const result: i32 = @intFromFloat(s_damage);
    if (@import("debug.zig").enabled) {
        std.log.info("MAGIC_DMG obj={X} mag#{} str={} def={} base_dmg={} elem={} result={}", .{
            magic_object_id, magic_id, magic_strength_in, defense,
            global.gpg.g.magics[magic_id].base_damage, elem, result,
        });
    }
    return result;
}

// FIGHT_DetectMagicTargetChange — fight.c L3551. Force sTarget to 0 / -1
// based on magic_type. Used right before PreMagicAnim so the cast targets
// match the spell's intent (e.g. apply-to-party always sTarget=-1).
fn detectMagicTargetChange(magic_id: u16, sTarget: i32) i32 {
    const t = global.gpg.g.magics[magic_id].magic_type;
    var s = sTarget;
    if (s == -1 and (t == global.MAGIC_TYPE_NORMAL or
        t == global.MAGIC_TYPE_APPLY_TO_PLAYER or
        t == global.MAGIC_TYPE_TRANCE))
    {
        s = 0;
    }
    if (s != -1 and (t == global.MAGIC_TYPE_ATTACK_ALL or
        t == global.MAGIC_TYPE_ATTACK_WHOLE or
        t == global.MAGIC_TYPE_ATTACK_FIELD or
        t == global.MAGIC_TYPE_APPLY_TO_PARTY or
        t == global.MAGIC_TYPE_SUMMON))
    {
        s = -1;
    }
    return s;
}

// PAL_BattleCheckHidingEffect — fight.c L3511 PAL_CLASSIC branch.
fn checkHidingEffect() void {
    if (battle.g_battle.hiding_time < 0) {
        battle.g_battle.hiding_time = -battle.g_battle.hiding_time;
        video.backupScreen();
        battle.battleMakeScene();
        battle.battleFadeScene();
    }
}

pub fn calcPhysicalAttackDamage(attack_strength: i32, defense: i32, attack_resistance: i32) i32 {
    var d = calcBaseDamage(attack_strength, defense);
    if (attack_resistance != 0) d = @divTrunc(d, attack_resistance);
    return d;
}

// --- Dexterity ---

fn getEnemyDexterity(idx: u32) i32 {
    const e = &battle.g_battle.enemies[idx];
    var s: i32 = (@as(i32, e.e.level) + 6) * 3;
    s += @as(i16, @bitCast(e.e.dexterity));
    if (s > 999) s = 999;
    return s;
}

fn getPlayerActualDexterity(role: u16) u16 {
    var w: u32 = global.getPlayerDexterity(role);
    if (global.gpg.player_status[role][global.STATUS_HASTE] != 0) w *= 3;
    if (w > 999) w = 999;
    return @truncate(w);
}

// --- Battle frame helpers ---

// Re-render the scene buffer + UI overlay every frame, with optional gesture
// updates for idle enemies (matches PAL_BattleDelay's `fUpdateGesture`).
fn renderFrame(update_gesture: bool, label_word: i32) void {
    if (update_gesture) {
        var j: u32 = 0;
        while (j <= @as(u32, @intCast(@max(battle.g_battle.max_enemy_index, 0)))) : (j += 1) {
            const e = &battle.g_battle.enemies[j];
            if (e.object_id == 0 or
                e.status[global.STATUS_SLEEP] != 0 or
                e.status[global.STATUS_PARALYZED] != 0) continue;
            if (e.e.idle_anim_speed != 0) e.e.idle_anim_speed -%= 1;
            if (e.e.idle_anim_speed == 0) {
                e.current_frame +%= 1;
                const enemy_id = global.gpg.g.objects[e.object_id].data[0];
                e.e.idle_anim_speed = global.gpg.g.enemies[enemy_id].idle_anim_speed;
            }
            if (e.current_frame >= e.e.idle_frames) e.current_frame = 0;
        }
    }

    battle.battleMakeScene();
    @memcpy(&video.screen_pixels, &battle.g_battle.scene_buf_pixels);

    // Optional centered label (e.g. "Escape failed!" or item name).
    if (label_word > 0) {
        const w: u16 = @intCast(label_word);
        text.drawText(text.getWord(w), global.palXY(210, 50), 15, true, false);
    } else if (label_word < 0) {
        const w: u16 = @intCast(-label_word);
        text.drawText(text.getWord(w), global.palXY(170, 45), 0x3C, true, false);
    }

    @import("battleui.zig").update();
    video.updateScreen(null);
}

// PAL_BattleDelay — block for `duration` battle frames, redrawing.
pub fn battleDelay(duration: u32, label_word: i32, update_gesture: bool) void {
    var dw_time = util.getTicks() + global.BATTLE_FRAME_TIME;
    var i: u32 = 0;
    while (i < duration) : (i += 1) {
        if (util.shouldQuit()) return;
        while (util.getTicks() < dw_time) {
            input.processEvent();
            std.Thread.yield() catch {};
            if (util.shouldQuit()) return;
        }
        dw_time = util.getTicks() + global.BATTLE_FRAME_TIME;
        renderFrame(update_gesture, label_word);
    }
}

// PAL_BattleBackupStat — snapshot HP/MP for delta display.
pub fn backupStat() void {
    var i: u32 = 0;
    while (battle.g_battle.max_enemy_index >= 0 and i <= @as(u32, @intCast(battle.g_battle.max_enemy_index))) : (i += 1) {
        if (battle.g_battle.enemies[i].object_id == 0) continue;
        battle.g_battle.enemies[i].prev_hp = battle.g_battle.enemies[i].e.health;
    }
    i = 0;
    while (i <= global.gpg.max_party_member_index) : (i += 1) {
        const role = global.gpg.party[i].player_role;
        battle.g_battle.players[i].prev_hp = global.gpg.g.player_roles.hp[role];
        battle.g_battle.players[i].prev_mp = global.gpg.g.player_roles.mp[role];
    }
}

// PAL_BattleDisplayStatChange — emit floating numbers for HP deltas. Returns
// true if anything was scheduled.
pub fn displayStatChange() bool {
    var any = false;
    const showNum = @import("battleui.zig").showNum;

    var i: u32 = 0;
    while (battle.g_battle.max_enemy_index >= 0 and i <= @as(u32, @intCast(battle.g_battle.max_enemy_index))) : (i += 1) {
        const e = &battle.g_battle.enemies[i];
        if (e.object_id == 0) continue;
        if (e.prev_hp != e.e.health) {
            const dmg: i32 = @as(i32, e.e.health) - @as(i32, e.prev_hp);
            const x: i32 = @as(i32, global.palX(e.pos)) - 9;
            var y: i32 = @as(i32, global.palY(e.pos)) - 115;
            if (y < 10) y = 10;
            if (dmg < 0) {
                showNum(@intCast(-dmg), global.palXY(@truncate(x), @truncate(y)), .red);
            } else if (dmg > 0) {
                showNum(@intCast(dmg), global.palXY(@truncate(x), @truncate(y)), .cyan);
            }
            any = true;
        }
    }
    i = 0;
    while (i <= global.gpg.max_party_member_index) : (i += 1) {
        const role = global.gpg.party[i].player_role;
        const p = &battle.g_battle.players[i];
        const cur_hp: i32 = @as(i32, global.gpg.g.player_roles.hp[role]);
        const prev_hp: i32 = @as(i32, p.prev_hp);

        // HP delta — fight.c L670-L687.
        if (cur_hp != prev_hp) {
            const dmg = cur_hp - prev_hp;
            const x: i32 = @as(i32, global.palX(p.pos)) - 9;
            var y: i32 = @as(i32, global.palY(p.pos)) - 75;
            if (y < 10) y = 10;
            if (dmg < 0) {
                showNum(@intCast(-dmg), global.palXY(@truncate(x), @truncate(y)), .red);
            } else if (dmg > 0) {
                showNum(@intCast(dmg), global.palXY(@truncate(x), @truncate(y)), .cyan);
            }
            any = true;
        }

        // MP delta — fight.c L690-L711. Recovery shows cyan; the 魔改
        // EX_SHOW_MP_DROP path also surfaces drains in purple so a player
        // can see their MP being burned by something other than their own
        // spellcasts.
        const cur_mp: i32 = @as(i32, global.gpg.g.player_roles.mp[role]);
        const prev_mp: i32 = @as(i32, p.prev_mp);
        if (cur_mp != prev_mp) {
            const d_mp = cur_mp - prev_mp;
            const x: i32 = @as(i32, global.palX(p.pos)) - 9;
            var y: i32 = @as(i32, global.palY(p.pos)) - 67;
            if (y < 10) y = 10;
            if (d_mp > 0) {
                showNum(@intCast(d_mp), global.palXY(@truncate(x), @truncate(y)), .blue);
            }
            // MP-drop display (魔改 EX_SHOW_MP_DROP) intentionally disabled —
            // every spellcast would otherwise spam a purple number on the
            // caster.
            any = true;
        }
    }
    return any;
}

// PAL_BattleUpdateFighters — set every fighter's gesture/position from state.
pub fn updateFighters() void {
    var i: u32 = 0;
    while (i <= global.gpg.max_party_member_index) : (i += 1) {
        const role = global.gpg.party[i].player_role;
        const p = &battle.g_battle.players[i];
        if (!p.defending) p.pos = p.pos_original;
        p.color_shift = 0;
        if (global.gpg.g.player_roles.hp[role] == 0) {
            p.current_frame = if (global.gpg.player_status[role][global.STATUS_PUPPET] == 0) 2 else 0;
        } else if (global.gpg.player_status[role][global.STATUS_SLEEP] != 0 or isPlayerDying(role)) {
            p.current_frame = 1;
        } else if (p.defending and !battle.g_battle.enemy_cleared) {
            p.current_frame = 3;
        } else {
            p.current_frame = 0;
        }
    }

    i = 0;
    while (battle.g_battle.max_enemy_index >= 0 and i <= @as(u32, @intCast(battle.g_battle.max_enemy_index))) : (i += 1) {
        const e = &battle.g_battle.enemies[i];
        if (e.object_id == 0) continue;
        e.pos = e.pos_original;
        e.color_shift = 0;
        if (e.status[global.STATUS_SLEEP] > 0 or e.status[global.STATUS_PARALYZED] > 0) {
            e.current_frame = 0;
            continue;
        }
        if (e.e.idle_anim_speed != 0) e.e.idle_anim_speed -%= 1;
        if (e.e.idle_anim_speed == 0) {
            e.current_frame +%= 1;
            const enemy_id = global.gpg.g.objects[e.object_id].data[0];
            e.e.idle_anim_speed = global.gpg.g.enemies[enemy_id].idle_anim_speed;
        }
        if (e.current_frame >= e.e.idle_frames) e.current_frame = 0;
    }
}

// PAL_BattlePostActionCheck — fight.c L719. Clear KO'd enemies and play the
// fade-out animation; set fEnemyCleared when the team is wiped.
pub fn postActionCheck(fCheckPlayers: bool) void {
    var fFade = false;
    var fEnemyRemaining = false;

    var i: u32 = 0;
    while (battle.g_battle.max_enemy_index >= 0 and i <= @as(u32, @intCast(battle.g_battle.max_enemy_index))) : (i += 1) {
        const e = &battle.g_battle.enemies[i];
        if (e.object_id == 0) continue;
        if (@as(i16, @bitCast(e.e.health)) <= 0) {
            // fight.c L756 — enemy death sound.
            @import("audio.zig").playSound(@intCast(e.e.death_sound));
            // Debug mode: 10× exp/cash for grinding speed during testing.
            const mul: i32 = if (@import("debug.zig").enabled) 10 else 1;
            battle.g_battle.exp_gained += @as(i32, e.e.exp) * mul;
            battle.g_battle.cash_gained += @as(i32, e.e.cash) * mul;
            e.object_id = 0;
            if (e.sprite) |buf| {
                global.allocator.free(buf);
                e.sprite = null;
            }
            fFade = true;
            continue;
        }
        fEnemyRemaining = true;
    }

    if (!fEnemyRemaining) {
        battle.g_battle.enemy_cleared = true;
        battle.g_battle.ui.state = .wait;
    }

    // fCheckPlayers branch (fight.c L775-886): friend-death + dying scripts.
    if (fCheckPlayers) blk: {
        // Friend-death pass.
        var pi: u32 = 0;
        while (pi <= global.gpg.max_party_member_index) : (pi += 1) {
            var w: u16 = global.gpg.party[pi].player_role;
            const prev_hp = battle.g_battle.players[pi].prev_hp;

            if (global.gpg.g.player_roles.hp[w] < prev_hp and global.gpg.g.player_roles.hp[w] == 0) {
                w = global.gpg.g.player_roles.covered_by[w];

                var j: u32 = 0;
                var found: bool = false;
                while (j <= global.gpg.max_party_member_index) : (j += 1) {
                    if (global.gpg.party[j].player_role == w) {
                        found = true;
                        break;
                    }
                }

                if (global.gpg.g.player_roles.hp[w] > 0 and
                    global.gpg.player_status[w][global.STATUS_SLEEP] == 0 and
                    global.gpg.player_status[w][global.STATUS_PARALYZED] == 0 and
                    global.gpg.player_status[w][global.STATUS_CONFUSED] == 0 and
                    found)
                {
                    const wName = global.gpg.g.player_roles.name[w];
                    const sFD = global.gpg.g.objects[wName].player().script_on_friend_death;
                    if (sFD != 0) {
                        battleDelay(10, 0, true);

                        battle.battleMakeScene();
                        @memcpy(&video.screen_pixels, &battle.g_battle.scene_buf_pixels);
                        video.updateScreen(null);

                        battle.g_battle.result = .pause;
                        const new_sFD = script.runTriggerScript(sFD, w);
                        global.gpg.g.objects[wName].data[2] = new_sFD;
                        battle.g_battle.result = .on_going;

                        input.clearKeyState();
                        break :blk;
                    }
                }
            }
        }

        // Dying pass.
        pi = 0;
        while (pi <= global.gpg.max_party_member_index) : (pi += 1) {
            const w: u16 = global.gpg.party[pi].player_role;

            if (global.gpg.player_status[w][global.STATUS_SLEEP] != 0 or
                global.gpg.player_status[w][global.STATUS_CONFUSED] != 0)
            {
                continue;
            }

            const prev_hp = battle.g_battle.players[pi].prev_hp;
            if (global.gpg.g.player_roles.hp[w] < prev_hp) {
                if (global.gpg.g.player_roles.hp[w] > 0 and isPlayerDying(w) and
                    prev_hp >= global.gpg.g.player_roles.max_hp[w] / 5)
                {
                    const wCover = global.gpg.g.player_roles.covered_by[w];

                    if (global.gpg.player_status[wCover][global.STATUS_SLEEP] != 0 or
                        global.gpg.player_status[wCover][global.STATUS_PARALYZED] != 0 or
                        global.gpg.player_status[wCover][global.STATUS_CONFUSED] != 0)
                    {
                        continue;
                    }

                    const wName = global.gpg.g.player_roles.name[w];

                    var j: u32 = 0;
                    var found: bool = false;
                    while (j <= global.gpg.max_party_member_index) : (j += 1) {
                        if (global.gpg.party[j].player_role == wCover) {
                            found = true;
                            break;
                        }
                    }
                    if (!found or global.gpg.g.player_roles.hp[wCover] == 0) continue;

                    const sDying = global.gpg.g.objects[wName].player().script_on_dying;
                    if (sDying != 0) {
                        // fight.c L850 — dying voice cue.
                        @import("audio.zig").playSound(@intCast(global.gpg.g.player_roles.dying_sound[w]));
                        battleDelay(10, 0, true);

                        battle.battleMakeScene();
                        @memcpy(&video.screen_pixels, &battle.g_battle.scene_buf_pixels);
                        video.updateScreen(null);

                        battle.g_battle.result = .pause;
                        const new_sDying = script.runTriggerScript(sDying, w);
                        global.gpg.g.objects[wName].data[3] = new_sDying;
                        battle.g_battle.result = .on_going;
                        input.clearKeyState();
                    }
                    break :blk;
                }
            }
        }
    }

    if (fFade) {
        // L891-893: VIDEO_BackupScreen + makeScene + fadeScene to dissolve the
        // dead enemy out smoothly. The 72-frame fade also lets show_num
        // entries (10-frame lifetime) expire on their own.
        video.backupScreen();
        battle.battleMakeScene();
        battle.battleFadeScene();
    }

    // Fade out the summoned god (fight.c L897-912).
    if (battle.g_battle.summon_sprite != null) {
        updateFighters();
        battleDelay(1, 0, false);

        global.allocator.free(battle.g_battle.summon_sprite.?);
        battle.g_battle.summon_sprite = null;

        battle.g_battle.background_color_shift = 0;

        video.backupScreen();
        battle.battleMakeScene();
        battle.battleFadeScene();
    }
}

// PAL_BattleCommitAction — fight.c L1811. Player committed their action.
pub fn commitAction(repeat: bool) void {
    const idx = battle.g_battle.ui.cur_player_index;
    const p = &battle.g_battle.players[idx];

    if (repeat) {
        const tgt = p.action.target;
        p.action = p.prev_action;
        p.action.target = tgt;
        if (p.action.action_type == .pass) {
            p.action.action_type = .attack;
            p.action.action_id = 0;
            p.action.target = -1;
        }
    } else {
        p.action.action_type = @enumFromInt(battle.g_battle.ui.action_type);
        p.action.action_id = battle.g_battle.ui.object_id;
        p.action.target = @intCast(battle.g_battle.ui.selected_index);
        if (p.action.action_type == .attack) {
            p.action.action_id = if (battle.g_battle.ui.auto_attack) 1 else 0;
        }
        if (p.action.action_type == .attack and p.action.target != -1) {
            battle.g_battle.ui.prev_enemy_target = p.action.target;
        }
    }

    // PAL_CLASSIC coop-magic preflight (fight.c L3361-L3409): everyone but the
    // dying/silenced/etc gets flagged as a contributor; if only one healthy
    // ally exists, fall back to a regular attack. Done before consumable
    // bookkeeping so the action_type is final by then.
    if (p.action.action_type == .coop_magic) {
        var iTotalHealthy: u32 = 0;
        var i: u32 = 0;
        while (i <= global.gpg.max_party_member_index) : (i += 1) {
            const w = global.gpg.party[i].player_role;
            const ok = isPlayerHealthy(w);
            battle.g_battle.coop_contributors[i] = if (ok) 1 else 0;
            if (ok) iTotalHealthy += 1;
        }
        if (iTotalHealthy <= 1) {
            p.action.action_type = .attack;
            p.action.action_id = 0;
        } else {
            const wObject = global.getPlayerCooperativeMagic(global.gpg.party[idx].player_role);
            const flags = global.gpg.g.objects[wObject].magic().flags;
            if ((flags & global.MAGIC_FLAG_APPLY_TO_ALL) != 0) {
                p.action.target = -1;
            } else if (p.action.target == -1) {
                p.action.target = @intCast(battleSelectAutoTargetFrom(p.action.target));
            }
        }
    }

    // PAL_CLASSIC: increment nAmountInUse for use_item / throw_item.
    if (p.action.action_type == .throw_item) {
        var i: u32 = 0;
        while (i < global.MAX_INVENTORY) : (i += 1) {
            if (global.gpg.inventory[i].item == p.action.action_id) {
                global.gpg.inventory[i].amount_in_use +%= 1;
                break;
            }
        }
    } else if (p.action.action_type == .use_item) {
        const flags = global.gpg.g.objects[p.action.action_id].item().flags;
        if ((flags & global.ITEM_FLAG_CONSUMING) != 0) {
            var i: u32 = 0;
            while (i < global.MAX_INVENTORY) : (i += 1) {
                if (global.gpg.inventory[i].item == p.action.action_id) {
                    global.gpg.inventory[i].amount_in_use +%= 1;
                    break;
                }
            }
        }
    }

    // fight.c L1976-L1979: PAL_CLASSIC sets fFlee=TRUE when the action is
    // Flee, so every later player in the SelectAction phase auto-flees.
    if (p.action.action_type == .flee) {
        battle.g_battle.flee = true;
    }

    p.state = .act;
    battle.g_battle.ui.state = .wait;
    battle.g_battle.ui.menu_state = .main;
}

// Refund Use/Throw item nAmountInUse on Back-key (PAL_CLASSIC undo). Mirrors
// the loop in uibattle.c's kKeyMenu handler around L1239.
pub fn refundUiActionConsumables(player_index: u16) void {
    const a = battle.g_battle.players[player_index].action;
    if (a.action_type == .throw_item) {
        var i: u32 = 0;
        while (i < global.MAX_INVENTORY) : (i += 1) {
            if (global.gpg.inventory[i].item == a.action_id) {
                if (global.gpg.inventory[i].amount_in_use > 0)
                    global.gpg.inventory[i].amount_in_use -= 1;
                break;
            }
        }
    } else if (a.action_type == .use_item) {
        const flags = global.gpg.g.objects[a.action_id].item().flags;
        if ((flags & global.ITEM_FLAG_CONSUMING) != 0) {
            var i: u32 = 0;
            while (i < global.MAX_INVENTORY) : (i += 1) {
                if (global.gpg.inventory[i].item == a.action_id) {
                    if (global.gpg.inventory[i].amount_in_use > 0)
                        global.gpg.inventory[i].amount_in_use -= 1;
                    break;
                }
            }
        }
    }
}

// PAL_BattlePlayerCheckReady — fight.c L1023. PAL_CLASSIC SelectAction phase
// only: promote the next .wait player to .com so the UI menu opens for them.
pub fn playerCheckReady() void {
    if (battle.g_battle.phase != .select_action) return;
    if (battle.g_battle.ui.state != .wait) return;

    var i: u32 = 0;
    while (i <= global.gpg.max_party_member_index) : (i += 1) {
        const role = global.gpg.party[i].player_role;
        // Skip players who can't act this turn.
        if (global.gpg.g.player_roles.hp[role] == 0 or
            global.gpg.player_status[role][global.STATUS_SLEEP] != 0 or
            global.gpg.player_status[role][global.STATUS_CONFUSED] != 0 or
            global.gpg.player_status[role][global.STATUS_PARALYZED] != 0) continue;
        if (battle.g_battle.players[i].state == .wait) {
            battle.g_battle.players[i].state = .com;
            // Mirror PAL_BattlePlayerCheckReady (fight.c:1068): clear defend
            // so last turn's defending stance doesn't carry into this menu.
            battle.g_battle.players[i].defending = false;
            battle.g_battle.moving_player_index = @intCast(i);
            @import("battleui.zig").playerReady(@intCast(i));
            return;
        } else if (battle.g_battle.players[i].action.action_type == .coop_magic) {
            // Skip the rest of the party — coop magic eats everyone's turn.
            allActionsSelected();
            return;
        }
    }
    // Everyone has chosen → switch to perform_action.
    allActionsSelected();
}

// PAL_BattleStartFrame's "actions for all players are decided" branch —
// build the action queue, sort by dexterity, flip to perform_action.
fn allActionsSelected() void {
    if (!battle.g_battle.repeat) {
        var i: u32 = 0;
        while (i <= global.gpg.max_party_member_index) : (i += 1) {
            battle.g_battle.players[i].prev_action = battle.g_battle.players[i].action;
        }
    }
    battle.g_battle.repeat = false;
    battle.g_battle.force = false;
    battle.g_battle.flee = false;
    // fight.c L1446-L1447: snapshot the auto-atk UI flag so the round can
    // honour it across players (R-key repeat path), and clear the per-round
    // "I auto-attacked" tracker.
    battle.g_battle.prev_auto_atk = battle.g_battle.ui.auto_attack;
    battle.g_battle.prev_player_auto_atk = false;
    battle.g_battle.cur_action = 0;

    for (&battle.g_battle.action_queue) |*q| q.* = .{ .index = 0xFFFF, .dexterity = 0xFFFF };

    var j: u32 = 0;

    // Enemies.
    var i: u32 = 0;
    while (battle.g_battle.max_enemy_index >= 0 and i <= @as(u32, @intCast(battle.g_battle.max_enemy_index))) : (i += 1) {
        if (battle.g_battle.enemies[i].object_id == 0) continue;
        const dex_base: f32 = @floatFromInt(getEnemyDexterity(i));
        const dex: u32 = @intFromFloat(dex_base * util.randomFloatRange(0.9, 1.1));
        battle.g_battle.action_queue[j] = .{
            .is_enemy = true,
            .index = @intCast(i),
            .dexterity = @truncate(dex),
        };
        j += 1;
    }

    // Players.
    i = 0;
    while (i <= global.gpg.max_party_member_index) : (i += 1) {
        const role = global.gpg.party[i].player_role;
        var qe: battle.ActionQueue = .{ .is_enemy = false, .index = @intCast(i) };

        if (global.gpg.g.player_roles.hp[role] == 0 or
            global.gpg.player_status[role][global.STATUS_SLEEP] != 0 or
            global.gpg.player_status[role][global.STATUS_PARALYZED] != 0)
        {
            qe.dexterity = 0;
            battle.g_battle.players[i].action.action_type = .attack;
            battle.g_battle.players[i].action.action_id = 0;
            battle.g_battle.players[i].state = .act;
        } else {
            var dex: f32 = @floatFromInt(getPlayerActualDexterity(role));
            if (global.gpg.player_status[role][global.STATUS_CONFUSED] != 0) {
                battle.g_battle.players[i].action.action_type = .attack;
                battle.g_battle.players[i].action.action_id = 0;
                battle.g_battle.players[i].state = .act;
            }
            switch (battle.g_battle.players[i].action.action_type) {
                .coop_magic => dex *= 10,
                .defend => dex *= 5,
                .magic => {
                    const obj_id = battle.g_battle.players[i].action.action_id;
                    const flags = global.gpg.g.objects[obj_id].magic().flags;
                    if ((flags & global.MAGIC_FLAG_USABLE_TO_ENEMY) == 0) dex *= 3;
                },
                .flee => dex /= 2,
                .use_item => dex *= 3,
                else => {},
            }
            if (isPlayerDying(role)) dex /= 2;
            dex *= util.randomFloatRange(0.9, 1.1);
            qe.dexterity = @intFromFloat(dex);
        }
        battle.g_battle.action_queue[j] = qe;
        j += 1;
    }

    // Selection-sort by dexterity descending (signed compare like SDLPAL).
    var a: u32 = 0;
    while (a < battle.MAX_ACTIONQUEUE_ITEMS) : (a += 1) {
        var b: u32 = a;
        while (b < battle.MAX_ACTIONQUEUE_ITEMS) : (b += 1) {
            const av: i16 = @bitCast(battle.g_battle.action_queue[a].dexterity);
            const bv: i16 = @bitCast(battle.g_battle.action_queue[b].dexterity);
            if (av < bv) {
                const tmp = battle.g_battle.action_queue[a];
                battle.g_battle.action_queue[a] = battle.g_battle.action_queue[b];
                battle.g_battle.action_queue[b] = tmp;
            }
        }
    }

    battle.g_battle.phase = .perform_action;
}

// --- Action execution ---

// Validate the action target before perform — Stage 7c just relies on the
// commit-time target. PAL_CLASSIC reroutes a few illegal cases (target
// dead, magic with no MP, etc); we'll grow this as needed.
fn validateAction(player_index: u16) void {
    const p = &battle.g_battle.players[player_index];
    if (p.action.action_type == .attack and p.action.target >= 0) {
        const t: usize = @intCast(p.action.target);
        if (battle.g_battle.enemies[t].object_id == 0 or @as(i16, @bitCast(battle.g_battle.enemies[t].e.health)) <= 0) {
            const auto = battleSelectAutoTarget();
            p.action.target = if (auto < 0) -1 else @intCast(auto);
        }
    }
}

// Simplified PAL_BattleShowPlayerAttackAnim — slide the attacker to the
// target, pop a hit-flash, slide back. No effect-sprite blit yet; that's
// in g_battle.effect_sprite.
// PAL_BattleShowPlayerAttackAnim — fight.c L2008. Full port of the player
// physical attack animation: lunge in, swing (frame 8 → 9), 3 frames of
// effect sprite from FIRE/DATA effect_sprite indexed via rgwBattleEffectIndex,
// flash + back-and-forth bounce on targets.
fn playerAttackAnim(player_index: u16, target: i32, critical: bool) void {
    const role = global.gpg.party[player_index].player_role;
    const p = &battle.g_battle.players[player_index];

    // fight.c L2061 — attack/critical voice while alive.
    if (global.gpg.g.player_roles.hp[role] > 0) {
        const sfx: u16 = if (critical)
            global.gpg.g.player_roles.critical_sound[role]
        else
            global.gpg.g.player_roles.attack_sound[role];
        @import("audio.zig").playSound(@intCast(sfx));
    }

    var enemy_x: i32 = 0;
    var enemy_y: i32 = 0;
    var enemy_h: i32 = 0;
    var dist: i32 = 0;

    if (target != -1) {
        const e = &battle.g_battle.enemies[@intCast(target)];
        enemy_x = global.palX(e.pos);
        enemy_y = global.palY(e.pos);
        if (e.sprite) |sp| {
            if (palcommon.spriteGetFrame(sp, @intCast(e.current_frame))) |b0| {
                enemy_h = palcommon.rleGetHeight(b0);
            }
        }
        if (target >= 3) dist = (target - @as(i32, @intCast(player_index))) * 8;
    } else {
        enemy_x = 150;
        enemy_y = 100;
    }

    // Effect sprite frames (3 frames per attack stage).
    var index: u32 = global.gpg.g.battle_effect_index[battle.getPlayerBattleSprite(role)][1];
    index *= 3;

    // Lunge in.
    var x: i32 = enemy_x - dist + 64;
    var y: i32 = enemy_y + dist + 20;

    p.current_frame = 8;
    if (global.gpg.player_status[role][global.STATUS_DUAL_ATTACK] > 0 and global.playerCanAttackAll(role)) {
        const max_idx: u32 = global.gpg.max_party_member_index;
        const px: i32 = battle.PLAYER_POS_PUB[max_idx][player_index][0] - 8;
        const py: i32 = battle.PLAYER_POS_PUB[max_idx][player_index][1] - 4;
        if (!p.second_attack) {
            p.pos = global.palXY(@truncate(px), @truncate(py));
        } else {
            p.pos = global.palXY(@truncate(px - 12), @truncate(py - 8));
        }
    } else {
        p.pos = global.palXY(@truncate(x), @truncate(y));
    }
    battleDelay(2, 0, true);

    x -= 10;
    y -= 2;
    if (global.gpg.player_status[role][global.STATUS_DUAL_ATTACK] > 0 and global.playerCanAttackAll(role)) {
        const max_idx: u32 = global.gpg.max_party_member_index;
        const px: i32 = battle.PLAYER_POS_PUB[max_idx][player_index][0] - 8;
        const py: i32 = battle.PLAYER_POS_PUB[max_idx][player_index][1] - 4;
        if (!p.second_attack) {
            p.pos = global.palXY(@truncate(px), @truncate(py));
        } else {
            p.pos = global.palXY(@truncate(px - 12), @truncate(py - 8));
        }
    } else {
        p.pos = global.palXY(@truncate(x), @truncate(y));
    }
    battleDelay(1, 0, true);

    p.current_frame = 9;
    x -= 16;
    y -= 4;
    _ = &x;
    _ = &y;

    // fight.c L2124 — weapon impact SFX.
    @import("audio.zig").playSound(@intCast(global.gpg.g.player_roles.weapon_sound[role]));

    // Effect frames: 3 ticks of sprite over the target(s) + idle gestures.
    x = enemy_x;
    y = enemy_y - @divTrunc(enemy_h, 3) + 10;

    var dw_time = util.getTicks() + global.BATTLE_FRAME_TIME;
    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        const eff_sprite = battle.g_battle.effect_sprite orelse break;
        const b = palcommon.spriteGetFrame(eff_sprite, @intCast(index)) orelse break;
        index += 1;

        while (util.getTicks() < dw_time) {
            input.processEvent();
            std.Thread.yield() catch {};
            if (util.shouldQuit()) return;
        }
        dw_time = util.getTicks() + global.BATTLE_FRAME_TIME;

        // Tick enemy idle gestures.
        var j: u32 = 0;
        while (battle.g_battle.max_enemy_index >= 0 and j <= @as(u32, @intCast(battle.g_battle.max_enemy_index))) : (j += 1) {
            const e = &battle.g_battle.enemies[j];
            if (e.object_id == 0 or
                e.status[global.STATUS_SLEEP] > 0 or
                e.status[global.STATUS_PARALYZED] > 0) continue;
            e.e.idle_anim_speed -%= 1;
            if (e.e.idle_anim_speed == 0) {
                e.current_frame +%= 1;
                const enemy_id = global.gpg.g.objects[e.object_id].data[0];
                e.e.idle_anim_speed = global.gpg.g.enemies[enemy_id].idle_anim_speed;
            }
            if (e.current_frame >= e.e.idle_frames) e.current_frame = 0;
        }

        battle.battleMakeScene();
        @memcpy(&video.screen_pixels, &battle.g_battle.scene_buf_pixels);

        if (global.playerCanAttackAll(role)) {
            // Splash effect on every alive enemy at their canonical pos.
            const max_idx: i32 = battle.g_battle.max_enemy_index;
            var ej: u32 = 0;
            while (ej < global.MAX_ENEMIES_IN_TEAM) : (ej += 1) {
                if (battle.g_battle.enemies[ej].object_id != 0) {
                    const ep = global.gpg.g.enemy_pos.pos[ej][@intCast(@max(max_idx, 0))];
                    const ex: i32 = ep.x;
                    const ey: i32 = @as(i32, ep.y) + battle.g_battle.enemies[ej].e.y_pos_offset;
                    _ = palcommon.rleBlitToSurface(b, &video.screen, global.palXY(
                        @truncate(ex - @divTrunc(palcommon.rleGetWidth(b), 2)),
                        @truncate(ey - palcommon.rleGetHeight(b)),
                    ));
                }
            }
        } else {
            _ = palcommon.rleBlitToSurface(b, &video.screen, global.palXY(
                @truncate(x - @divTrunc(palcommon.rleGetWidth(b), 2)),
                @truncate(y - palcommon.rleGetHeight(b)),
            ));
        }

        x -= 16;
        y += 16;

        @import("battleui.zig").update();

        if (i == 0) {
            // Apply damage flash on first frame.
            if (target == -1) {
                var k: u32 = 0;
                while (battle.g_battle.max_enemy_index >= 0 and k <= @as(u32, @intCast(battle.g_battle.max_enemy_index))) : (k += 1) {
                    battle.g_battle.enemies[k].color_shift = 6;
                }
            } else {
                battle.g_battle.enemies[@intCast(target)].color_shift = 6;
            }
            _ = displayStatChange();
            backupStat();
        }

        video.updateScreen(null);

        if (i == 1) {
            const px: i32 = global.palX(p.pos);
            const py: i32 = global.palY(p.pos);
            p.pos = global.palXY(@truncate(px + 2), @truncate(py + 1));
        }
    }

    // Clear color shifts.
    {
        var k: u32 = 0;
        while (battle.g_battle.max_enemy_index >= 0 and k <= @as(u32, @intCast(battle.g_battle.max_enemy_index))) : (k += 1) {
            battle.g_battle.enemies[k].color_shift = 0;
        }
    }

    // Knockback bounce: 3 ticks, dist starts at 8, halved-and-flipped each tick.
    var bounce_dist: i32 = 8;
    if (target == -1) {
        var ti: u32 = 0;
        while (ti < 3) : (ti += 1) {
            var k: u32 = 0;
            while (battle.g_battle.max_enemy_index >= 0 and k <= @as(u32, @intCast(battle.g_battle.max_enemy_index))) : (k += 1) {
                const ex: i32 = global.palX(battle.g_battle.enemies[k].pos);
                const ey: i32 = global.palY(battle.g_battle.enemies[k].pos);
                battle.g_battle.enemies[k].pos = global.palXY(@truncate(ex - bounce_dist), @truncate(ey));
            }
            battleDelay(1, 0, true);
            bounce_dist = -@divTrunc(bounce_dist, 2);
        }
    } else {
        var tx: i32 = global.palX(battle.g_battle.enemies[@intCast(target)].pos);
        var ty: i32 = global.palY(battle.g_battle.enemies[@intCast(target)].pos);
        var ti: u32 = 0;
        while (ti < 3) : (ti += 1) {
            tx -= bounce_dist;
            bounce_dist = -@divTrunc(bounce_dist, 2);
            ty += bounce_dist;
            battle.g_battle.enemies[@intCast(target)].pos = global.palXY(@truncate(tx), @truncate(ty));
            battleDelay(1, 0, true);
        }
    }
}

// PAL_BattlePlayerPerformAction — physical attack / defend / flee / pass.
// Magic / items will land in 7d follow-ups.
pub fn playerPerformAction(player_index: u16) void {
    const role = global.gpg.party[player_index].player_role;
    const p = &battle.g_battle.players[player_index];
    battle.g_battle.moving_player_index = player_index;
    battle.g_battle.blow = 0;

    // fight.c L3610: snapshot original target so we can restore at end
    // (validateAction may rewrite it for auto-target on dead enemy etc.).
    const orig_target: i16 = p.action.target;

    validateAction(player_index);
    backupStat();

    switch (p.action.action_type) {
        .attack => {
            // DUAL_ATTACK status replays the entire attack block twice
            // (fight.c L3628 / L3681). The pre-attack frame=7 + delay only
            // happens on the first iteration.
            const dual: u32 = if (global.gpg.player_status[role][global.STATUS_DUAL_ATTACK] > 0) 2 else 1;
            var t_iter: u32 = 0;
            while (t_iter < dual) : (t_iter += 1) {
                if (p.action.target >= 0) {
                    const t: usize = @intCast(p.action.target);
                    const enemy = &battle.g_battle.enemies[t];
                    // SDLPAL fight.c:3630-3633 does the def += level*4 step in
                    // WORD arithmetic, so an enemy with wDefense=0xFFFF (the
                    // "no defense" sentinel in DATA chunk 1) wraps around to a
                    // small positive value. Mirror the wraparound by computing
                    // in u16 first, then widening for the damage formula.
                    const str: i32 = global.getPlayerAttackStrength(role);
                    var def_w: u16 = enemy.e.defense;
                    def_w +%= @intCast((@as(i32, enemy.e.level) + 6) * 4);
                    const def: i32 = def_w;
                    const res: i32 = enemy.e.physical_resistance;
                    var dmg: i32 = calcPhysicalAttackDamage(str, def, res);
                    dmg += util.randomLong(1, 2);
                    var critical = false;
                    if (util.randomLong(0, 5) == 0 or
                        global.gpg.player_status[role][global.STATUS_BRAVERY] > 0)
                    {
                        dmg *= 3;
                        critical = true;
                    }
                    if (role == 0 and util.randomLong(0, 11) == 0) {
                        dmg *= 2;
                        critical = true;
                    }
                    const jitter: f32 = util.randomFloatRange(1.0, 1.125);
                    dmg = @intFromFloat(@as(f32, @floatFromInt(dmg)) * jitter);
                    if (dmg <= 0) dmg = 1;
                    const hp_i: i32 = @as(i32, enemy.e.health) - dmg;
                    enemy.e.health = if (hp_i < 0) 0 else @intCast(hp_i);
                    if (t_iter == 0) {
                        p.current_frame = 7;
                        battleDelay(4, 0, true);
                    }
                    playerAttackAnim(player_index, p.action.target, critical);
                } else {
                    // Attack-all (fight.c L3681-L3747).
                    const indices = [_]i32{ 2, 1, 0, 4, 3 };
                    var division: i32 = 1;
                    var x: i32 = 1;
                    const critical = (util.randomLong(0, 5) == 0 or
                        global.gpg.player_status[role][global.STATUS_BRAVERY] > 0);
                    if (t_iter == 0) {
                        p.current_frame = 7;
                        battleDelay(4, 0, true);
                    }
                    for (indices) |idx| {
                        if (idx > battle.g_battle.max_enemy_index) continue;
                        const u: usize = @intCast(idx);
                        const enemy = &battle.g_battle.enemies[u];
                        if (enemy.object_id == 0) continue;
                        const str: i32 = global.getPlayerAttackStrength(role);
                        var def_w: u16 = enemy.e.defense;
                        def_w +%= @intCast((@as(i32, enemy.e.level) + 6) * 4);
                        const def: i32 = def_w;
                        const res: i32 = enemy.e.physical_resistance;
                        var dmg: i32 = calcPhysicalAttackDamage(str, def, res);
                        if (critical) dmg *= 3;
                        dmg = @divTrunc(dmg, division);
                        if (dmg <= 0) dmg = 1;
                        const hp_i: i32 = @as(i32, enemy.e.health) - dmg;
                        enemy.e.health = if (hp_i < 0) 0 else @intCast(hp_i);
                        if (enemy.object_id != 0) division *= 2;
                    }
                    if (t_iter > 0) {
                        if (x == 1) {
                            p.second_attack = true;
                            x -= 1;
                        } else {
                            p.second_attack = false;
                        }
                    }
                    playerAttackAnim(player_index, -1, critical);
                    battleDelay(4, 0, true);
                }
            }
            p.second_attack = false;
            updateFighters();
            battleDelay(3, 0, true);
            global.gpg.exp.attack[role].count +%= 1;
            global.gpg.exp.health[role].count +%= @intCast(util.randomLong(2, 3));
        },
        .defend => {
            // SDLPAL fight.c:4115 only sets fDefending; the gesture comes
            // from PAL_BattleUpdateFighters next frame.
            p.defending = true;
            global.gpg.exp.defense[role].count +%= 2;
            updateFighters();
            battleDelay(2, 0, true);
        },
        .flee => {
            // fight.c L4119-L4172. Successful escape runs PAL_BattlePlayerEscape;
            // failure shows the BATTLE_LABEL_ESCAPEFAIL banner.
            var str: i32 = global.getPlayerFleeRate(role);
            var def: i32 = 0;
            var ei: u32 = 0;
            while (battle.g_battle.max_enemy_index >= 0 and ei <= @as(u32, @intCast(battle.g_battle.max_enemy_index))) : (ei += 1) {
                if (battle.g_battle.enemies[ei].object_id == 0) continue;
                def += @as(i16, @bitCast(battle.g_battle.enemies[ei].e.dexterity));
                def += (@as(i32, battle.g_battle.enemies[ei].e.level) + 6) * 4;
            }
            if (def < 0) def = 0;
            _ = &str;
            if (str >= util.randomLong(0, def) and !battle.g_battle.is_boss) {
                playerEscape();
            } else {
                p.current_frame = 0;
                var k: u32 = 0;
                while (k < 3) : (k += 1) {
                    const px: i32 = @as(i32, global.palX(p.pos)) + 4;
                    const py: i32 = @as(i32, global.palY(p.pos)) + 2;
                    p.pos = global.palXY(@truncate(px), @truncate(py));
                    battleDelay(1, 0, true);
                }
                p.current_frame = 1;
                battleDelay(8, 39, true); // BATTLE_LABEL_ESCAPEFAIL
                global.gpg.exp.flee[role].count +%= 2;
            }
        },
        .pass => {},
        .attack_mate => {
            // fight.c L3760-L3854. Coop turn skips this entire branch.
            if (battle.g_battle.this_turn_coop) {} else {
                // Anyone else alive?
                var anyone_alive: bool = false;
                {
                    var j: u32 = 0;
                    while (j <= global.gpg.max_party_member_index) : (j += 1) {
                        if (j == player_index) continue;
                        if (global.gpg.g.player_roles.hp[global.gpg.party[j].player_role] > 0) {
                            anyone_alive = true;
                            break;
                        }
                    }
                }
                if (anyone_alive) {
                    // Random target (skipping self / dead).
                    var t_idx: u32 = 0;
                    while (true) {
                        t_idx = @intCast(util.randomLong(0, @intCast(global.gpg.max_party_member_index)));
                        if (t_idx == player_index) continue;
                        if (global.gpg.g.player_roles.hp[global.gpg.party[t_idx].player_role] != 0) break;
                    }

                    // Two-frame "winding up" gesture (frame 8 ↔ 0).
                    var j: u32 = 0;
                    while (j < 2) : (j += 1) {
                        p.current_frame = 8;
                        battleDelay(1, 0, true);
                        p.current_frame = 0;
                        battleDelay(1, 0, true);
                    }
                    battleDelay(2, 0, true);

                    // Slide attacker to (target + (30, 12)) with raised gesture.
                    const tx: i32 = @as(i32, global.palX(battle.g_battle.players[t_idx].pos)) + 30;
                    const ty: i32 = @as(i32, global.palY(battle.g_battle.players[t_idx].pos)) + 12;
                    p.pos = global.palXY(@truncate(tx), @truncate(ty));
                    p.current_frame = 8;
                    battleDelay(5, 0, true);

                    p.current_frame = 9;
                    // Audio: weapon sound — skipped.

                    const t_role = global.gpg.party[t_idx].player_role;
                    var str: i32 = global.getPlayerAttackStrength(role);
                    var def: i32 = global.getPlayerDefense(t_role);
                    if (battle.g_battle.players[t_idx].defending) def *= 2;
                    _ = &str;

                    var dmg: i32 = calcPhysicalAttackDamage(str, def, 2);
                    if (global.gpg.player_status[t_role][global.STATUS_PROTECT] > 0) dmg = @divTrunc(dmg, 2);
                    if (dmg <= 0) dmg = 1;
                    const cur_hp: i32 = global.gpg.g.player_roles.hp[t_role];
                    if (dmg > cur_hp) dmg = cur_hp;
                    global.gpg.g.player_roles.hp[t_role] = @intCast(cur_hp - dmg);

                    // Knockback (-12, -6).
                    const tpx: i32 = global.palX(battle.g_battle.players[t_idx].pos);
                    const tpy: i32 = global.palY(battle.g_battle.players[t_idx].pos);
                    battle.g_battle.players[t_idx].pos = global.palXY(@truncate(tpx - 12), @truncate(tpy - 6));
                    battleDelay(1, 0, true);

                    battle.g_battle.players[t_idx].color_shift = 6;
                    battleDelay(1, 0, true);

                    _ = displayStatChange();

                    battle.g_battle.players[t_idx].color_shift = 0;
                    battleDelay(4, 0, true);

                    updateFighters();
                    battleDelay(4, 0, true);
                }
            }
        },
        .magic => {
            // fight.c L4174-4330. Coop hands are skipped via fThisTurnCoop.
            if (battle.g_battle.this_turn_coop) {
                // No-op when this turn is consumed by a coop magic.
            } else {
                const wObject = p.action.action_id;
                const wMagicNum = global.gpg.g.objects[wObject].magic().magic_number;
                const sTarget0 = detectMagicTargetChange(@intCast(wMagicNum), p.action.target);

                battleShowPlayerPreMagicAnim(player_index, global.gpg.g.magics[wMagicNum].magic_type == global.MAGIC_TYPE_SUMMON);

                // PAL_CLASSIC: cost MP unconditionally (gpGlobals->fAutoBattle is false).
                const cost = global.gpg.g.magics[wMagicNum].cost_mp;
                if (@as(i16, @bitCast(global.gpg.g.player_roles.mp[role])) < @as(i16, @bitCast(cost))) {
                    global.gpg.g.player_roles.mp[role] = 0;
                } else {
                    global.gpg.g.player_roles.mp[role] -= cost;
                }

                const m_type = global.gpg.g.magics[wMagicNum].magic_type;
                if (m_type == global.MAGIC_TYPE_APPLY_TO_PLAYER or
                    m_type == global.MAGIC_TYPE_APPLY_TO_PARTY or
                    m_type == global.MAGIC_TYPE_TRANCE)
                {
                    // Defensive magic.
                    var w_role: u16 = 0;
                    if (p.action.target != -1) {
                        w_role = global.gpg.party[@intCast(p.action.target)].player_role;
                    } else if (m_type == global.MAGIC_TYPE_TRANCE) {
                        w_role = role;
                    }

                    const new_use = script.runTriggerScript(global.gpg.g.objects[wObject].magic().script_on_use, role);
                    global.gpg.g.objects[wObject].data[3] = new_use;
                    if (script.g_script_success) {
                        battleShowPlayerDefMagicAnim(player_index, wObject, sTarget0);
                        const new_succ = script.runTriggerScript(global.gpg.g.objects[wObject].magic().script_on_success, w_role);
                        global.gpg.g.objects[wObject].data[2] = new_succ;
                        if (script.g_script_success) {
                            if (m_type == global.MAGIC_TYPE_TRANCE) {
                                var ti: i32 = 0;
                                while (ti < 6) : (ti += 1) {
                                    p.color_shift = ti * 2;
                                    battleDelay(1, 0, true);
                                }
                                video.backupScreen();
                                // PAL_LoadBattleSprites — re-derive sprite from the new battle sprite id.
                                p.color_shift = 0;
                                battle.battleMakeScene();
                                battle.battleFadeScene();
                            }
                        }
                    }
                } else {
                    // Offensive magic.
                    const new_use = script.runTriggerScript(global.gpg.g.objects[wObject].magic().script_on_use, role);
                    global.gpg.g.objects[wObject].data[3] = new_use;
                    if (script.g_script_success) {
                        if (m_type == global.MAGIC_TYPE_SUMMON) {
                            battleShowPlayerSummonMagicAnim(player_index, wObject);
                        } else {
                            battleShowPlayerOffMagicAnim(player_index, wObject, sTarget0, false);
                        }

                        const new_succ = script.runTriggerScript(
                            global.gpg.g.objects[wObject].magic().script_on_success,
                            if (sTarget0 == -1) 0xFFFF else @as(u16, @intCast(sTarget0)),
                        );
                        global.gpg.g.objects[wObject].data[2] = new_succ;

                        if (@as(i16, @bitCast(global.gpg.g.magics[wMagicNum].base_damage)) > 0) {
                            if (sTarget0 == -1) {
                                // Damage all enemies.
                                var ei: u32 = 0;
                                while (battle.g_battle.max_enemy_index >= 0 and ei <= @as(u32, @intCast(battle.g_battle.max_enemy_index))) : (ei += 1) {
                                    const e = &battle.g_battle.enemies[ei];
                                    if (e.object_id == 0) continue;
                                    const str: u16 = global.getPlayerMagicStrength(role);
                                    var def: i32 = e.e.defense;
                                    def += (@as(i32, e.e.level) + 6) * 4;
                                    var dmg = calcMagicDamage(str, def, &e.e.elem_resistance, e.e.poison_resistance, 1, wObject);
                                    if (dmg <= 0) dmg = 1;
                                    const new_hp: i32 = @as(i32, e.e.health) - dmg;
                                    e.e.health = if (new_hp < 0) 0 else @intCast(new_hp);
                                }
                            } else {
                                // Damage one enemy.
                                const e = &battle.g_battle.enemies[@intCast(sTarget0)];
                                const str: u16 = global.getPlayerMagicStrength(role);
                                var def: i32 = e.e.defense;
                                def += (@as(i32, e.e.level) + 6) * 4;
                                var dmg = calcMagicDamage(str, def, &e.e.elem_resistance, e.e.poison_resistance, 1, wObject);
                                if (dmg <= 0) dmg = 1;
                                const new_hp: i32 = @as(i32, e.e.health) - dmg;
                                e.e.health = if (new_hp < 0) 0 else @intCast(new_hp);
                            }
                        }
                    }
                }

                _ = displayStatChange();
                battleShowPostMagicAnim();
                battleDelay(5, 0, true);

                checkHidingEffect();

                global.gpg.exp.magic_exp[role].count +%= @intCast(util.randomLong(2, 3));
                global.gpg.exp.magic_power[role].count +%= 1;
            }
        },
        .throw_item => {
            // fight.c L4332-4376.
            if (battle.g_battle.this_turn_coop) {} else {
                const wObject = p.action.action_id;

                var ii: i32 = 0;
                while (ii < 4) : (ii += 1) {
                    const px: i32 = @as(i32, global.palX(p.pos)) - (4 - ii);
                    const py: i32 = @as(i32, global.palY(p.pos)) - @divTrunc(4 - ii, 2);
                    p.pos = global.palXY(@truncate(px), @truncate(py));
                    battleDelay(1, 0, true);
                }
                battleDelay(2, wObject, true);

                p.current_frame = 5;
                battleDelay(8, wObject, true);

                p.current_frame = 6;
                battleDelay(2, wObject, true);

                // Run the throw script.
                const new_throw = script.runTriggerScript(
                    global.gpg.g.objects[wObject].item().script_on_throw,
                    if (p.action.target == -1) 0xFFFF else @as(u16, @intCast(p.action.target)),
                );
                global.gpg.g.objects[wObject].data[4] = new_throw; // OBJECT_ITEM.script_on_throw

                _ = global.addItemToInventory(wObject, -1);

                _ = displayStatChange();
                battleDelay(4, 0, true);
                updateFighters();
                battleDelay(4, 0, true);

                checkHidingEffect();
            }
        },
        .use_item => {
            // fight.c L4378-4407.
            if (battle.g_battle.this_turn_coop) {} else {
                const wObject = p.action.action_id;
                battleShowPlayerUseItemAnim(player_index, wObject, p.action.target);

                const target_role: u16 = if (p.action.target == -1)
                    0xFFFF
                else
                    global.gpg.party[@intCast(p.action.target)].player_role;
                const new_use = script.runTriggerScript(
                    global.gpg.g.objects[wObject].item().script_on_use,
                    target_role,
                );
                global.gpg.g.objects[wObject].data[2] = new_use; // OBJECT_ITEM.script_on_use

                if ((global.gpg.g.objects[wObject].item().flags & global.ITEM_FLAG_CONSUMING) != 0) {
                    _ = global.addItemToInventory(wObject, -1);
                }

                checkHidingEffect();

                updateFighters();
                _ = displayStatChange();
                battleDelay(8, 0, true);
            }
        },
        .coop_magic => {
            // fight.c L3856-L4108. Full coop path.
            battle.g_battle.this_turn_coop = true;

            const wObject = global.getPlayerCooperativeMagic(role);
            const wMagicNum = global.gpg.g.objects[wObject].magic().magic_number;
            const sTarget0 = detectMagicTargetChange(@intCast(wMagicNum), p.action.target);

            // 魔改 — extra slot for the 4th coop contributor.
            const rgwCoopPos = [4][2]i32{ .{ 208, 157 }, .{ 234, 170 }, .{ 260, 183 }, .{ 286, 196 } };

            if (global.gpg.g.magics[wMagicNum].magic_type == global.MAGIC_TYPE_SUMMON) {
                battleShowPlayerPreMagicAnim(player_index, true);
                battleShowPlayerSummonMagicAnim(0xFFFF, wObject);
            } else {
                // Gather: 6 frames lerp every contributor toward rgwCoopPos.
                var i: i32 = 1;
                while (i <= 6) : (i += 1) {
                    var x: i32 = @as(i32, global.palX(p.pos_original)) * (6 - i);
                    var y: i32 = @as(i32, global.palY(p.pos_original)) * (6 - i);
                    x += rgwCoopPos[0][0] * i;
                    y += rgwCoopPos[0][1] * i;
                    x = @divTrunc(x, 6);
                    y = @divTrunc(y, 6);
                    p.pos = global.palXY(@truncate(x), @truncate(y));

                    var t: u32 = 0;
                    var j: u32 = 0;
                    while (j <= global.gpg.max_party_member_index) : (j += 1) {
                        if (j == player_index) continue;
                        t += 1;
                        if (battle.g_battle.coop_contributors[j] == 0) continue;
                        if (t >= rgwCoopPos.len) break;

                        const op = battle.g_battle.players[j].pos_original;
                        var jx: i32 = @as(i32, global.palX(op)) * (6 - i);
                        var jy: i32 = @as(i32, global.palY(op)) * (6 - i);
                        jx += rgwCoopPos[t][0] * i;
                        jy += rgwCoopPos[t][1] * i;
                        jx = @divTrunc(jx, 6);
                        jy = @divTrunc(jy, 6);
                        battle.g_battle.players[j].pos = global.palXY(@truncate(jx), @truncate(jy));
                    }
                    battleDelay(1, 0, true);
                }

                // Have each contributor flip to gesture frame 5 in reverse order.
                {
                    var ki: i32 = @intCast(global.gpg.max_party_member_index);
                    while (ki >= 0) : (ki -= 1) {
                        const k: u32 = @intCast(ki);
                        if (k == player_index) continue;
                        if (battle.g_battle.coop_contributors[k] == 0) continue;
                        battle.g_battle.players[k].current_frame = 5;
                        battleDelay(3, 0, true);
                    }
                }

                p.color_shift = 6;
                p.current_frame = 5;
                battleDelay(5, 0, true);

                p.current_frame = 6;
                p.color_shift = 0;
                battleDelay(3, 0, true);

                battleShowPlayerOffMagicAnim(0xFFFF, wObject, sTarget0, false);
            }

            // Drain MP from every contributor (clamping to 1 if it would go ≤0).
            // SDLPAL writes to rgwHP — that's an SDLPAL bug-compatible quirk.
            // Copy it as-is to match the reference port.
            var ic: u32 = 0;
            while (ic <= global.gpg.max_party_member_index) : (ic += 1) {
                if (battle.g_battle.coop_contributors[ic] == 0) continue;
                const r = global.gpg.party[ic].player_role;
                const cost = global.gpg.g.magics[wMagicNum].cost_mp;
                const cur_hp: i32 = global.gpg.g.player_roles.hp[r];
                var new_hp: i32 = cur_hp - @as(i32, cost);
                if (new_hp <= 0) new_hp = 1;
                global.gpg.g.player_roles.hp[r] = @intCast(new_hp);

                battle.g_battle.players[ic].state = .wait;
            }

            // Don't show the HP delta as a damage number.
            backupStat();

            // Combined attack/magic strength of all contributors / 4.
            var str_sum: i32 = 0;
            var is: u32 = 0;
            while (is <= global.gpg.max_party_member_index) : (is += 1) {
                if (battle.g_battle.coop_contributors[is] == 0) continue;
                const r = global.gpg.party[is].player_role;
                str_sum += global.getPlayerAttackStrength(r);
                str_sum += global.getPlayerMagicStrength(r);
            }
            str_sum = @divTrunc(str_sum, 4);

            // Inflict damage.
            if (sTarget0 == -1) {
                var ei: u32 = 0;
                while (battle.g_battle.max_enemy_index >= 0 and ei <= @as(u32, @intCast(battle.g_battle.max_enemy_index))) : (ei += 1) {
                    const e2 = &battle.g_battle.enemies[ei];
                    if (e2.object_id == 0) continue;
                    var def: i32 = e2.e.defense;
                    def += (@as(i32, e2.e.level) + 6) * 4;
                    var dmg = calcMagicDamage(@intCast(@as(u16, @intCast(@max(str_sum, 0)))), def, &e2.e.elem_resistance, e2.e.poison_resistance, 1, wObject);
                    if (dmg <= 0) dmg = 1;
                    const new_h: i32 = @as(i32, e2.e.health) - dmg;
                    e2.e.health = if (new_h < 0) 0 else @intCast(new_h);
                }
            } else {
                const e2 = &battle.g_battle.enemies[@intCast(sTarget0)];
                var def: i32 = e2.e.defense;
                def += (@as(i32, e2.e.level) + 6) * 4;
                var dmg = calcMagicDamage(@intCast(@as(u16, @intCast(@max(str_sum, 0)))), def, &e2.e.elem_resistance, e2.e.poison_resistance, 1, wObject);
                if (dmg <= 0) dmg = 1;
                const new_h: i32 = @as(i32, e2.e.health) - dmg;
                e2.e.health = if (new_h < 0) 0 else @intCast(new_h);
            }

            _ = displayStatChange();
            battleShowPostMagicAnim();
            battleDelay(5, 0, true);

            if (global.gpg.g.magics[wMagicNum].magic_type != global.MAGIC_TYPE_SUMMON) {
                postActionCheck(false);

                // Move all contributors back (6 frames, reverse interpolation).
                var ib: i32 = 1;
                while (ib <= 6) : (ib += 1) {
                    var x: i32 = @as(i32, global.palX(p.pos_original)) * ib;
                    var y: i32 = @as(i32, global.palY(p.pos_original)) * ib;
                    x += rgwCoopPos[0][0] * (6 - ib);
                    y += rgwCoopPos[0][1] * (6 - ib);
                    x = @divTrunc(x, 6);
                    y = @divTrunc(y, 6);
                    p.pos = global.palXY(@truncate(x), @truncate(y));

                    var t: u32 = 0;
                    var j: u32 = 0;
                    while (j <= global.gpg.max_party_member_index) : (j += 1) {
                        if (battle.g_battle.coop_contributors[j] == 0) continue;
                        battle.g_battle.players[j].current_frame = 0;
                        if (j == player_index) continue;
                        t += 1;
                        if (t >= rgwCoopPos.len) break;

                        const op = battle.g_battle.players[j].pos_original;
                        var jx: i32 = @as(i32, global.palX(op)) * ib;
                        var jy: i32 = @as(i32, global.palY(op)) * ib;
                        jx += rgwCoopPos[t][0] * (6 - ib);
                        jy += rgwCoopPos[t][1] * (6 - ib);
                        jx = @divTrunc(jx, 6);
                        jy = @divTrunc(jy, 6);
                        battle.g_battle.players[j].pos = global.palXY(@truncate(jx), @truncate(jy));
                    }
                    battleDelay(1, 0, true);
                }
            }
        },
    }

    p.state = .wait;
    p.action.action_type = .pass;
    postActionCheck(false);

    // fight.c L4424: restore the originally-typed target so a follow-up
    // repeat-action sees what the player asked for, not what validateAction
    // re-pointed at.
    p.action.target = orig_target;
}

fn getFleeRateAvg() i32 {
    var sum: u32 = 0;
    var n: u32 = 0;
    var i: u32 = 0;
    while (i <= global.gpg.max_party_member_index) : (i += 1) {
        const role = global.gpg.party[i].player_role;
        if (global.gpg.g.player_roles.hp[role] == 0) continue;
        sum +%= global.getPlayerFleeRate(role);
        n += 1;
    }
    if (n == 0) return 0;
    return @intCast(sum / n);
}

// Pick a target for an enemy attack — random alive party member.
fn enemySelectTarget() i32 {
    var alive: [global.MAX_PLAYERS_IN_PARTY]u32 = undefined;
    var n: u32 = 0;
    var i: u32 = 0;
    while (i <= global.gpg.max_party_member_index) : (i += 1) {
        if (global.gpg.g.player_roles.hp[global.gpg.party[i].player_role] > 0) {
            alive[n] = i;
            n += 1;
        }
    }
    if (n == 0) return 0;
    return @intCast(alive[@intCast(util.randomLong(0, @intCast(n - 1)))]);
}

// PAL_BattleEnemyPerformAction — fight.c L4551. Full SDLPAL port:
// sleep/paralyzed/hiding pre-check, confused (attack other enemy),
// magic branch, fall-through to physical attack with cover/auto-defend.
pub fn enemyPerformAction(enemy_index: u32) void {
    const e = &battle.g_battle.enemies[enemy_index];

    backupStat();
    battle.g_battle.blow = 0;

    var sTarget: i32 = enemySelectTarget();
    var wPlayerRole = global.gpg.party[@intCast(sTarget)].player_role;
    const wMagic: u16 = e.e.magic;

    if (e.status[global.STATUS_SLEEP] > 0 or
        e.status[global.STATUS_PARALYZED] > 0 or
        battle.g_battle.hiding_time > 0)
    {
        // Do nothing.
        return;
    } else if (e.status[global.STATUS_CONFUSED] > 0) {
        // Confused: wander toward another enemy and hit it (L4593-L4654).
        const iTarget = enemySelectEnemyTarget(enemy_index);
        if (iTarget == @as(i32, @intCast(enemy_index))) return;
        const it: u32 = @intCast(iTarget);
        const iX: i32 = global.palX(battle.g_battle.enemies[it].pos);
        const iY: i32 = global.palY(battle.g_battle.enemies[it].pos);
        var i: u32 = 0;
        while (i < 3) : (i += 1) {
            var x: i32 = global.palX(e.pos);
            var y: i32 = global.palY(e.pos);
            x = @divTrunc(x + iX, 2);
            y = @divTrunc(y + iY, 2);
            e.pos = global.palXY(@truncate(x), @truncate(y));
            battleDelay(1, 0, true);
        }

        // Effect frames 9..11 above the target.
        var dw_time = util.getTicks() + global.BATTLE_FRAME_TIME;
        const tgt_target_y: i32 = global.palY(battle.g_battle.enemies[it].pos);
        const xx: i32 = @divTrunc(global.palX(e.pos) + global.palX(battle.g_battle.enemies[it].pos), 2);
        var yy: i32 = tgt_target_y;
        if (battle.g_battle.enemies[it].sprite) |sp| {
            const f0 = palcommon.spriteGetFrame(sp, 0);
            if (f0) |b0| yy -= @divTrunc(palcommon.rleGetHeight(b0), 3);
        }
        yy += 10;
        i = 9;
        while (i < 12) : (i += 1) {
            const eff_sprite = battle.g_battle.effect_sprite orelse break;
            const b = palcommon.spriteGetFrame(eff_sprite, @intCast(i)) orelse break;
            while (util.getTicks() < dw_time) {
                input.processEvent();
                std.Thread.yield() catch {};
                if (util.shouldQuit()) return;
            }
            dw_time = util.getTicks() + global.BATTLE_FRAME_TIME;

            battle.battleMakeScene();
            @memcpy(&video.screen_pixels, &battle.g_battle.scene_buf_pixels);
            const w_b: i32 = palcommon.rleGetWidth(b);
            const h_b: i32 = palcommon.rleGetHeight(b);
            _ = palcommon.rleBlitToSurface(b, &video.screen, global.palXY(@truncate(xx - @divTrunc(w_b, 2)), @truncate(yy - h_b)));
            @import("battleui.zig").update();
            video.updateScreen(null);
        }

        var str_c: i32 = @as(i16, @bitCast(e.e.attack_strength));
        str_c += (@as(i32, e.e.level) + 6) * 6;
        var def_c: i32 = @as(i16, @bitCast(battle.g_battle.enemies[it].e.defense));
        def_c += (@as(i32, battle.g_battle.enemies[it].e.level) + 6) * 4;
        const phys_res: u16 = @max(battle.g_battle.enemies[it].e.physical_resistance, 1);
        var sDmg: i32 = @divTrunc(calcBaseDamage(str_c, def_c) * 2, @as(i32, phys_res));
        if (sDmg <= 0) sDmg = 1;
        const cur_h: i32 = battle.g_battle.enemies[it].e.health;
        const new_h: i32 = cur_h - sDmg;
        battle.g_battle.enemies[it].e.health = if (new_h < 0) 0 else @intCast(new_h);

        _ = displayStatChange();
        battleShowPostMagicAnim();
        battleDelay(5, 0, true);

        e.pos = e.pos_original;
        battleDelay(2, 0, true);

        postActionCheck(false);
        return;
    } else if (wMagic != 0 and
        util.randomLong(0, 9) < @as(i32, e.e.magic_rate) and
        e.status[global.STATUS_SILENCE] == 0)
    {
        // Magical attack (L4656-L4909).
        if (wMagic == 0xFFFF) return;
        enemyPerformMagicAction(enemy_index, wMagic, &sTarget, &wPlayerRole);
        return;
    }

    // -- Physical attack path (L4910 onward). --
    const wFrameBak: u16 = battle.g_battle.players[@intCast(sTarget)].current_frame;

    var str: i32 = @as(i16, @bitCast(e.e.attack_strength));
    str += (@as(i32, e.e.level) + 6) * 6;
    if (str < 0) str = 0;
    var def: i32 = global.getPlayerDefense(wPlayerRole);
    if (battle.g_battle.players[@intCast(sTarget)].defending) def *= 2;

    var iCoverIndex: i32 = -1;
    var fAutoDefend: bool = util.randomLong(0, 16) >= 10;

    // Cover logic (L4940-L4969).
    if ((isPlayerDying(wPlayerRole) or
        global.gpg.player_status[wPlayerRole][global.STATUS_CONFUSED] > 0 or
        global.gpg.player_status[wPlayerRole][global.STATUS_SLEEP] > 0 or
        global.gpg.player_status[wPlayerRole][global.STATUS_PARALYZED] > 0) and fAutoDefend)
    {
        const cover_role = global.gpg.g.player_roles.covered_by[wPlayerRole];
        var ci: u32 = 0;
        while (ci <= global.gpg.max_party_member_index) : (ci += 1) {
            if (global.gpg.party[ci].player_role == cover_role) {
                iCoverIndex = @intCast(ci);
                break;
            }
        }
        if (iCoverIndex != -1) {
            const cr = global.gpg.party[@intCast(iCoverIndex)].player_role;
            if (isPlayerDying(cr) or
                global.gpg.player_status[cr][global.STATUS_CONFUSED] > 0 or
                global.gpg.player_status[cr][global.STATUS_SLEEP] > 0 or
                global.gpg.player_status[cr][global.STATUS_PARALYZED] > 0)
            {
                iCoverIndex = -1;
            }
        }
    }

    if (iCoverIndex == -1 and
        (global.gpg.player_status[wPlayerRole][global.STATUS_CONFUSED] > 0 or
            global.gpg.player_status[wPlayerRole][global.STATUS_SLEEP] > 0 or
            global.gpg.player_status[wPlayerRole][global.STATUS_PARALYZED] > 0))
    {
        fAutoDefend = false;
    }

    // fight.c L4934 — enemy attack voice (cue precedes the windup frames).
    @import("audio.zig").playSound(@as(i32, e.e.attack_sound));

    // Idle/magic frames before the attack (L4987-L4992).
    {
        var ii: u32 = 0;
        while (ii < e.e.magic_frames) : (ii += 1) {
            e.current_frame = e.e.idle_frames + @as(u16, @intCast(ii));
            battleDelay(2, 0, false);
        }
    }
    // Step toward target (L4994-L5000).
    {
        var ii: i32 = 0;
        while (ii < 3 - @as(i32, e.e.magic_frames)) : (ii += 1) {
            const xx: i32 = global.palX(e.pos) - 2;
            const yy: i32 = global.palY(e.pos) - 1;
            e.pos = global.palXY(@truncate(xx), @truncate(yy));
            battleDelay(1, 0, false);
        }
    }
    // fight.c L5003 — charge / footstep cue.
    @import("audio.zig").playSound(@as(i32, e.e.action_sound));
    battleDelay(1, 0, false);

    const ex: i32 = global.palX(battle.g_battle.players[@intCast(sTarget)].pos) - 44;
    const ey: i32 = global.palY(battle.g_battle.players[@intCast(sTarget)].pos) - 16;

    // fight.c L5010: hit/cover sound is decided up front; falls back to the
    // enemy's wCallSound, overridden by the cover/defending player's
    // rgwCoverSound when applicable.
    var iSound: i32 = @as(i32, e.e.call_sound);
    if (iCoverIndex != -1) {
        const cover_role = global.gpg.party[@intCast(iCoverIndex)].player_role;
        iSound = @as(i32, global.gpg.g.player_roles.cover_sound[cover_role]);
        battle.g_battle.players[@intCast(iCoverIndex)].current_frame = 3;
        const cx: i32 = global.palX(battle.g_battle.players[@intCast(sTarget)].pos) - 24;
        const cy: i32 = global.palY(battle.g_battle.players[@intCast(sTarget)].pos) - 12;
        battle.g_battle.players[@intCast(iCoverIndex)].pos = global.palXY(@truncate(cx), @truncate(cy));
    } else if (fAutoDefend) {
        battle.g_battle.players[@intCast(sTarget)].current_frame = 3;
        iSound = @as(i32, global.gpg.g.player_roles.cover_sound[wPlayerRole]);
    }

    // Attack frames at ex/ey (L5029-L5050).
    if (e.e.attack_frames == 0) {
        e.current_frame = e.e.idle_frames - 1;
        e.pos = global.palXY(@truncate(ex), @truncate(ey));
        battleDelay(2, 0, false);
    } else {
        var ii: i32 = 0;
        while (ii <= @as(i32, e.e.attack_frames)) : (ii += 1) {
            const frame_i: i32 = @as(i32, e.e.idle_frames) + @as(i32, e.e.magic_frames) + ii - 1;
            e.current_frame = if (frame_i < 0) 0 else @intCast(frame_i);
            e.pos = global.palXY(@truncate(ex), @truncate(ey));
            battleDelay(@max(e.e.act_wait_frames, 1), 0, false);
        }
    }

    // Damage (L5052-L5081). SDLPAL: when fAutoDefend is true AND there's no
    // cover, damage block is skipped entirely (full evasion). When there IS
    // cover, the cover takes damage divided by 2 (the only place /2 happens).
    if (!fAutoDefend) {
        battle.g_battle.players[@intCast(sTarget)].current_frame = 4;

        var sDamage = calcPhysicalAttackDamage(str + util.randomLong(0, 2), def, 2);
        sDamage += util.randomLong(0, 1);

        if (iCoverIndex != -1) sDamage = @divTrunc(sDamage, 2);
        if (global.gpg.player_status[wPlayerRole][global.STATUS_PROTECT] > 0) sDamage = @divTrunc(sDamage, 2);
        if (sDamage <= 0) sDamage = 1;

        const target_role: u16 = if (iCoverIndex != -1)
            global.gpg.party[@intCast(iCoverIndex)].player_role
        else
            wPlayerRole;
        const cur_hp: i32 = global.gpg.g.player_roles.hp[target_role];
        if (cur_hp < sDamage) sDamage = cur_hp;
        global.gpg.g.player_roles.hp[target_role] = @intCast(cur_hp - sDamage);

        _ = displayStatChange();
        if (iCoverIndex != -1) {
            battle.g_battle.players[@intCast(iCoverIndex)].color_shift = 6;
        } else {
            battle.g_battle.players[@intCast(sTarget)].color_shift = 6;
        }
    }
    // fight.c L5084 — hit/cover/dodge sound (the iSound chosen up at L5010).
    @import("audio.zig").playSound(iSound);
    battleDelay(1, 0, false);
    if (iCoverIndex != -1) battle.g_battle.players[@intCast(iCoverIndex)].color_shift = 0;
    battle.g_battle.players[@intCast(sTarget)].color_shift = 0;

    // Knockback (L5090-L5104). With cover: enemy slides back -10/-8 + cover
    // slides +4/+2; without cover: target itself slides +8/+4.
    if (iCoverIndex != -1) {
        const e_kx: i32 = global.palX(e.pos);
        const e_ky: i32 = global.palY(e.pos);
        e.pos = global.palXY(@truncate(e_kx - 10), @truncate(e_ky - 8));
        const cx: i32 = global.palX(battle.g_battle.players[@intCast(iCoverIndex)].pos);
        const cy: i32 = global.palY(battle.g_battle.players[@intCast(iCoverIndex)].pos);
        battle.g_battle.players[@intCast(iCoverIndex)].pos = global.palXY(@truncate(cx + 4), @truncate(cy + 2));
    } else {
        const tx0: i32 = global.palX(battle.g_battle.players[@intCast(sTarget)].pos);
        const ty0: i32 = global.palY(battle.g_battle.players[@intCast(sTarget)].pos);
        battle.g_battle.players[@intCast(sTarget)].pos = global.palXY(@truncate(tx0 + 8), @truncate(ty0 + 4));
    }
    battleDelay(1, 0, false);

    // Pick the post-frame for the inflictor (sTarget — fight.c L5108-5116
    // checks wPlayerRole, not the cover).
    var wPostFrame: u16 = wFrameBak;
    if (global.gpg.g.player_roles.hp[wPlayerRole] == 0) {
        // fight.c L5110 — death cry on KO.
        @import("audio.zig").playSound(@as(i32, global.gpg.g.player_roles.death_sound[wPlayerRole]));
        wPostFrame = 2;
    } else if (isPlayerDying(wPlayerRole)) {
        wPostFrame = 1;
    }

    // Slight settle for the inflictor (only when no cover).
    if (iCoverIndex == -1) {
        const tx1: i32 = global.palX(battle.g_battle.players[@intCast(sTarget)].pos);
        const ty1: i32 = global.palY(battle.g_battle.players[@intCast(sTarget)].pos);
        battle.g_battle.players[@intCast(sTarget)].pos = global.palXY(@truncate(tx1 + 2), @truncate(ty1 + 1));
    }
    battleDelay(3, 0, false);

    // Enemy retreats (L5127-L5130).
    e.pos = e.pos_original;
    e.current_frame = 0;
    battleDelay(1, 0, false);

    // Show the resting frame for the hit player (L5132-L5135).
    battle.g_battle.players[@intCast(sTarget)].current_frame = wPostFrame;
    battleDelay(1, 0, true);
    battleDelay(4, 0, true);

    updateFighters();

    // L5139-L5146: when no cover and not auto-defending, the enemy may
    // inflict an attached wAttackEquivItem (poison, petrify, etc.) gated by
    // wAttackEquivItemRate vs the target's poison resistance.
    if (iCoverIndex == -1 and !fAutoDefend and
        @as(i32, e.e.attack_equiv_item_rate) >= util.randomLong(1, 10) and
        @as(i32, global.getPlayerPoisonResistance(wPlayerRole)) < util.randomLong(1, 100))
    {
        const obj_id = e.e.attack_equiv_item;
        const new_use = script.runTriggerScript(global.gpg.g.objects[obj_id].item().script_on_use, wPlayerRole);
        global.gpg.g.objects[obj_id].data[2] = new_use; // OBJECT_ITEM.script_on_use
    }

    postActionCheck(true);
}

// PAL_BattleEnemySelectEnemyTargetIndex — used by the confused branch.
fn enemySelectEnemyTarget(self_index: u32) i32 {
    var alive: [global.MAX_ENEMIES_IN_TEAM]u32 = undefined;
    var n: u32 = 0;
    var i: u32 = 0;
    while (battle.g_battle.max_enemy_index >= 0 and i <= @as(u32, @intCast(battle.g_battle.max_enemy_index))) : (i += 1) {
        if (i == self_index) continue;
        if (battle.g_battle.enemies[i].object_id == 0) continue;
        alive[n] = i;
        n += 1;
    }
    if (n == 0) return @intCast(self_index);
    return @intCast(alive[@intCast(util.randomLong(0, @intCast(n - 1)))]);
}

// fight.c L4656-L4909: enemy magical attack.
fn enemyPerformMagicAction(enemy_index: u32, wMagic: u16, sTargetPtr: *i32, wPlayerRolePtr: *u16) void {
    const e = &battle.g_battle.enemies[enemy_index];
    const wMagicNum: u32 = global.gpg.g.objects[wMagic].magic().magic_number;

    var str: i32 = @as(i16, @bitCast(e.e.magic_strength));
    str += (@as(i32, e.e.level) + 6) * 6;
    if (str < 0) str = 0;

    // Step forward (L4680-L4693).
    {
        var ex: i32 = global.palX(e.pos);
        var ey: i32 = global.palY(e.pos);
        ex += 12;
        ey += 6;
        e.pos = global.palXY(@truncate(ex), @truncate(ey));
        battleDelay(1, 0, false);
        ex += 4;
        ey += 2;
        e.pos = global.palXY(@truncate(ex), @truncate(ey));
        battleDelay(1, 0, false);
    }

    // fight.c L4695 — incantation cue right before the casting frames.
    @import("audio.zig").playSound(@as(i32, e.e.magic_sound));

    // Casting frames (L4697-L4707).
    {
        var i: u32 = 0;
        while (i < e.e.magic_frames) : (i += 1) {
            e.current_frame = e.e.idle_frames + @as(u16, @intCast(i));
            battleDelay(@max(e.e.act_wait_frames, 1), 0, false);
        }
        if (e.e.magic_frames == 0) {
            battleDelay(1, 0, false);
        }
    }

    // If fire_delay is 0, also play attack frames now (L4709-L4717).
    if (global.gpg.g.magics[wMagicNum].fire_delay == 0) {
        var ai: i32 = 0;
        while (ai <= @as(i32, e.e.attack_frames)) : (ai += 1) {
            const frame_i: i32 = ai - 1 + @as(i32, e.e.idle_frames) + @as(i32, e.e.magic_frames);
            e.current_frame = if (frame_i < 0) 0 else @intCast(frame_i);
            battleDelay(@max(e.e.act_wait_frames, 1), 0, false);
        }
    }

    // Auto-defend (L4719-L4757).
    var rgfMagAutoDefend = [_]bool{false} ** global.MAX_PLAYERS_IN_PARTY;
    var fAutoDefend: bool = false;

    if (global.gpg.g.magics[wMagicNum].magic_type != global.MAGIC_TYPE_NORMAL) {
        sTargetPtr.* = -1;

        var i: u32 = 0;
        while (i <= global.gpg.max_party_member_index) : (i += 1) {
            const w = global.gpg.party[i].player_role;
            if (global.gpg.player_status[w][global.STATUS_SLEEP] == 0 and
                global.gpg.player_status[w][global.STATUS_PARALYZED] == 0 and
                global.gpg.player_status[w][global.STATUS_CONFUSED] == 0 and
                util.randomLong(0, 2) == 0 and
                global.gpg.g.player_roles.hp[w] != 0)
            {
                rgfMagAutoDefend[i] = true;
                battle.g_battle.players[i].current_frame = 3;
            } else {
                rgfMagAutoDefend[i] = false;
            }
        }
    } else if (global.gpg.player_status[wPlayerRolePtr.*][global.STATUS_SLEEP] == 0 and
        global.gpg.player_status[wPlayerRolePtr.*][global.STATUS_PARALYZED] == 0 and
        global.gpg.player_status[wPlayerRolePtr.*][global.STATUS_CONFUSED] == 0 and
        util.randomLong(0, 2) == 0)
    {
        fAutoDefend = true;
        battle.g_battle.players[@intCast(sTargetPtr.*)].current_frame = 3;
    }

    // Run script_on_use → enemy magic anim → script_on_success.
    const new_use = script.runTriggerScript(global.gpg.g.objects[wMagic].magic().script_on_use, wPlayerRolePtr.*);
    global.gpg.g.objects[wMagic].data[3] = new_use;

    if (script.g_script_success) {
        battleShowEnemyMagicAnim(@intCast(enemy_index), wMagic, sTargetPtr.*);
        const new_succ = script.runTriggerScript(global.gpg.g.objects[wMagic].magic().script_on_success, wPlayerRolePtr.*);
        global.gpg.g.objects[wMagic].data[2] = new_succ;
    }

    // Damage (L4772-L4854).
    if (@as(i16, @bitCast(global.gpg.g.magics[wMagicNum].base_damage)) > 0) {
        if (sTargetPtr.* == -1) {
            // Damage all alive players.
            var i: u32 = 0;
            while (i <= global.gpg.max_party_member_index) : (i += 1) {
                const w = global.gpg.party[i].player_role;
                if (global.gpg.g.player_roles.hp[w] == 0) continue;

                const def_v: u16 = global.getPlayerDefense(w);
                var rgwElem: [global.NUM_MAGIC_ELEMENTAL]u16 align(1) = undefined;
                var x: u32 = 0;
                while (x < global.NUM_MAGIC_ELEMENTAL) : (x += 1) {
                    rgwElem[x] = 100 + global.getPlayerElementalResistance(w, x);
                }
                const poison_res: u16 = 100 + global.getPlayerPoisonResistance(w);
                var sDamage = calcMagicDamage(@intCast(str), def_v, &rgwElem, poison_res, 20, wMagic);

                var div: i32 = 1;
                if (battle.g_battle.players[i].defending) div *= 2;
                if (global.gpg.player_status[w][global.STATUS_PROTECT] > 0) div *= 2;
                if (rgfMagAutoDefend[i]) div += 1;
                sDamage = @divTrunc(sDamage, div);

                const cur_hp: i32 = global.gpg.g.player_roles.hp[w];
                if (sDamage > cur_hp) sDamage = cur_hp;
                if (sDamage < 0) sDamage = 0;
                global.gpg.g.player_roles.hp[w] = @intCast(cur_hp - sDamage);
            }
        } else {
            // Damage one player.
            const w = wPlayerRolePtr.*;
            const def_v: u16 = global.getPlayerDefense(w);
            var rgwElem: [global.NUM_MAGIC_ELEMENTAL]u16 align(1) = undefined;
            var x: u32 = 0;
            while (x < global.NUM_MAGIC_ELEMENTAL) : (x += 1) {
                rgwElem[x] = 100 + global.getPlayerElementalResistance(w, x);
            }
            const poison_res: u16 = 100 + global.getPlayerPoisonResistance(w);
            var sDamage = calcMagicDamage(@intCast(str), def_v, &rgwElem, poison_res, 20, wMagic);

            var div: i32 = 1;
            if (battle.g_battle.players[@intCast(sTargetPtr.*)].defending) div *= 2;
            if (global.gpg.player_status[w][global.STATUS_PROTECT] > 0) div *= 2;
            if (fAutoDefend) div += 1;
            sDamage = @divTrunc(sDamage, div);

            const cur_hp: i32 = global.gpg.g.player_roles.hp[w];
            if (sDamage > cur_hp) sDamage = cur_hp;
            if (sDamage < 0) sDamage = 0;
            global.gpg.g.player_roles.hp[w] = @intCast(cur_hp - sDamage);
        }
    }

    _ = displayStatChange();

    // Hit-react flash for affected players (L4861-L4899).
    {
        var i: u32 = 0;
        while (i < 5) : (i += 1) {
            if (sTargetPtr.* == -1) {
                var x: u32 = 0;
                while (x <= global.gpg.max_party_member_index) : (x += 1) {
                    const w = global.gpg.party[x].player_role;
                    if (battle.g_battle.players[x].prev_hp == global.gpg.g.player_roles.hp[w]) continue;
                    battle.g_battle.players[x].current_frame = 4;
                    if (i > 0) {
                        const tx: i32 = global.palX(battle.g_battle.players[x].pos) + (@as(i32, 8) >> @as(u5, @intCast(i)));
                        const ty: i32 = global.palY(battle.g_battle.players[x].pos) + (@as(i32, 4) >> @as(u5, @intCast(i)));
                        battle.g_battle.players[x].pos = global.palXY(@truncate(tx), @truncate(ty));
                    }
                    battle.g_battle.players[x].color_shift = if (i < 3) 6 else 0;
                }
            } else {
                const ti: u32 = @intCast(sTargetPtr.*);
                battle.g_battle.players[ti].current_frame = 4;
                if (i > 0) {
                    const tx: i32 = global.palX(battle.g_battle.players[ti].pos) + (@as(i32, 8) >> @as(u5, @intCast(i)));
                    const ty: i32 = global.palY(battle.g_battle.players[ti].pos) + (@as(i32, 4) >> @as(u5, @intCast(i)));
                    battle.g_battle.players[ti].pos = global.palXY(@truncate(tx), @truncate(ty));
                }
                battle.g_battle.players[ti].color_shift = if (i < 3) 6 else 0;
            }
            battleDelay(1, 0, false);
        }
    }

    e.current_frame = 0;
    e.pos = e.pos_original;

    battleDelay(1, 0, false);
    updateFighters();

    postActionCheck(true);
    battleDelay(8, 0, true);
}

// PAL_BattlePlayerEscape — slide all alive players off-screen.
pub fn playerEscape() void {
    @import("audio.zig").playSound(45);
    updateFighters();

    var i: u32 = 0;
    while (i <= global.gpg.max_party_member_index) : (i += 1) {
        const role = global.gpg.party[i].player_role;
        if (global.gpg.g.player_roles.hp[role] > 0) {
            battle.g_battle.players[i].current_frame = 0;
        }
    }

    var step: u32 = 0;
    while (step < 16) : (step += 1) {
        var j: u32 = 0;
        while (j <= global.gpg.max_party_member_index) : (j += 1) {
            const role = global.gpg.party[j].player_role;
            if (global.gpg.g.player_roles.hp[role] == 0) continue;

            const px: i32 = global.palX(battle.g_battle.players[j].pos);
            const py: i32 = global.palY(battle.g_battle.players[j].pos);

            // Per-slot drift offsets (battle.c L1484-L1510). Slot 0 has a
            // fall-through to slot 1's offset when only one player is present.
            var dx: i32 = 0;
            var dy: i32 = 0;
            switch (j) {
                0 => {
                    if (global.gpg.max_party_member_index > 0) {
                        dx = 4;
                        dy = 6;
                    } else {
                        dx = 4;
                        dy = 4;
                    }
                },
                1 => {
                    dx = 4;
                    dy = 4;
                },
                2 => {
                    dx = 6;
                    dy = 3;
                },
                // 魔改 — 4th party slot mirrors slot 2's drift.
                3 => {
                    dx = 6;
                    dy = 3;
                },
                else => unreachable,
            }
            battle.g_battle.players[j].pos = global.palXY(@truncate(px + dx), @truncate(py + dy));
        }
        battleDelay(1, 0, false);
    }

    // Move everyone off-screen so the final frame is empty.
    i = 0;
    while (i <= global.gpg.max_party_member_index) : (i += 1) {
        battle.g_battle.players[i].pos = global.palXY(@as(i16, @bitCast(@as(u16, 9999))), @as(i16, @bitCast(@as(u16, 9999))));
    }
    battleDelay(1, 0, false);
    battle.g_battle.result = .fleed;
}

// Per-frame loop body for the magic animations: PAL_BattleMakeScene +
// VIDEO_CopyEntireSurface(g_Battle.lpSceneBuf, gpScreen) + PAL_BattleUIUpdate
// + VIDEO_UpdateScreen — same render path as PAL_BattleDelay but without the
// gesture tick (fight.c L2827-2832 / L3052-3057). The magic sprite added via
// PAL_BattleAddSpriteObject is consumed by the next makeScene call.
fn battleFrameMagic() void {
    battle.battleMakeScene();
    @memcpy(&video.screen_pixels, &battle.g_battle.scene_buf_pixels);
    @import("battleui.zig").update();
    video.updateScreen(null);
}

// PAL_BattleShowPlayerOffMagicAnim — fight.c L2609. Plays the offensive
// magic animation. fSummon=true skips the per-frame sound and the player
// gesture flip (because the summoned god owns the screen).
pub fn battleShowPlayerOffMagicAnim(player_index: u16, object_id: u16, sTarget: i32, fSummon: bool) void {
    _ = fSummon;

    const fire = global.gpg.f.fire orelse return;

    const iMagicNum: u32 = global.gpg.g.objects[object_id].magic().magic_number;
    const iEffectNum: u32 = global.gpg.g.magics[iMagicNum].effect;

    // 魔改 — read render_mode once. Reverse flag flips frame index within
    // the active span; Mirror (general or HERO_OFF specific) sets the
    // global flag drawMagicSprite reads; TripleParallel swaps the
    // ATTACK_ALL effect-position table for a tighter staggered triple.
    const render_mode: u16 = global.gpg.g.magics[iMagicNum].render_mode;
    const reverse: bool = (render_mode & (global.MAGIC_RENDER_REVERSE | global.MAGIC_RENDER_REVERSE_HERO_OFF)) != 0;
    const mirror: bool = (render_mode & (global.MAGIC_RENDER_MIRROR | global.MAGIC_RENDER_MIRROR_HERO_OFF)) != 0;
    const triple_parallel: bool = (render_mode & global.MAGIC_RENDER_TRIPLE_PARALLEL) != 0;
    battle.g_battle.magic_render_mirror = mirror;
    battle.g_battle.magic_mono_color = @truncate(render_mode >> 8);

    // PAL_MKFGetDecompressedSize → if <= 0, return.
    const decomp_size = fire.getDecompressedSize(iEffectNum, false) catch return;
    if (decomp_size == 0) return;

    const lpSpriteEffect = global.allocator.alloc(u8, decomp_size) catch return;
    defer global.allocator.free(lpSpriteEffect);
    {
        const compressed = fire.getChunkData(iEffectNum) catch return;
        _ = @import("yj1.zig").decompress(compressed, lpSpriteEffect) catch return;
    }

    const n: i32 = palcommon.spriteGetNumFrames(lpSpriteEffect);

    battleDelay(1, 0, true);

    const fire_delay: i32 = global.gpg.g.magics[iMagicNum].fire_delay;
    const effect_times: i32 = @as(i16, @bitCast(global.gpg.g.magics[iMagicNum].effect_times));
    const shake: i32 = global.gpg.g.magics[iMagicNum].shake;

    var l: i32 = n - fire_delay;
    l *= effect_times;
    l += n;
    l += shake;

    const wave_save: u16 = global.gpg.screen_wave;
    global.gpg.screen_wave +%= global.gpg.g.magics[iMagicNum].wave;

    const speed: i32 = @as(i16, @bitCast(@as(u16, @bitCast(global.gpg.g.magics[iMagicNum].speed))));
    const frame_ms: u32 = @intCast(@max((speed + 5) * 10, 10));

    var dw_time: u32 = util.getTicks() + frame_ms;
    var i: i32 = 0;
    while (i < l) : (i += 1) {
        if (i == fire_delay and player_index != 0xFFFF) {
            battle.g_battle.players[player_index].current_frame = 6;
            // fight.c L2501 — magic sound at the fire-delay frame.
            @import("audio.zig").playSound(@as(i32, global.gpg.g.magics[iMagicNum].sound));
        }

        // Random "blow" jitter applied to all enemy positions.
        const blow: i32 = if (battle.g_battle.blow > 0)
            util.randomLong(0, battle.g_battle.blow)
        else
            util.randomLong(battle.g_battle.blow, 0);
        var k: u32 = 0;
        while (battle.g_battle.max_enemy_index >= 0 and k <= @as(u32, @intCast(battle.g_battle.max_enemy_index))) : (k += 1) {
            if (battle.g_battle.enemies[k].object_id == 0) continue;
            const x: i32 = @as(i32, global.palX(battle.g_battle.enemies[k].pos)) + blow;
            const y: i32 = @as(i32, global.palY(battle.g_battle.enemies[k].pos)) + @divTrunc(blow, 2);
            battle.g_battle.enemies[k].pos = global.palXY(@truncate(x), @truncate(y));
        }

        // Pick the effect frame for this tick.
        var fk: i32 = 0;
        if (l - i > shake) {
            if (i < n) {
                fk = i;
            } else {
                fk = i - fire_delay;
                fk = @mod(fk, n - fire_delay);
                fk += fire_delay;
            }
            // 魔改 — Reverse plays frames within the active span backwards.
            if (reverse) fk = n - 1 - fk;
            battle.g_battle.magic_bitmap = palcommon.spriteGetFrame(lpSpriteEffect, fk);
        } else {
            video.shakeScreen(@intCast(i), 3);
            fk = @mod(l - shake - 1, n);
            if (reverse) fk = n - 1 - fk;
            battle.g_battle.magic_bitmap = palcommon.spriteGetFrame(lpSpriteEffect, fk);
        }

        // Wait for this frame's tick.
        while (util.getTicks() < dw_time) {
            input.processEvent();
            std.Thread.yield() catch {};
            if (util.shouldQuit()) {
                battle.g_battle.magic_bitmap = null;
                battle.g_battle.magic_render_mirror = false;
    battle.g_battle.magic_mono_color = 0;
                battle.g_battle.magic_mono_color = 0;
                return;
            }
        }
        dw_time = util.getTicks() + frame_ms;

        const layer_off: i16 = @bitCast(global.gpg.g.magics[iMagicNum].specific);

        // Make space for new magic sprite objects this frame.
        battle.spriteAddUnlock();

        const m_type = global.gpg.g.magics[iMagicNum].magic_type;
        // fight.c L2757-L2820: when wKeepEffect == 0xFFFF AND screen_wave < 9,
        // blit the LAST frame of the magic sprite into the battle background
        // so the residue stays on the field after the spell finishes.
        const keep_effect: bool = (i == l - 1) and
            (global.gpg.screen_wave < 9) and
            (global.gpg.g.magics[iMagicNum].keep_effect == 0xFFFF);

        if (m_type == global.MAGIC_TYPE_NORMAL) {
            std.debug.assert(sTarget != -1);
            // 魔改 — when mirrored on the hero side, negate x_offset so the
            // flipped bitmap still leads from the caster toward the target.
            const x_off: i32 = blk: {
                const raw: i32 = @as(i16, @bitCast(global.gpg.g.magics[iMagicNum].x_offset));
                break :blk if (mirror) -raw else raw;
            };
            const tx: i32 = @as(i32, global.palX(battle.g_battle.enemies[@intCast(sTarget)].pos)) + x_off;
            const ty: i32 = @as(i32, global.palY(battle.g_battle.enemies[@intCast(sTarget)].pos)) +
                @as(i16, @bitCast(global.gpg.g.magics[iMagicNum].y_offset));
            battle.addSpriteObject(.magic, @intCast(iMagicNum), global.palXY(@truncate(tx), @truncate(ty)), layer_off, false);
            if (keep_effect) blitMagicResidueToBackground(lpSpriteEffect, fk, tx, ty);
        } else if (m_type == global.MAGIC_TYPE_ATTACK_ALL) {
            std.debug.assert(sTarget == -1);
            // 魔改 — TripleParallel uses a tighter staggered cluster.
            const effectpos: [3][2]i32 = if (triple_parallel)
                .{ .{ 70, 100 }, .{ 90, 120 }, .{ 110, 140 } }
            else
                .{ .{ 70, 140 }, .{ 100, 110 }, .{ 160, 100 } };
            for (effectpos) |p| {
                const raw_x: i32 = @as(i16, @bitCast(global.gpg.g.magics[iMagicNum].x_offset));
                const tx: i32 = p[0] + if (mirror) -raw_x else raw_x;
                const ty: i32 = p[1] + @as(i16, @bitCast(global.gpg.g.magics[iMagicNum].y_offset));
                battle.addSpriteObject(.magic, @intCast(iMagicNum), global.palXY(@truncate(tx), @truncate(ty)), layer_off, false);
                if (keep_effect) blitMagicResidueToBackground(lpSpriteEffect, fk, tx, ty);
            }
        } else if (m_type == global.MAGIC_TYPE_ATTACK_WHOLE or m_type == global.MAGIC_TYPE_ATTACK_FIELD) {
            std.debug.assert(sTarget == -1);
            const tx0: i32 = if (m_type == global.MAGIC_TYPE_ATTACK_WHOLE) 120 else 160;
            const ty0: i32 = if (m_type == global.MAGIC_TYPE_ATTACK_WHOLE) 100 else 200;
            const raw_x: i32 = @as(i16, @bitCast(global.gpg.g.magics[iMagicNum].x_offset));
            const tx: i32 = tx0 + if (mirror) -raw_x else raw_x;
            const ty: i32 = ty0 + @as(i16, @bitCast(global.gpg.g.magics[iMagicNum].y_offset));
            battle.addSpriteObject(.magic, @intCast(iMagicNum), global.palXY(@truncate(tx), @truncate(ty)), layer_off, false);
            if (keep_effect) blitMagicResidueToBackground(lpSpriteEffect, fk, tx, ty);
        } else {
            std.debug.assert(false);
        }

        battleFrameMagic();
    }

    global.gpg.screen_wave = wave_save;
    video.shakeScreen(0, 0);
    battle.g_battle.magic_bitmap = null;
    battle.g_battle.magic_render_mirror = false;
    battle.g_battle.magic_mono_color = 0;

    var k: u32 = 0;
    while (battle.g_battle.max_enemy_index >= 0 and k <= @as(u32, @intCast(battle.g_battle.max_enemy_index))) : (k += 1) {
        battle.g_battle.enemies[k].pos = battle.g_battle.enemies[k].pos_original;
    }
}

// fight.c L2757: blit the last magic frame onto the battle background so the
// residue (e.g. burnt grass, ice patches) persists for the rest of the fight.
fn blitMagicResidueToBackground(sprite_effect: []const u8, frame_idx: i32, x: i32, y: i32) void {
    const b = palcommon.spriteGetFrame(sprite_effect, frame_idx) orelse return;
    var bg_surface: palcommon.Surface = .{
        .w = video.SCREEN_WIDTH,
        .h = video.SCREEN_HEIGHT,
        .pitch = video.SCREEN_WIDTH,
        .pixels = &battle.g_battle.background_pixels,
    };
    const w: i32 = palcommon.rleGetWidth(b);
    const h: i32 = palcommon.rleGetHeight(b);
    const pos = global.palXY(@truncate(x - @divTrunc(w, 2)), @truncate(y - h));
    if (battle.g_battle.magic_render_mirror) {
        _ = palcommon.rleBlitToSurfaceInMirror(b, &bg_surface, pos);
    } else {
        _ = palcommon.rleBlitToSurface(b, &bg_surface, pos);
    }
}

// PAL_BattleShowEnemyMagicAnim — fight.c L2846. Same shape as the player
// version but the per-frame jitter applies to players, the sprite anchor
// table is for player slots, and the enemy itself plays its magic frames.
pub fn battleShowEnemyMagicAnim(enemy_index: u16, object_id: u16, sTarget: i32) void {
    const fire = global.gpg.f.fire orelse return;

    const iMagicNum: u32 = global.gpg.g.objects[object_id].magic().magic_number;
    const iEffectNum: u32 = global.gpg.g.magics[iMagicNum].effect;

    // 魔改 — same flag layout as the player offensive variant. The enemy
    // side honours the general MIRROR/REVERSE flags and the enemy-specific
    // variants.
    const render_mode: u16 = global.gpg.g.magics[iMagicNum].render_mode;
    const reverse: bool = (render_mode & (global.MAGIC_RENDER_REVERSE | global.MAGIC_RENDER_REVERSE_ENEMY_OFF)) != 0;
    const mirror: bool = (render_mode & (global.MAGIC_RENDER_MIRROR | global.MAGIC_RENDER_MIRROR_ENEMY_OFF)) != 0;
    battle.g_battle.magic_render_mirror = mirror;
    battle.g_battle.magic_mono_color = @truncate(render_mode >> 8);


    const decomp_size = fire.getDecompressedSize(iEffectNum, false) catch return;
    if (decomp_size == 0) return;

    const lpSpriteEffect = global.allocator.alloc(u8, decomp_size) catch return;
    defer global.allocator.free(lpSpriteEffect);
    {
        const compressed = fire.getChunkData(iEffectNum) catch return;
        _ = @import("yj1.zig").decompress(compressed, lpSpriteEffect) catch return;
    }

    const n: i32 = palcommon.spriteGetNumFrames(lpSpriteEffect);

    const fire_delay: i32 = global.gpg.g.magics[iMagicNum].fire_delay;
    const effect_times: i32 = @as(i16, @bitCast(global.gpg.g.magics[iMagicNum].effect_times));
    const shake: i32 = global.gpg.g.magics[iMagicNum].shake;

    var l: i32 = n - fire_delay;
    l *= effect_times;
    l += n;
    l += shake;

    const wave_save: u16 = global.gpg.screen_wave;
    global.gpg.screen_wave +%= global.gpg.g.magics[iMagicNum].wave;

    const speed: i32 = @as(i16, @bitCast(@as(u16, @bitCast(global.gpg.g.magics[iMagicNum].speed))));
    const frame_ms: u32 = @intCast(@max((speed + 5) * 10, 10));

    var dw_time: u32 = util.getTicks() + frame_ms;
    var i: i32 = 0;
    while (i < l) : (i += 1) {
        const blow: i32 = if (battle.g_battle.blow > 0)
            util.randomLong(0, battle.g_battle.blow)
        else
            util.randomLong(battle.g_battle.blow, 0);
        var k: u32 = 0;
        while (k <= global.gpg.max_party_member_index) : (k += 1) {
            const x: i32 = @as(i32, global.palX(battle.g_battle.players[k].pos)) + blow;
            const y: i32 = @as(i32, global.palY(battle.g_battle.players[k].pos)) + @divTrunc(blow, 2);
            battle.g_battle.players[k].pos = global.palXY(@truncate(x), @truncate(y));
        }

        var fk: i32 = 0;
        if (l - i > shake) {
            if (i < n) {
                fk = i;
            } else {
                fk = i - fire_delay;
                fk = @mod(fk, n - fire_delay);
                fk += fire_delay;
            }
            if (reverse) fk = n - 1 - fk;
            battle.g_battle.magic_bitmap = palcommon.spriteGetFrame(lpSpriteEffect, fk);

            // fight.c L2713 — re-trigger the magic SFX every time the effect
            // loop wraps back to fire_delay (the cue plays once per repeat).
            if (n != fire_delay and @mod(i - fire_delay, n) == 0) {
                @import("audio.zig").playSound(@as(i32, global.gpg.g.magics[iMagicNum].sound));
            }

            // While the casting frames play, switch the enemy gesture to its
            // attack pose (idle_frames + magic_frames + offset).
            if (fire_delay > 0 and i >= fire_delay and
                i < fire_delay + @as(i32, battle.g_battle.enemies[enemy_index].e.attack_frames))
            {
                battle.g_battle.enemies[enemy_index].current_frame =
                    @intCast(@as(u32, @intCast(i)) - @as(u32, @intCast(fire_delay)) +
                        battle.g_battle.enemies[enemy_index].e.idle_frames +
                        battle.g_battle.enemies[enemy_index].e.magic_frames);
            }
        } else {
            video.shakeScreen(@intCast(i), 3);
            fk = @mod(l - shake - 1, n);
            if (reverse) fk = n - 1 - fk;
            battle.g_battle.magic_bitmap = palcommon.spriteGetFrame(lpSpriteEffect, fk);
        }

        while (util.getTicks() < dw_time) {
            input.processEvent();
            std.Thread.yield() catch {};
            if (util.shouldQuit()) {
                battle.g_battle.magic_bitmap = null;
                battle.g_battle.magic_render_mirror = false;
    battle.g_battle.magic_mono_color = 0;
                battle.g_battle.magic_mono_color = 0;
                return;
            }
        }
        dw_time = util.getTicks() + frame_ms;

        const layer_off: i16 = @bitCast(global.gpg.g.magics[iMagicNum].specific);
        battle.spriteAddUnlock();

        const m_type = global.gpg.g.magics[iMagicNum].magic_type;
        const keep_effect: bool = (i == l - 1) and
            (global.gpg.screen_wave < 9) and
            (global.gpg.g.magics[iMagicNum].keep_effect == 0xFFFF);

        if (m_type == global.MAGIC_TYPE_NORMAL) {
            std.debug.assert(sTarget != -1);
            const x_off: i32 = blk: {
                const raw: i32 = @as(i16, @bitCast(global.gpg.g.magics[iMagicNum].x_offset));
                break :blk if (mirror) -raw else raw;
            };
            const tx: i32 = @as(i32, global.palX(battle.g_battle.players[@intCast(sTarget)].pos)) + x_off;
            const ty: i32 = @as(i32, global.palY(battle.g_battle.players[@intCast(sTarget)].pos)) +
                @as(i16, @bitCast(global.gpg.g.magics[iMagicNum].y_offset));
            battle.addSpriteObject(.magic, @intCast(iMagicNum), global.palXY(@truncate(tx), @truncate(ty)), layer_off, false);
            if (keep_effect) blitMagicResidueToBackground(lpSpriteEffect, fk, tx, ty);
        } else if (m_type == global.MAGIC_TYPE_ATTACK_ALL) {
            std.debug.assert(sTarget == -1);
            const effectpos = [_][2]i32{ .{ 180, 180 }, .{ 234, 170 }, .{ 270, 146 } };
            for (effectpos) |p| {
                const tx: i32 = p[0] + @as(i16, @bitCast(global.gpg.g.magics[iMagicNum].x_offset));
                const ty: i32 = p[1] + @as(i16, @bitCast(global.gpg.g.magics[iMagicNum].y_offset));
                battle.addSpriteObject(.magic, @intCast(iMagicNum), global.palXY(@truncate(tx), @truncate(ty)), layer_off, false);
                if (keep_effect) blitMagicResidueToBackground(lpSpriteEffect, fk, tx, ty);
            }
        } else if (m_type == global.MAGIC_TYPE_ATTACK_WHOLE or m_type == global.MAGIC_TYPE_ATTACK_FIELD) {
            std.debug.assert(sTarget == -1);
            const tx0: i32 = if (m_type == global.MAGIC_TYPE_ATTACK_WHOLE) 240 else 160;
            const ty0: i32 = if (m_type == global.MAGIC_TYPE_ATTACK_WHOLE) 150 else 200;
            const tx: i32 = tx0 + @as(i16, @bitCast(global.gpg.g.magics[iMagicNum].x_offset));
            const ty: i32 = ty0 + @as(i16, @bitCast(global.gpg.g.magics[iMagicNum].y_offset));
            battle.addSpriteObject(.magic, @intCast(iMagicNum), global.palXY(@truncate(tx), @truncate(ty)), layer_off, false);
            if (keep_effect) blitMagicResidueToBackground(lpSpriteEffect, fk, tx, ty);
        } else {
            std.debug.assert(false);
        }

        battleFrameMagic();
    }

    global.gpg.screen_wave = wave_save;
    video.shakeScreen(0, 0);
    battle.g_battle.magic_bitmap = null;
    battle.g_battle.magic_render_mirror = false;
    battle.g_battle.magic_mono_color = 0;

    var k: u32 = 0;
    while (k <= global.gpg.max_party_member_index) : (k += 1) {
        battle.g_battle.players[k].pos = battle.g_battle.players[k].pos_original;
    }
}

// PAL_BattleShowPlayerDefMagicAnim — fight.c L2447.
pub fn battleShowPlayerDefMagicAnim(player_index: u16, object_id: u16, sTarget: i32) void {
    const fire = global.gpg.f.fire orelse return;

    const iMagicNum: u32 = global.gpg.g.objects[object_id].magic().magic_number;
    const iEffectNum: u32 = global.gpg.g.magics[iMagicNum].effect;

    const decomp_size = fire.getDecompressedSize(iEffectNum, false) catch return;
    if (decomp_size == 0) return;

    const lpSpriteEffect = global.allocator.alloc(u8, decomp_size) catch return;
    defer global.allocator.free(lpSpriteEffect);
    {
        const compressed = fire.getChunkData(iEffectNum) catch return;
        _ = @import("yj1.zig").decompress(compressed, lpSpriteEffect) catch return;
    }
    const n: i32 = palcommon.spriteGetNumFrames(lpSpriteEffect);

    battle.g_battle.players[player_index].current_frame = 6;
    battleDelay(1, 0, true);

    const speed: i32 = @as(i16, @bitCast(@as(u16, @bitCast(global.gpg.g.magics[iMagicNum].speed))));
    const frame_ms: u32 = @intCast(@max((speed + 5) * 10, 10));

    // 魔改 — Reverse plays frames backwards. Mirror is intentionally not
    // honoured for defensive magic (the visual sits on the friendly target).
    const render_mode: u16 = global.gpg.g.magics[iMagicNum].render_mode;
    const reverse: bool = (render_mode & (global.MAGIC_RENDER_REVERSE | global.MAGIC_RENDER_REVERSE_HERO_OFF)) != 0;
    battle.g_battle.magic_mono_color = @truncate(render_mode >> 8);


    var dw_time: u32 = util.getTicks() + frame_ms;
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const fk: i32 = if (reverse) n - 1 - i else i;
        battle.g_battle.magic_bitmap = palcommon.spriteGetFrame(lpSpriteEffect, fk);

        // fight.c L2501 — play the magic cue once at fire_delay frame.
        if (i == @as(i32, global.gpg.g.magics[iMagicNum].fire_delay)) {
            @import("audio.zig").playSound(@as(i32, global.gpg.g.magics[iMagicNum].sound));
        }

        while (util.getTicks() < dw_time) {
            input.processEvent();
            std.Thread.yield() catch {};
            if (util.shouldQuit()) {
                battle.g_battle.magic_bitmap = null;
                return;
            }
        }
        dw_time = util.getTicks() + frame_ms;

        const layer_off: i16 = @bitCast(global.gpg.g.magics[iMagicNum].specific);
        battle.spriteAddUnlock();

        const m_type = global.gpg.g.magics[iMagicNum].magic_type;
        if (m_type == global.MAGIC_TYPE_APPLY_TO_PARTY) {
            std.debug.assert(sTarget == -1);
            var k: u32 = 0;
            while (k <= global.gpg.max_party_member_index) : (k += 1) {
                const tx: i32 = @as(i32, global.palX(battle.g_battle.players[k].pos)) +
                    @as(i16, @bitCast(global.gpg.g.magics[iMagicNum].x_offset));
                const ty: i32 = @as(i32, global.palY(battle.g_battle.players[k].pos)) +
                    @as(i16, @bitCast(global.gpg.g.magics[iMagicNum].y_offset));
                battle.addSpriteObject(.magic, @intCast(iMagicNum), global.palXY(@truncate(tx), @truncate(ty)), layer_off, false);
            }
        } else if (m_type == global.MAGIC_TYPE_APPLY_TO_PLAYER) {
            std.debug.assert(sTarget != -1);
            const tx: i32 = @as(i32, global.palX(battle.g_battle.players[@intCast(sTarget)].pos)) +
                @as(i16, @bitCast(global.gpg.g.magics[iMagicNum].x_offset));
            const ty: i32 = @as(i32, global.palY(battle.g_battle.players[@intCast(sTarget)].pos)) +
                @as(i16, @bitCast(global.gpg.g.magics[iMagicNum].y_offset));
            battle.addSpriteObject(.magic, @intCast(iMagicNum), global.palXY(@truncate(tx), @truncate(ty)), layer_off, false);
        } else {
            std.debug.assert(false);
        }
        battleFrameMagic();
    }
    battle.g_battle.magic_bitmap = null;

    // Color-shift fade-in then fade-out.
    var f: i32 = 0;
    while (f < 6) : (f += 1) {
        if (global.gpg.g.magics[iMagicNum].magic_type == global.MAGIC_TYPE_APPLY_TO_PARTY) {
            var j: u32 = 0;
            while (j <= global.gpg.max_party_member_index) : (j += 1) {
                battle.g_battle.players[j].color_shift = f;
            }
        } else {
            battle.g_battle.players[@intCast(sTarget)].color_shift = f;
        }
        battleDelay(1, 0, true);
    }
    f = 6;
    while (f >= 0) : (f -= 1) {
        if (global.gpg.g.magics[iMagicNum].magic_type == global.MAGIC_TYPE_APPLY_TO_PARTY) {
            var j: u32 = 0;
            while (j <= global.gpg.max_party_member_index) : (j += 1) {
                battle.g_battle.players[j].color_shift = f;
            }
        } else {
            battle.g_battle.players[@intCast(sTarget)].color_shift = f;
        }
        battleDelay(1, 0, true);
    }
}

// PAL_BattleShowPlayerPreMagicAnim — fight.c L2337. Player crouches, then a
// 10-frame burst of effect_sprite light-frames pulses over their head.
pub fn battleShowPlayerPreMagicAnim(player_index: u16, fSummon: bool) void {
    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        const px: i32 = @as(i32, global.palX(battle.g_battle.players[player_index].pos)) - (4 - i);
        const py: i32 = @as(i32, global.palY(battle.g_battle.players[player_index].pos)) - @divTrunc(4 - i, 2);
        battle.g_battle.players[player_index].pos = global.palXY(@truncate(px), @truncate(py));
        battleDelay(1, 0, true);
    }
    battleDelay(2, 0, true);
    battle.g_battle.players[player_index].current_frame = 5;

    // fight.c L2377 — incantation cue. The role's per-character magic_sound,
    // played as soon as the casting frame appears.
    {
        const role_for_voice = global.gpg.party[player_index].player_role;
        @import("audio.zig").playSound(@as(i32, global.gpg.g.player_roles.magic_sound[role_for_voice]));
    }

    if (!fSummon) {
        const role = global.gpg.party[player_index].player_role;
        const x: i32 = global.palX(battle.g_battle.players[player_index].pos);
        const y: i32 = global.palY(battle.g_battle.players[player_index].pos);
        const sprite_idx = battle.getPlayerBattleSprite(role);
        var index: u32 = global.gpg.g.battle_effect_index[sprite_idx][0];
        index *= 10;
        index += 15;

        var dw_time: u32 = util.getTicks();
        var k: u32 = 0;
        while (k < 10) : (k += 1) {
            const eff_sprite = battle.g_battle.effect_sprite orelse break;
            const b = palcommon.spriteGetFrame(eff_sprite, @intCast(index)) orelse break;
            index += 1;

            while (util.getTicks() < dw_time) {
                input.processEvent();
                std.Thread.yield() catch {};
                if (util.shouldQuit()) return;
            }
            dw_time = util.getTicks() + global.BATTLE_FRAME_TIME;

            // Tick enemy gestures (mirrors L2411-2431).
            var j: u32 = 0;
            while (battle.g_battle.max_enemy_index >= 0 and j <= @as(u32, @intCast(battle.g_battle.max_enemy_index))) : (j += 1) {
                const e = &battle.g_battle.enemies[j];
                if (e.object_id == 0 or
                    e.status[global.STATUS_SLEEP] != 0 or
                    e.status[global.STATUS_PARALYZED] != 0) continue;
                if (e.e.idle_anim_speed != 0) e.e.idle_anim_speed -%= 1;
                if (e.e.idle_anim_speed == 0) {
                    e.current_frame +%= 1;
                    const enemy_id = global.gpg.g.objects[e.object_id].data[0];
                    e.e.idle_anim_speed = global.gpg.g.enemies[enemy_id].idle_anim_speed;
                }
                if (e.current_frame >= e.e.idle_frames) e.current_frame = 0;
            }

            battle.battleMakeScene();
            @memcpy(&video.screen_pixels, &battle.g_battle.scene_buf_pixels);

            // Blit the effect frame above the player.
            const w: i32 = palcommon.rleGetWidth(b);
            const h: i32 = palcommon.rleGetHeight(b);
            _ = palcommon.rleBlitToSurface(b, &video.screen, global.palXY(@truncate(x - @divTrunc(w, 2)), @truncate(y - h)));

            @import("battleui.zig").update();
            video.updateScreen(null);
        }
    }
    battleDelay(1, 0, true);
}

// PAL_BattleShowPlayerSummonMagicAnim — fight.c L3071. Brighten party, fade
// in the summon sprite, run its frames, then call the offensive anim with
// fSummon=TRUE on the inner magic.
pub fn battleShowPlayerSummonMagicAnim(player_index: u16, object_id: u16) void {
    _ = player_index; // SDLPAL also takes wPlayerIndex but never uses it.
    const f_mkf = global.gpg.f.f orelse return;

    const iMagicNum: u32 = global.gpg.g.objects[object_id].magic().magic_number;

    // Find the magic object whose magicNumber == this magic's effect.
    var wEffectMagicID: u32 = 0;
    while (wEffectMagicID < global.MAX_OBJECTS) : (wEffectMagicID += 1) {
        if (global.gpg.g.objects[wEffectMagicID].magic().magic_number ==
            global.gpg.g.magics[iMagicNum].effect) break;
    }
    if (wEffectMagicID >= global.MAX_OBJECTS) return;

    // Brighten party.
    var i: i32 = 1;
    while (i <= 10) : (i += 1) {
        var j: u32 = 0;
        while (j <= global.gpg.max_party_member_index) : (j += 1) {
            battle.g_battle.players[j].color_shift = i;
        }
        battleDelay(1, object_id, true);
    }

    video.backupScreen();

    // Load summon sprite from F.MKF.
    const summon_chunk: u32 = @as(u32, global.gpg.g.magics[iMagicNum].specific) + 10;
    const summon_size = f_mkf.getDecompressedSize(summon_chunk, false) catch return;
    if (summon_size == 0) return;
    const summon_buf = global.allocator.alloc(u8, summon_size) catch return;
    {
        const compressed = f_mkf.getChunkData(summon_chunk) catch {
            global.allocator.free(summon_buf);
            return;
        };
        _ = @import("yj1.zig").decompress(compressed, summon_buf) catch {
            global.allocator.free(summon_buf);
            return;
        };
    }
    battle.g_battle.summon_sprite = summon_buf;
    battle.g_battle.summon_frame = 0;
    battle.g_battle.pos_summon = global.palXY(
        @truncate(240 + @as(i32, @bitCast(@as(i32, @as(i16, @bitCast(global.gpg.g.magics[iMagicNum].x_offset)))))),
        @truncate(165 + @as(i32, @bitCast(@as(i32, @as(i16, @bitCast(global.gpg.g.magics[iMagicNum].y_offset)))))),
    );
    battle.g_battle.background_color_shift = @intCast(@as(i16, @bitCast(global.gpg.g.magics[iMagicNum].effect_times)));
    battle.g_battle.summon_color_shift = true;

    // Fade in the summoned god.
    battle.battleMakeScene();
    battle.battleFadeScene();

    battle.g_battle.summon_color_shift = false;

    // Show the animation.
    const speed: i32 = @as(i16, @bitCast(@as(u16, @bitCast(global.gpg.g.magics[iMagicNum].speed))));
    const frame_ms: u32 = @intCast(@max((speed + 5) * 10, 10));
    var dw_time: u32 = util.getTicks();
    const total_frames: i32 = palcommon.spriteGetNumFrames(summon_buf);
    while (battle.g_battle.summon_frame < total_frames - 1) {
        while (util.getTicks() < dw_time) {
            input.processEvent();
            std.Thread.yield() catch {};
            if (util.shouldQuit()) return;
        }
        dw_time = util.getTicks() + frame_ms;

        battle.battleMakeScene();
        @memcpy(&video.screen_pixels, &battle.g_battle.scene_buf_pixels);
        @import("battleui.zig").update();
        video.updateScreen(null);
        battle.g_battle.summon_frame += 1;
    }

    // Show the actual magic effect on top.
    battleShowPlayerOffMagicAnim(0xFFFF, @intCast(wEffectMagicID), -1, true);
}

// PAL_BattleShowPlayerUseItemAnim — fight.c L2266.
pub fn battleShowPlayerUseItemAnim(player_index: u16, object_id: u16, sTarget: i32) void {
    battleDelay(4, 0, true);

    const px: i32 = @as(i32, global.palX(battle.g_battle.players[player_index].pos)) - 15;
    const py: i32 = @as(i32, global.palY(battle.g_battle.players[player_index].pos)) - 7;
    battle.g_battle.players[player_index].pos = global.palXY(@truncate(px), @truncate(py));
    battle.g_battle.players[player_index].current_frame = 5;

    var i: i32 = 0;
    while (i <= 6) : (i += 1) {
        if (sTarget == -1) {
            var j: u32 = 0;
            while (j <= global.gpg.max_party_member_index) : (j += 1) {
                battle.g_battle.players[j].color_shift = i;
            }
        } else {
            battle.g_battle.players[@intCast(sTarget)].color_shift = i;
        }
        battleDelay(1, object_id, true);
    }
    i = 5;
    while (i >= 0) : (i -= 1) {
        if (sTarget == -1) {
            var j: u32 = 0;
            while (j <= global.gpg.max_party_member_index) : (j += 1) {
                battle.g_battle.players[j].color_shift = i;
            }
        } else {
            battle.g_battle.players[@intCast(sTarget)].color_shift = i;
        }
        battleDelay(1, object_id, true);
    }
}

// PAL_BattleShowPostMagicAnim — fight.c L3189. After damage applies, jiggle
// the affected enemies left/right with one red flash on the middle frame.
pub fn battleShowPostMagicAnim() void {
    var pos_bak: [global.MAX_ENEMIES_IN_TEAM]u32 = undefined;
    var k: u32 = 0;
    while (k < global.MAX_ENEMIES_IN_TEAM) : (k += 1) {
        pos_bak[k] = battle.g_battle.enemies[k].pos;
    }

    var dist: i32 = 8;
    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        var j: u32 = 0;
        while (battle.g_battle.max_enemy_index >= 0 and j <= @as(u32, @intCast(battle.g_battle.max_enemy_index))) : (j += 1) {
            const e = &battle.g_battle.enemies[j];
            if (e.e.health == e.prev_hp) continue;
            const x: i32 = @as(i32, global.palX(e.pos)) - dist;
            const y: i32 = global.palY(e.pos);
            e.pos = global.palXY(@truncate(x), @truncate(y));
            e.color_shift = if (i == 1) 6 else 0;
        }
        battleDelay(1, 0, true);
        dist = -@divTrunc(dist, 2);
    }

    k = 0;
    while (k < global.MAX_ENEMIES_IN_TEAM) : (k += 1) {
        battle.g_battle.enemies[k].pos = pos_bak[k];
    }
    battleDelay(1, 0, true);
}

// PAL_BattleEnemyEscape — slide all enemies off-screen leftward.
pub fn enemyEscape() void {
    var moved = true;
    while (moved) {
        moved = false;
        var j: u32 = 0;
        while (battle.g_battle.max_enemy_index >= 0 and j <= @as(u32, @intCast(battle.g_battle.max_enemy_index))) : (j += 1) {
            const e = &battle.g_battle.enemies[j];
            if (e.object_id == 0) continue;
            const x: i32 = @as(i32, global.palX(e.pos)) - 5;
            const y: i32 = global.palY(e.pos);
            e.pos = global.palXY(@truncate(x), @truncate(y));
            const sprite = e.sprite orelse continue;
            const frame = palcommon.spriteGetFrame(sprite, 0) orelse continue;
            const w: i32 = palcommon.rleGetWidth(frame);
            if (x + w > 0) moved = true;
        }
        battle.battleMakeScene();
        @memcpy(&video.screen_pixels, &battle.g_battle.scene_buf_pixels);
        video.updateScreen(null);
        util.delay(10);
    }
    util.delay(500);
    battle.g_battle.result = .terminated;
}

// PAL_BattleSimulateMagic — fight.c L5301. Run an offensive magic animation
// owned by no player slot (player_index = 0xFFFF) and apply damage to the
// target. Used by item-throw scripts and the 0x0042 / 0x0066 opcodes.
pub fn battleSimulateMagic(sTarget_in: i32, magic_object_id: u16, base_damage: u16) void {
    var sTarget: i32 = sTarget_in;
    const flags = global.gpg.g.objects[magic_object_id].magic().flags;
    if ((flags & global.MAGIC_FLAG_APPLY_TO_ALL) != 0) {
        sTarget = -1;
    } else if (sTarget == -1) {
        sTarget = battleSelectAutoTargetFrom(sTarget);
    }

    battleShowPlayerOffMagicAnim(0xFFFF, magic_object_id, sTarget, false);

    const magic_num = global.gpg.g.objects[magic_object_id].magic().magic_number;
    const m_base_damage = global.gpg.g.magics[magic_num].base_damage;
    if (@as(i16, @bitCast(m_base_damage)) > 0 or base_damage > 0) {
        if (sTarget == -1) {
            var i: u32 = 0;
            while (battle.g_battle.max_enemy_index >= 0 and i <= @as(u32, @intCast(battle.g_battle.max_enemy_index))) : (i += 1) {
                const e = &battle.g_battle.enemies[i];
                if (e.object_id == 0) continue;
                var def: i32 = @as(i16, @bitCast(e.e.defense));
                def += (@as(i32, e.e.level) + 6) * 4;
                if (def < 0) def = 0;
                var dmg = calcMagicDamage(base_damage, def, &e.e.elem_resistance, e.e.poison_resistance, 1, magic_object_id);
                if (dmg < 0) dmg = 0;
                const new_h: i32 = @as(i32, e.e.health) - dmg;
                e.e.health = if (new_h < 0) 0 else @intCast(new_h);
            }
        } else {
            const e = &battle.g_battle.enemies[@intCast(sTarget)];
            var def: i32 = @as(i16, @bitCast(e.e.defense));
            def += (@as(i32, e.e.level) + 6) * 4;
            if (def < 0) def = 0;
            var dmg = calcMagicDamage(base_damage, def, &e.e.elem_resistance, e.e.poison_resistance, 1, magic_object_id);
            if (dmg < 0) dmg = 0;
            const new_h: i32 = @as(i32, e.e.health) - dmg;
            e.e.health = if (new_h < 0) 0 else @intCast(new_h);
        }
    }
}

// PAL_CLASSIC: show a centered single-line "得到 ..." dialog. SDLPAL composes
// via PAL_swprintf (battle.c L5268-L5283); we hand-render the BIG5 bytes
// since wide-string formatting isn't ported.
pub fn showGetDialog(word_get: u16, num_or_neg: i32, word2: u16) void {
    var buf: [128]u8 = undefined;
    var len: usize = 0;

    const w1 = text.getWord(word_get);
    @memcpy(buf[len..][0..w1.len], w1);
    len += w1.len;

    if (num_or_neg >= 0) {
        const num_s = std.fmt.bufPrint(buf[len..], " {d} ", .{num_or_neg}) catch return;
        len += num_s.len;
    }

    const w2 = text.getWord(word2);
    @memcpy(buf[len..][0..w2.len], w2);
    len += w2.len;

    text.startDialog(.center_window, 0, 0, false);
    text.showDialogText(buf[0..len]);
}

// PAL_BattleStealFromEnemy — fight.c L5193. Player slides over to the enemy,
// flashes a red flicker, then either grabs cash (wStealItem == 0) or an item.
pub fn battleStealFromEnemy(target: u16, steal_rate: u16) void {
    const i_player: u32 = battle.g_battle.moving_player_index;
    const e = &battle.g_battle.enemies[target];

    battle.g_battle.players[i_player].current_frame = 10;
    const offset: i32 = (@as(i32, target) - @as(i32, @intCast(i_player))) * 8;

    var x: i32 = global.palX(e.pos) + 64 - offset;
    var y: i32 = global.palY(e.pos) + 22 + offset;
    battle.g_battle.players[i_player].pos = global.palXY(@truncate(x), @truncate(y));
    battleDelay(1, 0, true);

    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        x -= i + 8;
        y -= 4;
        battle.g_battle.players[i_player].pos = global.palXY(@truncate(x), @truncate(y));
        if (i == 4) e.color_shift = 6;
        battleDelay(1, 0, true);
    }
    e.color_shift = 0;
    x -= 1;
    battle.g_battle.players[i_player].pos = global.palXY(@truncate(x), @truncate(y));
    battleDelay(3, 0, true);

    battle.g_battle.players[i_player].state = .wait;
    updateFighters();
    battleDelay(1, 0, true);

    if (e.e.n_steal_item > 0 and
        (util.randomLong(0, 10) <= @as(i32, steal_rate) or steal_rate == 0))
    {
        if (e.e.steal_item == 0) {
            // Cash.
            const div: u32 = @intCast(util.randomLong(2, 3));
            const c: u32 = @as(u32, e.e.n_steal_item) / div;
            if (c > e.e.n_steal_item) {
                e.e.n_steal_item = 0;
            } else {
                e.e.n_steal_item -= @intCast(c);
            }
            global.gpg.cash +%= c;

            // SDLPAL "得到 N 钱" (PAL_GetWord(34) + count + PAL_GetWord(10)).
            if (c > 0) {
                showGetDialog(34, @intCast(c), 10);
            }
        } else {
            e.e.n_steal_item -= 1;
            _ = global.addItemToInventory(e.e.steal_item, 1);
            // "得到 <item>" (PAL_GetWord(34) + PAL_GetWord(item)).
            showGetDialog(34, -1, e.e.steal_item);
        }
    }
}
//   - kBattleWinGetExpLabel        = 30
//   - kBattleWinBeatEnemyLabel     = 9
//   - kBattleWinDollarLabel        = 10
//   - kBattleWinLevelUpLabel       = 32
//   - kBattleWinAddMagicLabel      = 33
//   - kBattleWinLevelUpLabelColor  = 0xBB
//   - SPRITENUM_ARROW              = 47
//   - SPRITENUM_SLASH              = 39
//   - kStatusLabelLevel..FleeRate  = 48..55
pub fn battleWon() void {
    const play = @import("play.zig");
    const SPRITENUM_ARROW: i32 = 47;
    const SPRITENUM_SLASH: i32 = 39;
    const BATTLEWIN_LEVELUP_LABEL_COLOR: u8 = 0xBB;

    // Play victory music (RIX track 3, non-looping, no fade).
    @import("audio.zig").playMusic(3, false, 0);

    // PLAYERROLES OrigPlayerRoles = gpGlobals->g.PlayerRoles;
    var orig_player_roles = global.gpg.g.player_roles;

    video.backupScreen();

    if (battle.g_battle.exp_gained > 0) {
        // int w1 = PAL_WordWidth(BATTLEWIN_GETEXP_LABEL) + 3;
        const w1: i32 = ui.wordWidth(30) + 3;
        // int ww1 = (w1 - 8) << 3;
        const ww1: i32 = (w1 - 8) << 3;

        // PAL_CreateSingleLineBox(PAL_XY(83 - ww1, 60), w1, FALSE);
        _ = ui.createSingleLineBox(global.palXY(@truncate(83 - ww1), 60), w1, false);
        // PAL_CreateSingleLineBox(PAL_XY(65, 105), 10, FALSE);
        _ = ui.createSingleLineBox(global.palXY(65, 105), 10, false);

        text.drawText(text.getWord(30), global.palXY(@truncate(95 - ww1), 70), 0, false, false);
        text.drawText(text.getWord(9), global.palXY(77, 115), 0, false, false);
        text.drawText(text.getWord(10), global.palXY(197, 115), 0, false, false);

        ui.drawNumber(@intCast(@as(u32, @intCast(battle.g_battle.exp_gained))), 5, global.palXY(@truncate(182 + ww1), 74), .yellow, .right);
        ui.drawNumber(@intCast(@as(u32, @intCast(battle.g_battle.cash_gained))), 5, global.palXY(162, 119), .yellow, .mid);

        video.updateScreen(null);
        play.waitForAnyKey(if (battle.g_battle.is_boss) 5500 else 3000);
    }

    // gpGlobals->dwCash += g_Battle.iCashGained;
    global.gpg.cash +%= @intCast(battle.g_battle.cash_gained);

    // Compute maxNameWidth / maxPropertyWidth / offsetX (battle.c L1057-1084).
    var max_name_width: i32 = 0;
    {
        var k: u32 = 0;
        while (k < global.MAX_PLAYABLE_PLAYER_ROLES) : (k += 1) {
            const ww = ui.wordWidth(global.gpg.g.player_roles.name[k]);
            if (ww > max_name_width) max_name_width = ww;
        }
    }
    var max_property_width: i32 = 0;
    {
        var lbl: u16 = 48;
        while (lbl <= 55) : (lbl += 1) {
            const ww = ui.wordWidth(lbl);
            if (ww > max_property_width) max_property_width = ww;
        }
        max_property_width -= 1;
    }
    const property_length: i32 = max_property_width - 1;
    const offset_x: i32 = -8 * property_length;

    // Add the experience points for each players.
    var i: u32 = 0;
    while (i <= global.gpg.max_party_member_index) : (i += 1) {
        var fLevelUp: bool = false;

        const w = global.gpg.party[i].player_role;
        if (global.gpg.g.player_roles.hp[w] == 0) {
            continue; // don't care about dead players
        }

        var dwExp: u32 = global.gpg.exp.primary[w].exp;
        dwExp +%= @intCast(@as(u32, @intCast(battle.g_battle.exp_gained)));

        if (global.gpg.g.player_roles.level[w] > global.MAX_LEVELS) {
            global.gpg.g.player_roles.level[w] = global.MAX_LEVELS;
        }

        while (dwExp >= global.gpg.g.level_up_exp[global.gpg.g.player_roles.level[w]]) {
            dwExp -= global.gpg.g.level_up_exp[global.gpg.g.player_roles.level[w]];
            if (global.gpg.g.player_roles.level[w] < global.MAX_LEVELS) {
                fLevelUp = true;
                global.playerLevelUp(w, 1);
                global.gpg.g.player_roles.hp[w] = global.gpg.g.player_roles.max_hp[w];
                global.gpg.g.player_roles.mp[w] = global.gpg.g.player_roles.max_mp[w];
            }
        }

        global.gpg.exp.primary[w].exp = @intCast(dwExp & 0xFFFF);

        if (fLevelUp) {
            video.restoreScreen();

            // PAL_CreateSingleLineBox(PAL_XY(offsetX+80, 0), propertyLength+10, FALSE);
            _ = ui.createSingleLineBox(global.palXY(@truncate(offset_x + 80), 0), property_length + 10, false);
            // PAL_CreateBox(PAL_XY(offsetX+82, 32), 7, propertyLength+8, 1, FALSE);
            _ = ui.createBox(global.palXY(@truncate(offset_x + 82), 32), 7, property_length + 8, 1, false);

            // PAL_swprintf(buffer, ..., L"%ls%ls%ls", Name, LEVEL_LABEL, LEVELUP_LABEL);
            // PAL_DrawText(buffer, PAL_XY(110, 10), 0, FALSE, FALSE, FALSE);
            // We translate `wcscpy + DrawText` as 3 separate DrawText calls; the
            // x-advance is name width then label widths, in PAL_X units.
            {
                const name = text.getWord(global.gpg.g.player_roles.name[w]);
                const lvl_w = text.getWord(48);
                const up_w = text.getWord(32);
                var x: i32 = 110;
                text.drawText(name, global.palXY(@truncate(x), 10), 0, false, false);
                x += ui.textWidth(name);
                text.drawText(lvl_w, global.palXY(@truncate(x), 10), 0, false, false);
                x += ui.textWidth(lvl_w);
                text.drawText(up_w, global.palXY(@truncate(x), 10), 0, false, false);
            }

            // 8 arrows on the right column.
            var j: i32 = 0;
            while (j < 8) : (j += 1) {
                if (palcommon.spriteGetFrame(ui.sprite_ui, SPRITENUM_ARROW)) |bmp| {
                    _ = palcommon.rleBlitToSurface(bmp, &video.screen, global.palXY(@truncate(-offset_x + 180), @truncate(48 + 18 * j)));
                }
            }

            // 8 row labels.
            text.drawText(text.getWord(48), global.palXY(@truncate(offset_x + 100), 44), BATTLEWIN_LEVELUP_LABEL_COLOR, true, false);
            text.drawText(text.getWord(49), global.palXY(@truncate(offset_x + 100), 62), BATTLEWIN_LEVELUP_LABEL_COLOR, true, false);
            text.drawText(text.getWord(50), global.palXY(@truncate(offset_x + 100), 80), BATTLEWIN_LEVELUP_LABEL_COLOR, true, false);
            text.drawText(text.getWord(51), global.palXY(@truncate(offset_x + 100), 98), BATTLEWIN_LEVELUP_LABEL_COLOR, true, false);
            text.drawText(text.getWord(52), global.palXY(@truncate(offset_x + 100), 116), BATTLEWIN_LEVELUP_LABEL_COLOR, true, false);
            text.drawText(text.getWord(53), global.palXY(@truncate(offset_x + 100), 134), BATTLEWIN_LEVELUP_LABEL_COLOR, true, false);
            text.drawText(text.getWord(54), global.palXY(@truncate(offset_x + 100), 152), BATTLEWIN_LEVELUP_LABEL_COLOR, true, false);
            text.drawText(text.getWord(55), global.palXY(@truncate(offset_x + 100), 170), BATTLEWIN_LEVELUP_LABEL_COLOR, true, false);

            // Level row.
            ui.drawNumber(orig_player_roles.level[w], 4, global.palXY(@truncate(-offset_x + 133), 47), .yellow, .right);
            ui.drawNumber(global.gpg.g.player_roles.level[w], 4, global.palXY(@truncate(-offset_x + 195), 47), .yellow, .right);

            // HP row (curHP/maxHP, slash, then post curHP/maxHP).
            ui.drawNumber(orig_player_roles.hp[w], 4, global.palXY(@truncate(-offset_x + 133), 64), .yellow, .right);
            ui.drawNumber(orig_player_roles.max_hp[w], 4, global.palXY(@truncate(-offset_x + 154), 68), .blue, .right);
            if (palcommon.spriteGetFrame(ui.sprite_ui, SPRITENUM_SLASH)) |bmp| {
                _ = palcommon.rleBlitToSurface(bmp, &video.screen, global.palXY(@truncate(-offset_x + 156), 66));
            }
            ui.drawNumber(global.gpg.g.player_roles.hp[w], 4, global.palXY(@truncate(-offset_x + 195), 64), .yellow, .right);
            ui.drawNumber(global.gpg.g.player_roles.max_hp[w], 4, global.palXY(@truncate(-offset_x + 216), 68), .blue, .right);
            if (palcommon.spriteGetFrame(ui.sprite_ui, SPRITENUM_SLASH)) |bmp| {
                _ = palcommon.rleBlitToSurface(bmp, &video.screen, global.palXY(@truncate(-offset_x + 218), 66));
            }

            // MP row.
            ui.drawNumber(orig_player_roles.mp[w], 4, global.palXY(@truncate(-offset_x + 133), 82), .yellow, .right);
            ui.drawNumber(orig_player_roles.max_mp[w], 4, global.palXY(@truncate(-offset_x + 154), 86), .blue, .right);
            if (palcommon.spriteGetFrame(ui.sprite_ui, SPRITENUM_SLASH)) |bmp| {
                _ = palcommon.rleBlitToSurface(bmp, &video.screen, global.palXY(@truncate(-offset_x + 156), 84));
            }
            ui.drawNumber(global.gpg.g.player_roles.mp[w], 4, global.palXY(@truncate(-offset_x + 195), 82), .yellow, .right);
            ui.drawNumber(global.gpg.g.player_roles.max_mp[w], 4, global.palXY(@truncate(-offset_x + 216), 86), .blue, .right);
            if (palcommon.spriteGetFrame(ui.sprite_ui, SPRITENUM_SLASH)) |bmp| {
                _ = palcommon.rleBlitToSurface(bmp, &video.screen, global.palXY(@truncate(-offset_x + 218), 84));
            }

            // Attack row: orig + (effective - base) on left, effective on right.
            ui.drawNumber(
                orig_player_roles.attack_strength[w] +% global.getPlayerAttackStrength(w) -% global.gpg.g.player_roles.attack_strength[w],
                4,
                global.palXY(@truncate(-offset_x + 133), 101),
                .yellow,
                .right,
            );
            ui.drawNumber(global.getPlayerAttackStrength(w), 4, global.palXY(@truncate(-offset_x + 195), 101), .yellow, .right);

            // Magic row.
            ui.drawNumber(
                orig_player_roles.magic_strength[w] +% global.getPlayerMagicStrength(w) -% global.gpg.g.player_roles.magic_strength[w],
                4,
                global.palXY(@truncate(-offset_x + 133), 119),
                .yellow,
                .right,
            );
            ui.drawNumber(global.getPlayerMagicStrength(w), 4, global.palXY(@truncate(-offset_x + 195), 119), .yellow, .right);

            // Defense row.
            ui.drawNumber(
                orig_player_roles.defense[w] +% global.getPlayerDefense(w) -% global.gpg.g.player_roles.defense[w],
                4,
                global.palXY(@truncate(-offset_x + 133), 137),
                .yellow,
                .right,
            );
            ui.drawNumber(global.getPlayerDefense(w), 4, global.palXY(@truncate(-offset_x + 195), 137), .yellow, .right);

            // Dexterity row.
            ui.drawNumber(
                orig_player_roles.dexterity[w] +% global.getPlayerDexterity(w) -% global.gpg.g.player_roles.dexterity[w],
                4,
                global.palXY(@truncate(-offset_x + 133), 155),
                .yellow,
                .right,
            );
            ui.drawNumber(global.getPlayerDexterity(w), 4, global.palXY(@truncate(-offset_x + 195), 155), .yellow, .right);

            // FleeRate row.
            ui.drawNumber(
                orig_player_roles.flee_rate[w] +% global.getPlayerFleeRate(w) -% global.gpg.g.player_roles.flee_rate[w],
                4,
                global.palXY(@truncate(-offset_x + 133), 173),
                .yellow,
                .right,
            );
            ui.drawNumber(global.getPlayerFleeRate(w), 4, global.palXY(@truncate(-offset_x + 195), 173), .yellow, .right);

            video.updateScreen(null);
            play.waitForAnyKey(3000);

            orig_player_roles = global.gpg.g.player_roles;
        }

        // Increasing of other hidden levels.
        var iTotalCount: u32 = 0;
        iTotalCount += global.gpg.exp.attack[w].count;
        iTotalCount += global.gpg.exp.defense[w].count;
        iTotalCount += global.gpg.exp.dexterity[w].count;
        iTotalCount += global.gpg.exp.flee[w].count;
        iTotalCount += global.gpg.exp.health[w].count;
        iTotalCount += global.gpg.exp.magic_exp[w].count;
        iTotalCount += global.gpg.exp.magic_power[w].count;

        if (iTotalCount > 0) {
            checkHiddenExp(w, iTotalCount, &global.gpg.exp.health, &global.gpg.g.player_roles.max_hp, 49, max_name_width, max_property_width, offset_x, &orig_player_roles);
            checkHiddenExp(w, iTotalCount, &global.gpg.exp.magic_exp, &global.gpg.g.player_roles.max_mp, 50, max_name_width, max_property_width, offset_x, &orig_player_roles);
            checkHiddenExp(w, iTotalCount, &global.gpg.exp.attack, &global.gpg.g.player_roles.attack_strength, 51, max_name_width, max_property_width, offset_x, &orig_player_roles);
            checkHiddenExp(w, iTotalCount, &global.gpg.exp.magic_power, &global.gpg.g.player_roles.magic_strength, 52, max_name_width, max_property_width, offset_x, &orig_player_roles);
            checkHiddenExp(w, iTotalCount, &global.gpg.exp.defense, &global.gpg.g.player_roles.defense, 53, max_name_width, max_property_width, offset_x, &orig_player_roles);
            checkHiddenExp(w, iTotalCount, &global.gpg.exp.dexterity, &global.gpg.g.player_roles.dexterity, 54, max_name_width, max_property_width, offset_x, &orig_player_roles);
            checkHiddenExp(w, iTotalCount, &global.gpg.exp.flee, &global.gpg.g.player_roles.flee_rate, 55, max_name_width, max_property_width, offset_x, &orig_player_roles);

            if (fLevelUp) {
                global.gpg.g.player_roles.hp[w] = global.gpg.g.player_roles.max_hp[w];
                global.gpg.g.player_roles.mp[w] = global.gpg.g.player_roles.max_mp[w];
            }
        }

        // Learn all magics at the current level. SDLPAL's LEVELUPMAGIC_ALL.m[]
        // is sized to MAX_PLAYABLE_PLAYER_ROLES (5); roles above that index
        // (e.g. NPCs forced into the party via debug) have no level-up table
        // and we just skip them.
        if (w >= global.MAX_PLAYABLE_PLAYER_ROLES) continue;
        var jj: u32 = 0;
        while (jj < global.gpg.g.level_up_magics.len) : (jj += 1) {
            const lm = global.gpg.g.level_up_magics[jj].m[w];
            if (lm.magic == 0 or lm.level > global.gpg.g.player_roles.level[w]) continue;

            if (global.addMagic(w, lm.magic)) {
                var ww: i32 = ui.wordWidth(global.gpg.g.player_roles.name[w]);
                const w1: i32 = if (ww > 3) ww else 3;
                ww = ui.wordWidth(33);
                const w2: i32 = if (ww > 2) ww else 2;
                ww = ui.wordWidth(lm.magic);
                const w3: i32 = if (ww > 5) ww else 5;
                ww = (w1 + w2 + w3 - 10) << 3;

                _ = ui.createSingleLineBox(global.palXY(@truncate(65 - ww), 105), w1 + w2 + w3, false);

                text.drawText(text.getWord(global.gpg.g.player_roles.name[w]), global.palXY(@truncate(75 - ww), 115), 0, false, false);
                text.drawText(text.getWord(33), global.palXY(@truncate(75 + 16 * w1 - ww), 115), 0, false, false);
                text.drawText(text.getWord(lm.magic), global.palXY(@truncate(75 + 16 * (w1 + w2) - ww), 115), 0x1B, false, false);

                video.updateScreen(null);
                play.waitForAnyKey(3000);
            }
        }
    }

    // Run post-battle scripts for each enemy.
    i = 0;
    while (battle.g_battle.max_enemy_index >= 0 and i <= @as(u32, @intCast(battle.g_battle.max_enemy_index))) : (i += 1) {
        _ = script.runTriggerScript(battle.g_battle.enemies[i].script_on_battle_end, @intCast(i));
    }

    // Auto half-heal.
    i = 0;
    while (i <= global.gpg.max_party_member_index) : (i += 1) {
        const w = global.gpg.party[i].player_role;
        const max_hp = global.gpg.g.player_roles.max_hp[w];
        const max_mp = global.gpg.g.player_roles.max_mp[w];
        global.gpg.g.player_roles.hp[w] +%= (max_hp - global.gpg.g.player_roles.hp[w]) / 2;
        global.gpg.g.player_roles.mp[w] +%= (max_mp - global.gpg.g.player_roles.mp[w]) / 2;
    }

    video.restoreScreen();
}

// CHECK_HIDDEN_EXP macro from battle.c L1238-L1274. The macro mutates
// gpGlobals->Exp.<expname>[w] and gpGlobals->g.PlayerRoles.<statname>[w], then
// (if the stat changed) draws a single-line banner "<Name><Label>升級 <delta>"
// and waits for a key. We translate it as a function with the macro args
// passed explicitly; the layout constants come from L1268-L1270.
fn checkHiddenExp(
    role: u16,
    iTotalCount: u32,
    exp_arr: *align(1) [global.MAX_PLAYER_ROLES]global.Experience,
    stat_arr: *align(1) [global.MAX_PLAYER_ROLES]u16,
    label_word: u16,
    max_name_width: i32,
    max_property_width: i32,
    offset_x: i32,
    orig_player_roles: *const global.PlayerRoles,
) void {
    const play = @import("play.zig");
    _ = orig_player_roles; // SDLPAL diff is taken against current statname only.

    var dwExp: u32 = @intCast(@as(u32, @intCast(battle.g_battle.exp_gained)));
    dwExp *= exp_arr[role].count;
    dwExp /= iTotalCount;
    dwExp *= 2;
    dwExp += exp_arr[role].exp;

    if (exp_arr[role].level > global.MAX_LEVELS) {
        exp_arr[role].level = global.MAX_LEVELS;
    }

    const orig_stat: u16 = stat_arr[role];

    while (dwExp >= global.gpg.g.level_up_exp[exp_arr[role].level]) {
        dwExp -= global.gpg.g.level_up_exp[exp_arr[role].level];
        stat_arr[role] +%= @intCast(util.randomLong(1, 2));
        if (exp_arr[role].level < global.MAX_LEVELS) {
            exp_arr[role].level += 1;
        }
    }
    exp_arr[role].exp = @intCast(dwExp & 0xFFFF);

    if (stat_arr[role] != orig_stat) {
        // PAL_swprintf(buffer, ..., L"%ls%ls%ls", Name, label, LEVELUP_LABEL);
        // PAL_CreateSingleLineBox(PAL_XY(offsetX+78, 60), maxNameWidth+maxPropertyWidth + PAL_TextWidth(LEVELUP_LABEL)/32 + 4, FALSE);
        // PAL_DrawText(buffer, PAL_XY(offsetX+90, 70), 0, FALSE, FALSE, FALSE);
        const levelup_label = text.getWord(32);
        _ = ui.createSingleLineBox(
            global.palXY(@truncate(offset_x + 78), 60),
            max_name_width + max_property_width + @divTrunc(ui.textWidth(levelup_label), 32) + 4,
            false,
        );
        // wcscpy → 3 sequential DrawText calls advancing by textWidth.
        const name = text.getWord(global.gpg.g.player_roles.name[role]);
        const label = text.getWord(label_word);
        var x: i32 = offset_x + 90;
        text.drawText(name, global.palXY(@truncate(x), 70), 0, false, false);
        x += ui.textWidth(name);
        text.drawText(label, global.palXY(@truncate(x), 70), 0, false, false);
        x += ui.textWidth(label);
        text.drawText(levelup_label, global.palXY(@truncate(x), 70), 0, false, false);

        // PAL_DrawNumber(diff, 5, PAL_XY(183 + (maxNameWidth+maxPropertyWidth-3)*8, 74), kYellow, kRight);
        ui.drawNumber(
            stat_arr[role] - orig_stat,
            5,
            global.palXY(@truncate(183 + (max_name_width + max_property_width - 3) * 8), 74),
            .yellow,
            .right,
        );
        video.updateScreen(null);
        play.waitForAnyKey(3000);
    }
}

// Single-frame entry from battle.zig main loop. Drives select/perform.
pub fn startFrame() void {
    if (!battle.g_battle.enemy_cleared) updateFighters();

    // Battle ended?
    if (battle.g_battle.enemy_cleared) {
        battle.g_battle.result = .won;
        return;
    }
    var alive_party = false;
    var i: u32 = 0;
    while (i <= global.gpg.max_party_member_index) : (i += 1) {
        if (global.gpg.g.player_roles.hp[global.gpg.party[i].player_role] != 0) alive_party = true;
    }
    if (!alive_party) {
        battle.g_battle.result = .lost;
        return;
    }

    if (battle.g_battle.phase == .select_action) {
        playerCheckReady();
        return;
    }

    // perform_action: pop next queue entry.
    if (battle.g_battle.cur_action >= battle.MAX_ACTIONQUEUE_ITEMS or
        battle.g_battle.action_queue[@intCast(battle.g_battle.cur_action)].dexterity == 0xFFFF)
    {
        // Round over.
        i = 0;
        while (i <= global.gpg.max_party_member_index) : (i += 1) {
            battle.g_battle.players[i].defending = false;
            battle.g_battle.players[i].pos = battle.g_battle.players[i].pos_original;
            battle.g_battle.players[i].state = .wait;
            battle.g_battle.players[i].action.action_type = .pass;
        }
        // Clear in-use items.
        for (&global.gpg.inventory) |*it| it.amount_in_use = 0;

        // Run poison scripts (fight.c L1611-L1662).
        backupStat();

        i = 0;
        while (i <= global.gpg.max_party_member_index) : (i += 1) {
            const role = global.gpg.party[i].player_role;
            var j: u32 = 0;
            while (j < global.MAX_POISONS) : (j += 1) {
                if (global.gpg.poison_status[j][i].poison_id != 0) {
                    global.gpg.poison_status[j][i].poison_script =
                        script.runTriggerScript(global.gpg.poison_status[j][i].poison_script, role);
                }
            }
            // Tick statuses.
            for (&global.gpg.player_status[role]) |*s| {
                if (s.* > 0) s.* -= 1;
            }
        }

        i = 0;
        while (battle.g_battle.max_enemy_index >= 0 and i <= @as(u32, @intCast(battle.g_battle.max_enemy_index))) : (i += 1) {
            var j: u32 = 0;
            while (j < global.MAX_POISONS) : (j += 1) {
                if (battle.g_battle.enemies[i].poisons[j].poison_id != 0) {
                    battle.g_battle.enemies[i].poisons[j].poison_script =
                        script.runTriggerScript(battle.g_battle.enemies[i].poisons[j].poison_script, @intCast(i));
                }
            }
            for (&battle.g_battle.enemies[i].status) |*s| {
                if (s.* > 0) s.* -= 1;
            }
        }

        postActionCheck(false);
        if (displayStatChange()) {
            battleDelay(8, 0, true);
        }

        // Hiding-time tick (fight.c L1670-L1678).
        if (battle.g_battle.hiding_time > 0) {
            battle.g_battle.hiding_time -= 1;
            if (battle.g_battle.hiding_time == 0) {
                video.backupScreen();
                battle.battleMakeScene();
                battle.battleFadeScene();
            }
        }

        // fight.c L1680-L1692: per-round enemy script_on_turn_start.
        if (battle.g_battle.hiding_time == 0) {
            i = 0;
            while (battle.g_battle.max_enemy_index >= 0 and i <= @as(u32, @intCast(battle.g_battle.max_enemy_index))) : (i += 1) {
                if (battle.g_battle.enemies[i].object_id == 0) continue;
                battle.g_battle.enemies[i].script_on_turn_start =
                    script.runTriggerScript(battle.g_battle.enemies[i].script_on_turn_start, @intCast(i));
            }
        }

        battle.g_battle.phase = .select_action;
        battle.g_battle.this_turn_coop = false;
        return;
    }

    const q = battle.g_battle.action_queue[@intCast(battle.g_battle.cur_action)];
    battle.g_battle.cur_action += 1;

    if (q.is_enemy) {
        const idx: u32 = q.index;
        if (battle.g_battle.hiding_time == 0 and
            battle.g_battle.enemies[idx].object_id != 0)
        {
            // fight.c L1719-L1724: per-action enemy script_on_ready (e.g.
            // boss talk lines) and fEnemyMoving guard.
            battle.g_battle.enemies[idx].script_on_ready =
                script.runTriggerScript(battle.g_battle.enemies[idx].script_on_ready, @intCast(idx));
            battle.g_battle.enemy_moving = true;
            enemyPerformAction(idx);
            battle.g_battle.enemy_moving = false;
        }
    } else if (battle.g_battle.players[q.index].state == .act) {
        // fight.c L1727-L1759: re-validate the action right before performing
        // it — HP/sleep/paralyzed players pass; confused players hit a mate
        // (or pass when dying).
        const pi: u16 = @intCast(q.index);
        const wPlayerRole = global.gpg.party[pi].player_role;

        if (global.gpg.g.player_roles.hp[wPlayerRole] == 0) {
            if (global.gpg.player_status[wPlayerRole][global.STATUS_PUPPET] == 0) {
                battle.g_battle.players[pi].action.action_type = .pass;
            }
        } else if (global.gpg.player_status[wPlayerRole][global.STATUS_SLEEP] > 0 or
            global.gpg.player_status[wPlayerRole][global.STATUS_PARALYZED] > 0)
        {
            battle.g_battle.players[pi].action.action_type = .pass;
        } else if (global.gpg.player_status[wPlayerRole][global.STATUS_CONFUSED] > 0) {
            battle.g_battle.players[pi].action.action_type =
                if (isPlayerDying(wPlayerRole)) .pass else .attack_mate;
        } else if (battle.g_battle.players[pi].action.action_type == .attack and
            battle.g_battle.players[pi].action.action_id != 0)
        {
            // fight.c L1748-L1751: a confirmed-auto attack starts the
            // chain so subsequent players inherit it.
            battle.g_battle.prev_player_auto_atk = true;
        } else if (battle.g_battle.prev_player_auto_atk) {
            // fight.c L1753-L1759: an earlier player set auto-atk this
            // round; replay it for this player.
            battle.g_battle.ui.cur_player_index = @intCast(pi);
            battle.g_battle.ui.selected_index = battle.g_battle.players[pi].action.target;
            battle.g_battle.ui.action_type = @intFromEnum(battle.BattleActionType.attack);
            commitAction(false);
        }

        battle.g_battle.moving_player_index = @intCast(pi);
        playerPerformAction(pi);
    }
}
