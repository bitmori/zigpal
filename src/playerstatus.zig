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
const text = @import("text.zig");
const input = @import("input.zig");
const util = @import("util.zig");

// From ui.h.
const STATUS_BACKGROUND_FBPNUM: u32 = 0;
const STATUS_COLOR_EQUIPMENT: u8 = 0xBE;
const SPRITENUM_SLASH: i32 = 39;

const STATUS_LABEL_EXP: u16 = 2;
const STATUS_LABEL_LEVEL: u16 = 48;
const STATUS_LABEL_HP: u16 = 49;
const STATUS_LABEL_MP: u16 = 50;
const STATUS_LABEL_ATTACKPOWER: u16 = 51;
const STATUS_LABEL_MAGICPOWER: u16 = 52;
const STATUS_LABEL_RESISTANCE: u16 = 53;
const STATUS_LABEL_DEXTERITY: u16 = 54;
const STATUS_LABEL_FLEERATE: u16 = 55;

// Layout positions (default DOS layout from palcfg.c).
const PL_ROLE_NAME = global.palXY(110, 8);
const PL_ROLE_IMAGE = global.palXY(110, 30);
const PL_ROLE_EXP_LABEL = global.palXY(6, 6);
const PL_ROLE_LEVEL_LABEL = global.palXY(6, 32);
const PL_ROLE_HP_LABEL = global.palXY(6, 54);
const PL_ROLE_MP_LABEL = global.palXY(6, 76);
const PL_ROLE_STATUS_LABELS = [_]palcommon.Pos{
    global.palXY(6, 98),  global.palXY(6, 118),
    global.palXY(6, 138), global.palXY(6, 158),
    global.palXY(6, 178),
};
const PL_ROLE_CURR_EXP = global.palXY(58, 6);
const PL_ROLE_NEXT_EXP = global.palXY(58, 15);
const PL_ROLE_LEVEL = global.palXY(54, 35);
const PL_ROLE_CUR_HP = global.palXY(42, 56);
const PL_ROLE_MAX_HP = global.palXY(63, 61);
const PL_ROLE_HP_SLASH = global.palXY(65, 58);
const PL_ROLE_CUR_MP = global.palXY(42, 78);
const PL_ROLE_MAX_MP = global.palXY(63, 83);
const PL_ROLE_MP_SLASH = global.palXY(65, 80);
const PL_ROLE_STATUS_VALUES = [_]palcommon.Pos{
    global.palXY(42, 102), global.palXY(42, 122),
    global.palXY(42, 142), global.palXY(42, 162),
    global.palXY(42, 182),
};
const PL_ROLE_EQUIP_IMAGE_BOXES = [_]palcommon.Pos{
    global.palXY(189, -1),  global.palXY(247, 39),
    global.palXY(251, 101), global.palXY(201, 133),
    global.palXY(141, 141), global.palXY(81, 125),
};
const PL_ROLE_EQUIP_NAMES = [_]palcommon.Pos{
    global.palXY(195, 38),  global.palXY(253, 78),
    global.palXY(257, 140), global.palXY(207, 172),
    global.palXY(147, 180), global.palXY(87, 164),
};
const PL_ROLE_POISON_NAMES = [_]palcommon.Pos{
    global.palXY(185, 58),  global.palXY(185, 76),
    global.palXY(185, 94),  global.palXY(185, 112),
    global.palXY(185, 130), global.palXY(185, 148),
    global.palXY(185, 166), global.palXY(185, 184),
    global.palXY(185, 184), global.palXY(185, 184),
};

// PAL_PlayerStatus.
pub fn playerStatus() void {
    const fbp = global.gpg.f.fbp orelse return;

    const bg_buf = decompressFbpChunk(fbp, STATUS_BACKGROUND_FBPNUM) catch return;
    defer global.allocator.free(bg_buf);

    var rle_buf: [palcommon.PAL_RLEBUFSIZE]u8 = undefined;
    var current: i32 = 0;

    while (current >= 0 and current <= @as(i32, global.gpg.max_party_member_index)) {
        const player_role: u16 = global.gpg.party[@intCast(current)].player_role;

        // Background.
        _ = palcommon.fbpBlitToSurface(bg_buf, &video.screen);

        // Role avatar from RGM.MKF.
        if (global.gpg.f.rgm) |rgm| {
            const avatar_chunk = global.gpg.g.player_roles.avatar[player_role];
            const got = readRleChunk(rgm, avatar_chunk, &rle_buf);
            if (got > 0) {
                _ = palcommon.rleBlitToSurface(rle_buf[0..got], &video.screen, PL_ROLE_IMAGE);
            }
        }

        // Equipments.
        if (global.gpg.f.ball) |ball| {
            var i: u32 = 0;
            while (i < global.MAX_PLAYER_EQUIPMENTS) : (i += 1) {
                const w = global.gpg.g.player_roles.equipment[i][player_role];
                if (w == 0) continue;

                const bitmap = global.gpg.g.objects[w].item().bitmap;
                const got = readRleChunk(ball, bitmap, &rle_buf);
                if (got > 0) {
                    _ = palcommon.rleBlitToSurface(
                        rle_buf[0..got],
                        &video.screen,
                        global.palXyOffset(PL_ROLE_EQUIP_IMAGE_BOXES[i], 1, 1),
                    );
                }

                // Name label, possibly nudged left if it would overflow 320.
                var offset: i32 = ui.wordWidth(w) * 16;
                const name_x: i32 = palcommon.palX(PL_ROLE_EQUIP_NAMES[i]);
                if (name_x + offset > 320) {
                    offset = 320 - name_x - offset;
                } else {
                    offset = 0;
                }
                text.drawText(
                    text.getWord(w),
                    global.palXyOffset(PL_ROLE_EQUIP_NAMES[i], offset, 0),
                    STATUS_COLOR_EQUIPMENT,
                    true,
                    false,
                );
            }
        }

        // Stat labels.
        const labels0 = [_]u16{ STATUS_LABEL_EXP, STATUS_LABEL_LEVEL, STATUS_LABEL_HP, STATUS_LABEL_MP };
        const label_positions = [_]palcommon.Pos{
            PL_ROLE_EXP_LABEL, PL_ROLE_LEVEL_LABEL, PL_ROLE_HP_LABEL, PL_ROLE_MP_LABEL,
        };
        for (labels0, 0..) |lbl, i| {
            text.drawText(text.getWord(lbl), label_positions[i], ui.MENUITEM_COLOR, true, false);
        }
        const labels = [_]u16{
            STATUS_LABEL_ATTACKPOWER, STATUS_LABEL_MAGICPOWER, STATUS_LABEL_RESISTANCE,
            STATUS_LABEL_DEXTERITY,   STATUS_LABEL_FLEERATE,
        };
        for (labels, 0..) |lbl, i| {
            text.drawText(text.getWord(lbl), PL_ROLE_STATUS_LABELS[i], ui.MENUITEM_COLOR, true, false);
        }

        // Role name.
        text.drawText(
            text.getWord(global.gpg.g.player_roles.name[player_role]),
            PL_ROLE_NAME,
            ui.MENUITEM_COLOR_CONFIRMED,
            true,
            false,
        );

        // HP/MP slashes.
        if (palcommon.spriteGetFrame(ui.sprite_ui, SPRITENUM_SLASH)) |slash| {
            _ = palcommon.rleBlitToSurface(slash, &video.screen, PL_ROLE_HP_SLASH);
            _ = palcommon.rleBlitToSurface(slash, &video.screen, PL_ROLE_MP_SLASH);
        }

        // Numbers.
        ui.drawNumber(global.gpg.exp.primary[player_role].exp, 5, PL_ROLE_CURR_EXP, .yellow, .right);
        const level: u16 = global.gpg.g.player_roles.level[player_role];
        ui.drawNumber(global.gpg.g.level_up_exp[level], 5, PL_ROLE_NEXT_EXP, .cyan, .right);
        ui.drawNumber(level, 2, PL_ROLE_LEVEL, .yellow, .right);
        ui.drawNumber(global.gpg.g.player_roles.hp[player_role], 4, PL_ROLE_CUR_HP, .yellow, .right);
        ui.drawNumber(global.gpg.g.player_roles.max_hp[player_role], 4, PL_ROLE_MAX_HP, .blue, .right);
        ui.drawNumber(global.gpg.g.player_roles.mp[player_role], 4, PL_ROLE_CUR_MP, .yellow, .right);
        ui.drawNumber(global.gpg.g.player_roles.max_mp[player_role], 4, PL_ROLE_MAX_MP, .blue, .right);

        ui.drawNumber(global.getPlayerAttackStrength(player_role), 4, PL_ROLE_STATUS_VALUES[0], .yellow, .right);
        ui.drawNumber(global.getPlayerMagicStrength(player_role), 4, PL_ROLE_STATUS_VALUES[1], .yellow, .right);
        ui.drawNumber(global.getPlayerDefense(player_role), 4, PL_ROLE_STATUS_VALUES[2], .yellow, .right);
        ui.drawNumber(global.getPlayerDexterity(player_role), 4, PL_ROLE_STATUS_VALUES[3], .yellow, .right);
        ui.drawNumber(global.getPlayerFleeRate(player_role), 4, PL_ROLE_STATUS_VALUES[4], .yellow, .right);

        // Poisons.
        var pi: u32 = 0;
        var pj: u32 = 0;
        while (pi < global.MAX_POISONS) : (pi += 1) {
            const w = global.gpg.poison_status[pi][@intCast(current)].poison_id;
            if (w != 0 and global.gpg.g.objects[w].poison().poison_level <= 3) {
                const color: u8 = @intCast((global.gpg.g.objects[w].poison().color + 10) & 0xFF);
                text.drawText(
                    text.getWord(w),
                    PL_ROLE_POISON_NAMES[pj],
                    color,
                    true,
                    false,
                );
                pj += 1;
            }
        }

        video.updateScreen(null);

        input.clearKeyState();
        while (true) {
            if (util.shouldQuit()) {
                current = -1;
                break;
            }
            util.delay(1);
            input.processEvent();
            const k = input.state.key_press;
            if ((k & input.KEY_MENU) != 0) {
                current = -1;
                break;
            } else if ((k & (input.KEY_LEFT | input.KEY_UP)) != 0) {
                current -= 1;
                break;
            } else if ((k & (input.KEY_RIGHT | input.KEY_DOWN | input.KEY_SEARCH)) != 0) {
                current += 1;
                break;
            }
        }
    }
}

// Read a chunk from MKF — chunks in BALL/RGM are not YJ1-compressed, so we
// just memcpy the raw chunk data into the caller's buffer.
fn readRleChunk(mkf: palcommon.MkfFile, chunk_num: u32, dst: []u8) usize {
    const data = mkf.getChunkData(chunk_num) catch return 0;
    if (data.len == 0 or data.len > dst.len) return 0;
    @memcpy(dst[0..data.len], data);
    return data.len;
}

// FBP chunks are YJ1-compressed. Decompress to a heap-allocated buffer.
fn decompressFbpChunk(mkf: palcommon.MkfFile, chunk_num: u32) ![]u8 {
    const yj1 = @import("yj1.zig");
    const compressed = try mkf.getChunkData(chunk_num);
    const decompressed_size = try mkf.getDecompressedSize(chunk_num, false);
    const buf = try global.allocator.alloc(u8, decompressed_size);
    errdefer global.allocator.free(buf);
    _ = try yj1.decompress(compressed, buf);
    return buf;
}
