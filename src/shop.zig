// Copyright (c) 2009-2011, Wei Mingzhi <whistler_wmz@users.sf.net>.
// Copyright (c) 2011-2026, SDLPAL development team.
// All rights reserved.
//
// This file is part of SDLPAL.
//
// SDLPAL is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License, version 3
// as published by the Free Software Foundation.

// PAL_BuyMenu / PAL_SellMenu — shops and pawn (当铺) UI. Pawn is just
// PAL_SellMenu under a different storefront in SDLPAL: when the script
// triggers opcode 0x0027, the resulting menu filters inventory by the
// `kItemFlagSellable` flag, which is what the pawn shop also uses.

const std = @import("std");
const global = @import("global.zig");
const palcommon = @import("palcommon.zig");
const video = @import("video.zig");
const ui = @import("ui.zig");
const text = @import("text.zig");
const input = @import("input.zig");
const util = @import("util.zig");
const scene = @import("scene.zig");
const uigame = @import("uigame.zig");
const itemmenu = @import("itemmenu.zig");

const SPRITENUM_ITEMBOX: i32 = 70;
const CASH_LABEL: u16 = 21;
const BUYMENU_LABEL_CURRENT: u16 = 35;
const SELLMENU_LABEL_PRICE: u16 = 25;

var buy_first_render: bool = true;

// PAL_BuyMenu_OnItemChange.
fn buyMenuOnItemChange(current_item: u16) void {
    var x: i32 = 40;
    var y: i32 = 8;

    if (buy_first_render) {
        if (palcommon.spriteGetFrame(ui.sprite_ui, SPRITENUM_ITEMBOX)) |bmp| {
            _ = palcommon.rleBlitToSurfaceWithShadow(bmp, &video.screen, global.palXY(@intCast(x + 6), @intCast(y + 6)), true);
        }
    }

    if (palcommon.spriteGetFrame(ui.sprite_ui, SPRITENUM_ITEMBOX)) |bmp| {
        _ = palcommon.rleBlitToSurface(bmp, &video.screen, global.palXY(@intCast(x), @intCast(y)));
    }

    // Draw item bitmap from BALL.MKF (chunk = wBitmap).
    x = 48;
    y = 15;
    if (global.gpg.f.ball) |ball| {
        const bmp_chunk = global.gpg.g.objects[current_item].item().bitmap;
        if (ball.getChunkData(bmp_chunk)) |chunk| {
            _ = palcommon.rleBlitToSurface(chunk, &video.screen, global.palXY(@intCast(x), @intCast(y)));
        } else |_| {}
    }

    // Inventory count for the highlighted item (counts equipped copies too).
    var n: u32 = 0;
    var i: usize = 0;
    while (i < global.MAX_INVENTORY) : (i += 1) {
        if (global.gpg.inventory[i].item == 0) break;
        if (global.gpg.inventory[i].item == current_item) {
            n = global.gpg.inventory[i].amount;
            break;
        }
    }
    var eq: u32 = 0;
    while (eq < global.MAX_PLAYER_EQUIPMENTS) : (eq += 1) {
        var j: u32 = 0;
        while (j <= global.gpg.max_party_member_index) : (j += 1) {
            const role = global.gpg.party[j].player_role;
            if (global.gpg.g.player_roles.equipment[eq][role] == current_item) n += 1;
        }
    }

    // "current" inventory amount box.
    x = 20;
    y = 100;
    if (buy_first_render) {
        _ = ui.createSingleLineBoxWithShadow(global.palXY(@intCast(x), @intCast(y)), 5, false, 6);
    } else {
        _ = ui.createSingleLineBoxWithShadow(global.palXY(@intCast(x), @intCast(y)), 5, false, 0);
    }
    text.drawText(text.getWord(BUYMENU_LABEL_CURRENT), global.palXY(@intCast(x + 10), @intCast(y + 10)), 0, false, false);
    ui.drawNumber(n, 6, global.palXY(@intCast(x + 49), @intCast(y + 15)), .yellow, .right);

    // Cash box.
    x = 20;
    y = 141;
    if (buy_first_render) {
        _ = ui.createSingleLineBoxWithShadow(global.palXY(@intCast(x), @intCast(y)), 5, false, 6);
    } else {
        _ = ui.createSingleLineBoxWithShadow(global.palXY(@intCast(x), @intCast(y)), 5, false, 0);
    }
    text.drawText(text.getWord(CASH_LABEL), global.palXY(@intCast(x + 10), @intCast(y + 10)), 0, false, false);
    ui.drawNumber(global.gpg.cash, 6, global.palXY(@intCast(x + 49), @intCast(y + 15)), .yellow, .right);

    video.updateScreen(null);
    buy_first_render = false;
}

// PAL_BuyMenu — open a buying menu for store wStoreNum.
pub fn buyMenu(store_num: u16) void {
    var menu_items: [global.MAX_STORE_ITEM]ui.MenuItem = undefined;
    var n: usize = 0;
    var y: i32 = 21;

    while (n < global.MAX_STORE_ITEM) : (n += 1) {
        const obj = global.gpg.g.stores[store_num].items[n];
        if (obj == 0) break;
        menu_items[n] = .{
            .value = obj,
            .num_word = obj,
            .enabled = true,
            .pos = global.palXY(150, @intCast(y)),
        };
        y += 18;
    }

    if (n == 0) return;

    _ = ui.createBox(global.palXY(122, 8), 8, 8, 1, false);

    var i: usize = 0;
    while (i < n) : (i += 1) {
        const price = global.gpg.g.objects[menu_items[i].value].item().price;
        ui.drawNumber(price, 6, global.palXY(238, @intCast(26 + @as(i32, @intCast(i)) * 18)), .yellow, .right);
    }

    var current: u16 = 0;
    buy_first_render = true;

    while (true) {
        if (util.shouldQuit()) return;
        const w = ui.readMenu(buyMenuOnItemChange, menu_items[0..n], current, ui.MENUITEM_COLOR);
        if (w == ui.MENUITEM_VALUE_CANCELLED) break;

        const price = global.gpg.g.objects[w].item().price;
        if (price > 0 and price <= global.gpg.cash) {
            // Cap the amount picker at what the wallet can afford and at the
            // 99-per-stack cap that addItemToInventory enforces.
            const owned: u32 = global.getItemAmount(w);
            const room: u32 = if (owned >= 99) 0 else 99 - owned;
            const affordable: u32 = global.gpg.cash / price;
            const max: u32 = @min(room, affordable);
            if (max > 0) {
                const qty = uigame.amountSelect(max);
                if (qty > 0 and uigame.confirmMenu()) {
                    global.gpg.cash -= price * qty;
                    _ = global.addItemToInventory(w, @intCast(qty));
                }
            }
        }

        // Re-place cursor on the just-bought row.
        i = 0;
        while (i < n) : (i += 1) {
            if (w == menu_items[i].value) {
                current = @intCast(i);
                break;
            }
        }
    }
}

// PAL_SellMenu_OnItemChange.
fn sellMenuOnItemChange(current_item: u16) void {
    var x: i32 = 100;
    const y: i32 = 150;

    _ = ui.createSingleLineBoxWithShadow(global.palXY(@intCast(x), @intCast(y)), 5, false, 0);
    text.drawText(text.getWord(CASH_LABEL), global.palXY(@intCast(x + 10), @intCast(y + 10)), 0, false, false);
    ui.drawNumber(global.gpg.cash, 6, global.palXY(@intCast(x + 48), @intCast(y + 15)), .yellow, .right);

    x += 124;

    _ = ui.createSingleLineBoxWithShadow(global.palXY(@intCast(x), @intCast(y)), 5, false, 0);

    const flags = global.gpg.g.objects[current_item].item().flags;
    if ((flags & global.ITEM_FLAG_SELLABLE) != 0) {
        text.drawText(text.getWord(SELLMENU_LABEL_PRICE), global.palXY(@intCast(x + 10), @intCast(y + 10)), 0, false, false);
        const half = global.gpg.g.objects[current_item].item().price / 2;
        ui.drawNumber(half, 6, global.palXY(@intCast(x + 48), @intCast(y + 15)), .yellow, .right);
    }
}

// PAL_SellMenu — sell items (also serves as the pawn-shop UI in SDLPAL).
pub fn sellMenu() void {
    while (true) {
        if (util.shouldQuit()) return;
        const w = itemmenu.itemSelectMenu(sellMenuOnItemChange, global.ITEM_FLAG_SELLABLE);
        if (w == 0) break;

        const owned: u32 = global.getItemAmount(w);
        if (owned == 0) continue;
        const qty = uigame.amountSelect(owned);
        if (qty == 0) continue;
        if (uigame.confirmMenu()) {
            const sold = global.addItemToInventory(w, -@as(i32, @intCast(qty)));
            if (sold != 0) {
                const half = global.gpg.g.objects[w].item().price / 2;
                global.gpg.cash += half * qty;
            }
        }
    }
}
