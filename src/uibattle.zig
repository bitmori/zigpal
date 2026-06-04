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
const video = @import("video.zig");
const ui = @import("ui.zig");

const SPRITENUM_PLAYERINFOBOX: i32 = 18;
const SPRITENUM_PLAYERFACE_FIRST: i32 = 48;
const SPRITENUM_SLASH: i32 = 39;

// PAL_PlayerInfoBox — render the player's info card (face, HP/MP). PAL_CLASSIC
// build only — the original signature carried unused time-meter args.
pub fn playerInfoBox(pos: palcommon.Pos, player_role: u16) void {

    if (palcommon.spriteGetFrame(ui.sprite_ui, SPRITENUM_PLAYERINFOBOX)) |bmp| {
        _ = palcommon.rleBlitToSurface(bmp, &video.screen, pos);
    }

    // Determine the strongest poison status to colorize the face.
    var party_index: i32 = -1;
    var i: u32 = 0;
    while (i <= global.gpg.max_party_member_index) : (i += 1) {
        if (global.gpg.party[i].player_role == player_role) {
            party_index = @intCast(i);
            break;
        }
    }

    var max_level: u16 = 0;
    var poison_color: u8 = 0xFF;
    if (party_index >= 0 and party_index <= @as(i32, global.gpg.max_party_member_index)) {
        var pi: u32 = 0;
        while (pi < global.MAX_POISONS) : (pi += 1) {
            const pid = global.gpg.poison_status[pi][@intCast(party_index)].poison_id;
            if (pid != 0 and global.gpg.g.objects[pid].poison().poison_level <= 3) {
                if (global.gpg.g.objects[pid].poison().poison_level >= max_level) {
                    max_level = global.gpg.g.objects[pid].poison().poison_level;
                    poison_color = @truncate(global.gpg.g.objects[pid].poison().color);
                }
            }
        }
    }

    if (global.gpg.g.player_roles.hp[player_role] == 0) {
        poison_color = 0;
    }

    const face_pos = palcommon.palXY(@intCast(palcommon.palX(pos) - 2), @intCast(palcommon.palY(pos) - 4));
    if (palcommon.spriteGetFrame(ui.sprite_ui, SPRITENUM_PLAYERFACE_FIRST + @as(i32, player_role))) |bmp| {
        if (poison_color == 0xFF) {
            _ = palcommon.rleBlitToSurface(bmp, &video.screen, face_pos);
        } else {
            _ = palcommon.rleBlitMonoColor(bmp, &video.screen, face_pos, poison_color, 0);
        }
    }

    // Classic HP/MP layout.
    if (palcommon.spriteGetFrame(ui.sprite_ui, SPRITENUM_SLASH)) |slash| {
        _ = palcommon.rleBlitToSurface(slash, &video.screen, palcommon.palXY(@intCast(palcommon.palX(pos) + 49), @intCast(palcommon.palY(pos) + 6)));
        _ = palcommon.rleBlitToSurface(slash, &video.screen, palcommon.palXY(@intCast(palcommon.palX(pos) + 49), @intCast(palcommon.palY(pos) + 22)));
    }
    ui.drawNumber(global.gpg.g.player_roles.max_hp[player_role], 4,
        palcommon.palXY(@intCast(palcommon.palX(pos) + 47), @intCast(palcommon.palY(pos) + 8)), .yellow, .right);
    ui.drawNumber(global.gpg.g.player_roles.hp[player_role], 4,
        palcommon.palXY(@intCast(palcommon.palX(pos) + 26), @intCast(palcommon.palY(pos) + 5)), .yellow, .right);
    ui.drawNumber(global.gpg.g.player_roles.max_mp[player_role], 4,
        palcommon.palXY(@intCast(palcommon.palX(pos) + 47), @intCast(palcommon.palY(pos) + 24)), .cyan, .right);
    ui.drawNumber(global.gpg.g.player_roles.mp[player_role], 4,
        palcommon.palXY(@intCast(palcommon.palX(pos) + 26), @intCast(palcommon.palY(pos) + 21)), .cyan, .right);
}
