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
const input = @import("input.zig");
const video = @import("video.zig");
const util = @import("util.zig");
const scene_mod = @import("scene.zig");
const script = @import("script.zig");

// PAL_GameUpdate — port of play.c PAL_GameUpdate.
pub fn gameUpdate(trigger: bool) void {
    if (trigger) {
        if (global.gpg.entering_scene) {
            global.gpg.entering_scene = false;
            const i: usize = @as(usize, global.gpg.num_scene) - 1;
            global.gpg.g.scenes[i].script_on_enter =
                script.runTriggerScript(global.gpg.g.scenes[i].script_on_enter, 0xFFFF);

            if (global.gpg.entering_scene) return;

            input.clearKeyState();
            input.forgetDirection();
            scene_mod.makeScene();
        }

        const scene_idx = @as(usize, global.gpg.num_scene) - 1;
        var event_object_id: u32 = global.gpg.g.scenes[scene_idx].event_object_index + 1;
        const end_eo: u32 = global.gpg.g.scenes[scene_idx + 1].event_object_index;

        while (event_object_id <= end_eo) : (event_object_id += 1) {
            const p = &global.gpg.g.event_objects[event_object_id - 1];

            if (p.vanish_time != 0) {
                p.vanish_time +%= if (p.vanish_time < 0) @as(i16, 1) else @as(i16, -1);
                continue;
            }

            if (p.state < 0) {
                const px = @as(i32, @bitCast(@as(u32, p.x)));
                const py = @as(i32, @bitCast(@as(u32, p.y)));
                if (px < global.palX(global.gpg.viewport) or px > global.palX(global.gpg.viewport) + 320 or
                    py < global.palY(global.gpg.viewport) or py > global.palY(global.gpg.viewport) + 320)
                {
                    p.state = @intCast(@abs(p.state));
                    p.current_frame_num = 0;
                }
            } else if (p.state > 0 and p.trigger_mode >= global.TRIGGER_TOUCH_NEAR) {
                const dx_abs = @abs(global.palX(global.gpg.viewport) + global.palX(global.gpg.party_offset) - @as(i32, @bitCast(@as(u32, p.x))));
                const dy_abs = @abs(global.palY(global.gpg.viewport) + global.palY(global.gpg.party_offset) - @as(i32, @bitCast(@as(u32, p.y)))) * 2;
                if (dx_abs + dy_abs < (@as(i32, p.trigger_mode) - global.TRIGGER_TOUCH_NEAR) * 32 + 16) {
                    if (p.sprite_frames != 0) {
                        p.current_frame_num = 0;
                        const x_off: i32 = global.palX(global.gpg.viewport) + global.palX(global.gpg.party_offset) - @as(i32, @bitCast(@as(u32, p.x)));
                        const y_off: i32 = global.palY(global.gpg.viewport) + global.palY(global.gpg.party_offset) - @as(i32, @bitCast(@as(u32, p.y)));
                        if (x_off > 0) {
                            p.direction = if (y_off > 0) 3 else 2; // east or north
                        } else {
                            p.direction = if (y_off > 0) 0 else 1; // south or west
                        }
                        scene_mod.updatePartyGestures(false);
                        scene_mod.makeScene();
                        video.updateScreen(null);
                    }

                    p.trigger_script = script.runTriggerScript(p.trigger_script, @intCast(event_object_id));
                    input.clearKeyState();
                    if (global.gpg.entering_scene) return;
                }
            }
        }
    }

    // Run autoscript for each event object.
    const scene_idx2 = @as(usize, global.gpg.num_scene) - 1;
    var eid2: u32 = global.gpg.g.scenes[scene_idx2].event_object_index + 1;
    const end_eo2: u32 = global.gpg.g.scenes[scene_idx2 + 1].event_object_index;
    while (eid2 <= end_eo2) : (eid2 += 1) {
        const p = &global.gpg.g.event_objects[eid2 - 1];

        if (p.state > 0 and p.vanish_time == 0) {
            const auto = p.auto_script;
            if (auto != 0) {
                p.auto_script = script.runAutoScript(auto, @intCast(eid2));
                if (global.gpg.entering_scene) return;
            }
        }

        // Check if the player is in the way.
        if (trigger and p.state >= global.OBJ_STATE_BLOCKER and p.sprite_num != 0) {
            const dx_abs = @abs(@as(i32, @bitCast(@as(u32, p.x))) - global.palX(global.gpg.viewport) - global.palX(global.gpg.party_offset));
            const dy_abs = @abs(@as(i32, @bitCast(@as(u32, p.y))) - global.palY(global.gpg.viewport) - global.palY(global.gpg.party_offset)) * 2;
            if (dx_abs + dy_abs <= 12) {
                // Player in the way — try to push past in successive directions.
                var w_dir: u32 = (@as(u32, p.direction) + 1) % 4;
                var i: u32 = 0;
                while (i < 4) : (i += 1) {
                    var x: i32 = global.palX(global.gpg.viewport) + global.palX(global.gpg.party_offset);
                    var y: i32 = global.palY(global.gpg.viewport) + global.palY(global.gpg.party_offset);
                    x += if (w_dir == 1 or w_dir == 0) @as(i32, -16) else @as(i32, 16);
                    y += if (w_dir == 1 or w_dir == 2) @as(i32, -8) else @as(i32, 8);
                    const pos = global.palXY(@truncate(x), @truncate(y));
                    if (!scene_mod.checkObstacleWithRange(pos, true, 0, true)) {
                        global.gpg.viewport = global.palXY(
                            @truncate(global.palX(pos) - global.palX(global.gpg.party_offset)),
                            @truncate(global.palY(pos) - global.palY(global.gpg.party_offset)),
                        );
                        break;
                    }
                    w_dir = (w_dir + 1) % 4;
                }
            }
        }
    }

    if (global.gpg.chase_speed_change_cycles > 0) {
        global.gpg.chase_speed_change_cycles -= 1;
        if (global.gpg.chase_speed_change_cycles == 0) {
            global.gpg.chase_range = 1;
        }
    }

    global.gpg.frame_num +%= 1;
}

// PAL_GetSearchTriggerRange — 13 checkpoints around the party for search events.
const TriggerRange = struct { pos: [13]u32 };

fn getSearchTriggerRange() TriggerRange {
    var x: i32 = global.palX(global.gpg.viewport) + global.palX(global.gpg.party_offset);
    var y: i32 = global.palY(global.gpg.viewport) + global.palY(global.gpg.party_offset);

    const x_offset: i32 = if (global.gpg.party_direction == 2 or global.gpg.party_direction == 3) 16 else -16;
    const y_offset: i32 = if (global.gpg.party_direction == 3 or global.gpg.party_direction == 0) 8 else -8;

    var r: TriggerRange = undefined;
    r.pos[0] = global.palXY(@truncate(x), @truncate(y));

    var i: usize = 0;
    while (i < 4) : (i += 1) {
        r.pos[i * 3 + 1] = global.palXY(@truncate(x + x_offset), @truncate(y + y_offset));
        r.pos[i * 3 + 2] = global.palXY(@truncate(x), @truncate(y + y_offset * 2));
        r.pos[i * 3 + 3] = global.palXY(@truncate(x + 2 * x_offset), @truncate(y));
        x += x_offset;
        y += y_offset;
    }
    return r;
}

// PAL_Search — process searching trigger events.
pub fn search() void {
    const r = getSearchTriggerRange();
    const scene_idx = @as(usize, global.gpg.num_scene) - 1;
    const start_eo: u32 = global.gpg.g.scenes[scene_idx].event_object_index;
    const end_eo: u32 = global.gpg.g.scenes[scene_idx + 1].event_object_index;

    var i: usize = 0;
    while (i < 13) : (i += 1) {
        const px = global.palX(r.pos[i]);
        const py = global.palY(r.pos[i]);
        const dh: i32 = if (@mod(@as(i32, px), 32) != 0) 1 else 0;
        const dx: i32 = @divTrunc(@as(i32, px), 32);
        const dy: i32 = @divTrunc(@as(i32, py), 16);

        var k: u32 = start_eo;
        while (k < end_eo) : (k += 1) {
            const p = &global.gpg.g.event_objects[k];
            const ex: i32 = @divTrunc(@as(i32, @bitCast(@as(u32, p.x))), 32);
            const ey: i32 = @divTrunc(@as(i32, @bitCast(@as(u32, p.y))), 16);
            const eh: i32 = if (@mod(@as(i32, @bitCast(@as(u32, p.x))), 32) != 0) 1 else 0;

            if (p.state <= 0 or p.trigger_mode >= global.TRIGGER_TOUCH_NEAR or
                @as(i32, p.trigger_mode) * 6 - 4 < @as(i32, @intCast(i)) or
                dx != ex or dy != ey or dh != eh)
            {
                continue;
            }

            if (@as(u32, p.sprite_frames) * 4 > p.current_frame_num) {
                p.current_frame_num = 0;
                p.direction = (global.gpg.party_direction + 2) % 4;

                var l: usize = 0;
                while (l <= global.gpg.max_party_member_index) : (l += 1) {
                    global.gpg.party[l].frame = @intCast(@as(u32, global.gpg.party_direction) * 3);
                }
                scene_mod.makeScene();
                video.updateScreen(null);
            }

            p.trigger_script = script.runTriggerScript(p.trigger_script, @intCast(k + 1));
            util.delay(50);
            input.clearKeyState();
            return;
        }
    }
}

// PAL_StartFrame — port of play.c PAL_StartFrame.
pub fn startFrame() void {
    gameUpdate(true);
    if (global.gpg.entering_scene) return;

    updateParty();
    scene_mod.makeScene();
    video.updateScreen(null);

    const k = input.state.key_press;
    if ((k & input.KEY_MENU) != 0) {
        @import("uigame.zig").inGameMenu();
        input.clearKeyState();
    } else if ((k & input.KEY_USEITEM) != 0) {
        @import("itemmenu.zig").gameUseItem();
    } else if ((k & input.KEY_THROWITEM) != 0) {
        @import("itemmenu.zig").gameEquipItem();
    } else if ((k & input.KEY_FORCE) != 0) {
        @import("magicmenu.zig").inGameMagicMenu();
    } else if ((k & input.KEY_STATUS) != 0) {
        @import("playerstatus.zig").playerStatus();
    } else if ((k & input.KEY_SEARCH) != 0) {
        search();
    } else if ((k & input.KEY_FLEE) != 0) {
        @import("uigame.zig").quitGame();
    }

    @import("debug.zig").pollMenuRequest();
}

// PAL_UpdateParty — re-export from scene.zig so play.zig serves as the public API.
pub fn updateParty() void {
    scene_mod.updateParty();
}

// PAL_WaitForKey — wait for menu/search key, with optional timeout (in ms).
pub fn waitForKeyInternal(timeout_ms: u32, allow_any_key: bool) void {
    const start = util.getTicks();
    const target = start +% timeout_ms;
    input.clearKeyState();

    while (timeout_ms == 0 or util.getTicks() < target) {
        if (util.shouldQuit()) return;
        util.delay(5);
        input.processEvent();
        const k = input.state.key_press;
        if (allow_any_key and k != 0) break;
        if ((k & (input.KEY_SEARCH | input.KEY_MENU)) != 0) break;
    }
}

pub fn waitForKey(timeout_ms: u32) void {
    waitForKeyInternal(timeout_ms, false);
}

pub fn waitForAnyKey(timeout_ms: u32) void {
    waitForKeyInternal(timeout_ms, true);
}
