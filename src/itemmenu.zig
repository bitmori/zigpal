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
const scene = @import("scene.zig");
const script = @import("script.zig");
const yj1 = @import("yj1.zig");

// Constants from ui.h.
const SPRITENUM_ITEMBOX: i32 = 70;
const SPRITENUM_CURSOR: i32 = 69;
const SPRITENUM_SLASH: i32 = 39;
const ITEMUSEMENU_COLOR_STATLABEL: u8 = 0xBB;
const STATUS_COLOR_EQUIPMENT: u8 = 0xBE;
const DESCTEXT_COLOR: u8 = 0x3C;
const EQUIPMENU_BACKGROUND_FBPNUM: u32 = 1;

const STATUS_LABEL_LEVEL: u16 = 48;
const STATUS_LABEL_HP: u16 = 49;
const STATUS_LABEL_MP: u16 = 50;
const STATUS_LABEL_ATTACKPOWER: u16 = 51;
const STATUS_LABEL_MAGICPOWER: u16 = 52;
const STATUS_LABEL_RESISTANCE: u16 = 53;
const STATUS_LABEL_DEXTERITY: u16 = 54;
const STATUS_LABEL_FLEERATE: u16 = 55;
const INVMENU_LABEL_USE: u16 = 23;
const INVMENU_LABEL_EQUIP: u16 = 22;

// Equip-screen layout positions.
const EQUIP_IMAGE_BOX = global.palXY(8, 8);
const EQUIP_ROLE_LIST_BOX = global.palXY(2, 95);
const EQUIP_ITEM_NAME = global.palXY(5, 70);
const EQUIP_ITEM_AMOUNT = global.palXY(51, 57);
const EQUIP_NAMES = [_]palcommon.Pos{
    global.palXY(130, 11), global.palXY(130, 33),
    global.palXY(130, 55), global.palXY(130, 77),
    global.palXY(130, 99), global.palXY(130, 121),
};
const EQUIP_STATUS_VALUES = [_]palcommon.Pos{
    global.palXY(260, 14), global.palXY(260, 36),
    global.palXY(260, 58), global.palXY(260, 80),
    global.palXY(260, 102),
};

// PAL_ItemSelectMenu state.
var g_num_inventory: i32 = 0;
var g_item_flags: u16 = 0;
var g_no_desc: bool = false;
var g_force_selectable: bool = false;

// PAL_ItemSelectMenuInit.
pub fn itemSelectMenuInit(item_flags: u16) void {
    g_item_flags = item_flags;
    global.compressInventory();

    g_num_inventory = 0;
    while (g_num_inventory < global.MAX_INVENTORY and
        global.gpg.inventory[@intCast(g_num_inventory)].item != 0)
    {
        g_num_inventory += 1;
    }

    // Add usable equipped items.
    if ((item_flags & global.ITEM_FLAG_USABLE) != 0 and !global.gpg.in_battle) {
        var i: u32 = 0;
        while (i <= global.gpg.max_party_member_index) : (i += 1) {
            const w = global.gpg.party[i].player_role;
            var j: u32 = 0;
            while (j < global.MAX_PLAYER_EQUIPMENTS) : (j += 1) {
                const eq = global.gpg.g.player_roles.equipment[j][w];
                if ((global.gpg.g.objects[eq].item().flags & global.ITEM_FLAG_USABLE) != 0) {
                    if (g_num_inventory < global.MAX_INVENTORY) {
                        global.gpg.inventory[@intCast(g_num_inventory)] = .{
                            .item = eq,
                            .amount = 0,
                            .amount_in_use = @as(u16, @bitCast(@as(i16, -1))),
                        };
                        g_num_inventory += 1;
                    }
                }
            }
        }
    }
}

// PAL_ItemSelectMenuUpdate — returns the selected item, 0 if cancelled,
// 0xFFFF if not yet confirmed.
pub fn itemSelectMenuUpdate() u16 {
    // dwWordLength is the per-word byte stride in WORD.DAT — 10 for the DOS
    // Chinese build. SDLPAL's pixel formulas multiply on it to space items.
    const word_length: i32 = 10;
    const items_per_line: i32 = @divTrunc(32, word_length);
    const item_text_width: i32 = 8 * word_length + 20;
    const lines_per_page: i32 = 7;
    const cursor_x_offset: i32 = @divTrunc(word_length * 5, 2);
    const amount_x_offset: i32 = word_length * 8 + 1;
    const page_line_offset: i32 = @divTrunc(lines_per_page + 1, 2);

    var item_delta: i32 = 0;
    const k_press = input.state.key_press;
    if ((k_press & input.KEY_UP) != 0) {
        item_delta = -items_per_line;
    } else if ((k_press & input.KEY_DOWN) != 0) {
        item_delta = items_per_line;
    } else if ((k_press & input.KEY_LEFT) != 0) {
        item_delta = -1;
    } else if ((k_press & input.KEY_RIGHT) != 0) {
        item_delta = 1;
    } else if ((k_press & input.KEY_PGUP) != 0) {
        item_delta = -(items_per_line * lines_per_page);
    } else if ((k_press & input.KEY_PGDN) != 0) {
        item_delta = items_per_line * lines_per_page;
    } else if ((k_press & input.KEY_HOME) != 0) {
        item_delta = -global.gpg.cur_inv_menu_item;
    } else if ((k_press & input.KEY_END) != 0) {
        item_delta = g_num_inventory - global.gpg.cur_inv_menu_item - 1;
    } else if ((k_press & input.KEY_MENU) != 0) {
        return 0;
    }

    if (global.gpg.cur_inv_menu_item + item_delta < 0)
        global.gpg.cur_inv_menu_item = 0
    else if (global.gpg.cur_inv_menu_item + item_delta >= g_num_inventory)
        global.gpg.cur_inv_menu_item = g_num_inventory - 1
    else
        global.gpg.cur_inv_menu_item += item_delta;

    _ = ui.createBoxWithShadow(global.palXY(2, 0), lines_per_page - 1, 17, 1, false, 0);

    var i: i32 = @divTrunc(global.gpg.cur_inv_menu_item, items_per_line) * items_per_line - items_per_line * page_line_offset;
    if (i < 0) i = 0;

    const x_base: i32 = 0;
    const y_base: i32 = 140;
    var cursor_pos = global.palXY(@intCast(15 + cursor_x_offset), 22);

    var j: i32 = 0;
    outer: while (j < lines_per_page) : (j += 1) {
        var k: i32 = 0;
        while (k < items_per_line) : (k += 1) {
            const idx: usize = @intCast(i);
            const w_object: u16 = if (idx < global.MAX_INVENTORY) global.gpg.inventory[idx].item else 0;
            var color: u8 = ui.MENUITEM_COLOR;

            if (idx >= global.MAX_INVENTORY or w_object == 0) {
                break :outer;
            }

            const flags = global.gpg.g.objects[w_object].item().flags;
            const inv = global.gpg.inventory[idx];
            const usable = (g_force_selectable or (flags & g_item_flags) != 0) and
                @as(i16, @bitCast(inv.amount)) > @as(i16, @bitCast(inv.amount_in_use));

            if (i == global.gpg.cur_inv_menu_item) {
                if (!usable) {
                    color = ui.MENUITEM_COLOR_SELECTED_INACTIVE;
                } else if (inv.amount == 0) {
                    color = ui.MENUITEM_COLOR_EQUIPPEDITEM;
                } else {
                    color = ui.menuItemColorSelected();
                }
            } else if (!usable) {
                color = ui.MENUITEM_COLOR_INACTIVE;
            } else if (inv.amount == 0) {
                color = ui.MENUITEM_COLOR_EQUIPPEDITEM;
            }

            text.drawText(
                text.getWord(w_object),
                global.palXY(@intCast(15 + k * item_text_width), @intCast(12 + j * 18)),
                color,
                true,
                false,
            );

            if (i == global.gpg.cur_inv_menu_item) {
                cursor_pos = global.palXY(
                    @intCast(15 + cursor_x_offset + k * item_text_width),
                    @intCast(22 + j * 18),
                );

                if (palcommon.spriteGetFrame(ui.sprite_ui, SPRITENUM_ITEMBOX)) |bmp| {
                    _ = palcommon.rleBlitToSurfaceWithShadow(bmp, &video.screen, global.palXY(@intCast(x_base + 5), @intCast(y_base + 5)), true);
                    _ = palcommon.rleBlitToSurface(bmp, &video.screen, global.palXY(@intCast(x_base), @intCast(y_base)));
                }

                if (global.gpg.f.ball) |ball| {
                    const bitmap = global.gpg.g.objects[w_object].item().bitmap;
                    const bmp = ball.getChunkData(bitmap) catch null;
                    if (bmp) |b| {
                        _ = palcommon.rleBlitToSurface(b, &video.screen, global.palXY(@intCast(x_base + 8), @intCast(y_base + 7)));
                    }
                }
            }

            const surplus: i32 = @as(i32, @as(i16, @bitCast(inv.amount))) - @as(i32, @as(i16, @bitCast(inv.amount_in_use)));
            if (surplus > 1) {
                ui.drawNumber(
                    @intCast(surplus),
                    2,
                    global.palXY(@intCast(15 + amount_x_offset + k * item_text_width), @intCast(17 + j * 18)),
                    .cyan,
                    .right,
                );
            }

            i += 1;
        }
    }

    if (palcommon.spriteGetFrame(ui.sprite_ui, SPRITENUM_CURSOR)) |bmp| {
        _ = palcommon.rleBlitToSurface(bmp, &video.screen, cursor_pos);
    }

    const w_object_sel: u16 = global.gpg.inventory[@intCast(global.gpg.cur_inv_menu_item)].item;

    // Object description rendered with zpix UTF-8 font.
    if (!g_no_desc) {
        const objectdesc = @import("objectdesc.zig");
        if (objectdesc.get(w_object_sel)) |desc| {
            _ = objectdesc.drawAt(desc, 75, 150, DESCTEXT_COLOR);
        }
    }

    // Debug overlay: object fields.
    if (@import("debug.zig").enabled) {
        const d = global.gpg.g.objects[w_object_sel].data;
        var dbg_buf: [128]u8 = undefined;
        const s = std.fmt.bufPrint(&dbg_buf, "#{X}=[\xe5\x9b\xbe\xe7\x89\x87={X} \xe4\xbb\xb7\xe6\xa0\xbc={X} \xe4\xbd\xbf\xe7\x94\xa8={X} \xe8\xa3\x85\xe5\xa4\x87={X} \xe6\x8a\x95\xe6\x8e\xb7={X} \xe6\x97\x97={X}]", .{
            w_object_sel, d[0], d[1], d[2], d[3], d[4], d[5],
        }) catch return 0xFFFF;
        _ = @import("objectdesc.zig").drawAt(s, 10, 174, 0x0B);
    }

    // Item-description rendering via wScriptDesc is for Win95 builds only,
    // and we compile DOS-only — skip it.
    if ((k_press & input.KEY_SEARCH) != 0) {
        const inv = global.gpg.inventory[@intCast(global.gpg.cur_inv_menu_item)];
        const flags = global.gpg.g.objects[w_object_sel].item().flags;
        if ((g_force_selectable or (flags & g_item_flags) != 0) and
            @as(i16, @bitCast(inv.amount)) > @as(i16, @bitCast(inv.amount_in_use)))
        {
            if (inv.amount > 0) {
                const cur = global.gpg.cur_inv_menu_item;
                const jj: i32 = if (cur < items_per_line * page_line_offset)
                    @divTrunc(cur, items_per_line)
                else
                    page_line_offset;
                const kk: i32 = @mod(cur, items_per_line);

                text.drawText(
                    text.getWord(w_object_sel),
                    global.palXY(@intCast(15 + kk * item_text_width), @intCast(12 + jj * 18)),
                    ui.MENUITEM_COLOR_CONFIRMED,
                    false,
                    false,
                );
                if (palcommon.spriteGetFrame(ui.sprite_ui, SPRITENUM_CURSOR)) |bmp| {
                    _ = palcommon.rleBlitToSurface(bmp, &video.screen, cursor_pos);
                }
            }

            return w_object_sel;
        }
    }

    return 0xFFFF;
}

// Debug entry: render the item-selection menu over an arbitrary list of
// item object IDs (instead of the player's inventory). Used by 進寶 so it
// inherits the full chrome — itemBox sprite, amount column, description
// panel — of the regular menu.
pub fn itemSelectMenuFromList(item_ids: []const u16) u16 {
    // Save inventory + cur_inv_menu_item, install debug list, restore on exit.
    const saved_inventory = global.gpg.inventory;
    const saved_cur = global.gpg.cur_inv_menu_item;
    defer {
        global.gpg.inventory = saved_inventory;
        global.gpg.cur_inv_menu_item = saved_cur;
        g_force_selectable = false;
    }

    @memset(&global.gpg.inventory, .{ .item = 0, .amount = 0, .amount_in_use = 0 });
    var n: usize = 0;
    var i: usize = 0;
    while (i < item_ids.len and n < global.MAX_INVENTORY) : (i += 1) {
        if (item_ids[i] == 0) continue;
        global.gpg.inventory[n] = .{ .item = item_ids[i], .amount = 1, .amount_in_use = 0 };
        n += 1;
    }

    // Match the inventory's item flags so every entry is selectable. We OR
    // every item flag together; itemSelectMenuUpdate's usability check is
    // (object.flags & g_item_flags) != 0 — so as long as the item itself
    // has any flag set (all real items do), it'll pass.
    g_item_flags = 0xFFFF;
    g_force_selectable = true;
    g_num_inventory = @intCast(n);
    if (g_num_inventory == 0) {
        g_force_selectable = false;
        return 0;
    }
    global.gpg.cur_inv_menu_item = 0;

    input.clearKeyState();
    var dw_time = util.getTicks();
    while (true) {
        if (util.shouldQuit()) return 0;
        scene.makeScene();
        const w = itemSelectMenuUpdate();
        video.updateScreen(null);
        input.clearKeyState();
        input.processEvent();
        while (util.getTicks() < dw_time) {
            input.processEvent();
            if (input.state.key_press != 0) break;
            util.delay(5);
            if (util.shouldQuit()) return 0;
        }
        dw_time = util.getTicks() + global.FRAME_TIME;

        if (w != 0xFFFF) return w;
    }
}

// PAL_ItemSelectMenu — show item-selection menu, returns selected item or 0 if cancelled.
pub fn itemSelectMenu(on_change: ui.ItemChangedCallback, item_flags: u16) u16 {
    itemSelectMenuInit(item_flags);
    // Empty inventory — nothing to pick. Bail before the loop, otherwise the
    // cursor would clamp to g_num_inventory-1 == -1 and index inventory[-1].
    if (g_num_inventory == 0) return 0;
    if (global.gpg.cur_inv_menu_item >= g_num_inventory) {
        global.gpg.cur_inv_menu_item = g_num_inventory - 1;
    }
    if (global.gpg.cur_inv_menu_item < 0) global.gpg.cur_inv_menu_item = 0;
    var prev_index = global.gpg.cur_inv_menu_item;

    input.clearKeyState();

    if (on_change) |cb| {
        g_no_desc = true;
        cb(global.gpg.inventory[@intCast(global.gpg.cur_inv_menu_item)].item);
    }

    var dw_time = util.getTicks();

    while (true) {
        if (util.shouldQuit()) {
            g_no_desc = false;
            return 0;
        }

        if (on_change == null) {
            scene.makeScene();
        }

        const w = itemSelectMenuUpdate();
        video.updateScreen(null);

        input.clearKeyState();
        input.processEvent();
        while (util.getTicks() < dw_time) {
            input.processEvent();
            if (input.state.key_press != 0) break;
            util.delay(5);
            if (util.shouldQuit()) {
                g_no_desc = false;
                return 0;
            }
        }
        dw_time = util.getTicks() + global.FRAME_TIME;

        if (w != 0xFFFF) {
            g_no_desc = false;
            return w;
        }

        if (prev_index != global.gpg.cur_inv_menu_item) {
            const idx = global.gpg.cur_inv_menu_item;
            if (idx >= 0 and idx < global.MAX_INVENTORY) {
                if (on_change) |cb| cb(global.gpg.inventory[@intCast(idx)].item);
            }
            prev_index = global.gpg.cur_inv_menu_item;
        }
    }
}

// PAL_ItemUseMenu — choose which player gets to use the item.
var s_selected_player: i16 = 0;
pub fn itemUseMenu(item_to_use: u16) u16 {
    var selected_player = s_selected_player;

    while (true) {
        if (util.shouldQuit()) return ui.MENUITEM_VALUE_CANCELLED;
        if (selected_player > @as(i16, @intCast(global.gpg.max_party_member_index))) {
            selected_player = 0;
        }

        // 魔改 — box height 8 so 4 player names fit on the left.
        _ = ui.createBox(global.palXY(110, 2), 8, 9, 0, false);

        // Stat labels at 18px spacing to fit within the taller box.
        const stat_labels = [_]u16{
            STATUS_LABEL_LEVEL, STATUS_LABEL_HP, STATUS_LABEL_MP,
            STATUS_LABEL_ATTACKPOWER, STATUS_LABEL_MAGICPOWER,
            STATUS_LABEL_RESISTANCE, STATUS_LABEL_DEXTERITY, STATUS_LABEL_FLEERATE,
        };
        for (stat_labels, 0..) |lbl, j| {
            text.drawText(text.getWord(lbl), global.palXY(200, @intCast(16 + 18 * @as(i32, @intCast(j)))), ITEMUSEMENU_COLOR_STATLABEL, true, false);
        }

        const role: u16 = global.gpg.party[@intCast(selected_player)].player_role;

        // Stat values — 18px spacing to match labels.
        ui.drawNumber(global.gpg.g.player_roles.level[role], 4, global.palXY(240, 20), .yellow, .right);
        if (palcommon.spriteGetFrame(ui.sprite_ui, SPRITENUM_SLASH)) |slash| {
            _ = palcommon.rleBlitToSurface(slash, &video.screen, global.palXY(263, 16 + 18 + 2));
            _ = palcommon.rleBlitToSurface(slash, &video.screen, global.palXY(263, 16 + 18 * 2 + 2));
        }
        ui.drawNumber(global.gpg.g.player_roles.max_hp[role], 4, global.palXY(261, 16 + 18 + 4), .blue, .right);
        ui.drawNumber(global.gpg.g.player_roles.hp[role], 4, global.palXY(240, 16 + 18 + 1), .yellow, .right);
        ui.drawNumber(global.gpg.g.player_roles.max_mp[role], 4, global.palXY(261, 16 + 18 * 2 + 4), .blue, .right);
        ui.drawNumber(global.gpg.g.player_roles.mp[role], 4, global.palXY(240, 16 + 18 * 2 + 1), .yellow, .right);
        ui.drawNumber(global.getPlayerAttackStrength(role), 4, global.palXY(240, 16 + 18 * 3 + 4), .yellow, .right);
        ui.drawNumber(global.getPlayerMagicStrength(role), 4, global.palXY(240, 16 + 18 * 4 + 4), .yellow, .right);
        ui.drawNumber(global.getPlayerDefense(role), 4, global.palXY(240, 16 + 18 * 5 + 4), .yellow, .right);
        ui.drawNumber(global.getPlayerDexterity(role), 4, global.palXY(240, 16 + 18 * 6 + 4), .yellow, .right);
        ui.drawNumber(global.getPlayerFleeRate(role), 4, global.palXY(240, 16 + 18 * 7 + 4), .yellow, .right);

        var i: u32 = 0;
        while (i <= global.gpg.max_party_member_index) : (i += 1) {
            const color: u8 = if (i == @as(u32, @intCast(selected_player))) ui.menuItemColorSelected() else ui.MENUITEM_COLOR;
            const r = global.gpg.party[i].player_role;
            text.drawText(
                text.getWord(global.gpg.g.player_roles.name[r]),
                global.palXY(125, @intCast(16 + 20 * i)),
                color,
                true,
                false,
            );
        }

        // 魔改 — item box shifts down 20px so it doesn't collide with 4 names.
        const item_box_y: i16 = 80 + 20;
        if (palcommon.spriteGetFrame(ui.sprite_ui, SPRITENUM_ITEMBOX)) |bmp| {
            _ = palcommon.rleBlitToSurface(bmp, &video.screen, global.palXY(120, item_box_y));
        }

        const amount = global.getItemAmount(item_to_use);
        if (amount > 0) {
            if (global.gpg.f.ball) |ball| {
                const bitmap = global.gpg.g.objects[item_to_use].item().bitmap;
                const bmp = ball.getChunkData(bitmap) catch null;
                if (bmp) |b| {
                    _ = palcommon.rleBlitToSurface(b, &video.screen, global.palXY(127, item_box_y + 8));
                }
            }
            text.drawText(text.getWord(item_to_use), global.palXY(116, item_box_y + 63), STATUS_COLOR_EQUIPMENT, true, false);
            ui.drawNumber(amount, 2, global.palXY(170, item_box_y + 53), .cyan, .right);
        }

        video.updateScreen(null);

        input.clearKeyState();
        while (true) {
            if (util.shouldQuit()) return ui.MENUITEM_VALUE_CANCELLED;
            input.processEvent();
            if (input.state.key_press != 0) break;
            util.delay(1);
        }

        if (amount <= 0) return ui.MENUITEM_VALUE_CANCELLED;

        const k = input.state.key_press;
        if ((k & (input.KEY_UP | input.KEY_LEFT)) != 0) {
            selected_player -= 1;
            if (selected_player < 0) selected_player = @intCast(global.gpg.max_party_member_index);
        } else if ((k & (input.KEY_DOWN | input.KEY_RIGHT)) != 0) {
            selected_player += 1;
            if (selected_player > @as(i16, @intCast(global.gpg.max_party_member_index))) selected_player = 0;
        } else if ((k & input.KEY_MENU) != 0) {
            return ui.MENUITEM_VALUE_CANCELLED;
        } else if ((k & input.KEY_SEARCH) != 0) {
            s_selected_player = selected_player;
            return global.gpg.party[@intCast(selected_player)].player_role;
        }
    }
}

// PAL_GameUseItem.
pub fn gameUseItem() void {
    while (true) {
        const w_object = itemSelectMenu(null, global.ITEM_FLAG_USABLE);
        if (w_object == 0) return;

        const flags = global.gpg.g.objects[w_object].item().flags;
        if ((flags & global.ITEM_FLAG_APPLY_TO_ALL) == 0) {
            while (true) {
                const player = itemUseMenu(w_object);
                if (player == ui.MENUITEM_VALUE_CANCELLED) break;

                const new_script = script.runTriggerScript(global.gpg.g.objects[w_object].item().script_on_use, player);
                global.gpg.g.objects[w_object].data[2] = new_script;

                if ((flags & global.ITEM_FLAG_CONSUMING) != 0 and script.g_script_success) {
                    _ = global.addItemToInventory(w_object, -1);
                }
            }
        } else {
            const new_script = script.runTriggerScript(global.gpg.g.objects[w_object].item().script_on_use, 0xFFFF);
            global.gpg.g.objects[w_object].data[2] = new_script;
            if ((flags & global.ITEM_FLAG_CONSUMING) != 0 and script.g_script_success) {
                _ = global.addItemToInventory(w_object, -1);
            }
            return;
        }
    }
}

// PAL_GameEquipItem.
pub fn gameEquipItem() void {
    while (true) {
        const w_object = itemSelectMenu(null, global.ITEM_FLAG_EQUIPABLE);
        if (w_object == 0) return;
        equipItemMenu(w_object);
    }
}

// PAL_EquipItemMenu.
pub fn equipItemMenu(item_in: u16) void {
    var item = item_in;
    const fbp = global.gpg.f.fbp orelse return;
    const bg_buf = decompressFbpChunk(fbp, EQUIPMENU_BACKGROUND_FBPNUM) catch return;
    defer global.allocator.free(bg_buf);

    global.gpg.last_unequipped_item = item;

    var current_player: i32 = 0;

    while (true) {
        if (util.shouldQuit()) return;
        item = global.gpg.last_unequipped_item;

        _ = palcommon.fbpBlitToSurface(bg_buf, &video.screen);

        if (global.gpg.f.ball) |ball| {
            const bitmap = global.gpg.g.objects[item].item().bitmap;
            const bmp = ball.getChunkData(bitmap) catch null;
            if (bmp) |b| {
                _ = palcommon.rleBlitToSurface(b, &video.screen, global.palXyOffset(EQUIP_IMAGE_BOX, 8, 8));
            }
        }

        var w: u16 = global.gpg.party[@intCast(current_player)].player_role;
        var i: u32 = 0;
        while (i < global.MAX_PLAYER_EQUIPMENTS) : (i += 1) {
            const eq = global.gpg.g.player_roles.equipment[i][w];
            if (eq != 0) {
                text.drawText(text.getWord(eq), EQUIP_NAMES[i], ui.MENUITEM_COLOR, true, false);
            }
        }

        ui.drawNumber(global.getPlayerAttackStrength(w), 4, EQUIP_STATUS_VALUES[0], .cyan, .right);
        ui.drawNumber(global.getPlayerMagicStrength(w), 4, EQUIP_STATUS_VALUES[1], .cyan, .right);
        ui.drawNumber(global.getPlayerDefense(w), 4, EQUIP_STATUS_VALUES[2], .cyan, .right);
        ui.drawNumber(global.getPlayerDexterity(w), 4, EQUIP_STATUS_VALUES[3], .cyan, .right);
        ui.drawNumber(global.getPlayerFleeRate(w), 4, EQUIP_STATUS_VALUES[4], .cyan, .right);

        _ = ui.createBox(EQUIP_ROLE_LIST_BOX, @intCast(global.gpg.max_party_member_index), ui.wordMaxWidth(36, 4) - 1, 0, false);

        i = 0;
        while (i <= global.gpg.max_party_member_index) : (i += 1) {
            w = global.gpg.party[i].player_role;
            var color: u8 = undefined;
            const eq_flag: u16 = global.ITEM_FLAG_EQUIPABLE_BY_PLAYER_ROLE_FIRST << @intCast(w);
            const can_equip = (global.gpg.g.objects[item].item().flags & eq_flag) != 0;
            if (i == @as(u32, @intCast(current_player))) {
                color = if (can_equip) ui.menuItemColorSelected() else ui.MENUITEM_COLOR_SELECTED_INACTIVE;
            } else {
                color = if (can_equip) ui.MENUITEM_COLOR else ui.MENUITEM_COLOR_INACTIVE;
            }
            text.drawText(
                text.getWord(global.gpg.g.player_roles.name[w]),
                global.palXyOffset(EQUIP_ROLE_LIST_BOX, 13, @intCast(13 + 18 * i)),
                color,
                true,
                false,
            );
        }

        if (item != 0) {
            text.drawText(text.getWord(item), EQUIP_ITEM_NAME, ui.MENUITEM_COLOR_CONFIRMED, true, false);
            ui.drawNumber(global.getItemAmount(item), 2, EQUIP_ITEM_AMOUNT, .cyan, .right);
        }

        video.updateScreen(null);

        input.clearKeyState();
        while (true) {
            if (util.shouldQuit()) return;
            input.processEvent();
            if (input.state.key_press != 0) break;
            util.delay(1);
        }

        if (item == 0) return;

        const k = input.state.key_press;
        if ((k & (input.KEY_UP | input.KEY_LEFT)) != 0) {
            current_player -= 1;
            if (current_player < 0) current_player = @intCast(global.gpg.max_party_member_index);
        } else if ((k & (input.KEY_DOWN | input.KEY_RIGHT)) != 0) {
            current_player += 1;
            if (current_player > @as(i32, global.gpg.max_party_member_index)) current_player = 0;
        } else if ((k & input.KEY_MENU) != 0) {
            return;
        } else if ((k & input.KEY_SEARCH) != 0) {
            w = global.gpg.party[@intCast(current_player)].player_role;
            const eq_flag: u16 = global.ITEM_FLAG_EQUIPABLE_BY_PLAYER_ROLE_FIRST << @intCast(w);
            if ((global.gpg.g.objects[item].item().flags & eq_flag) != 0) {
                const new_script = script.runTriggerScript(
                    global.gpg.g.objects[item].item().script_on_equip,
                    global.gpg.party[@intCast(current_player)].player_role,
                );
                global.gpg.g.objects[item].data[3] = new_script;
            }
        }
    }
}

// PAL_InventoryMenu.
pub fn inventoryMenu() void {
    const State = struct {
        var w: u16 = 0;
    };

    const items: [2]ui.MenuItem = .{
        .{ .value = 1, .num_word = INVMENU_LABEL_EQUIP, .enabled = true, .pos = global.palXY(43, 73) },
        .{ .value = 2, .num_word = INVMENU_LABEL_USE, .enabled = true, .pos = global.palXY(43, 73 + 18) },
    };
    _ = ui.createBox(global.palXY(30, 60), 1, ui.menuTextMaxWidth(&items) - 1, 0, false);

    const default_idx: u16 = if (State.w == 0) 0 else State.w - 1;
    State.w = ui.readMenu(null, &items, default_idx, ui.MENUITEM_COLOR);

    switch (State.w) {
        1 => gameEquipItem(),
        2 => gameUseItem(),
        else => {},
    }
}

fn decompressFbpChunk(mkf: palcommon.MkfFile, chunk_num: u32) ![]u8 {
    const compressed = try mkf.getChunkData(chunk_num);
    const decompressed_size = try mkf.getDecompressedSize(chunk_num, false);
    const buf = try global.allocator.alloc(u8, decompressed_size);
    errdefer global.allocator.free(buf);
    _ = try yj1.decompress(compressed, buf);
    return buf;
}
