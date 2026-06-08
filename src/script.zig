// Copyright (c) 2009-2011, Wei Mingzhi <whistler_wmz@users.sf.net>.
// Copyright (c) 2011-2026, SDLPAL development team.
// All rights reserved.
//
// This file is part of SDLPAL.
//
// SDLPAL is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License, version 3
// as published by the Free Software Foundation.
//
// PAL_RunTriggerScript / PAL_RunAutoScript / PAL_InterpretInstruction —
// translated from script.c. Battle/menu/dialog/text opcodes call into
// stub helpers (Stage 6/7) that for now only update bookkeeping state.

const std = @import("std");
const global = @import("global.zig");
const util = @import("util.zig");
const video = @import("video.zig");
const input = @import("input.zig");
const palette_mod = @import("palette.zig");
const palcommon = @import("palcommon.zig");
const scene_mod = @import("scene.zig");
const res = @import("res.zig");
const text = @import("text.zig");

// Globals tracked across script invocations.
pub var g_script_success: bool = true;
pub var g_cur_equip_part: i32 = -1;
var g_last_event_object: u16 = 0;

// Apply a poison to enemy[idx] if not already present (script.c L1196-L1216).
fn applyPoisonToEnemyAt(idx: u16, poison_id: u16, ev_id: u16) void {
    const battle_mod = @import("battle.zig");
    var j: u32 = 0;
    while (j < global.MAX_POISONS) : (j += 1) {
        if (battle_mod.g_battle.enemies[idx].poisons[j].poison_id == poison_id) return;
    }
    j = 0;
    while (j < global.MAX_POISONS) : (j += 1) {
        if (battle_mod.g_battle.enemies[idx].poisons[j].poison_id == 0) {
            battle_mod.g_battle.enemies[idx].poisons[j].poison_id = poison_id;
            battle_mod.g_battle.enemies[idx].poisons[j].poison_script =
                runTriggerScript(global.gpg.g.objects[poison_id].poison().enemy_script, ev_id);
            return;
        }
    }
}

// --- Helpers ---

inline fn rolesPtr() [*]u16 {
    return @ptrCast(@alignCast(&global.gpg.g.player_roles));
}

inline fn equipEffectPtr(part: usize) [*]u16 {
    return @ptrCast(@alignCast(&global.gpg.equipment_effect[part]));
}

// PAL_NPCWalkTo — walk an NPC towards (x, y). Returns true if arrived.
fn npcWalkTo(event_object_id: u16, x: u16, y: u16, h: u16, speed: i32) bool {
    if (event_object_id == 0 or event_object_id > global.gpg.g.event_objects.len) return false;
    const p = &global.gpg.g.event_objects[event_object_id - 1];

    const px: i32 = @intCast(@as(u32, p.x));
    const py: i32 = @intCast(@as(u32, p.y));
    const tx: i32 = @intCast(@as(u32, x) * 32 + @as(u32, h) * 16);
    const ty: i32 = @intCast(@as(u32, y) * 16 + @as(u32, h) * 8);

    const x_offset = tx - px;
    const y_offset = ty - py;

    // Translation of script.c PAL_NPCWalkTo:
    //   if (yOffset < 0) direction = (xOffset < 0) ? kDirWest  : kDirNorth;
    //   else             direction = (xOffset < 0) ? kDirSouth : kDirEast;
    if (y_offset < 0) {
        p.direction = if (x_offset < 0) 1 else 2; // West / North
    } else {
        p.direction = if (x_offset < 0) 0 else 3; // South / East
    }

    if (@abs(x_offset) < 2 * speed or @abs(y_offset) < 2 * speed) {
        p.x = @truncate(@as(u32, @bitCast(tx)));
        p.y = @truncate(@as(u32, @bitCast(ty)));
    } else {
        scene_mod.npcWalkOneStep(event_object_id, speed);
    }

    if (@as(i32, @intCast(@as(u32, p.x))) == tx and @as(i32, @intCast(@as(u32, p.y))) == ty) {
        p.current_frame_num = 0;
        return true;
    }
    return false;
}

// PAL_PartyWalkTo — translation of script.c PAL_PartyWalkTo.
fn partyWalkTo(x: u16, y: u16, h: u16, speed: i32) void {
    var x_offset: i32 = @as(i32, x) * 32 + @as(i32, h) * 16 - global.palX(global.gpg.viewport) - global.palX(global.gpg.party_offset);
    var y_offset: i32 = @as(i32, y) * 16 + @as(i32, h) * 8 - global.palY(global.gpg.viewport) - global.palY(global.gpg.party_offset);

    var t: u32 = 0;

    while (x_offset != 0 or y_offset != 0) {
        if (util.shouldQuit()) return;
        util.delayUntil(t);
        t = util.getTicks() + global.FRAME_TIME;

        var i: i32 = 3;
        while (i >= 0) : (i -= 1) {
            global.gpg.trail[@intCast(i + 1)] = global.gpg.trail[@intCast(i)];
        }
        global.gpg.trail[0].direction = global.gpg.party_direction;
        global.gpg.trail[0].x = @bitCast(@as(i16, @truncate(global.palX(global.gpg.viewport) + global.palX(global.gpg.party_offset))));
        global.gpg.trail[0].y = @bitCast(@as(i16, @truncate(global.palY(global.gpg.viewport) + global.palY(global.gpg.party_offset))));

        if (y_offset < 0) {
            global.gpg.party_direction = if (x_offset < 0) 1 else 2;
        } else {
            global.gpg.party_direction = if (x_offset < 0) 0 else 3;
        }

        var dx: i32 = global.palX(global.gpg.viewport);
        var dy: i32 = global.palY(global.gpg.viewport);

        if (@abs(x_offset) <= speed * 2) {
            dx += x_offset;
        } else {
            dx += speed * (if (x_offset < 0) @as(i32, -2) else @as(i32, 2));
        }

        if (@abs(y_offset) <= speed) {
            dy += y_offset;
        } else {
            dy += speed * (if (y_offset < 0) @as(i32, -1) else @as(i32, 1));
        }

        global.gpg.viewport = global.palXY(@truncate(dx), @truncate(dy));

        scene_mod.updatePartyGestures(true);
        @import("play.zig").gameUpdate(false);
        scene_mod.makeScene();
        video.updateScreen(null);

        x_offset = @as(i32, x) * 32 + @as(i32, h) * 16 - global.palX(global.gpg.viewport) - global.palX(global.gpg.party_offset);
        y_offset = @as(i32, y) * 16 + @as(i32, h) * 8 - global.palY(global.gpg.viewport) - global.palY(global.gpg.party_offset);
    }

    scene_mod.updatePartyGestures(false);
}

// PAL_PartyRideEventObject — ride an event object across the map.
// Mirrors script.c L203's PAL_PartyRideEventObject: viewport-relative offsets,
// trail bookkeeping for follower lag, party-direction updates, and a final
// step that snaps dx/dy to the remaining offset so we never overshoot.
fn partyRideEventObject(event_object_id: u16, x: u16, y: u16, h: u16, speed: i32) void {
    if (event_object_id == 0 or event_object_id > global.gpg.g.event_objects.len) return;
    const p = &global.gpg.g.event_objects[event_object_id - 1];

    var x_offset: i32 = @as(i32, x) * 32 + @as(i32, h) * 16 - global.palX(global.gpg.viewport) - global.palX(global.gpg.party_offset);
    var y_offset: i32 = @as(i32, y) * 16 + @as(i32, h) * 8 - global.palY(global.gpg.viewport) - global.palY(global.gpg.party_offset);

    var t: u32 = 0;

    while (x_offset != 0 or y_offset != 0) {
        if (util.shouldQuit()) return;
        util.delayUntil(t);
        t = util.getTicks() + global.FRAME_TIME;

        if (y_offset < 0) {
            global.gpg.party_direction = if (x_offset < 0) 1 else 2;
        } else {
            global.gpg.party_direction = if (x_offset < 0) 0 else 3;
        }

        const dx: i32 = if (@abs(x_offset) > speed * 2)
            speed * (if (x_offset < 0) @as(i32, -2) else @as(i32, 2))
        else
            x_offset;

        const dy: i32 = if (@abs(y_offset) > speed)
            speed * (if (y_offset < 0) @as(i32, -1) else @as(i32, 1))
        else
            y_offset;

        // Push the party trail so followers lag behind the leader.
        var i: i32 = 3;
        while (i >= 0) : (i -= 1) {
            global.gpg.trail[@intCast(i + 1)] = global.gpg.trail[@intCast(i)];
        }
        global.gpg.trail[0].direction = global.gpg.party_direction;
        global.gpg.trail[0].x = @bitCast(@as(i16, @truncate(global.palX(global.gpg.viewport) + dx + global.palX(global.gpg.party_offset))));
        global.gpg.trail[0].y = @bitCast(@as(i16, @truncate(global.palY(global.gpg.viewport) + dy + global.palY(global.gpg.party_offset))));

        // Move viewport and ridden object together so the party stays atop it.
        global.gpg.viewport = global.palXY(
            @truncate(global.palX(global.gpg.viewport) + dx),
            @truncate(global.palY(global.gpg.viewport) + dy),
        );
        p.x = @bitCast(@as(u16, @truncate(@as(u32, @bitCast(@as(i32, @as(i16, @bitCast(p.x))) + dx)))));
        p.y = @bitCast(@as(u16, @truncate(@as(u32, @bitCast(@as(i32, @as(i16, @bitCast(p.y))) + dy)))));

        @import("play.zig").gameUpdate(false);
        scene_mod.makeScene();
        video.updateScreen(null);

        x_offset = @as(i32, x) * 32 + @as(i32, h) * 16 - global.palX(global.gpg.viewport) - global.palX(global.gpg.party_offset);
        y_offset = @as(i32, y) * 16 + @as(i32, h) * 8 - global.palY(global.gpg.viewport) - global.palY(global.gpg.party_offset);
    }
}

// PAL_MonsterChasePlayer — script.c L310. Move an event-object monster
// toward the party every frame. fFloating skips obstacle checks (flying
// monsters). When wChaseRange == 0 (Exorcism-Fragrance), the monster spins
// in place changing direction every two frames.
fn monsterChasePlayer(event_object_id: u16, speed: u16, chase_range: u16, floating: bool) void {
    if (event_object_id == 0 or event_object_id > global.gpg.g.event_objects.len) return;
    const evt_obj = &global.gpg.g.event_objects[event_object_id - 1];

    var monster_speed: u16 = 0;

    if (global.gpg.chase_range != 0) {
        const target_x: i32 = global.palX(global.gpg.viewport) + global.palX(global.gpg.party_offset) - @as(i32, @bitCast(@as(u32, evt_obj.x)));
        const target_y: i32 = global.palY(global.gpg.viewport) + global.palY(global.gpg.party_offset) - @as(i32, @bitCast(@as(u32, evt_obj.y)));

        var x: i32 = target_x;
        var y: i32 = target_y;
        if (x == 0) x = if (util.randomLong(0, 1) != 0) -1 else 1;
        if (y == 0) y = if (util.randomLong(0, 1) != 0) -1 else 1;

        var prevx: u16 = evt_obj.x;
        var prevy: u16 = evt_obj.y;

        const i_mod: u16 = prevx % 32;
        const j_mod: u16 = prevy % 16;

        prevx /= 32;
        prevy /= 16;
        var l: u16 = 0;

        if (i_mod + j_mod * 2 >= 16) {
            if (i_mod + j_mod * 2 >= 48) {
                prevx +%= 1;
                prevy +%= 1;
            } else if (32 - @as(i32, i_mod) + @as(i32, j_mod) * 2 < 16) {
                prevx +%= 1;
            } else if (32 - @as(i32, i_mod) + @as(i32, j_mod) * 2 < 48) {
                l = 1;
            } else {
                prevy +%= 1;
            }
        }

        prevx = prevx * 32 + l * 16;
        prevy = prevy * 16 + l * 8;

        // Is the party near?
        const dist: i32 = (if (x < 0) -x else x) + (if (y < 0) -y else y) * 2;
        if (dist < @as(i32, chase_range) * 32 * @as(i32, global.gpg.chase_range)) {
            // Direction (palcommon.h: kDirSouth=0, kDirWest=1, kDirNorth=2,
            // kDirEast=3). x>0 means the party is east of the monster.
            if (x < 0) {
                evt_obj.direction = if (y < 0) 1 else 0; // West / South
            } else {
                evt_obj.direction = if (y < 0) 2 else 3; // North / East
            }

            // Step.
            var nx: i32 = @bitCast(@as(u32, evt_obj.x));
            var ny: i32 = @bitCast(@as(u32, evt_obj.y));
            if (x != 0) nx += @divTrunc(x, if (x < 0) -x else x) * 16;
            if (y != 0) ny += @divTrunc(y, if (y < 0) -y else y) * 8;

            if (floating) {
                monster_speed = speed;
            } else {
                if (!scene_mod.checkObstacle(global.palXY(@truncate(nx), @truncate(ny)), true, event_object_id)) {
                    monster_speed = speed;
                } else {
                    evt_obj.x = prevx;
                    evt_obj.y = prevy;
                }

                // Wiggle test the four corners — revert if any blocks.
                var wig: i32 = 0;
                while (wig < 4) : (wig += 1) {
                    switch (wig) {
                        0 => { evt_obj.x -%= 4; evt_obj.y +%= 2; },
                        1 => { evt_obj.x -%= 4; evt_obj.y -%= 2; },
                        2 => { evt_obj.x +%= 4; evt_obj.y -%= 2; },
                        3 => { evt_obj.x +%= 4; evt_obj.y +%= 2; },
                        else => unreachable,
                    }
                    if (scene_mod.checkObstacle(global.palXY(@bitCast(@as(u16, evt_obj.x)), @bitCast(@as(u16, evt_obj.y))), false, 0)) {
                        evt_obj.x = prevx;
                        evt_obj.y = prevy;
                    }
                }
            }
        }
    } else {
        // Exorcism-Fragrance: spin in place every other frame.
        if ((global.gpg.frame_num & 1) != 0) {
            evt_obj.direction +%= 1;
            if (evt_obj.direction > 3) evt_obj.direction = 0;
        }
    }

    scene_mod.npcWalkOneStep(event_object_id, monster_speed);
}

// Helper: decompress an FBP chunk into an owned buffer (320×200).
fn loadFbpChunk(chunk_num: u16) ?[]u8 {
    const fbp = global.gpg.f.fbp orelse return null;
    const compressed = fbp.getChunkData(chunk_num) catch return null;
    const decomp_size = fbp.getDecompressedSize(chunk_num, false) catch return null;
    const buf = global.allocator.alloc(u8, @max(decomp_size, 320 * 200)) catch return null;
    _ = @import("yj1.zig").decompress(compressed, buf) catch {
        global.allocator.free(buf);
        return null;
    };
    return buf;
}

// PAL_ShowFBP — ending.c L49. Decompress chunk, optionally cross-fade from
// current screen to it over 16 × 6 steps, then commit. Audio/sprite-effect
// branch (gxCurEffectSprite) skipped — no audio in this port.
fn showFbp(chunk_num: u16, fade: u16) void {
    const buf = loadFbpChunk(chunk_num) orelse return;
    defer global.allocator.free(buf);

    if (fade != 0) {
        const rg_index = [_]usize{ 0, 3, 1, 5, 2, 4 };
        var fade_speed: u32 = @as(u32, fade) + 1;
        fade_speed *= 10;

        // SDLPAL allocates a temporary surface for the new image; we use a
        // local buffer and blit pixel-by-pixel.
        var p_pixels: [320 * 200]u8 = undefined;
        @memcpy(p_pixels[0..@min(buf.len, 320 * 200)], buf[0..@min(buf.len, 320 * 200)]);

        video.backupScreen();

        var i: u32 = 0;
        while (i < 16) : (i += 1) {
            var j: u32 = 0;
            while (j < 6) : (j += 1) {
                var k: usize = rg_index[j];
                while (k < 320 * 200) : (k += 6) {
                    const a = p_pixels[k];
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
                @memcpy(&video.screen_pixels, &video.screen_bak_pixels);
                video.updateScreen(null);
                util.delay(fade_speed);
            }
        }
    }

    // HACKHACK: matches SDLPAL's "ending picture" exception (chunk 49).
    if (chunk_num != 49) {
        _ = palcommon.fbpBlitToSurface(buf[0..@min(buf.len, 320 * 200)], &video.screen);
    }
    video.updateScreen(null);
}

// PAL_ScrollFBP — ending.c L152. Scroll a 320×200 FBP chunk into the screen
// from top or bottom, blending against the backup buffer for the parts not
// yet revealed.
fn scrollFbp(chunk_num: u16, scroll_speed_in: u16, scroll_down: bool) void {
    const buf = loadFbpChunk(chunk_num) orelse return;
    defer global.allocator.free(buf);
    var p_pixels: [320 * 200]u8 = undefined;
    @memcpy(p_pixels[0..@min(buf.len, 320 * 200)], buf[0..@min(buf.len, 320 * 200)]);

    video.backupScreen();

    var scroll_speed: u32 = scroll_speed_in;
    if (scroll_speed == 0) scroll_speed = 1;

    var l: u32 = 0;
    while (l < 220) : (l += 1) {
        const i: u32 = if (l > 200) 200 else l;

        // Build composite: backup buffer occupies (200 - i) rows, new image i.
        var dst_pixels: [320 * 200]u8 = undefined;
        if (scroll_down) {
            // Top (200 - i) rows = backup; bottom i rows = new image (top i rows).
            const old_h = 200 - i;
            // backup rows 0..old_h → dst rows i..200
            var y: u32 = 0;
            while (y < old_h) : (y += 1) {
                @memcpy(dst_pixels[(i + y) * 320 ..][0..320], video.screen_bak_pixels[y * 320 ..][0..320]);
            }
            // new rows (200-i)..200 → dst rows 0..i
            y = 0;
            while (y < i) : (y += 1) {
                @memcpy(dst_pixels[y * 320 ..][0..320], p_pixels[(200 - i + y) * 320 ..][0..320]);
            }
        } else {
            const old_h = 200 - i;
            // backup rows i..200 → dst rows 0..old_h
            var y: u32 = 0;
            while (y < old_h) : (y += 1) {
                @memcpy(dst_pixels[y * 320 ..][0..320], video.screen_bak_pixels[(i + y) * 320 ..][0..320]);
            }
            // new rows 0..i → dst rows old_h..200
            y = 0;
            while (y < i) : (y += 1) {
                @memcpy(dst_pixels[(old_h + y) * 320 ..][0..320], p_pixels[y * 320 ..][0..320]);
            }
        }

        @memcpy(&video.screen_pixels, &dst_pixels);
        scene_mod.applyWave();
        video.updateScreen(null);

        if (global.gpg.need_to_fade_in) {
            palette_mod.fadeIn(@intCast(global.gpg.num_palette), global.gpg.night_palette, 1);
            global.gpg.need_to_fade_in = false;
        }

        util.delay(800 / scroll_speed);
    }

    @memcpy(&video.screen_pixels, &p_pixels);
    video.updateScreen(null);
}

// PAL_EndingAnimation — ending.c L281. The 400-frame "beast climbing
// through clouds" finale (DOS chunks 61/62 from FBP, 571/572 sprites in MGO).
fn endingAnimation() void {
    const fbp = global.gpg.f.fbp orelse return;
    const mgo = global.gpg.f.mgo orelse return;

    // Upper / lower background scenes (320×200 each).
    const upper = loadFbpChunk(61) orelse return;
    defer global.allocator.free(upper);
    const lower = loadFbpChunk(62) orelse return;
    defer global.allocator.free(lower);
    _ = fbp;

    // Beast sprite (chunk 571) + girl (chunk 572).
    const yj1 = @import("yj1.zig");
    const beast_compressed = mgo.getChunkData(571) catch return;
    const beast_size = mgo.getDecompressedSize(571, false) catch return;
    const beast = global.allocator.alloc(u8, @max(beast_size, 64000)) catch return;
    defer global.allocator.free(beast);
    _ = yj1.decompress(beast_compressed, beast) catch return;

    const girl_compressed = mgo.getChunkData(572) catch return;
    const girl_size = mgo.getDecompressedSize(572, false) catch return;
    const girl = global.allocator.alloc(u8, @max(girl_size, 6000)) catch return;
    defer global.allocator.free(girl);
    _ = yj1.decompress(girl_compressed, girl) catch return;

    global.gpg.screen_wave = 2;
    var y_pos_girl: i32 = 180;

    var i: u32 = 0;
    while (i < 400) : (i += 1) {
        // Background composite: upper scrolls up by i/2, lower scrolls in.
        const split: u32 = i / 2;

        var dst: [320 * 200]u8 = undefined;
        // Top split rows = lower buffer rows 0..(200-split)? No — match SDLPAL:
        // dst[split..200] = pLower[0..200-split]; dst[0..split] = pUpper[200-split..200].
        // Effectively: lower scrolls down (revealing top), upper rises into view.
        if (split > 0) {
            // Top split rows of dst = pUpper rows [200-split..200].
            @memcpy(dst[0 .. split * 320], upper[(200 - split) * 320 .. 200 * 320]);
        }
        @memcpy(dst[split * 320 .. 200 * 320], lower[0 .. (200 - split) * 320]);

        @memcpy(&video.screen_pixels, &dst);
        scene_mod.applyWave();

        // Beast sprite frames 0 and 1.
        if (palcommon.spriteGetFrame(beast, 0)) |bf0| {
            _ = palcommon.rleBlitToSurface(bf0, &video.screen, global.palXY(0, @truncate(-400 + @as(i32, @intCast(i)))));
        }
        if (palcommon.spriteGetFrame(beast, 1)) |bf1| {
            _ = palcommon.rleBlitToSurface(bf1, &video.screen, global.palXY(0, @truncate(-200 + @as(i32, @intCast(i)))));
        }

        // Girl rises until y=80.
        y_pos_girl -= @as(i32, @intCast(i & 1));
        if (y_pos_girl < 80) y_pos_girl = 80;
        const girl_frame: i32 = @intCast((util.getTicks() / 50) % 4);
        if (palcommon.spriteGetFrame(girl, girl_frame)) |gf| {
            _ = palcommon.rleBlitToSurface(gf, &video.screen, global.palXY(220, @truncate(y_pos_girl)));
        }

        video.updateScreen(null);
        if (global.gpg.need_to_fade_in) {
            palette_mod.fadeIn(@intCast(global.gpg.num_palette), global.gpg.night_palette, 1);
            global.gpg.need_to_fade_in = false;
        }
        util.delay(50);
    }

    global.gpg.screen_wave = 0;
}

// --- Top-level entry points ---

// PAL_RunAutoScript — runs the autoscript of an event object, one instruction per frame.
pub fn runAutoScript(script_entry_in: u16, event_object_id: u16) u16 {
    var w_script_entry = script_entry_in;
    while (true) {
        const p_script = &global.gpg.g.script_entries[w_script_entry];
        traceAuto(event_object_id, w_script_entry, p_script.operation, p_script.operand[0], p_script.operand[1], p_script.operand[2]);
        const p_evt: ?*global.EventObject = if (event_object_id != 0)
            &global.gpg.g.event_objects[event_object_id - 1]
        else
            null;

        switch (p_script.operation) {
            0x0000 => return w_script_entry,
            0x0001 => return w_script_entry +% 1,
            0x0002 => {
                if (p_evt) |pe| {
                    if (p_script.operand[1] == 0 or blk: {
                        pe.script_idle_frame_count_auto +%= 1;
                        break :blk pe.script_idle_frame_count_auto < p_script.operand[1];
                    }) {
                        return p_script.operand[0];
                    } else {
                        pe.script_idle_frame_count_auto = 0;
                        return w_script_entry +% 1;
                    }
                } else {
                    return p_script.operand[0];
                }
            },
            0x0003 => {
                if (p_evt) |pe| {
                    if (p_script.operand[1] == 0 or blk: {
                        pe.script_idle_frame_count_auto +%= 1;
                        break :blk pe.script_idle_frame_count_auto < p_script.operand[1];
                    }) {
                        w_script_entry = p_script.operand[0];
                        continue;
                    } else {
                        pe.script_idle_frame_count_auto = 0;
                        return w_script_entry +% 1;
                    }
                } else {
                    w_script_entry = p_script.operand[0];
                    continue;
                }
            },
            0x0004 => {
                _ = runTriggerScript(p_script.operand[0], if (p_script.operand[1] != 0) p_script.operand[1] else event_object_id);
                return w_script_entry +% 1;
            },
            0x0006 => {
                if (util.randomLong(1, 100) >= @as(i32, p_script.operand[0])) {
                    if (p_script.operand[1] != 0) {
                        w_script_entry = p_script.operand[1];
                        continue;
                    }
                    return w_script_entry;
                } else {
                    return w_script_entry +% 1;
                }
            },
            0x0009 => {
                if (p_evt) |pe| {
                    pe.script_idle_frame_count_auto +%= 1;
                    if (pe.script_idle_frame_count_auto >= p_script.operand[0]) {
                        pe.script_idle_frame_count_auto = 0;
                        return w_script_entry +% 1;
                    }
                    return w_script_entry;
                } else {
                    return w_script_entry +% 1;
                }
            },
            0xFFFF, 0x00A7 => return w_script_entry +% 1,
            else => return interpretInstruction(w_script_entry, event_object_id),
        }
    }
}

// PAL_RunTriggerScript — runs a trigger script (synchronous, may take many frames).
pub fn runTriggerScript(script_entry_in: u16, event_object_id_in: u16) u16 {
    var w_script_entry = script_entry_in;
    var w_next_script_entry = w_script_entry;
    var f_ended = false;

    var event_object_id = event_object_id_in;
    if (event_object_id == 0xFFFF) event_object_id = g_last_event_object;
    g_last_event_object = event_object_id;

    g_script_success = true;
    text.dialogSetDelayTime(3);

    while (w_script_entry != 0 and !f_ended) {
        const p_script = &global.gpg.g.script_entries[w_script_entry];
        const p_evt_obj: ?*global.EventObject = if (event_object_id != 0)
            &global.gpg.g.event_objects[event_object_id - 1]
        else
            null;

        switch (p_script.operation) {
            0x0000 => {
                f_ended = true;
            },
            0x0001 => {
                f_ended = true;
                w_next_script_entry = w_script_entry +% 1;
            },
            0x0002 => {
                if (p_evt_obj) |pe| {
                    if (p_script.operand[1] == 0 or blk: {
                        pe.script_idle_frame +%= 1;
                        break :blk pe.script_idle_frame < p_script.operand[1];
                    }) {
                        f_ended = true;
                        w_next_script_entry = p_script.operand[0];
                    } else {
                        pe.script_idle_frame = 0;
                        w_script_entry +%= 1;
                    }
                } else {
                    f_ended = true;
                    w_next_script_entry = p_script.operand[0];
                }
            },
            0x0003 => {
                if (p_evt_obj) |pe| {
                    if (p_script.operand[1] == 0 or blk: {
                        pe.script_idle_frame +%= 1;
                        break :blk pe.script_idle_frame < p_script.operand[1];
                    }) {
                        w_script_entry = p_script.operand[0];
                    } else {
                        pe.script_idle_frame = 0;
                        w_script_entry +%= 1;
                    }
                } else {
                    w_script_entry = p_script.operand[0];
                }
            },
            0x0004 => {
                _ = runTriggerScript(p_script.operand[0], if (p_script.operand[1] == 0) event_object_id else p_script.operand[1]);
                w_script_entry +%= 1;
            },
            0x0005 => {
                // Redraw screen — SDLPAL calls PAL_ClearDialog(TRUE) first so
                // the user has a chance to read the dialog before it's wiped.
                text.clearDialog(true);
                if (!global.gpg.in_battle) {
                    if (p_script.operand[2] != 0) scene_mod.updatePartyGestures(false);
                    scene_mod.makeScene();
                    video.updateScreen(null);
                    util.delay(if (p_script.operand[1] == 0) 60 else p_script.operand[1] * 60);
                }
                w_script_entry +%= 1;
            },
            0x0006 => {
                if (util.randomLong(1, 100) >= @as(i32, p_script.operand[0])) {
                    w_script_entry = p_script.operand[1];
                } else {
                    w_script_entry +%= 1;
                }
            },
            0x0007 => {
                // PAL_StartBattle — operand[0]=enemy team, operand[1]=onLost script,
                // operand[2]=onFleed script (zero means: not allowed to flee, i.e. boss).
                const result = @import("battle.zig").startBattle(p_script.operand[0], p_script.operand[2] == 0);
                if (result == .lost and p_script.operand[1] != 0) {
                    w_script_entry = p_script.operand[1];
                } else if (result == .fleed and p_script.operand[2] != 0) {
                    w_script_entry = p_script.operand[2];
                } else {
                    w_script_entry +%= 1;
                }
                global.gpg.auto_battle = false;
            },
            0x0008 => {
                w_script_entry +%= 1;
                w_next_script_entry = w_script_entry;
            },
            0x0009 => {
                // wait for N frames — SDLPAL calls PAL_ClearDialog(TRUE) so
                // the user can read the previous dialog before the wait runs
                // and (more importantly) so the dialog box + waiting icon are
                // restored away before the scene is redrawn.
                text.clearDialog(true);
                var i: u32 = 0;
                const cnt: u32 = if (p_script.operand[0] == 0) 1 else p_script.operand[0];
                var time = util.getTicks() + global.FRAME_TIME;
                while (i < cnt) : (i += 1) {
                    if (util.shouldQuit()) break;
                    util.delayUntil(time);
                    time = util.getTicks() + global.FRAME_TIME;
                    if (p_script.operand[2] != 0) scene_mod.updatePartyGestures(false);
                    @import("play.zig").gameUpdate(p_script.operand[1] != 0);
                    scene_mod.makeScene();
                    video.updateScreen(null);
                }
                w_script_entry +%= 1;
            },
            0x000A => {
                // Goto operand[0] if player chose "no".
                text.clearDialog(false);
                if (!@import("uigame.zig").confirmMenu()) {
                    w_script_entry = p_script.operand[0];
                } else {
                    w_script_entry +%= 1;
                }
            },
            0x003B => {
                // Show dialog in the middle of the screen.
                text.clearDialog(true);
                text.startDialog(.center, @intCast(p_script.operand[0] & 0xff), 0, p_script.operand[2] != 0);
                w_script_entry +%= 1;
            },
            0x003C => {
                // Show dialog in the upper part of the screen.
                text.clearDialog(true);
                text.startDialog(.upper, @intCast(p_script.operand[1] & 0xff), p_script.operand[0], p_script.operand[2] != 0);
                w_script_entry +%= 1;
            },
            0x003D => {
                // Show dialog in the lower part of the screen.
                text.clearDialog(true);
                text.startDialog(.lower, @intCast(p_script.operand[1] & 0xff), p_script.operand[0], p_script.operand[2] != 0);
                w_script_entry +%= 1;
            },
            0x003E => {
                // Show text in a window at the center of the screen.
                text.clearDialog(true);
                text.startDialog(.center_window, @intCast(p_script.operand[0] & 0xff), 0, false);
                w_script_entry +%= 1;
            },
            0x008E => {
                text.clearDialog(true);
                video.restoreScreen();
                video.updateScreen(null);
                w_script_entry +%= 1;
            },
            0xFFFF => {
                // Print dialog text.
                text.showDialogText(text.getMsg(p_script.operand[0]));
                w_script_entry +%= 1;
            },
            else => {
                text.clearDialog(true);
                w_script_entry = interpretInstruction(w_script_entry, event_object_id);
            },
        }
    }

    text.endDialog();
    g_cur_equip_part = -1;
    return w_next_script_entry;
}

// PAL_InterpretInstruction — execute one opcode and return the next script entry.
fn interpretInstruction(script_entry_in: u16, event_object_id: u16) u16 {
    var w_script_entry = script_entry_in;
    const p_script = &global.gpg.g.script_entries[w_script_entry];

    const p_evt_obj: ?*global.EventObject = if (event_object_id != 0)
        &global.gpg.g.event_objects[event_object_id - 1]
    else
        null;

    var p_current: ?*global.EventObject = null;
    var w_cur_event_object_id: u16 = 0;
    if (p_script.operand[0] == 0 or p_script.operand[0] == 0xFFFF) {
        p_current = p_evt_obj;
        w_cur_event_object_id = event_object_id;
    } else {
        var idx: u32 = p_script.operand[0] - 1;
        if (idx > 0x9000) idx -= 0x9000;
        if (idx < global.gpg.g.event_objects.len) {
            p_current = &global.gpg.g.event_objects[idx];
        }
        w_cur_event_object_id = p_script.operand[0];
    }

    var i_player_role: u16 = 0;
    if (p_script.operand[0] < global.MAX_PLAYABLE_PLAYER_ROLES) {
        i_player_role = global.gpg.party[p_script.operand[0]].player_role;
    } else {
        i_player_role = global.gpg.party[0].player_role;
    }

    switch (p_script.operation) {
        0x000B, 0x000C, 0x000D, 0x000E => {
            if (p_evt_obj) |pe| {
                pe.direction = p_script.operation - 0x000B;
                scene_mod.npcWalkOneStep(event_object_id, 2);
            }
        },
        0x000F => {
            if (p_evt_obj) |pe| {
                if (p_script.operand[0] != 0xFFFF) pe.direction = p_script.operand[0];
                if (p_script.operand[1] != 0xFFFF) pe.current_frame_num = p_script.operand[1];
            }
        },
        0x0010 => {
            if (!npcWalkTo(event_object_id, p_script.operand[0], p_script.operand[1], p_script.operand[2], 3)) {
                if (w_script_entry > 0) w_script_entry -= 1;
            }
        },
        0x0011 => {
            const xor_bit: u16 = @intCast((@as(u32, event_object_id) & 1) ^ (global.gpg.frame_num & 1));
            traceWalk(event_object_id, w_script_entry, global.gpg.frame_num, xor_bit, p_script.operand[0], p_script.operand[1], p_script.operand[2]);
            if (xor_bit != 0) {
                if (!npcWalkTo(event_object_id, p_script.operand[0], p_script.operand[1], p_script.operand[2], 2)) {
                    if (w_script_entry > 0) w_script_entry -= 1;
                }
            } else {
                if (w_script_entry > 0) w_script_entry -= 1;
            }
        },
        0x0012 => {
            if (p_current) |pc| {
                pc.x = @bitCast(@as(i16, @truncate(@as(i32, @bitCast(@as(u32, p_script.operand[1]))) + global.palX(global.gpg.viewport) + global.palX(global.gpg.party_offset))));
                pc.y = @bitCast(@as(i16, @truncate(@as(i32, @bitCast(@as(u32, p_script.operand[2]))) + global.palY(global.gpg.viewport) + global.palY(global.gpg.party_offset))));
            }
        },
        0x0013 => {
            if (p_current) |pc| {
                pc.x = p_script.operand[1];
                pc.y = p_script.operand[2];
            }
        },
        0x0014 => {
            if (p_evt_obj) |pe| {
                pe.current_frame_num = p_script.operand[0];
                pe.direction = 0;
            }
        },
        0x0015 => {
            global.gpg.party_direction = p_script.operand[0];
            global.gpg.party[p_script.operand[2]].frame =
                @intCast(@as(u32, global.gpg.party_direction) * 3 + p_script.operand[1]);
        },
        0x0016 => {
            if (p_script.operand[0] != 0) {
                if (p_current) |pc| {
                    pc.direction = p_script.operand[1];
                    pc.current_frame_num = p_script.operand[2];
                }
            }
        },
        0x0017 => {
            // Set the player's extra attribute (equipment effect).
            const part = @as(usize, p_script.operand[0]) - 0xB;
            if (part <= global.MAX_PLAYER_EQUIPMENTS) {
                const p = equipEffectPtr(part);
                p[@as(usize, p_script.operand[1]) * global.MAX_PLAYER_ROLES + event_object_id] = p_script.operand[2];
            }
        },
        0x0018 => {
            // Equip the selected item.
            const part: usize = @as(usize, p_script.operand[0]) - 0x0B;
            g_cur_equip_part = @intCast(part);
            // Remove existing equipment effect — Stage 6 will run wScriptOnEquip.
            // (We model only the inventory swap here.)
            if (part <= global.MAX_PLAYER_EQUIPMENTS) {
                const equipped = global.gpg.g.player_roles.equipment[part][event_object_id];
                if (equipped != p_script.operand[1]) {
                    global.gpg.g.player_roles.equipment[part][event_object_id] = p_script.operand[1];
                    _ = global.addItemToInventory(p_script.operand[1], -1);
                    if (equipped != 0) _ = global.addItemToInventory(equipped, 1);
                    global.gpg.last_unequipped_item = equipped;
                }
            }
        },
        0x0019 => {
            // Increase/decrease player's attribute.
            const role: u16 = if (p_script.operand[2] == 0) event_object_id else p_script.operand[2] - 1;
            const p = rolesPtr();
            const idx = @as(usize, p_script.operand[0]) * global.MAX_PLAYER_ROLES + role;
            p[idx] +%= p_script.operand[1];
        },
        0x001A => {
            // Set player's stat.
            const role: u16 = if (p_script.operand[2] == 0) event_object_id else p_script.operand[2] - 1;
            const p = if (g_cur_equip_part != -1) equipEffectPtr(@intCast(g_cur_equip_part)) else rolesPtr();
            const idx = @as(usize, p_script.operand[0]) * global.MAX_PLAYER_ROLES + role;
            p[idx] = p_script.operand[1];
        },
        0x001B => {
            // Increase/decrease player's HP.
            if (p_script.operand[0] != 0) {
                g_script_success = false;
                var i: usize = 0;
                while (i <= global.gpg.max_party_member_index) : (i += 1) {
                    const w = global.gpg.party[i].player_role;
                    if (global.increaseHPMP(w, @bitCast(p_script.operand[1]), 0)) g_script_success = true;
                }
            } else {
                if (!global.increaseHPMP(event_object_id, @bitCast(p_script.operand[1]), 0)) g_script_success = false;
            }
        },
        0x001C => {
            // Increase/decrease player's MP.
            if (p_script.operand[0] != 0) {
                var i: usize = 0;
                while (i <= global.gpg.max_party_member_index) : (i += 1) {
                    const w = global.gpg.party[i].player_role;
                    _ = global.increaseHPMP(w, 0, @bitCast(p_script.operand[1]));
                }
            } else {
                if (!global.increaseHPMP(event_object_id, 0, @bitCast(p_script.operand[1]))) g_script_success = false;
            }
        },
        0x001D => {
            // Increase/decrease player's HP and MP.
            if (p_script.operand[0] != 0) {
                var i: usize = 0;
                while (i <= global.gpg.max_party_member_index) : (i += 1) {
                    const w = global.gpg.party[i].player_role;
                    _ = global.increaseHPMP(w, @bitCast(p_script.operand[1]), @bitCast(p_script.operand[1]));
                }
            } else {
                if (!global.increaseHPMP(event_object_id, @bitCast(p_script.operand[1]), @bitCast(p_script.operand[1]))) g_script_success = false;
            }
        },
        0x001E => {
            const delta: i32 = @as(i32, @bitCast(@as(u32, p_script.operand[0])));
            if (delta < 0 and global.gpg.cash < @as(u32, @intCast(-delta))) {
                w_script_entry = p_script.operand[1] -% 1;
            } else {
                global.gpg.cash = @bitCast(@as(i32, @bitCast(global.gpg.cash)) + delta);
            }
        },
        0x001F => {
            _ = global.addItemToInventory(p_script.operand[0], @as(i16, @bitCast(p_script.operand[1])));
        },
        0x0020 => {
            var x: i32 = if (p_script.operand[1] == 0) 1 else p_script.operand[1];
            if (x <= global.countItem(p_script.operand[0]) or p_script.operand[2] == 0) {
                const y = global.addItemToInventory(p_script.operand[0], -x);
                if (y <= 0) {
                    if (y < 0) x = -y;
                    var i: usize = 0;
                    while (i <= global.gpg.max_party_member_index) : (i += 1) {
                        const w = global.gpg.party[i].player_role;
                        var j: usize = 0;
                        while (j < global.MAX_PLAYER_EQUIPMENTS) : (j += 1) {
                            if (global.gpg.g.player_roles.equipment[j][w] == p_script.operand[0]) {
                                global.gpg.g.player_roles.equipment[j][w] = 0;
                                x -= 1;
                                if (x == 0) {
                                    i = 9999;
                                    break;
                                }
                            }
                        }
                    }
                }
            } else {
                w_script_entry = p_script.operand[2] -% 1;
            }
        },
        0x0022 => {
            // Revive player. Restore HP, then strip low-level poisons and
            // every clearable status — matches SDLPAL script.c L1059.
            if (p_script.operand[0] != 0) {
                g_script_success = false;
                var i: usize = 0;
                while (i <= global.gpg.max_party_member_index) : (i += 1) {
                    const w = global.gpg.party[i].player_role;
                    if (global.gpg.g.player_roles.hp[w] == 0) {
                        global.gpg.g.player_roles.hp[w] =
                            @intCast((@as(u32, global.gpg.g.player_roles.max_hp[w]) * p_script.operand[1]) / 10);
                        global.curePoisonByLevel(w, global.EX_POISON_PERSIST_AFTER_REVIVE);
                        var s: u16 = 0;
                        while (s < global.STATUS_ALL) : (s += 1) global.removePlayerStatus(w, s);
                        g_script_success = true;
                    }
                }
            } else {
                if (global.gpg.g.player_roles.hp[event_object_id] == 0) {
                    global.gpg.g.player_roles.hp[event_object_id] =
                        @intCast((@as(u32, global.gpg.g.player_roles.max_hp[event_object_id]) * p_script.operand[1]) / 10);
                    global.curePoisonByLevel(event_object_id, global.EX_POISON_PERSIST_AFTER_REVIVE);
                    var s: u16 = 0;
                    while (s < global.STATUS_ALL) : (s += 1) global.removePlayerStatus(event_object_id, s);
                } else g_script_success = false;
            }
        },
        0x0023 => {
            // Remove equipment(s) from a player.
            i_player_role = p_script.operand[0];
            if (p_script.operand[1] == 0) {
                var i: usize = 0;
                while (i < global.MAX_PLAYER_EQUIPMENTS) : (i += 1) {
                    const w = global.gpg.g.player_roles.equipment[i][i_player_role];
                    if (w != 0) {
                        _ = global.addItemToInventory(w, 1);
                        global.gpg.g.player_roles.equipment[i][i_player_role] = 0;
                    }
                }
            } else {
                const part = p_script.operand[1] - 1;
                const w = global.gpg.g.player_roles.equipment[part][i_player_role];
                if (w != 0) {
                    _ = global.addItemToInventory(w, 1);
                    global.gpg.g.player_roles.equipment[part][i_player_role] = 0;
                }
            }
        },
        0x0024 => {
            if (p_script.operand[0] != 0) if (p_current) |pc| { pc.auto_script = p_script.operand[1]; };
        },
        0x0025 => {
            if (p_script.operand[0] != 0) if (p_current) |pc| { pc.trigger_script = p_script.operand[1]; };
        },
        0x0026 => {
            // PAL_BuyMenu — open store wOperand[0].
            scene_mod.makeScene();
            video.updateScreen(null);
            @import("shop.zig").buyMenu(p_script.operand[0]);
        },
        0x0027 => {
            // PAL_SellMenu — also serves as 当铺 / pawn shop.
            scene_mod.makeScene();
            video.updateScreen(null);
            @import("shop.zig").sellMenu();
        },
        0x0021 => {
            // Inflict damage to the enemy. operand[0]==1 → all enemies.
            if (p_script.operand[0] != 0) {
                var i: u32 = 0;
                while (@import("battle.zig").g_battle.max_enemy_index >= 0 and
                    i <= @as(u32, @intCast(@import("battle.zig").g_battle.max_enemy_index))) : (i += 1)
                {
                    const e = &@import("battle.zig").g_battle.enemies[i];
                    if (e.object_id == 0) continue;
                    e.e.health -%= p_script.operand[1];
                }
            } else {
                @import("battle.zig").g_battle.enemies[event_object_id].e.health -%= p_script.operand[1];
            }
        },
        0x0028 => {
            // Apply poison to enemy. operand[0]==1 → all enemies; operand[1]=poison_id.
            const battle_mod = @import("battle.zig");
            const poison_id = p_script.operand[1];
            if (p_script.operand[0] != 0) {
                var i: u32 = 0;
                while (battle_mod.g_battle.max_enemy_index >= 0 and i <= @as(u32, @intCast(battle_mod.g_battle.max_enemy_index))) : (i += 1) {
                    const w = battle_mod.g_battle.enemies[i].object_id;
                    if (w == 0) continue;
                    if (util.randomLong(0, 9) >= @as(i32, global.gpg.g.objects[w].enemy().resistance_to_sorcery)) {
                        applyPoisonToEnemyAt(@intCast(i), poison_id, event_object_id);
                    }
                }
            } else {
                const w = battle_mod.g_battle.enemies[event_object_id].object_id;
                if (util.randomLong(0, 9) >= @as(i32, global.gpg.g.objects[w].enemy().resistance_to_sorcery)) {
                    applyPoisonToEnemyAt(event_object_id, poison_id, event_object_id);
                }
            }
        },
        0x0029 => {
            // Apply poison to player. Poisons whose level >= the pierce
            // threshold ignore resistance and always land (魔改 sure-hit).
            const poison_id = p_script.operand[1];
            const sure_hit = global.gpg.g.objects[poison_id].poison().poison_level >= global.EX_POISON_CAN_PIERCE_LEVEL;
            if (p_script.operand[0] != 0) {
                var i: u32 = 0;
                while (i <= global.gpg.max_party_member_index) : (i += 1) {
                    const w = global.gpg.party[i].player_role;
                    if (sure_hit or util.randomLong(1, 100) > @as(i32, global.getPlayerPoisonResistance(w))) {
                        global.addPoisonForPlayer(w, poison_id);
                    }
                }
            } else {
                if (sure_hit or util.randomLong(1, 100) > @as(i32, global.getPlayerPoisonResistance(event_object_id))) {
                    global.addPoisonForPlayer(event_object_id, poison_id);
                }
            }
        },
        0x002A => {
            // Cure poison by ID for enemy.
            const battle_mod = @import("battle.zig");
            const poison_id = p_script.operand[1];
            if (p_script.operand[0] != 0) {
                var i: u32 = 0;
                while (battle_mod.g_battle.max_enemy_index >= 0 and i <= @as(u32, @intCast(battle_mod.g_battle.max_enemy_index))) : (i += 1) {
                    if (battle_mod.g_battle.enemies[i].object_id == 0) continue;
                    var j: u32 = 0;
                    while (j < global.MAX_POISONS) : (j += 1) {
                        if (battle_mod.g_battle.enemies[i].poisons[j].poison_id == poison_id) {
                            battle_mod.g_battle.enemies[i].poisons[j].poison_id = 0;
                            battle_mod.g_battle.enemies[i].poisons[j].poison_script = 0;
                            break;
                        }
                    }
                }
            } else {
                var j: u32 = 0;
                while (j < global.MAX_POISONS) : (j += 1) {
                    if (battle_mod.g_battle.enemies[event_object_id].poisons[j].poison_id == poison_id) {
                        battle_mod.g_battle.enemies[event_object_id].poisons[j].poison_id = 0;
                        battle_mod.g_battle.enemies[event_object_id].poisons[j].poison_script = 0;
                        break;
                    }
                }
            }
        },
        0x002B => {
            // Cure poison by ID for player.
            const poison_id = p_script.operand[1];
            if (p_script.operand[0] != 0) {
                var i: u32 = 0;
                while (i <= global.gpg.max_party_member_index) : (i += 1) {
                    global.curePoisonByKind(global.gpg.party[i].player_role, poison_id);
                }
            } else {
                global.curePoisonByKind(event_object_id, poison_id);
            }
        },
        0x002C => {
            // Cure poisons by level.
            const lvl = p_script.operand[1];
            if (p_script.operand[0] != 0) {
                var i: u32 = 0;
                while (i <= global.gpg.max_party_member_index) : (i += 1) {
                    global.curePoisonByLevel(global.gpg.party[i].player_role, lvl);
                }
            } else {
                global.curePoisonByLevel(event_object_id, lvl);
            }
        },
        0x002D => {
            // Set status for player. operand[2] != 0 → apply to whole party.
            if (p_script.operand[2] != 0) {
                if (!global.setPlayerStatusAll(p_script.operand[0], p_script.operand[1])) {
                    g_script_success = false;
                }
            } else if (!global.setPlayerStatus(event_object_id, p_script.operand[0], p_script.operand[1])) {
                g_script_success = false;
            }
        },
        0x002E => {
            // Set status for enemy. resistance check.
            const battle_mod = @import("battle.zig");
            const w = battle_mod.g_battle.enemies[event_object_id].object_id;
            const i_max: i32 = 9; // PAL_CLASSIC
            if (util.randomLong(0, i_max) > @as(i32, global.gpg.g.objects[w].enemy().resistance_to_sorcery)) {
                battle_mod.g_battle.enemies[event_object_id].status[p_script.operand[0]] = p_script.operand[1];
            } else {
                w_script_entry = p_script.operand[2] -% 1;
            }
        },
        0x002F => {
            // Remove player's status.
            global.removePlayerStatus(event_object_id, p_script.operand[0]);
        },
        0x0033 => {
            // Collect enemy for items.
            const battle_mod = @import("battle.zig");
            const cv = battle_mod.g_battle.enemies[event_object_id].e.collect_value;
            if (cv != 0) {
                global.gpg.collect_value +%= cv;
            } else {
                w_script_entry = p_script.operand[0] -% 1;
            }
        },
        0x0034 => {
            // Transform collected enemies into items. PAL_CLASSIC: random
            // 1..wCollectValue, capped at 9; remove that many; give items[i-1].
            if (global.gpg.collect_value > 0) {
                var i: i32 = util.randomLong(1, global.gpg.collect_value);
                if (i > 9) i = 9;
                global.gpg.collect_value -= @intCast(i);
                i -= 1;
                const item_id = global.gpg.g.stores[0].items[@intCast(i)];
                _ = global.addItemToInventory(item_id, 1);
                @import("fight.zig").showGetDialog(42, -1, item_id);
            } else {
                w_script_entry = p_script.operand[0] -% 1;
            }
        },
        0x0039 => {
            // Drain HP from enemy to the moving player.
            const battle_mod = @import("battle.zig");
            const w = global.gpg.party[battle_mod.g_battle.moving_player_index].player_role;
            battle_mod.g_battle.enemies[event_object_id].e.health -%= p_script.operand[0];
            global.gpg.g.player_roles.hp[w] +%= p_script.operand[0];
            if (global.gpg.g.player_roles.hp[w] > global.gpg.g.player_roles.max_hp[w]) {
                global.gpg.g.player_roles.hp[w] = global.gpg.g.player_roles.max_hp[w];
            }
        },
        0x003A => {
            // Player flee from battle.
            const battle_mod = @import("battle.zig");
            if (battle_mod.g_battle.is_boss) {
                w_script_entry = p_script.operand[0] -% 1;
            } else {
                @import("fight.zig").playerEscape();
            }
        },
        0x0042 => {
            // PAL_BattleSimulateMagic.
            var i: i32 = @as(i16, @bitCast(p_script.operand[2]));
            i -= 1;
            if (i < 0) i = @intCast(event_object_id);
            @import("fight.zig").battleSimulateMagic(i, p_script.operand[0], p_script.operand[1]);
        },
        0x005B => {
            // Halve enemy HP, clamped by operand[0].
            const battle_mod = @import("battle.zig");
            var w = battle_mod.g_battle.enemies[event_object_id].e.health / 2 + 1;
            if (w > p_script.operand[0]) w = p_script.operand[0];
            battle_mod.g_battle.enemies[event_object_id].e.health -%= w;
        },
        0x005C => {
            // Hide for a while.
            const battle_mod = @import("battle.zig");
            const t: i32 = -@as(i32, p_script.operand[0]);
            battle_mod.g_battle.hiding_time = t;
        },
        0x005D => {
            // Jump if player NOT poisoned by kind.
            if (!global.isPlayerPoisonedByKind(event_object_id, p_script.operand[0])) {
                w_script_entry = p_script.operand[1] -% 1;
            }
        },
        0x005E => {
            // Jump if enemy NOT poisoned by ID.
            const battle_mod = @import("battle.zig");
            var i: u32 = 0;
            var found: bool = false;
            while (i < global.MAX_POISONS) : (i += 1) {
                if (battle_mod.g_battle.enemies[event_object_id].poisons[i].poison_id == p_script.operand[0]) {
                    found = true;
                    break;
                }
            }
            if (!found) w_script_entry = p_script.operand[1] -% 1;
        },
        0x005F => {
            // Kill the player immediately.
            global.gpg.g.player_roles.hp[event_object_id] = 0;
        },
        0x0060 => {
            // Immediate KO of the enemy.
            @import("battle.zig").g_battle.enemies[event_object_id].e.health = 0;
        },
        0x0061 => {
            // Jump if player not poisoned (by level >= 1).
            if (!global.isPlayerPoisonedByLevel(event_object_id, 0)) {
                w_script_entry = p_script.operand[0] -% 1;
            }
        },
        0x0062 => {
            // Pause enemy chasing for a while.
            global.gpg.chase_speed_change_cycles = p_script.operand[0];
            global.gpg.chase_range = 0;
        },
        0x0063 => {
            // Speed up enemy chasing for a while.
            global.gpg.chase_speed_change_cycles = p_script.operand[0];
            global.gpg.chase_range = 3;
        },
        0x0064 => {
            // Jump if enemy HP > operand[0]% of base health.
            const battle_mod = @import("battle.zig");
            const enemy_id = global.gpg.g.objects[battle_mod.g_battle.enemies[event_object_id].object_id].enemy().enemy_id;
            const cur: i32 = battle_mod.g_battle.enemies[event_object_id].e.health;
            const base: i32 = global.gpg.g.enemies[enemy_id].health;
            if (cur * 100 > base * @as(i32, p_script.operand[0])) {
                w_script_entry = p_script.operand[1] -% 1;
            }
        },
        0x0066 => {
            // Throw weapon at enemy. base = operand[1]*5 + atk * rand(0..3).
            const battle_mod = @import("battle.zig");
            const role = global.gpg.party[battle_mod.g_battle.moving_player_index].player_role;
            var w: i32 = @as(i32, p_script.operand[1]) * 5;
            w += @as(i32, global.gpg.g.player_roles.attack_strength[role]) * util.randomLong(0, 3);
            @import("fight.zig").battleSimulateMagic(@intCast(event_object_id), p_script.operand[0], @intCast(@as(u32, @bitCast(w))));
        },
        0x0067 => {
            // Enemy use magic.
            const battle_mod = @import("battle.zig");
            battle_mod.g_battle.enemies[event_object_id].e.magic = p_script.operand[0];
            battle_mod.g_battle.enemies[event_object_id].e.magic_rate =
                if (p_script.operand[1] == 0) 10 else p_script.operand[1];
        },
        0x0068 => {
            // Jump if it's enemy's turn.
            if (@import("battle.zig").g_battle.enemy_moving) {
                w_script_entry = p_script.operand[0] -% 1;
            }
        },
        0x0069 => {
            // Enemy escape.
            @import("fight.zig").enemyEscape();
        },
        0x006A => {
            // Steal from enemy.
            @import("fight.zig").battleStealFromEnemy(event_object_id, p_script.operand[0]);
        },
        0x006B => {
            // Blow away enemies.
            @import("battle.zig").g_battle.blow = @as(i16, @bitCast(p_script.operand[0]));
        },
        0x0030 => {
            // Increase player's stat temporarily by percent.
            const role: u16 = if (p_script.operand[2] == 0) event_object_id else p_script.operand[2] - 1;
            const p = equipEffectPtr(global.MAX_PLAYER_EQUIPMENTS); // kBodyPartExtra slot
            const p1 = rolesPtr();
            const idx = @as(usize, p_script.operand[0]) * global.MAX_PLAYER_ROLES + role;
            const stat = p1[idx];
            p[idx] = @intCast((@as(u32, stat) * p_script.operand[1]) / 100);
        },
        0x0031 => {
            global.gpg.equipment_effect[global.MAX_PLAYER_EQUIPMENTS].sprite_num_in_battle[event_object_id] = p_script.operand[0];
        },
        0x0035 => {
            // Shake the screen — Stage 4 done in video.zig.
            const lvl: u16 = if (p_script.operand[1] == 0) 4 else p_script.operand[1];
            video.shakeScreen(p_script.operand[0], lvl);
            if (p_script.operand[0] == 0) video.updateScreen(null);
        },
        0x0036 => {
            global.gpg.cur_playing_rng = p_script.operand[0];
        },
        0x0037 => {
            // PAL_RNGPlay — script.c:1544. operand[0]=start frame,
            // operand[1]=end frame (>0 means inclusive, ≤0 means -1/no end),
            // operand[2]=speed (0 → 16). cur_playing_rng was set by 0x0036.
            const end_f: i32 = if (@as(i16, @bitCast(p_script.operand[1])) > 0)
                @intCast(p_script.operand[1])
            else
                -1;
            const speed: i32 = if (@as(i16, @bitCast(p_script.operand[2])) > 0)
                @intCast(p_script.operand[2])
            else
                16;
            @import("rngplay.zig").rngPlay(
                global.gpg.cur_playing_rng,
                @intCast(p_script.operand[0]),
                end_f,
                speed,
            );
        },
        0x0038 => {
            // Teleport.
            if (!global.gpg.in_battle and global.gpg.g.scenes[global.gpg.num_scene - 1].script_on_teleport != 0) {
                _ = runTriggerScript(global.gpg.g.scenes[global.gpg.num_scene - 1].script_on_teleport, 0xFFFF);
            } else {
                g_script_success = false;
                w_script_entry = p_script.operand[0] -% 1;
            }
        },
        0x003F => {
            partyRideEventObject(event_object_id, p_script.operand[0], p_script.operand[1], p_script.operand[2], 2);
        },
        0x0040 => {
            if (p_script.operand[0] != 0) if (p_current) |pc| { pc.trigger_mode = p_script.operand[1]; };
        },
        0x0041 => {
            g_script_success = false;
        },
        0x0043 => {
            // Set background music.
            global.gpg.num_music = p_script.operand[0];
            @import("audio.zig").playMusic(p_script.operand[0], true, 1.0);
        },
        0x0044 => {
            partyRideEventObject(event_object_id, p_script.operand[0], p_script.operand[1], p_script.operand[2], 4);
        },
        0x0045 => {
            global.gpg.num_battle_music = p_script.operand[0];
        },
        0x0046 => {
            // Set the party position on the map.
            const x_offset: i32 = if (global.gpg.party_direction == 1 or global.gpg.party_direction == 0) 16 else -16;
            const y_offset: i32 = if (global.gpg.party_direction == 1 or global.gpg.party_direction == 2) 8 else -8;

            var x: i32 = @as(i32, p_script.operand[0]) * 32 + @as(i32, p_script.operand[2]) * 16;
            var y: i32 = @as(i32, p_script.operand[1]) * 16 + @as(i32, p_script.operand[2]) * 8;
            x -= global.palX(global.gpg.party_offset);
            y -= global.palY(global.gpg.party_offset);
            global.gpg.viewport = global.palXY(@truncate(x), @truncate(y));

            x = global.palX(global.gpg.party_offset);
            y = global.palY(global.gpg.party_offset);

            var i: usize = 0;
            while (i < global.MAX_PLAYABLE_PLAYER_ROLES) : (i += 1) {
                global.gpg.party[i].x = @truncate(x);
                global.gpg.party[i].y = @truncate(y);
                global.gpg.trail[i].x = @bitCast(@as(i16, @truncate(x + global.palX(global.gpg.viewport))));
                global.gpg.trail[i].y = @bitCast(@as(i16, @truncate(y + global.palY(global.gpg.viewport))));
                global.gpg.trail[i].direction = global.gpg.party_direction;
                x += x_offset;
                y += y_offset;
            }
        },
        0x0047 => {
            @import("audio.zig").playSound(p_script.operand[0]);
        },
        0x0049 => {
            if (p_script.operand[0] != 0) if (p_current) |pc| { pc.state = @bitCast(p_script.operand[1]); };
        },
        0x004A => {
            global.gpg.num_battle_field = p_script.operand[0];
        },
        0x004B => {
            if (p_evt_obj) |pe| pe.vanish_time = -15;
        },
        0x004C => {
            // PAL_MonsterChasePlayer — script.c:1733 + L310 helper.
            var max_dist: u16 = p_script.operand[0];
            var speed: u16 = p_script.operand[1];
            if (max_dist == 0) max_dist = 8;
            if (speed == 0) speed = 4;
            monsterChasePlayer(event_object_id, speed, max_dist, p_script.operand[2] != 0);
        },
        0x004D => {
            @import("play.zig").waitForKey(0);
        },
        0x004E => {
            palette_mod.fadeOut(1);
            global.reloadInNextTick(global.gpg.current_save_slot);
            return 0;
        },
        0x004F => {
            palette_mod.fadeToRed();
        },
        0x0050 => {
            video.updateScreen(null);
            palette_mod.fadeOut(if (p_script.operand[0] == 0) 1 else @intCast(p_script.operand[0]));
            global.gpg.need_to_fade_in = true;
        },
        0x0051 => {
            video.updateScreen(null);
            const d: i32 = @as(i32, @bitCast(@as(u32, p_script.operand[0])));
            palette_mod.fadeIn(@intCast(global.gpg.num_palette), global.gpg.night_palette, if (d > 0) d else 1);
            global.gpg.need_to_fade_in = false;
        },
        0x0052 => {
            if (p_evt_obj) |pe| {
                pe.state *= -1;
                pe.vanish_time = if (p_script.operand[0] == 0) 800 else @bitCast(p_script.operand[0]);
            }
        },
        0x0053 => {
            global.gpg.night_palette = false;
        },
        0x0054 => {
            global.gpg.night_palette = true;
        },
        0x0055 => {
            // Add magic to a player. operand[0]=magic id, operand[1]=role+1
            // (0 means use the event-object id).
            const role: u16 = if (p_script.operand[1] == 0) event_object_id else p_script.operand[1] - 1;
            const magic = p_script.operand[0];
            var i: usize = 0;
            while (i < global.MAX_PLAYER_MAGICS) : (i += 1) {
                if (global.gpg.g.player_roles.magic[i][role] == magic) break;
                if (global.gpg.g.player_roles.magic[i][role] == 0) {
                    global.gpg.g.player_roles.magic[i][role] = magic;
                    break;
                }
            }
        },
        0x0056 => {
            // Remove magic from a player.
            const role: u16 = if (p_script.operand[1] == 0) event_object_id else p_script.operand[1] - 1;
            const magic = p_script.operand[0];
            var i: usize = 0;
            while (i < global.MAX_PLAYER_MAGICS) : (i += 1) {
                if (global.gpg.g.player_roles.magic[i][role] == magic) {
                    global.gpg.g.player_roles.magic[i][role] = 0;
                    break;
                }
            }
        },
        0x0057 => {
            // Set the base damage of magic according to MP value (in-battle).
            const i: u16 = if (p_script.operand[1] == 0) 8 else p_script.operand[1];
            const j = global.gpg.g.objects[p_script.operand[0]].magic().magic_number;
            if (j < global.gpg.g.magics.len) {
                global.gpg.g.magics[j].base_damage = global.gpg.g.player_roles.mp[event_object_id] *% i;
            }
            global.gpg.g.player_roles.mp[event_object_id] = 0;
        },
        0x0058 => {
            // Jump if inventory has fewer than the specified amount of an item.
            if (global.getItemAmount(p_script.operand[0]) < @as(i16, @bitCast(p_script.operand[1]))) {
                w_script_entry = p_script.operand[2] -% 1;
            }
        },
        0x0059 => {
            // Change to the specified scene.
            const target = p_script.operand[0];
            if (target > 0 and target <= global.MAX_SCENES and global.gpg.num_scene != target) {
                global.gpg.num_scene = target;
                global.setLoadFlags(global.LOAD_SCENE);
                global.gpg.entering_scene = true;
                global.gpg.layer = 0;
            }
        },
        0x005A => {
            // Halve the player's HP.
            global.gpg.g.player_roles.hp[event_object_id] /= 2;
        },
        0x0065 => {
            global.gpg.g.player_roles.sprite_num[p_script.operand[0]] = p_script.operand[1];
            if (!global.gpg.in_battle and p_script.operand[2] != 0) {
                global.setLoadFlags(global.LOAD_PLAYER_SPRITE);
                res.loadResources() catch {};
            }
        },
        0x006C => {
            if (p_current) |pc| {
                pc.x = @bitCast(@as(i16, @bitCast(@as(u16, pc.x))) + @as(i16, @bitCast(p_script.operand[1])));
                pc.y = @bitCast(@as(i16, @bitCast(@as(u16, pc.y))) + @as(i16, @bitCast(p_script.operand[2])));
                scene_mod.npcWalkOneStep(w_cur_event_object_id, 0);
            }
        },
        0x006D => {
            if (p_script.operand[0] != 0) {
                if (p_script.operand[1] != 0) {
                    global.gpg.g.scenes[p_script.operand[0] - 1].script_on_enter = p_script.operand[1];
                }
                if (p_script.operand[2] != 0) {
                    global.gpg.g.scenes[p_script.operand[0] - 1].script_on_teleport = p_script.operand[2];
                }
                if (p_script.operand[1] == 0 and p_script.operand[2] == 0) {
                    global.gpg.g.scenes[p_script.operand[0] - 1].script_on_enter = 0;
                    global.gpg.g.scenes[p_script.operand[0] - 1].script_on_teleport = 0;
                }
            }
        },
        0x006E => {
            // Move the player to specified position in one step.
            var i: i32 = 3;
            while (i >= 0) : (i -= 1) {
                global.gpg.trail[@intCast(i + 1)] = global.gpg.trail[@intCast(i)];
            }
            global.gpg.trail[0].direction = global.gpg.party_direction;
            global.gpg.trail[0].x = @bitCast(@as(i16, @truncate(global.palX(global.gpg.viewport) + global.palX(global.gpg.party_offset))));
            global.gpg.trail[0].y = @bitCast(@as(i16, @truncate(global.palY(global.gpg.viewport) + global.palY(global.gpg.party_offset))));
            global.gpg.viewport = global.palXY(
                @truncate(global.palX(global.gpg.viewport) + @as(i32, @bitCast(@as(u32, p_script.operand[0])))),
                @truncate(global.palY(global.gpg.viewport) + @as(i32, @bitCast(@as(u32, p_script.operand[1])))),
            );
            global.gpg.layer = p_script.operand[2] * 8;
            if (p_script.operand[0] != 0 or p_script.operand[1] != 0) {
                scene_mod.updatePartyGestures(true);
            }
        },
        0x006F => {
            if (p_current) |pc| if (p_evt_obj) |pe| {
                if (pc.state == @as(i16, @bitCast(p_script.operand[1]))) {
                    pe.state = @bitCast(p_script.operand[1]);
                }
            };
        },
        0x0070 => {
            partyWalkTo(p_script.operand[0], p_script.operand[1], p_script.operand[2], 2);
        },
        0x0071 => {
            global.gpg.screen_wave = p_script.operand[0];
            global.gpg.wave_progression = @bitCast(p_script.operand[1]);
        },
        0x0073 => {
            // PAL_FadeToScene — script.c:2140. Backup current screen, render
            // the new scene, cross-fade between them at speed operand[0].
            video.backupScreen();
            scene_mod.makeScene();
            video.fadeScreen(p_script.operand[0]);
        },
        0x0074 => {
            var i: usize = 0;
            while (i <= global.gpg.max_party_member_index) : (i += 1) {
                const w = global.gpg.party[i].player_role;
                if (global.gpg.g.player_roles.hp[w] < global.gpg.g.player_roles.max_hp[w]) {
                    w_script_entry = p_script.operand[0] -% 1;
                    break;
                }
            }
        },
        0x0075 => {
            // 魔改 — 4-person party. The fork packs the 4th role into the
            // high byte of operand[2]: members = { op[0], op[1], op[2]&0xFF, op[2]>>8 }.
            const members = [4]u16{
                p_script.operand[0],
                p_script.operand[1],
                p_script.operand[2] & 0x00FF,
                p_script.operand[2] >> 8,
            };
            global.gpg.max_party_member_index = 0;
            for (members) |m| {
                if (m != 0) {
                    global.gpg.party[global.gpg.max_party_member_index].player_role = m - 1;
                    global.gpg.max_party_member_index += 1;
                }
            }
            if (global.gpg.max_party_member_index == 0) {
                global.gpg.party[0].player_role = 0;
                global.gpg.max_party_member_index = 1;
            }
            global.gpg.max_party_member_index -= 1;
            global.setLoadFlags(global.LOAD_PLAYER_SPRITE);
            res.loadResources() catch {};
        },
        0x0076 => {
            showFbp(p_script.operand[0], p_script.operand[1]);
        },
        0x0077 => {
            global.gpg.num_music = 0;
            @import("audio.zig").stopMusic(2.0);
        },
        0x0078 => {
            // unknown.
        },
        0x0079 => {
            var i: usize = 0;
            while (i <= global.gpg.max_party_member_index) : (i += 1) {
                if (global.gpg.g.player_roles.name[global.gpg.party[i].player_role] == p_script.operand[0]) {
                    w_script_entry = p_script.operand[1] -% 1;
                    break;
                }
            }
        },
        0x007A => {
            partyWalkTo(p_script.operand[0], p_script.operand[1], p_script.operand[2], 4);
        },
        0x007B => {
            partyWalkTo(p_script.operand[0], p_script.operand[1], p_script.operand[2], 8);
        },
        0x007C => {
            if (((event_object_id & 1) ^ (global.gpg.frame_num & 1)) != 0) {
                if (!npcWalkTo(event_object_id, p_script.operand[0], p_script.operand[1], p_script.operand[2], 4)) {
                    if (w_script_entry > 0) w_script_entry -= 1;
                }
            } else {
                if (w_script_entry > 0) w_script_entry -= 1;
            }
        },
        0x007D => {
            if (p_current) |pc| {
                pc.x = @bitCast(@as(i16, @bitCast(@as(u16, pc.x))) + @as(i16, @bitCast(p_script.operand[1])));
                pc.y = @bitCast(@as(i16, @bitCast(@as(u16, pc.y))) + @as(i16, @bitCast(p_script.operand[2])));
            }
        },
        0x007E => {
            if (p_current) |pc| pc.layer = @bitCast(p_script.operand[1]);
        },
        0x007F => {
            // Move the viewport (animated). Simplified: just move it instantaneously
            // and re-render. Real implementation steps over operand[2] frames.
            if (p_script.operand[0] == 0 and p_script.operand[1] == 0) {
                const dx = @as(i32, global.gpg.party[0].x) - 160;
                const dy = @as(i32, global.gpg.party[0].y) - 112;
                global.gpg.viewport = global.palXY(
                    @truncate(global.palX(global.gpg.viewport) + dx),
                    @truncate(global.palY(global.gpg.viewport) + dy),
                );
                global.gpg.party_offset = global.palXY(160, 112);
                var i: usize = 0;
                while (i <= @as(usize, global.gpg.max_party_member_index) + global.gpg.n_follower) : (i += 1) {
                    global.gpg.party[i].x -= @intCast(dx);
                    global.gpg.party[i].y -= @intCast(dy);
                }
            } else {
                const dx: i32 = @as(i16, @bitCast(p_script.operand[0]));
                const dy: i32 = @as(i16, @bitCast(p_script.operand[1]));
                const steps: u32 = if (p_script.operand[2] == 0xFFFF) 1 else p_script.operand[2];
                var n: u32 = 0;
                var time = util.getTicks() + global.FRAME_TIME;
                while (n < steps) : (n += 1) {
                    if (util.shouldQuit()) break;
                    if (p_script.operand[2] == 0xFFFF) {
                        global.gpg.viewport = global.palXY(
                            @truncate(@as(i32, p_script.operand[0]) * 32 - 160),
                            @truncate(@as(i32, p_script.operand[1]) * 16 - 112),
                        );
                    } else {
                        global.gpg.viewport = global.palXY(
                            @truncate(global.palX(global.gpg.viewport) + dx),
                            @truncate(global.palY(global.gpg.viewport) + dy),
                        );
                        global.gpg.party_offset = global.palXY(
                            @truncate(global.palX(global.gpg.party_offset) - dx),
                            @truncate(global.palY(global.gpg.party_offset) - dy),
                        );
                        var j: usize = 0;
                        while (j <= @as(usize, global.gpg.max_party_member_index) + global.gpg.n_follower) : (j += 1) {
                            global.gpg.party[j].x -= @intCast(dx);
                            global.gpg.party[j].y -= @intCast(dy);
                        }
                    }
                    if (p_script.operand[2] != 0xFFFF) @import("play.zig").gameUpdate(false);
                    scene_mod.makeScene();
                    video.updateScreen(null);
                    util.delayUntil(time);
                    time = util.getTicks() + global.FRAME_TIME;
                }
            }
        },
        0x0080 => {
            global.gpg.night_palette = !global.gpg.night_palette;
            palette_mod.paletteFade(@intCast(global.gpg.num_palette), global.gpg.night_palette, p_script.operand[0] == 0);
        },
        0x0081 => {
            const scene_idx = @as(usize, global.gpg.num_scene) - 1;
            const start = global.gpg.g.scenes[scene_idx].event_object_index;
            const end = global.gpg.g.scenes[scene_idx + 1].event_object_index;
            if (p_script.operand[0] <= start or p_script.operand[0] > end) {
                w_script_entry = p_script.operand[2] -% 1;
                g_script_success = false;
            } else if (p_current) |pc| {
                var x: i32 = @bitCast(@as(u32, pc.x));
                var y: i32 = @bitCast(@as(u32, pc.y));
                x += if (global.gpg.party_direction == 1 or global.gpg.party_direction == 0) @as(i32, 16) else @as(i32, -16);
                y += if (global.gpg.party_direction == 1 or global.gpg.party_direction == 2) @as(i32, 8) else @as(i32, -8);
                x -= global.palX(global.gpg.viewport) + global.palX(global.gpg.party_offset);
                y -= global.palY(global.gpg.viewport) + global.palY(global.gpg.party_offset);
                if (@abs(x) + @abs(y * 2) < @as(i32, p_script.operand[1]) * 32 + 16 and global.gpg.g.event_objects[p_script.operand[0] - 1].state > 0) {
                    if (p_script.operand[1] > 0) {
                        pc.trigger_mode = global.TRIGGER_TOUCH_NORMAL + p_script.operand[1];
                    }
                } else {
                    w_script_entry = p_script.operand[2] -% 1;
                    g_script_success = false;
                }
            }
        },
        0x0082 => {
            if (!npcWalkTo(event_object_id, p_script.operand[0], p_script.operand[1], p_script.operand[2], 8)) {
                if (w_script_entry > 0) w_script_entry -= 1;
            }
        },
        0x0083 => {
            const scene_idx = @as(usize, global.gpg.num_scene) - 1;
            const start = global.gpg.g.scenes[scene_idx].event_object_index;
            const end = global.gpg.g.scenes[scene_idx + 1].event_object_index;
            if (p_script.operand[0] <= start or p_script.operand[0] > end) {
                w_script_entry = p_script.operand[2] -% 1;
                g_script_success = false;
            } else if (p_evt_obj) |pe| if (p_current) |pc| {
                const xd = @as(i32, @bitCast(@as(u32, pe.x))) - @as(i32, @bitCast(@as(u32, pc.x)));
                const yd = @as(i32, @bitCast(@as(u32, pe.y))) - @as(i32, @bitCast(@as(u32, pc.y)));
                if (@abs(xd) + @abs(yd * 2) >= @as(i32, p_script.operand[1]) * 32 + 16) {
                    w_script_entry = p_script.operand[2] -% 1;
                    g_script_success = false;
                }
            };
        },
        0x0084 => {
            const scene_idx = @as(usize, global.gpg.num_scene) - 1;
            const start = global.gpg.g.scenes[scene_idx].event_object_index;
            const end = global.gpg.g.scenes[scene_idx + 1].event_object_index;
            if (p_script.operand[0] <= start or p_script.operand[0] > end) {
                w_script_entry = p_script.operand[2] -% 1;
                g_script_success = false;
            } else {
                var x: i32 = global.palX(global.gpg.viewport) + global.palX(global.gpg.party_offset);
                var y: i32 = global.palY(global.gpg.viewport) + global.palY(global.gpg.party_offset);
                x += if (global.gpg.party_direction == 1 or global.gpg.party_direction == 0) @as(i32, -16) else @as(i32, 16);
                y += if (global.gpg.party_direction == 1 or global.gpg.party_direction == 2) @as(i32, -8) else @as(i32, 8);
                if (scene_mod.checkObstacle(global.palXY(@truncate(x), @truncate(y)), false, 0)) {
                    w_script_entry = p_script.operand[2] -% 1;
                    g_script_success = false;
                } else if (p_current) |pc| {
                    pc.x = @truncate(@as(u32, @bitCast(x)));
                    pc.y = @truncate(@as(u32, @bitCast(y)));
                    pc.state = @bitCast(p_script.operand[1]);
                }
            }
        },
        0x0085 => {
            util.delay(@as(u32, p_script.operand[0]) * 80);
        },
        0x0086 => {
            // Jump if specified item is not equipped at least N times.
            var y_count: u32 = 0;
            var i: usize = 0;
            while (i <= global.gpg.max_party_member_index) : (i += 1) {
                const w = global.gpg.party[i].player_role;
                var j: usize = 0;
                while (j < global.MAX_PLAYER_EQUIPMENTS) : (j += 1) {
                    if (global.gpg.g.player_roles.equipment[j][w] == p_script.operand[0]) y_count += 1;
                }
            }
            if (y_count < p_script.operand[1]) w_script_entry = p_script.operand[2] -% 1;
        },
        0x0087 => {
            scene_mod.npcWalkOneStep(w_cur_event_object_id, 0);
        },
        0x0088 => {
            const cap: u32 = if (global.gpg.cash > 5000) 5000 else global.gpg.cash;
            global.gpg.cash -= cap;
            const j = global.gpg.g.objects[p_script.operand[0]].data[0]; // wMagicNumber
            if (j < global.gpg.g.magics.len) {
                global.gpg.g.magics[j].base_damage = @intCast(cap * 2 / 5);
            }
        },
        0x0089 => {
            // Set the battle result. SDLPAL script.c:2557 stores operand[0]
            // verbatim into g_Battle.BattleResult — used by victory/escape
            // scripts to drive the post-battle branch.
            const battle_mod = @import("battle.zig");
            battle_mod.g_battle.result = @enumFromInt(p_script.operand[0]);
        },
        0x008A => {
            global.gpg.auto_battle = true;
        },
        0x008B => {
            global.gpg.num_palette = p_script.operand[0];
            if (!global.gpg.need_to_fade_in) {
                palette_mod.setPalette(@intCast(global.gpg.num_palette), false);
            }
        },
        0x008C => {
            palette_mod.colorFade(@intCast(p_script.operand[1]), @intCast(p_script.operand[0] & 0xff), p_script.operand[2] != 0);
            global.gpg.need_to_fade_in = false;
        },
        0x008D => {
            global.playerLevelUp(event_object_id, p_script.operand[0]);
        },
        0x008F => {
            global.gpg.cash /= 2;
        },
        0x0090 => {
            global.gpg.g.objects[p_script.operand[0]].data[2 + p_script.operand[2]] = p_script.operand[1];
        },
        0x0091 => {
            // Jump if the enemy is not the first of the same kind. SDLPAL
            // script.c:2613. Used by division/clone enemies so only the
            // first instance runs a given turn-start script.
            if (global.gpg.in_battle) {
                const battle_mod = @import("battle.zig");
                var self_pos: i32 = 0;
                var count: i32 = 0;
                var i: u32 = 0;
                while (battle_mod.g_battle.max_enemy_index >= 0 and
                    i <= @as(u32, @intCast(battle_mod.g_battle.max_enemy_index))) : (i += 1)
                {
                    if (battle_mod.g_battle.enemies[i].object_id ==
                        battle_mod.g_battle.enemies[event_object_id].object_id)
                    {
                        count += 1;
                        if (i == event_object_id) self_pos = count;
                    }
                }
                if (self_pos > 1) w_script_entry = p_script.operand[0] -% 1;
            }
        },
        0x0092 => {
            // Show a magic-casting animation for a player in battle. SDLPAL
            // script.c:2637. Pre-cast pose + 5-step color flash on every
            // party member, then a battle-scene fade to commit the change.
            if (global.gpg.in_battle) {
                const battle_mod = @import("battle.zig");
                const fight_mod = @import("fight.zig");
                if (p_script.operand[0] != 0) {
                    fight_mod.battleShowPlayerPreMagicAnim(p_script.operand[0] - 1, false);
                    battle_mod.g_battle.players[p_script.operand[0] - 1].current_frame = 6;
                }

                var i: u32 = 0;
                while (i < 5) : (i += 1) {
                    var j: u32 = 0;
                    while (j <= global.gpg.max_party_member_index) : (j += 1) {
                        battle_mod.g_battle.players[j].color_shift = @intCast(i * 2);
                    }
                    fight_mod.battleDelay(1, 0, true);
                }

                @memcpy(&battle_mod.g_battle.scene_buf_pixels, &video.screen_pixels);
                fight_mod.updateFighters();
                battle_mod.battleMakeScene();
                battle_mod.battleFadeScene();
            }
        },
        0x0093 => {
            palette_mod.sceneFade(@intCast(global.gpg.num_palette), global.gpg.night_palette, @as(i16, @bitCast(p_script.operand[0])));
            global.gpg.need_to_fade_in = @as(i16, @bitCast(p_script.operand[0])) < 0;
        },
        0x0094 => {
            if (p_current) |pc| {
                if (pc.state == @as(i16, @bitCast(p_script.operand[1]))) {
                    w_script_entry = p_script.operand[2] -% 1;
                }
            }
        },
        0x0095 => {
            if (global.gpg.num_scene == p_script.operand[0]) {
                w_script_entry = p_script.operand[1] -% 1;
            }
        },
        0x0096 => {
            endingAnimation();
        },
        0x0097 => {
            partyRideEventObject(event_object_id, p_script.operand[0], p_script.operand[1], p_script.operand[2], 8);
        },
        0x0098 => {
            // Set followers.
            var j: i32 = 0;
            var i: usize = 0;
            while (i < 2) : (i += 1) {
                if (p_script.operand[i] > 0) {
                    const cur_follower: u16 = @intCast(i + 1);
                    j = @intCast(cur_follower);
                    global.gpg.n_follower = cur_follower;
                    global.gpg.party[global.gpg.max_party_member_index + cur_follower].player_role = p_script.operand[i];
                    global.setLoadFlags(global.LOAD_PLAYER_SPRITE);
                    res.loadResources() catch {};
                    global.gpg.party[global.gpg.max_party_member_index + cur_follower].x =
                        @as(i16, @bitCast(global.gpg.trail[3 + i].x)) - global.palX(global.gpg.viewport);
                    global.gpg.party[global.gpg.max_party_member_index + cur_follower].y =
                        @as(i16, @bitCast(global.gpg.trail[3 + i].y)) - global.palY(global.gpg.viewport);
                    global.gpg.party[global.gpg.max_party_member_index + cur_follower].frame =
                        @intCast(@as(u32, global.gpg.trail[3 + i].direction) * 3);
                }
            }
            if (j == 0) global.gpg.n_follower = 0;
        },
        0x0099 => {
            if (p_script.operand[0] == 0xFFFF) {
                global.gpg.g.scenes[global.gpg.num_scene - 1].map_num = p_script.operand[1];
                global.setLoadFlags(global.LOAD_SCENE);
                res.loadResources() catch {};
            } else {
                global.gpg.g.scenes[p_script.operand[0] - 1].map_num = p_script.operand[1];
            }
        },
        0x009A => {
            var i: u16 = p_script.operand[0];
            while (i <= p_script.operand[1]) : (i += 1) {
                if (i > 0 and i - 1 < global.gpg.g.event_objects.len) {
                    global.gpg.g.event_objects[i - 1].state = @bitCast(p_script.operand[2]);
                }
            }
        },
        0x009B => {
            // Fade to the current scene — SDLPAL script.c:2766. Used for
            // day/night transitions: backup the old screen, render the new
            // one with the toggled palette, then cross-fade between them so
            // the player sees the change instead of a hard cut.
            video.backupScreen();
            scene_mod.makeScene();
            video.fadeScreen(2);
        },
        0x009C => {
            // Enemy division — clone the current enemy into N siblings.
            // SDLPAL script.c:2776. Only fires when one enemy is left and
            // its HP > 1; on failure jumps to operand[1].
            const battle_mod = @import("battle.zig");
            const fight_mod = @import("fight.zig");

            // Count live enemies.
            var alive: i32 = 0;
            var ii: u32 = 0;
            while (battle_mod.g_battle.max_enemy_index >= 0 and
                ii <= @as(u32, @intCast(battle_mod.g_battle.max_enemy_index))) : (ii += 1)
            {
                if (battle_mod.g_battle.enemies[ii].object_id != 0) alive += 1;
            }

            if (alive != 1 or battle_mod.g_battle.enemies[w_cur_event_object_id].e.health <= 1) {
                if (p_script.operand[1] != 0) {
                    w_script_entry = p_script.operand[1] -% 1;
                }
            } else {
                var n_clones: i32 = @intCast(p_script.operand[0]);
                if (n_clones == 0) n_clones = 1;
                const x_div: i32 = n_clones + 1; // total fighters after split
                const y_add: i32 = n_clones;     // remainder distribution

                var rem: i32 = n_clones;
                var slot: u32 = 0;
                const SLOTS: u32 = global.MAX_ENEMIES_IN_TEAM;
                while (slot < SLOTS) : (slot += 1) {
                    if (rem <= 0) break;
                    if (battle_mod.g_battle.enemies[slot].object_id != 0) continue;
                    rem -= 1;
                    const src = battle_mod.g_battle.enemies[event_object_id];
                    battle_mod.g_battle.enemies[slot] = .{};
                    battle_mod.g_battle.enemies[slot].object_id = src.object_id;
                    battle_mod.g_battle.enemies[slot].e = src.e;
                    battle_mod.g_battle.enemies[slot].e.health =
                        @intCast(@divTrunc(@as(i32, src.e.health) + y_add, x_div));
                    battle_mod.g_battle.enemies[slot].script_on_turn_start = src.script_on_turn_start;
                    battle_mod.g_battle.enemies[slot].script_on_battle_end = src.script_on_battle_end;
                    battle_mod.g_battle.enemies[slot].script_on_ready = src.script_on_ready;
                    battle_mod.g_battle.enemies[slot].state = .wait;
                    battle_mod.g_battle.enemies[slot].color_shift = 0;
                }
                battle_mod.g_battle.enemies[w_cur_event_object_id].e.health = @intCast(@divTrunc(
                    @as(i32, battle_mod.g_battle.enemies[event_object_id].e.health) + y_add,
                    x_div,
                ));

                // Recompute max_enemy_index — last non-zero slot.
                var hi: i32 = 0;
                var ki: u32 = 0;
                while (ki < SLOTS) : (ki += 1) {
                    if (battle_mod.g_battle.enemies[ki].object_id != 0) hi = @intCast(ki);
                }
                battle_mod.g_battle.max_enemy_index = hi;

                battle_mod.loadBattleSprites();

                // Place every clone at the source enemy's position.
                const src_pos = battle_mod.g_battle.enemies[event_object_id].pos;
                var pi: u32 = 0;
                while (pi <= @as(u32, @intCast(battle_mod.g_battle.max_enemy_index))) : (pi += 1) {
                    if (battle_mod.g_battle.enemies[pi].object_id == 0) continue;
                    battle_mod.g_battle.enemies[pi].pos = src_pos;
                }

                // 10-step lerp to each clone's pos_original.
                var step: u32 = 0;
                while (step < 10) : (step += 1) {
                    var pj: u32 = 0;
                    while (pj <= @as(u32, @intCast(battle_mod.g_battle.max_enemy_index))) : (pj += 1) {
                        if (battle_mod.g_battle.enemies[pj].object_id == 0) continue;
                        const px = (@as(i32, global.palX(battle_mod.g_battle.enemies[pj].pos)) +
                            @as(i32, global.palX(battle_mod.g_battle.enemies[pj].pos_original))) >> 1;
                        const py = (@as(i32, global.palY(battle_mod.g_battle.enemies[pj].pos)) +
                            @as(i32, global.palY(battle_mod.g_battle.enemies[pj].pos_original))) >> 1;
                        battle_mod.g_battle.enemies[pj].pos =
                            global.palXY(@truncate(px), @truncate(py));
                    }
                    fight_mod.battleDelay(1, 0, true);
                }

                fight_mod.updateFighters();
                fight_mod.battleDelay(1, 0, true);
            }
        },
        0x009E => {
            // Enemy summons another monster.
            const battle_mod = @import("battle.zig");
            const fight_mod = @import("fight.zig");
            const e = &battle_mod.g_battle.enemies[event_object_id];

            // Casting frames.
            var f: u32 = 0;
            while (f < e.e.magic_frames) : (f += 1) {
                e.current_frame = e.e.idle_frames + @as(u16, @intCast(f));
                fight_mod.battleDelay(@max(e.e.act_wait_frames, 1), 0, false);
            }

            var x: u32 = 0;
            var w: u16 = p_script.operand[0];
            var y: i32 = if (@as(i16, @bitCast(p_script.operand[1])) <= 0) 1 else @as(i16, @bitCast(p_script.operand[1]));
            if (w == 0 or w == 0xFFFF) w = e.object_id;

            var k: u32 = 0;
            while (battle_mod.g_battle.max_enemy_index >= 0 and k <= @as(u32, @intCast(battle_mod.g_battle.max_enemy_index))) : (k += 1) {
                if (battle_mod.g_battle.enemies[k].object_id == 0) x += 1;
            }

            if (x < y or battle_mod.g_battle.hiding_time > 0 or
                e.status[global.STATUS_SLEEP] != 0 or
                e.status[global.STATUS_PARALYZED] != 0 or
                e.status[global.STATUS_CONFUSED] != 0)
            {
                if (p_script.operand[2] != 0) w_script_entry = p_script.operand[2] -% 1;
            } else {
                k = 0;
                while (battle_mod.g_battle.max_enemy_index >= 0 and k <= @as(u32, @intCast(battle_mod.g_battle.max_enemy_index))) : (k += 1) {
                    if (battle_mod.g_battle.enemies[k].object_id == 0) {
                        battle_mod.g_battle.enemies[k] = .{};
                        battle_mod.g_battle.enemies[k].object_id = w;
                        const enemy_id = global.gpg.g.objects[w].enemy().enemy_id;
                        battle_mod.g_battle.enemies[k].e = global.gpg.g.enemies[enemy_id];
                        battle_mod.g_battle.enemies[k].state = .wait;
                        battle_mod.g_battle.enemies[k].script_on_turn_start = global.gpg.g.objects[w].enemy().script_on_turn_start;
                        battle_mod.g_battle.enemies[k].script_on_battle_end = global.gpg.g.objects[w].enemy().script_on_battle_end;
                        battle_mod.g_battle.enemies[k].script_on_ready = global.gpg.g.objects[w].enemy().script_on_ready;
                        battle_mod.g_battle.enemies[k].color_shift = 8;
                        y -= 1;
                        if (y <= 0) break;
                    }
                }
                video.backupScreen();
                battle_mod.loadBattleSprites();
                battle_mod.battleMakeScene();
                battle_mod.battleFadeScene();
                fight_mod.battleDelay(2, 0, true);

                k = 0;
                while (battle_mod.g_battle.max_enemy_index >= 0 and k <= @as(u32, @intCast(battle_mod.g_battle.max_enemy_index))) : (k += 1) {
                    battle_mod.g_battle.enemies[k].color_shift = 0;
                }
                video.backupScreen();
                battle_mod.battleMakeScene();
                battle_mod.battleFadeScene();
            }
        },
        0x009F => {
            // Enemy transforms.
            const battle_mod = @import("battle.zig");
            const fight_mod = @import("fight.zig");
            const e = &battle_mod.g_battle.enemies[event_object_id];
            if (battle_mod.g_battle.hiding_time <= 0 and
                e.status[global.STATUS_SLEEP] == 0 and
                e.status[global.STATUS_PARALYZED] == 0 and
                e.status[global.STATUS_CONFUSED] == 0)
            {
                const old_hp = e.e.health;
                e.object_id = p_script.operand[0];
                const enemy_id = global.gpg.g.objects[p_script.operand[0]].enemy().enemy_id;
                e.e = global.gpg.g.enemies[enemy_id];
                e.e.health = old_hp;
                e.current_frame = 0;

                var i: i32 = 0;
                while (i < 6) : (i += 1) {
                    e.color_shift = i;
                    fight_mod.battleDelay(1, 0, false);
                }
                e.color_shift = 0;

                video.backupScreen();
                battle_mod.loadBattleSprites();
                battle_mod.battleMakeScene();
                battle_mod.battleFadeScene();
            }
        },
        0x00A0 => {
            // Quit game — graceful exit.
            @import("libretro_core.zig").quit_flag.store(true, .monotonic);
        },
        0x00A1 => {
            var i: usize = 0;
            while (i < global.MAX_PLAYABLE_PLAYER_ROLES) : (i += 1) {
                global.gpg.trail[i].direction = global.gpg.party_direction;
                global.gpg.trail[i].x = @bitCast(@as(i16, @truncate(@as(i32, global.gpg.party[0].x) + global.palX(global.gpg.viewport))));
                global.gpg.trail[i].y = @bitCast(@as(i16, @truncate(@as(i32, global.gpg.party[0].y) + global.palY(global.gpg.viewport))));
            }
            i = 1;
            while (i <= global.gpg.max_party_member_index) : (i += 1) {
                global.gpg.party[i].x = global.gpg.party[0].x;
                global.gpg.party[i].y = global.gpg.party[0].y - 1;
            }
            scene_mod.updatePartyGestures(false);
        },
        0x00A2 => {
            const r = util.randomLong(0, @as(i32, p_script.operand[0]) - 1);
            w_script_entry = @intCast(@as(i32, w_script_entry) + r);
        },
        0x00A3 => {
            global.gpg.num_music = p_script.operand[1];
            @import("audio.zig").playMusic(p_script.operand[1], true, 1.0);
        },
        0x00A4 => {
            // PAL_ScrollFBP. SDLPAL HACKHACK: chunk 68 is preceded by ShowFBP(69).
            if (p_script.operand[0] == 68) showFbp(69, 0);
            scrollFbp(p_script.operand[0], p_script.operand[2], true);
        },
        0x00A5 => {
            // Show FBP picture with sprite effects. operand[1] != 0xFFFF
            // would set the effect sprite (we skip — no audio path here).
            showFbp(p_script.operand[0], p_script.operand[2]);
        },
        0x00A6 => {
            video.backupScreen();
        },
        0x00A7 => {
            // SDLPAL just advances the script pointer — explicit no-op.
        },
        else => {
            // Unhandled — log once per opcode value so we can spot missing
            // implementations driving real game scripts.
            logUnhandled(p_script.operation);
        },
    }

    // Wrapping add: jumps that set entry = 0xFFFF (target -1) rely on this
    // ++ rolling back to 0 — SDLPAL leans on C's WORD wraparound here.
    return w_script_entry +% 1;
}

// Debug-only log files. Writes via std.c (libc); buffered through a small
// stack buffer formatted with std.fmt. Kept alive for the lifetime of the
// process; we never close them.
const c_io = std.c;

var unhandled_logged: [0x10000 / 8]u8 = [_]u8{0} ** (0x10000 / 8);
var unhandled_fd: c_io.fd_t = -1;
var unhandled_log_inited: bool = false;

fn openLogFile(name: []const u8) c_io.fd_t {
    const sys_dir = @import("libretro_core.zig").system_dir orelse return -1;
    var path_buf: [4096]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/pal/{s}\x00", .{ sys_dir, name }) catch return -1;
    const path_z: [*:0]const u8 = path_buf[0 .. path.len - 1 :0];
    return c_io.open(path_z, .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .TRUNC = true,
    }, @as(c_io.mode_t, 0o644));
}

fn writeLog(fd: c_io.fd_t, comptime fmt: []const u8, args: anytype) void {
    if (fd < 0) return;
    var buf: [512]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, fmt, args) catch return;
    _ = c_io.write(fd, s.ptr, s.len);
}

fn logUnhandled(op: u16) void {
    // Strict mode: ZIGPAL_STRICT_OPCODES=1 turns the silent log into a panic
    // so a missing opcode shows up as a hard failure during a coverage run.
    if (strictOpcodes()) {
        std.debug.panic("zigpal: unhandled script opcode 0x{X:0>4}", .{op});
    }

    const byte = op / 8;
    const bit: u3 = @intCast(op & 7);
    if ((unhandled_logged[byte] & (@as(u8, 1) << bit)) != 0) return;
    unhandled_logged[byte] |= @as(u8, 1) << bit;

    if (!unhandled_log_inited) {
        unhandled_log_inited = true;
        unhandled_fd = openLogFile("zigpal_unhandled_ops.log");
    }
    writeLog(unhandled_fd, "unhandled opcode 0x{X}\n", .{op});
}

var strict_opcodes_cached: ?bool = null;

extern "c" fn getenv(name: [*:0]const u8) ?[*:0]const u8;

fn strictOpcodes() bool {
    if (strict_opcodes_cached) |v| return v;
    const ptr = getenv("ZIGPAL_STRICT_OPCODES");
    var on = false;
    if (ptr) |raw| {
        const s = std.mem.span(raw);
        on = s.len > 0 and s[0] != '0';
    }
    strict_opcodes_cached = on;
    return on;
}

// AutoScript execution trace — written to system/pal/zigpal_autoscript.log so
// we can see exactly what each NPC's auto_script is doing. Filtered to a few
// event-object IDs to keep the log readable.
var trace_fd: c_io.fd_t = -1;
var trace_inited: bool = false;
const TRACE_EVENT_IDS: [3]u16 = .{ 61, 74, 53 }; // adjust as needed

fn traceAuto(event_object_id: u16, entry: u16, op: u16, op0: u16, op1: u16, op2: u16) void {
    var match = false;
    for (TRACE_EVENT_IDS) |id| {
        if (id == event_object_id) match = true;
    }
    if (!match) return;

    if (!trace_inited) {
        trace_inited = true;
        trace_fd = openLogFile("zigpal_autoscript.log");
    }

    traceAutoBody(event_object_id, entry, op, op0, op1, op2);
}

fn traceWalk(event_object_id: u16, entry: u16, frame_num: u32, xor_bit: u16, op0: u16, op1: u16, op2: u16) void {
    if (trace_fd < 0) return;
    const eo = if (event_object_id != 0 and event_object_id <= global.gpg.g.event_objects.len)
        &global.gpg.g.event_objects[event_object_id - 1]
    else
        null;
    const px: i32 = if (eo) |p| @intCast(@as(u32, p.x)) else -1;
    const py: i32 = if (eo) |p| @intCast(@as(u32, p.y)) else -1;
    writeLog(
        trace_fd,
        "  WALK eo={d} entry=0x{X} frame={d} xor={d} target=({d},{d},h={d}) pos=({d},{d})\n",
        .{ event_object_id, entry, frame_num, xor_bit, op0, op1, op2, px, py },
    );
}

fn traceAutoBody(event_object_id: u16, entry: u16, op: u16, op0: u16, op1: u16, op2: u16) void {
    if (trace_fd < 0) return;
    const eo = if (event_object_id != 0 and event_object_id <= global.gpg.g.event_objects.len)
        &global.gpg.g.event_objects[event_object_id - 1]
    else
        null;
    const px: i32 = if (eo) |p| @intCast(@as(u32, p.x)) else -1;
    const py: i32 = if (eo) |p| @intCast(@as(u32, p.y)) else -1;
    const pst: i32 = if (eo) |p| p.state else 0;
    const pdir: u32 = if (eo) |p| p.direction else 0;
    writeLog(
        trace_fd,
        "eo={d} entry=0x{X} op=0x{X:0>4} args={X:0>4},{X:0>4},{X:0>4} pos=({d},{d}) state={d} dir={d}\n",
        .{ event_object_id, entry, op, op0, op1, op2, px, py, pst, pdir },
    );
}
