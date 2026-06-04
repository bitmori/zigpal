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

// Word numbers from ui.h.
pub const MAINMENU_LABEL_NEWGAME: u16 = 7;
pub const MAINMENU_LABEL_LOADGAME: u16 = 8;
pub const LOADMENU_LABEL_SLOT_FIRST: u16 = 43;
pub const CONFIRMMENU_LABEL_NO: u16 = 19;
pub const CONFIRMMENU_LABEL_YES: u16 = 20;
pub const SWITCHMENU_LABEL_DISABLE: u16 = 17;
pub const SWITCHMENU_LABEL_ENABLE: u16 = 18;
pub const GAMEMENU_LABEL_STATUS: u16 = 3;
pub const GAMEMENU_LABEL_MAGIC: u16 = 4;
pub const GAMEMENU_LABEL_INVENTORY: u16 = 5;
pub const GAMEMENU_LABEL_SYSTEM: u16 = 6;
pub const SYSMENU_LABEL_SAVE: u16 = 11;
pub const SYSMENU_LABEL_LOAD: u16 = 12;
pub const SYSMENU_LABEL_MUSIC: u16 = 13;
pub const SYSMENU_LABEL_SOUND: u16 = 14;
pub const SYSMENU_LABEL_QUIT: u16 = 15;
pub const CASH_LABEL: u16 = 21;

// PAL_SelectionMenu — common selection box (used by PAL_ConfirmMenu/TripleMenu/SwitchMenu).
pub fn selectionMenu(items_word: []const u16, default_idx: u32) u16 {
    const n = items_word.len;
    if (n == 0 or n > 4) return ui.MENUITEM_VALUE_CANCELLED;

    var w: [4]i32 = undefined;
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        w[i] = if (i < n and items_word[i] != 0) ui.wordWidth(items_word[i]) else 1;
    }
    var dx: [4]i32 = .{ (w[0] - 1) * 16, (w[1] - 1) * 16, (w[2] - 1) * 16, (w[3] - 1) * 16 };

    const pos: [4]palcommon.Pos = .{
        global.palXY(145, 110),
        global.palXY(@intCast(220 + dx[0]), 110),
        global.palXY(145, 160),
        global.palXY(@intCast(220 + dx[2]), 160),
    };

    // If any required word is zero, bail out.
    i = 0;
    while (i < n) : (i += 1) {
        if (items_word[i] == 0) return ui.MENUITEM_VALUE_CANCELLED;
    }

    var menu_items: [4]ui.MenuItem = undefined;
    i = 0;
    while (i < n) : (i += 1) {
        menu_items[i] = .{
            .value = @intCast(i),
            .num_word = items_word[i],
            .enabled = true,
            .pos = pos[i],
        };
    }

    // Re-pack dx as in SDLPAL: dx[1]=dx[0]; dx[3]=dx[2]; dx[0]=dx[2]=0.
    dx[1] = dx[0];
    dx[3] = dx[2];
    dx[0] = 0;
    dx[2] = 0;

    var boxes: [4]?ui.Box = .{ null, null, null, null };
    i = 0;
    while (i < n) : (i += 1) {
        const bx: i32 = 130 + 75 * @as(i32, @intCast(i % 2)) + dx[i];
        const by: i32 = 100 + 50 * @as(i32, @intCast(i / 2));
        boxes[i] = ui.createSingleLineBox(global.palXY(@intCast(bx), @intCast(by)), w[i] + 1, true);
    }

    const ret = ui.readMenu(null, menu_items[0..n], @intCast(default_idx), ui.MENUITEM_COLOR);

    i = 0;
    while (i < n) : (i += 1) {
        ui.deleteBox(boxes[i]);
    }

    video.updateScreen(null);
    return ret;
}

// PAL_TripleMenu — show "no/yes/<wThirdWord>" selection.
pub fn tripleMenu(third_word: u16) u16 {
    const items: [3]u16 = .{ CONFIRMMENU_LABEL_NO, CONFIRMMENU_LABEL_YES, third_word };
    return selectionMenu(&items, 0);
}

// PAL_ConfirmMenu — yes/no.
pub fn confirmMenu() bool {
    const items: [2]u16 = .{ CONFIRMMENU_LABEL_NO, CONFIRMMENU_LABEL_YES };
    const ret = selectionMenu(&items, 0);
    return !(ret == ui.MENUITEM_VALUE_CANCELLED or ret == 0);
}

// Amount picker — used before shop buy / pawn sell / debug get-item to choose
// a quantity in the inclusive range [1, max]. Up/Down adjust by 1, Left/Right
// by 10. Returns 0 on cancel, otherwise the chosen quantity. Bounds-clamped.
pub fn amountSelect(max: u32) u32 {
    const input = @import("input.zig");
    const util = @import("util.zig");
    const text = @import("text.zig");
    if (max == 0) return 0;

    const max_i: i32 = @intCast(max);
    var amount: i32 = 1;
    if (amount > max_i) amount = max_i;

    // BIG5: 數量 = bc\xc6 b6\x71.
    const QTY_LABEL: []const u8 = "\xbc\xc6\xb6\x71";
    // Sprite for the "/" glyph used between current/max in the magic menu
    // (magicmenu.zig:24). Reusing it keeps the look consistent.
    const SPRITENUM_SLASH: i32 = 39;

    video.backupScreen();
    // Drop the SEARCH/MENU edge that opened this picker — readMenu (ui.zig:430)
    // returns without clearing key_press, which would otherwise be consumed
    // by the input loop below and instantly return amount=1.
    input.clearKeyState();
    var dw_time = util.getTicks() + global.FRAME_TIME;

    const box_x: i32 = 110;
    const box_y: i32 = 100;
    while (true) {
        if (util.shouldQuit()) {
            video.restoreScreen();
            video.updateScreen(null);
            return 0;
        }

        video.restoreScreen();
        // Same layout as the magic menu's MP indicator (magicmenu.zig:149-156):
        // yellow current value | slash sprite | cyan max value. Inventory
        // stacks cap at 99 so 2 digits is enough.
        _ = ui.createSingleLineBox(global.palXY(@truncate(box_x), @truncate(box_y)), 6, false);
        text.drawText(QTY_LABEL, global.palXY(@truncate(box_x + 14), @truncate(box_y + 10)), 0, false, false);
        // drawNumber with right-align + length=2 places the leftmost digit
        // at pos.x (ui.zig:287-294), so a 2-char label ending at +46 needs a
        // gap before the digits. Use +56 to leave ~10px of breathing room.
        ui.drawNumber(@intCast(amount), 2, global.palXY(@truncate(box_x + 56), @truncate(box_y + 14)), .yellow, .right);
        if (palcommon.spriteGetFrame(ui.sprite_ui, SPRITENUM_SLASH)) |slash| {
            _ = palcommon.rleBlitToSurface(slash, &video.screen, global.palXY(@truncate(box_x + 68), @truncate(box_y + 14)));
        }
        ui.drawNumber(max, 2, global.palXY(@truncate(box_x + 74), @truncate(box_y + 14)), .cyan, .right);
        video.updateScreen(null);

        while (util.getTicks() < dw_time) {
            input.processEvent();
            if (input.state.key_press != 0) break;
            util.delay(5);
            if (util.shouldQuit()) break;
        }
        dw_time = util.getTicks() + global.FRAME_TIME;

        const k = input.state.key_press;
        input.clearKeyState();

        if ((k & input.KEY_UP) != 0) amount += 1;
        if ((k & input.KEY_DOWN) != 0) amount -= 1;
        if ((k & input.KEY_RIGHT) != 0) amount += 10;
        if ((k & input.KEY_LEFT) != 0) amount -= 10;
        if (amount < 1) amount = 1;
        if (amount > max_i) amount = max_i;

        if ((k & input.KEY_SEARCH) != 0) {
            video.restoreScreen();
            video.updateScreen(null);
            return @intCast(amount);
        }
        if ((k & input.KEY_MENU) != 0) {
            video.restoreScreen();
            video.updateScreen(null);
            return 0;
        }
    }
}

// PAL_SwitchMenu — enable/disable.
pub fn switchMenu(enabled: bool) bool {
    const items: [2]u16 = .{ SWITCHMENU_LABEL_DISABLE, SWITCHMENU_LABEL_ENABLE };
    const def: u32 = if (enabled) 1 else 0;
    const ret = selectionMenu(&items, def);
    if (ret == ui.MENUITEM_VALUE_CANCELLED) return enabled;
    return ret != 0;
}

// PAL_ShowCash — draw the cash-amount box at top-left.
pub fn showCash(cash: u32) ?ui.Box {
    const box = ui.createSingleLineBox(global.palXY(0, 0), 5, true);
    if (box == null) return null;

    const text_mod = @import("text.zig");
    text_mod.drawText(text_mod.getWord(CASH_LABEL), global.palXY(10, 10), 0, false, false);
    ui.drawNumber(cash, 6, global.palXY(49, 14), .yellow, .right);
    return box;
}

fn inGameMenuOnItemChange(current: u16) void {
    global.gpg.cur_main_menu_item = @as(i32, current) - 1;
}

fn systemMenuOnItemChange(current: u16) void {
    global.gpg.cur_system_menu_item = @as(i32, current) - 1;
}

// PAL_QuitGame — uigame.c L2059. Confirm-then-shutdown. SDLPAL would call
// PAL_FadeOut + PAL_Shutdown(0); since we're a libretro core, we set the
// quit_flag instead and let the libretro frontend tear us down.
pub fn quitGame() void {
    if (confirmMenu()) {
        @import("palette.zig").fadeOut(2);
        @import("libretro_core.zig").quit_flag.store(true, .monotonic);
    }
}

// PAL_SystemMenu — save/load/music/sound/quit. Returns true if the user actually
// did something (save/load/quit), false if cancelled.
pub fn systemMenu() bool {
    const items: [5]ui.MenuItem = .{
        .{ .value = 1, .num_word = SYSMENU_LABEL_SAVE, .enabled = true, .pos = global.palXY(53, 72) },
        .{ .value = 2, .num_word = SYSMENU_LABEL_LOAD, .enabled = true, .pos = global.palXY(53, 72 + 18) },
        .{ .value = 3, .num_word = SYSMENU_LABEL_MUSIC, .enabled = true, .pos = global.palXY(53, 72 + 36) },
        .{ .value = 4, .num_word = SYSMENU_LABEL_SOUND, .enabled = true, .pos = global.palXY(53, 72 + 54) },
        .{ .value = 5, .num_word = SYSMENU_LABEL_QUIT, .enabled = true, .pos = global.palXY(53, 72 + 72) },
    };

    const menu_box = ui.createBox(global.palXY(40, 60), @intCast(items.len - 1), ui.menuTextMaxWidth(&items) - 1, 0, true);

    const default_idx: u16 = if (global.gpg.cur_system_menu_item < 0) 0 else @intCast(global.gpg.cur_system_menu_item);
    const ret = ui.readMenu(systemMenuOnItemChange, &items, default_idx, ui.MENUITEM_COLOR);

    if (ret == ui.MENUITEM_VALUE_CANCELLED) {
        ui.deleteBox(menu_box);
        video.updateScreen(null);
        return false;
    }

    switch (ret) {
        // Save game.
        1 => {
            const slot = saveSlotMenu(global.gpg.current_save_slot);
            if (slot != ui.MENUITEM_VALUE_CANCELLED) {
                global.gpg.current_save_slot = @intCast(slot);
                var saved_times: u16 = 0;
                var i: u32 = 1;
                while (i <= 5) : (i += 1) {
                    const cur = @import("save.zig").getSavedTimes(i);
                    if (cur > saved_times) saved_times = cur;
                }
                @import("save.zig").saveGame(slot, saved_times + 1) catch {};
            }
        },
        // Load game — fade out, schedule reload on next tick.
        2 => {
            const slot = saveSlotMenu(global.gpg.current_save_slot);
            if (slot != ui.MENUITEM_VALUE_CANCELLED) {
                @import("palette.zig").fadeOut(1);
                global.reloadInNextTick(@intCast(slot));
            }
        },
        // Music — no-op (no audio).
        3 => _ = switchMenu(false),
        // Sound — no-op (no audio).
        4 => _ = switchMenu(false),
        // Quit.
        5 => quitGame(),
        else => {},
    }

    ui.deleteBox(menu_box);
    video.updateScreen(null);
    return true;
}

// PAL_DrawOpeningMenuBackground — load FBP chunk 60 and blit as the menu BG.
pub fn drawOpeningMenuBackground() void {
    const fbp = global.gpg.f.fbp orelse return;
    const yj1 = @import("yj1.zig");
    const compressed = fbp.getChunkData(60) catch return;
    const decompressed_size = fbp.getDecompressedSize(60, false) catch return;
    const buf = global.allocator.alloc(u8, decompressed_size) catch return;
    defer global.allocator.free(buf);
    _ = yj1.decompress(compressed, buf) catch return;
    _ = palcommon.fbpBlitToSurface(buf, &video.screen);
    video.updateScreen(null);
}

// GetSavedTimes — reads the wSavedTimes counter from save slot N.
fn getSavedTimes(slot: u32) u32 {
    return @import("save.zig").getSavedTimes(slot);
}

// PAL_SaveSlotMenu — choose a save slot 1-5. Returns slot, or
// MENUITEM_VALUE_CANCELLED if cancelled.
pub fn saveSlotMenu(default_slot: u16) u16 {
    const w = ui.wordMaxWidth(LOADMENU_LABEL_SLOT_FIRST, 5);
    const dx: i32 = if (w > 4) (w - 4) * 16 else 0;

    var boxes: [5]?ui.Box = undefined;
    var menu_items: [5]ui.MenuItem = undefined;
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        const idx: usize = @intCast(i);
        const extra: i32 = if (w > 4) w - 4 else 0;
        boxes[idx] = ui.createSingleLineBox(global.palXY(@intCast(195 - dx), @intCast(7 + 38 * i)), 6 + extra, false);
        menu_items[idx] = .{
            .value = @intCast(i + 1),
            .num_word = LOADMENU_LABEL_SLOT_FIRST + @as(u16, @intCast(i)),
            .enabled = true,
            .pos = global.palXY(@intCast(210 - dx), @intCast(17 + 38 * i)),
        };
    }

    i = 1;
    while (i <= 5) : (i += 1) {
        ui.drawNumber(getSavedTimes(@intCast(i)), 4, global.palXY(270, @intCast(38 * i - 17)), .yellow, .right);
    }

    const default_idx: u16 = if (default_slot == 0) 0 else default_slot - 1;
    const ret = ui.readMenu(null, &menu_items, default_idx, ui.MENUITEM_COLOR);

    i = 0;
    while (i < 5) : (i += 1) {
        ui.deleteBox(boxes[@intCast(i)]);
    }
    video.updateScreen(null);
    return ret;
}

const MAINMENU_LABEL_NEWGAME_VAL: u16 = MAINMENU_LABEL_NEWGAME;

// PAL_OpeningMenu — main menu (New Game / Load Game). Returns the save slot
// to load (1-5), or 0 to start a new game.
pub fn openingMenu() i32 {
    const w0 = ui.wordWidth(MAINMENU_LABEL_NEWGAME);
    const w1 = ui.wordWidth(MAINMENU_LABEL_LOADGAME);

    var menu_items: [2]ui.MenuItem = .{
        .{ .value = 0, .num_word = MAINMENU_LABEL_NEWGAME, .enabled = true, .pos = global.palXY(@intCast(125 - (if (w0 > 4) (w0 - 4) * 8 else 0)), 95) },
        .{ .value = 1, .num_word = MAINMENU_LABEL_LOADGAME, .enabled = true, .pos = global.palXY(@intCast(125 - (if (w1 > 4) (w1 - 4) * 8 else 0)), 112) },
    };

    drawOpeningMenuBackground();
    @import("palette.zig").fadeIn(0, false, 1);

    var default_idx: u16 = 0;
    var item_selected: u16 = 0;

    while (true) {
        item_selected = ui.readMenu(null, &menu_items, default_idx, ui.MENUITEM_COLOR);

        if (item_selected == 0 or item_selected == ui.MENUITEM_VALUE_CANCELLED) {
            item_selected = 0;
            break;
        } else {
            video.backupScreen();
            item_selected = saveSlotMenu(1);
            video.restoreScreen();
            video.updateScreen(null);
            if (item_selected != ui.MENUITEM_VALUE_CANCELLED) break;
            default_idx = 0;
        }
    }

    @import("palette.zig").fadeOut(1);
    return @intCast(item_selected);
}

// PAL_InGameMenu — main in-game menu (Status / Magic / Inventory / System).
pub fn inGameMenu() void {
    video.backupScreen();

    const items: [4]ui.MenuItem = .{
        .{ .value = 1, .num_word = GAMEMENU_LABEL_STATUS, .enabled = true, .pos = global.palXY(16, 50) },
        .{ .value = 2, .num_word = GAMEMENU_LABEL_MAGIC, .enabled = true, .pos = global.palXY(16, 50 + 18) },
        .{ .value = 3, .num_word = GAMEMENU_LABEL_INVENTORY, .enabled = true, .pos = global.palXY(16, 50 + 36) },
        .{ .value = 4, .num_word = GAMEMENU_LABEL_SYSTEM, .enabled = true, .pos = global.palXY(16, 50 + 54) },
    };

    const cash_box = showCash(global.gpg.cash);
    const menu_box = ui.createBox(global.palXY(3, 37), 3, ui.menuTextMaxWidth(&items) - 1, 0, false);

    const itemmenu = @import("itemmenu.zig");
    const magicmenu = @import("magicmenu.zig");
    const player_status_mod = @import("playerstatus.zig");

    while (true) {
        const default_idx: u16 = if (global.gpg.cur_main_menu_item < 0) 0 else @intCast(global.gpg.cur_main_menu_item);
        const ret = ui.readMenu(inGameMenuOnItemChange, &items, default_idx, ui.MENUITEM_COLOR);
        if (ret == ui.MENUITEM_VALUE_CANCELLED) break;

        switch (ret) {
            1 => {
                player_status_mod.playerStatus();
                break;
            },
            2 => {
                magicmenu.inGameMagicMenu();
                break;
            },
            3 => {
                itemmenu.inventoryMenu();
                break;
            },
            4 => {
                if (systemMenu()) break;
            },
            else => {},
        }
    }

    ui.deleteBox(cash_box);
    ui.deleteBox(menu_box);
    video.restoreScreen();
    video.updateScreen(null);
}
