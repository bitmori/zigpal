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
const map_mod = @import("map.zig");
const res = @import("res.zig");
const palcommon = @import("palcommon.zig");
const palette_mod = @import("palette.zig");
const input = @import("input.zig");

const MAX_SPRITE_TO_DRAW = 2048;

const SpriteToDraw = struct {
    sprite_frame: []const u8,
    pos: u32,
    layer: i32,
};

var sprite_buf: [MAX_SPRITE_TO_DRAW]SpriteToDraw = undefined;
var n_sprite_to_draw: usize = 0;

fn addSpriteToDraw(sprite_frame: []const u8, x: i32, y: i32, layer: i32) void {
    if (n_sprite_to_draw >= MAX_SPRITE_TO_DRAW) return;
    sprite_buf[n_sprite_to_draw] = .{
        .sprite_frame = sprite_frame,
        .pos = global.palXY(@truncate(x), @truncate(y)),
        .layer = layer,
    };
    n_sprite_to_draw += 1;
}

// PAL_CalcCoverTiles
fn calcCoverTiles(s: SpriteToDraw) void {
    const map_p = res.getCurrentMap() orelse return;
    const sx: i32 = global.palX(global.gpg.viewport) + global.palX(s.pos) - @divTrunc(s.layer, 2);
    const sy: i32 = global.palY(global.gpg.viewport) + global.palY(s.pos) - s.layer;
    const sh: i32 = if (@mod(sx, 32) != 0) 1 else 0;

    const width: i32 = palcommon.rleGetWidth(s.sprite_frame);
    const height: i32 = palcommon.rleGetHeight(s.sprite_frame);

    var dx: i32 = 0;
    var dy: i32 = 0;
    var dh: i32 = 0;

    var y: i32 = @divTrunc(sy - height - 15, 16);
    while (y <= @divTrunc(sy, 16)) : (y += 1) {
        var x: i32 = @divTrunc(sx - @divTrunc(width, 2), 32);
        while (x <= @divTrunc(sx + @divTrunc(width, 2), 32)) : (x += 1) {
            const start_i: i32 = if (x == @divTrunc(sx - @divTrunc(width, 2), 32)) 0 else 3;
            var i: i32 = start_i;
            while (i < 5) : (i += 1) {
                switch (i) {
                    0 => {
                        dx = x;
                        dy = y;
                        dh = sh;
                    },
                    1 => {
                        dx = x - 1;
                    },
                    2 => {
                        dx = if (sh != 0) x else (x - 1);
                        dy = if (sh != 0) (y + 1) else y;
                        dh = 1 - sh;
                    },
                    3 => {
                        dx = x + 1;
                        dy = y;
                        dh = sh;
                    },
                    4 => {
                        dx = if (sh != 0) (x + 1) else x;
                        dy = if (sh != 0) (y + 1) else y;
                        dh = 1 - sh;
                    },
                    else => {},
                }

                var l: u8 = 0;
                while (l < 2) : (l += 1) {
                    const tile = map_mod.getTileBitmap(
                        map_p,
                        @truncate(@as(u32, @bitCast(dx)) & 0xff),
                        @truncate(@as(u32, @bitCast(dy)) & 0xff),
                        @truncate(@as(u32, @bitCast(dh)) & 0xff),
                        l,
                    );
                    const tile_h_raw: u8 = map_mod.getTileHeight(
                        map_p,
                        @truncate(@as(u32, @bitCast(dx)) & 0xff),
                        @truncate(@as(u32, @bitCast(dy)) & 0xff),
                        @truncate(@as(u32, @bitCast(dh)) & 0xff),
                        l,
                    );
                    const tile_h: i32 = @as(i32, @as(i8, @bitCast(tile_h_raw)));

                    if (tile != null and tile_h > 0 and (dy + tile_h) * 16 + dh * 8 >= sy) {
                        addSpriteToDraw(
                            tile.?,
                            dx * 32 + dh * 16 - 16 - global.palX(global.gpg.viewport),
                            dy * 16 + dh * 8 + 7 + @as(i32, l) + tile_h * 8 - global.palY(global.gpg.viewport),
                            tile_h * 8 + @as(i32, l),
                        );
                    }
                }
            }
        }
    }
}

// PAL_SceneDrawSprites
fn sceneDrawSprites() void {
    n_sprite_to_draw = 0;

    // Players
    var i: usize = 0;
    while (i <= @as(usize, global.gpg.max_party_member_index) + global.gpg.n_follower) : (i += 1) {
        const sprite = res.getPlayerSprite(@intCast(i)) orelse continue;
        const frame = palcommon.spriteGetFrame(sprite, @intCast(global.gpg.party[i].frame)) orelse continue;
        addSpriteToDraw(
            frame,
            @as(i32, global.gpg.party[i].x) - @divTrunc(@as(i32, palcommon.rleGetWidth(frame)), 2),
            @as(i32, global.gpg.party[i].y) + @as(i32, global.gpg.layer) + 10,
            @as(i32, global.gpg.layer) + 6,
        );
        calcCoverTiles(sprite_buf[n_sprite_to_draw - 1]);
    }

    // Event objects
    const scene_idx = @as(usize, global.gpg.num_scene) - 1;
    const start_eo: u32 = global.gpg.g.scenes[scene_idx].event_object_index;
    const end_eo: u32 = global.gpg.g.scenes[scene_idx + 1].event_object_index;
    var k: u32 = start_eo;
    while (k < end_eo) : (k += 1) {
        const eo = &global.gpg.g.event_objects[k];
        if (eo.state == @as(i16, global.OBJ_STATE_HIDDEN) or eo.vanish_time > 0 or eo.state < 0) continue;
        const sprite = res.getEventObjectSprite(@intCast(k + 1)) orelse continue;

        var i_frame: u32 = eo.current_frame_num;
        if (eo.sprite_frames == 3) {
            if (i_frame == 2) i_frame = 0;
            if (i_frame == 3) i_frame = 2;
        }
        const frame_idx: i32 = @intCast(@as(u32, eo.direction) * eo.sprite_frames + i_frame);
        const frame = palcommon.spriteGetFrame(sprite, frame_idx) orelse continue;

        var x: i32 = @as(i32, @as(i16, @bitCast(eo.x))) - global.palX(global.gpg.viewport);
        x -= @divTrunc(@as(i32, palcommon.rleGetWidth(frame)), 2);
        if (x >= 320 or x < -@as(i32, palcommon.rleGetWidth(frame))) continue;

        var y: i32 = @as(i32, @as(i16, @bitCast(eo.y))) - global.palY(global.gpg.viewport);
        y += @as(i32, eo.layer) * 8 + 9;

        const vy: i32 = y - @as(i32, palcommon.rleGetHeight(frame)) - @as(i32, eo.layer) * 8 + 2;
        if (vy >= 200 or vy < -@as(i32, palcommon.rleGetHeight(frame))) continue;

        addSpriteToDraw(frame, x, y, @as(i32, eo.layer) * 8 + 2);
        calcCoverTiles(sprite_buf[n_sprite_to_draw - 1]);
    }

    // Sort by Y position (bubble sort like SDLPAL).
    if (n_sprite_to_draw > 1) {
        var x: usize = 0;
        while (x < n_sprite_to_draw - 1) : (x += 1) {
            var swapped = false;
            var y2: usize = 0;
            while (y2 + 1 < n_sprite_to_draw - x) : (y2 += 1) {
                if (global.palY(sprite_buf[y2].pos) > global.palY(sprite_buf[y2 + 1].pos)) {
                    swapped = true;
                    const tmp = sprite_buf[y2];
                    sprite_buf[y2] = sprite_buf[y2 + 1];
                    sprite_buf[y2 + 1] = tmp;
                }
            }
            if (!swapped) break;
        }
    }

    // Draw all sprites.
    var idx: usize = 0;
    while (idx < n_sprite_to_draw) : (idx += 1) {
        const p = sprite_buf[idx];
        const sx = global.palX(p.pos);
        const sy: i32 = @as(i32, global.palY(p.pos)) - @as(i32, palcommon.rleGetHeight(p.sprite_frame)) - p.layer;
        _ = palcommon.rleBlitToSurface(p.sprite_frame, &video.screen, palcommon.palXY(sx, @truncate(sy)));
    }
}

// PAL_ApplyWave — apply screen wave effect to a surface.
var wave_index: i32 = 0;

pub fn applyWave() void {
    global.gpg.screen_wave = @intCast(@as(i32, @intCast(global.gpg.screen_wave)) + global.gpg.wave_progression);
    if (global.gpg.screen_wave == 0 or global.gpg.screen_wave >= 256) {
        global.gpg.screen_wave = 0;
        global.gpg.wave_progression = 0;
        return;
    }

    var wave: [32]i32 = undefined;
    var a: i32 = 0;
    var b: i32 = 60 + 8;
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        b -= 8;
        a += b;
        wave[i] = @divTrunc(a * @as(i32, global.gpg.screen_wave), 256);
        wave[i + 16] = 320 - wave[i];
    }

    var buf: [320]u8 = undefined;
    var line_idx: i32 = wave_index;
    var py: usize = 0;
    while (py < 200) : (py += 1) {
        const off = wave[@intCast(line_idx)];
        if (off > 0) {
            const off_u: usize = @intCast(off);
            const row = video.screen_pixels[py * 320 .. py * 320 + 320];
            @memcpy(buf[0..off_u], row[0..off_u]);
            std.mem.copyForwards(u8, row[0 .. 320 - off_u], row[off_u..320]);
            @memcpy(row[320 - off_u .. 320], buf[0..off_u]);
        }
        line_idx = @mod(line_idx + 1, 32);
    }

    wave_index = @mod(wave_index + 1, 32);
}

// PAL_MakeScene
pub fn makeScene() void {
    if (res.getCurrentMap()) |m| {
        const rect: map_mod.Rect = .{
            .x = global.palX(global.gpg.viewport),
            .y = global.palY(global.gpg.viewport),
            .w = 320,
            .h = 200,
        };
        map_mod.blitToSurface(m, &video.screen, rect, 0);
        map_mod.blitToSurface(m, &video.screen, rect, 1);
    }

    applyWave();
    sceneDrawSprites();
    @import("debug.zig").drawOverlay();
}

// Consume need_to_fade_in flag. Called once per frame from startFrame,
// NOT from inside makeScene (which may run nested inside paletteFade loops).
pub fn checkFadeIn() void {
    if (global.gpg.need_to_fade_in) {
        video.updateScreen(null);
        palette_mod.fadeIn(@intCast(global.gpg.num_palette), global.gpg.night_palette, 1);
        global.gpg.need_to_fade_in = false;
    }
}

// PAL_CheckObstacle / PAL_CheckObstacleWithRange
pub fn checkObstacle(pos: u32, check_event_objects: bool, self_object: u16) bool {
    return checkObstacleWithRange(pos, check_event_objects, self_object, false);
}

pub fn checkObstacleWithRange(pos: u32, check_event_objects: bool, self_object: u16, check_range: bool) bool {
    const block_x = @divTrunc(global.palX(global.gpg.party_offset), 32);
    const block_y = @divTrunc(global.palY(global.gpg.party_offset), 16);

    var x: i32 = @divTrunc(@as(i32, global.palX(pos)), 32);
    var y: i32 = @divTrunc(@as(i32, global.palY(pos)), 16);
    var h: u8 = 0;

    if (check_range) {
        if (x < block_x or x >= 2048 or y < block_y or y >= 2048) return true;
    }

    const xr: i32 = @mod(@as(i32, global.palX(pos)), 32);
    const yr: i32 = @mod(@as(i32, global.palY(pos)), 16);

    if (xr + yr * 2 >= 16) {
        if (xr + yr * 2 >= 48) {
            x += 1;
            y += 1;
        } else if (32 - xr + yr * 2 < 16) {
            x += 1;
        } else if (32 - xr + yr * 2 < 48) {
            h = 1;
        } else {
            y += 1;
        }
    }

    if (res.getCurrentMap()) |m| {
        if (map_mod.tileIsBlocked(m, @truncate(@as(u32, @bitCast(x)) & 0xff), @truncate(@as(u32, @bitCast(y)) & 0xff), h)) {
            return true;
        }
    }

    if (check_event_objects) {
        const scene_idx = @as(usize, global.gpg.num_scene) - 1;
        const start_eo: u32 = global.gpg.g.scenes[scene_idx].event_object_index;
        const end_eo: u32 = global.gpg.g.scenes[scene_idx + 1].event_object_index;
        var i: u32 = start_eo;
        while (i < end_eo) : (i += 1) {
            const p = &global.gpg.g.event_objects[i];
            if (i == @as(u32, self_object) -% 1) continue;
            if (p.state >= global.OBJ_STATE_BLOCKER) {
                const dx = @abs(@as(i32, @bitCast(@as(u32, p.x))) - @as(i32, global.palX(pos)));
                const dy = @abs(@as(i32, @bitCast(@as(u32, p.y))) - @as(i32, global.palY(pos))) * 2;
                if (dx + dy < 16) return true;
            }
        }
    }

    return false;
}

// PAL_UpdatePartyGestures
var s_this_step_frame: i32 = 0;

pub fn updatePartyGestures(walking: bool) void {
    var step_frame_follower: i32 = 0;
    var step_frame_leader: i32 = 0;

    if (walking and global.gpg.max_party_member_index < 3) {
        s_this_step_frame = @mod(s_this_step_frame + 1, 4);
        if ((s_this_step_frame & 1) != 0) {
            step_frame_leader = @divTrunc(s_this_step_frame + 1, 2);
            step_frame_follower = 3 - step_frame_leader;
        } else {
            step_frame_leader = 0;
            step_frame_follower = 0;
        }

        global.gpg.party[0].x = global.palX(global.gpg.party_offset);
        global.gpg.party[0].y = global.palY(global.gpg.party_offset);

        if (global.gpg.g.player_roles.walk_frames[global.gpg.party[0].player_role] == 4) {
            global.gpg.party[0].frame = @intCast(@as(i32, global.gpg.party_direction) * 4 + s_this_step_frame);
        } else {
            global.gpg.party[0].frame = @intCast(@as(i32, global.gpg.party_direction) * 3 + step_frame_leader);
        }

        var i: usize = 1;
        while (i <= global.gpg.max_party_member_index) : (i += 1) {
            global.gpg.party[i].x = @as(i16, @bitCast(global.gpg.trail[1].x)) - global.palX(global.gpg.viewport);
            global.gpg.party[i].y = @as(i16, @bitCast(global.gpg.trail[1].y)) - global.palY(global.gpg.viewport);

            if (i == 2) {
                global.gpg.party[i].x += if (global.gpg.trail[1].direction == 3 or global.gpg.trail[1].direction == 1) @as(i16, -16) else @as(i16, 16);
                global.gpg.party[i].y += 8;
            } else {
                global.gpg.party[i].x += if (global.gpg.trail[1].direction == 1 or global.gpg.trail[1].direction == 0) @as(i16, 16) else @as(i16, -16);
                global.gpg.party[i].y += if (global.gpg.trail[1].direction == 1 or global.gpg.trail[1].direction == 2) @as(i16, 8) else @as(i16, -8);
            }

            const px = @as(i32, global.gpg.party[i].x) + global.palX(global.gpg.viewport);
            const py = @as(i32, global.gpg.party[i].y) + global.palY(global.gpg.viewport);
            if (checkObstacleWithRange(global.palXY(@truncate(px), @truncate(py)), true, 0, true)) {
                global.gpg.party[i].x = @as(i16, @bitCast(global.gpg.trail[1].x)) - global.palX(global.gpg.viewport);
                global.gpg.party[i].y = @as(i16, @bitCast(global.gpg.trail[1].y)) - global.palY(global.gpg.viewport);
            }

            if (global.gpg.g.player_roles.walk_frames[global.gpg.party[i].player_role] == 4) {
                global.gpg.party[i].frame = @intCast(@as(i32, global.gpg.trail[2].direction) * 4 + s_this_step_frame);
            } else {
                global.gpg.party[i].frame = @intCast(@as(i32, global.gpg.trail[2].direction) * 3 + step_frame_leader);
            }
        }

        var f: u32 = 1;
        while (f <= global.gpg.n_follower) : (f += 1) {
            const idx = global.gpg.max_party_member_index + f;
            global.gpg.party[idx].x = @as(i16, @bitCast(global.gpg.trail[2 + f].x)) - global.palX(global.gpg.viewport);
            global.gpg.party[idx].y = @as(i16, @bitCast(global.gpg.trail[2 + f].y)) - global.palY(global.gpg.viewport);
            global.gpg.party[idx].frame = @intCast(@as(i32, global.gpg.trail[2 + f].direction) * 3 + step_frame_follower);
        }
    } else if (walking and global.gpg.max_party_member_index >= 3) {
        // 魔改 — 4-person party gesture update. Each follower uses its own
        // trail slot (i-1) and applies an offset based on trail[i-1].direction.
        s_this_step_frame = @mod(s_this_step_frame + 1, 4);
        if ((s_this_step_frame & 1) != 0) {
            step_frame_leader = @divTrunc(s_this_step_frame + 1, 2);
            step_frame_follower = 3 - step_frame_leader;
        } else {
            step_frame_leader = 0;
            step_frame_follower = 0;
        }

        global.gpg.party[0].x = global.palX(global.gpg.party_offset);
        global.gpg.party[0].y = global.palY(global.gpg.party_offset);

        if (global.gpg.g.player_roles.walk_frames[global.gpg.party[0].player_role] == 4) {
            global.gpg.party[0].frame = @intCast(@as(i32, global.gpg.party_direction) * 4 + s_this_step_frame);
        } else {
            global.gpg.party[0].frame = @intCast(@as(i32, global.gpg.party_direction) * 3 + step_frame_leader);
        }

        var i: usize = 1;
        while (i <= global.gpg.max_party_member_index) : (i += 1) {
            const trail_idx = i - 1;
            global.gpg.party[i].x = @as(i16, @bitCast(global.gpg.trail[trail_idx].x)) - global.palX(global.gpg.viewport);
            global.gpg.party[i].y = @as(i16, @bitCast(global.gpg.trail[trail_idx].y)) - global.palY(global.gpg.viewport);

            // Offset: west(1)/south(0) → x+16; else x-16.
            //         west(1)/north(2) → y+8; else y-8.
            const dir = global.gpg.trail[trail_idx].direction;
            global.gpg.party[i].x += if (dir == 1 or dir == 0) @as(i16, 16) else @as(i16, -16);
            global.gpg.party[i].y += if (dir == 1 or dir == 2) @as(i16, 8) else @as(i16, -8);

            const px = @as(i32, global.gpg.party[i].x) + global.palX(global.gpg.viewport);
            const py = @as(i32, global.gpg.party[i].y) + global.palY(global.gpg.viewport);
            if (checkObstacleWithRange(global.palXY(@truncate(px), @truncate(py)), true, 0, true)) {
                global.gpg.party[i].x = @as(i16, @bitCast(global.gpg.trail[trail_idx].x)) - global.palX(global.gpg.viewport);
                global.gpg.party[i].y = @as(i16, @bitCast(global.gpg.trail[trail_idx].y)) - global.palY(global.gpg.viewport);
            }

            if (global.gpg.g.player_roles.walk_frames[global.gpg.party[i].player_role] == 4) {
                global.gpg.party[i].frame = @intCast(@as(i32, global.gpg.trail[trail_idx].direction) * 4 + s_this_step_frame);
            } else {
                global.gpg.party[i].frame = @intCast(@as(i32, global.gpg.trail[trail_idx].direction) * 3 + step_frame_leader);
            }
        }

        if (global.gpg.n_follower > 0) {
            const follow_trail = global.gpg.max_party_member_index + 1;
            global.gpg.party[follow_trail].x = @as(i16, @bitCast(global.gpg.trail[follow_trail].x)) - global.palX(global.gpg.viewport);
            global.gpg.party[follow_trail].y = @as(i16, @bitCast(global.gpg.trail[follow_trail].y)) - global.palY(global.gpg.viewport);
            global.gpg.party[follow_trail].frame = @intCast(@as(i32, global.gpg.trail[follow_trail].direction) * 3 + step_frame_follower);
        }
    } else {
        var f0: i32 = global.gpg.g.player_roles.walk_frames[global.gpg.party[0].player_role];
        if (f0 == 0) f0 = 3;
        global.gpg.party[0].frame = @intCast(@as(i32, global.gpg.party_direction) * f0);

        var i: usize = 1;
        while (i <= global.gpg.max_party_member_index) : (i += 1) {
            var f: i32 = global.gpg.g.player_roles.walk_frames[global.gpg.party[i].player_role];
            if (f == 0) f = 3;
            global.gpg.party[i].frame = @intCast(@as(i32, global.gpg.trail[2].direction) * f);
        }

        var k: u32 = 1;
        while (k <= global.gpg.n_follower) : (k += 1) {
            const idx = global.gpg.max_party_member_index + k;
            global.gpg.party[idx].frame = @intCast(@as(i32, global.gpg.trail[2 + k].direction) * 3);
        }

        s_this_step_frame &= 2;
        s_this_step_frame ^= 2;
    }
}

// PAL_UpdateParty
pub fn updateParty() void {
    if (input.state.dir != .unknown) {
        const dir = input.state.dir;
        const x_offset: i32 = if (dir == .west or dir == .south) -16 else 16;
        const y_offset: i32 = if (dir == .west or dir == .north) -8 else 8;

        const x_source = global.palX(global.gpg.viewport) + global.palX(global.gpg.party_offset);
        const y_source = global.palY(global.gpg.viewport) + global.palY(global.gpg.party_offset);
        const x_target = x_source + x_offset;
        const y_target = y_source + y_offset;

        global.gpg.party_direction = @intFromEnum(dir);

        if (!checkObstacleWithRange(global.palXY(@truncate(x_target), @truncate(y_target)), true, 0, true)) {
            var i: i32 = 3;
            while (i >= 0) : (i -= 1) {
                global.gpg.trail[@intCast(i + 1)] = global.gpg.trail[@intCast(i)];
            }
            global.gpg.trail[0].direction = @intFromEnum(dir);
            global.gpg.trail[0].x = @bitCast(@as(i16, @truncate(x_source)));
            global.gpg.trail[0].y = @bitCast(@as(i16, @truncate(y_source)));

            global.gpg.viewport = global.palXY(
                @truncate(global.palX(global.gpg.viewport) + x_offset),
                @truncate(global.palY(global.gpg.viewport) + y_offset),
            );
            updatePartyGestures(true);
            return;
        }
    }
    updatePartyGestures(false);
}

// PAL_NPCWalkOneStep
pub fn npcWalkOneStep(event_object_id: u16, speed: i32) void {
    if (event_object_id == 0 or event_object_id > global.gpg.g.event_objects.len) return;
    const p = &global.gpg.g.event_objects[event_object_id - 1];

    const dx: i32 = if (p.direction == 1 or p.direction == 0) -2 else 2; // west/south negative
    const dy: i32 = if (p.direction == 1 or p.direction == 2) -1 else 1; // west/north negative
    p.x = @intCast(@as(i32, @bitCast(@as(u32, p.x))) + dx * speed);
    p.y = @intCast(@as(i32, @bitCast(@as(u32, p.y))) + dy * speed);

    if (p.sprite_frames > 0) {
        p.current_frame_num +%= 1;
        const m: u16 = if (p.sprite_frames == 3) 4 else p.sprite_frames;
        p.current_frame_num = @mod(p.current_frame_num, m);
    } else if (p.sprite_frames_auto > 0) {
        p.current_frame_num +%= 1;
        p.current_frame_num = @mod(p.current_frame_num, p.sprite_frames_auto);
    }
}
