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
const palette = @import("palette.zig");
const uibattle = @import("uibattle.zig");

const SPRITENUM_SLASH: i32 = 39;
const SPRITENUM_CURSOR: i32 = 69;
const SPRITENUM_CURSOR_UP: i32 = 67;
const CASH_LABEL: u16 = 21;

const MagicItem = struct {
    magic: u16,
    mp: u16,
    enabled: bool,
};

var rg_magic_item: [global.MAX_PLAYER_MAGICS]MagicItem = undefined;
var g_num_magic: i32 = 0;
var g_current_item: i32 = 0;
var g_player_mp: u16 = 0;

// PAL_MagicSelectionMenuInit.
pub fn magicSelectionMenuInit(player_role: u16, in_battle: bool, default_magic: u16) void {
    g_current_item = 0;
    g_num_magic = 0;
    g_player_mp = global.gpg.g.player_roles.mp[player_role];

    var i: u32 = 0;
    while (i < global.MAX_PLAYER_MAGICS) : (i += 1) {
        const w = global.gpg.g.player_roles.magic[i][player_role];
        if (w != 0) {
            rg_magic_item[@intCast(g_num_magic)].magic = w;
            const magic_num = global.gpg.g.objects[w].magic().magic_number;
            rg_magic_item[@intCast(g_num_magic)].mp = global.gpg.g.magics[magic_num].cost_mp;
            rg_magic_item[@intCast(g_num_magic)].enabled = true;

            if (rg_magic_item[@intCast(g_num_magic)].mp > g_player_mp) {
                rg_magic_item[@intCast(g_num_magic)].enabled = false;
            }

            const flags = global.gpg.g.objects[w].magic().flags;
            if (in_battle) {
                if ((flags & global.MAGIC_FLAG_USABLE_IN_BATTLE) == 0) {
                    rg_magic_item[@intCast(g_num_magic)].enabled = false;
                }
            } else {
                if ((flags & global.MAGIC_FLAG_USABLE_OUTSIDE_BATTLE) == 0) {
                    rg_magic_item[@intCast(g_num_magic)].enabled = false;
                }
            }
            g_num_magic += 1;
        }
    }

    // Bubble-sort by magic ID.
    var ii: i32 = 0;
    while (ii < g_num_magic - 1) : (ii += 1) {
        var done = true;
        var j: i32 = 0;
        while (j < g_num_magic - 1 - ii) : (j += 1) {
            const a = rg_magic_item[@intCast(j)];
            const b = rg_magic_item[@intCast(j + 1)];
            if (a.magic > b.magic) {
                rg_magic_item[@intCast(j)] = b;
                rg_magic_item[@intCast(j + 1)] = a;
                done = false;
            }
        }
        if (done) break;
    }

    var k: i32 = 0;
    while (k < g_num_magic) : (k += 1) {
        if (rg_magic_item[@intCast(k)].magic == default_magic) {
            g_current_item = k;
            break;
        }
    }
}

pub fn magicSelectionMenuUpdate() u16 {
    const word_length: i32 = 10;
    const items_per_line: i32 = @divTrunc(32, word_length);
    const item_text_width: i32 = 8 * word_length + 7;
    const lines_per_page: i32 = 5;
    const box_y_offset: i32 = 0;
    const cursor_x_offset: i32 = @divTrunc(word_length * 5, 2);
    const page_line_offset: i32 = @divTrunc(lines_per_page, 2);

    const k_press = input.state.key_press;
    var item_delta: i32 = 0;
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
        item_delta = -g_current_item;
    } else if ((k_press & input.KEY_END) != 0) {
        item_delta = g_num_magic - g_current_item - 1;
    } else if ((k_press & input.KEY_MENU) != 0) {
        return 0;
    }

    if (g_current_item + item_delta < 0)
        g_current_item = 0
    else if (g_current_item + item_delta >= g_num_magic)
        g_current_item = g_num_magic - 1
    else
        g_current_item += item_delta;

    _ = ui.createBoxWithShadow(global.palXY(10, @intCast(42 + box_y_offset)), lines_per_page - 1, 16, 1, false, 0);

    // Layout depends on whether descriptions are available. With descriptions:
    // single MP box on the left (the right side of the screen is freed up for
    // the description). Without: cash on the left, MP on the right.
    const has_desc = @import("objectdesc.zig").hasDescTable();

    if (!has_desc) {
        _ = ui.createSingleLineBox(global.palXY(0, 0), 5, false);
        text.drawText(text.getWord(CASH_LABEL), global.palXY(10, 10), 0, false, false);
        ui.drawNumber(global.gpg.cash, 6, global.palXY(49, 14), .yellow, .right);

        _ = ui.createSingleLineBox(global.palXY(215, 0), 5, false);
        if (palcommon.spriteGetFrame(ui.sprite_ui, SPRITENUM_SLASH)) |slash| {
            _ = palcommon.rleBlitToSurface(slash, &video.screen, global.palXY(260, 14));
        }
        if (g_num_magic > 0) {
            ui.drawNumber(rg_magic_item[@intCast(g_current_item)].mp, 4, global.palXY(230, 14), .yellow, .right);
        }
        ui.drawNumber(g_player_mp, 4, global.palXY(265, 14), .cyan, .right);
    } else {
        _ = ui.createSingleLineBox(global.palXY(0, 0), 5, false);
        if (palcommon.spriteGetFrame(ui.sprite_ui, SPRITENUM_SLASH)) |slash| {
            _ = palcommon.rleBlitToSurface(slash, &video.screen, global.palXY(45, 14));
        }
        if (g_num_magic > 0) {
            ui.drawNumber(rg_magic_item[@intCast(g_current_item)].mp, 4, global.palXY(15, 14), .yellow, .right);
        }
        ui.drawNumber(g_player_mp, 4, global.palXY(50, 14), .cyan, .right);
    }

    var i: i32 = @divTrunc(g_current_item, items_per_line) * items_per_line - items_per_line * page_line_offset;
    if (i < 0) i = 0;

    var j: i32 = 0;
    outer: while (j < lines_per_page) : (j += 1) {
        var k: i32 = 0;
        while (k < items_per_line) : (k += 1) {
            if (i >= g_num_magic) break :outer;

            var color: u8 = ui.MENUITEM_COLOR;
            if (i == g_current_item) {
                color = if (rg_magic_item[@intCast(i)].enabled) ui.menuItemColorSelected() else ui.MENUITEM_COLOR_SELECTED_INACTIVE;
            } else if (!rg_magic_item[@intCast(i)].enabled) {
                color = ui.MENUITEM_COLOR_INACTIVE;
            }

            text.drawText(
                text.getWord(rg_magic_item[@intCast(i)].magic),
                global.palXY(@intCast(35 + k * item_text_width), @intCast(54 + j * 18 + box_y_offset)),
                color,
                true,
                false,
            );

            if (i == g_current_item) {
                if (palcommon.spriteGetFrame(ui.sprite_ui, SPRITENUM_CURSOR)) |bmp| {
                    _ = palcommon.rleBlitToSurface(
                        bmp,
                        &video.screen,
                        global.palXY(@intCast(35 + cursor_x_offset + k * item_text_width), @intCast(64 + j * 18 + box_y_offset)),
                    );
                }
            }
            i += 1;
        }
    }

    // Description for the highlighted magic.
    if (g_num_magic > 0) {
        const objectdesc = @import("objectdesc.zig");
        if (objectdesc.get(rg_magic_item[@intCast(g_current_item)].magic)) |desc| {
            _ = objectdesc.drawAt(desc, 102, 3, 0x3C);
        }
    }

    // Debug overlay: hex ID at the top-left.
    if (g_num_magic > 0 and @import("debug.zig").enabled) {
        var hex_buf: [16]u8 = undefined;
        const s = std.fmt.bufPrint(&hex_buf, "{X}", .{rg_magic_item[@intCast(g_current_item)].magic}) catch return 0xFFFF;
        _ = @import("objectdesc.zig").drawAt(s, 2, 2, 0xFF);
    }

    if ((k_press & input.KEY_SEARCH) != 0) {
        if (g_num_magic > 0 and rg_magic_item[@intCast(g_current_item)].enabled) {
            const jj = @mod(g_current_item, items_per_line);
            const kk: i32 = if (g_current_item < items_per_line * page_line_offset)
                @divTrunc(g_current_item, items_per_line)
            else
                page_line_offset;
            const x = 35 + jj * item_text_width;
            const y = 54 + kk * 18 + box_y_offset;
            text.drawText(
                text.getWord(rg_magic_item[@intCast(g_current_item)].magic),
                global.palXY(@intCast(x), @intCast(y)),
                ui.MENUITEM_COLOR_CONFIRMED,
                false,
                true,
            );
            if (palcommon.spriteGetFrame(ui.sprite_ui, SPRITENUM_CURSOR)) |bmp| {
                _ = palcommon.rleBlitToSurface(bmp, &video.screen, global.palXY(@intCast(x + cursor_x_offset), @intCast(y + 10)));
            }
            return rg_magic_item[@intCast(g_current_item)].magic;
        }
    }

    return 0xFFFF;
}

// PAL_MagicSelectionMenu.
// Debug entry: render the magic-selection menu over an arbitrary list of
// magic object IDs (instead of the player's learned spells). Used by the
// 神授 debug action so it inherits the full chrome — MP frame, cursor sprite,
// description panel — of the regular menu.
pub fn magicSelectionMenuFromList(magic_ids: []const u16) u16 {
    g_current_item = 0;
    g_num_magic = 0;
    g_player_mp = 9999;

    var i: usize = 0;
    while (i < magic_ids.len and g_num_magic < global.MAX_PLAYER_MAGICS) : (i += 1) {
        const w = magic_ids[i];
        if (w == 0) continue;
        const magic_num = global.gpg.g.objects[w].magic().magic_number;
        if (magic_num == 0 or magic_num >= global.gpg.g.magics.len) continue;
        rg_magic_item[@intCast(g_num_magic)] = .{
            .magic = w,
            .mp = global.gpg.g.magics[magic_num].cost_mp,
            .enabled = true,
        };
        g_num_magic += 1;
    }

    // Bubble-sort by magic ID so the layout matches magicSelectionMenuInit.
    var ii: i32 = 0;
    while (ii < g_num_magic - 1) : (ii += 1) {
        var done = true;
        var j: i32 = 0;
        while (j < g_num_magic - 1 - ii) : (j += 1) {
            const a = rg_magic_item[@intCast(j)];
            const b = rg_magic_item[@intCast(j + 1)];
            if (a.magic > b.magic) {
                rg_magic_item[@intCast(j)] = b;
                rg_magic_item[@intCast(j + 1)] = a;
                done = false;
            }
        }
        if (done) break;
    }

    if (g_num_magic == 0) return 0;
    input.clearKeyState();

    var dw_time = util.getTicks();
    while (true) {
        if (util.shouldQuit()) return 0;
        scene.makeScene();
        const w = magicSelectionMenuUpdate();
        video.updateScreen(null);
        input.clearKeyState();
        if (w != 0xFFFF) return w;
        input.processEvent();
        while (util.getTicks() < dw_time) {
            input.processEvent();
            if (input.state.key_press != 0) break;
            util.delay(5);
            if (util.shouldQuit()) return 0;
        }
        dw_time = util.getTicks() + global.FRAME_TIME;
    }
}

pub fn magicSelectionMenu(player_role: u16, in_battle: bool, default_magic: u16) u16 {
    magicSelectionMenuInit(player_role, in_battle, default_magic);
    // No magic learned — bail out cleanly so we don't index rg_magic_item[-1].
    if (g_num_magic == 0) return 0;
    input.clearKeyState();

    var dw_time = util.getTicks();
    while (true) {
        if (util.shouldQuit()) return 0;
        scene.makeScene();

        var x: i32 = 45;
        var i: u32 = 0;
        while (i <= global.gpg.max_party_member_index) : (i += 1) {
            uibattle.playerInfoBox(global.palXY(@intCast(x), 165), global.gpg.party[i].player_role);
            x += 78;
        }

        const w = magicSelectionMenuUpdate();
        video.updateScreen(null);

        input.clearKeyState();
        if (w != 0xFFFF) return w;

        input.processEvent();
        while (util.getTicks() < dw_time) {
            input.processEvent();
            if (input.state.key_press != 0) break;
            util.delay(5);
            if (util.shouldQuit()) return 0;
        }
        dw_time = util.getTicks() + global.FRAME_TIME;
    }
}

// PAL_InGameMagicMenu.
pub fn inGameMagicMenu() void {
    const State = struct {
        var w: u16 = 0;
    };

    var w: u16 = 0;
    if (global.gpg.max_party_member_index == 0) {
        w = 0;
    } else {
        // Draw player info boxes.
        var y: i32 = 45;
        var i: u32 = 0;
        while (i <= global.gpg.max_party_member_index) : (i += 1) {
            uibattle.playerInfoBox(global.palXY(@intCast(y), 165), global.gpg.party[i].player_role);
            y += 78;
        }

        var menu_items: [global.MAX_PLAYERS_IN_PARTY]ui.MenuItem = undefined;
        y = 75;
        i = 0;
        while (i <= global.gpg.max_party_member_index) : (i += 1) {
            const role = global.gpg.party[i].player_role;
            menu_items[i] = .{
                .value = @intCast(i),
                .num_word = global.gpg.g.player_roles.name[role],
                .enabled = global.gpg.g.player_roles.hp[role] > 0,
                .pos = global.palXY(48, @intCast(y)),
            };
            y += 18;
        }

        const n_items: u32 = @as(u32, global.gpg.max_party_member_index) + 1;
        const items_slice = menu_items[0..n_items];
        _ = ui.createBox(global.palXY(35, 62), @intCast(global.gpg.max_party_member_index), ui.menuTextMaxWidth(items_slice) - 1, 0, false);

        const ret = ui.readMenu(null, items_slice, State.w, ui.MENUITEM_COLOR);
        if (ret == ui.MENUITEM_VALUE_CANCELLED) return;
        State.w = ret;
        w = ret;
    }

    var w_magic: u16 = 0;
    while (true) {
        if (util.shouldQuit()) return;
        w_magic = magicSelectionMenu(global.gpg.party[w].player_role, false, w_magic);
        if (w_magic == 0) break;

        video.backupScreen();

        const obj_magic = global.gpg.g.objects[w_magic].magic();
        if ((obj_magic.flags & global.MAGIC_FLAG_APPLY_TO_ALL) != 0) {
            const new_use = script.runTriggerScript(obj_magic.script_on_use, 0);
            global.gpg.g.objects[w_magic].data[3] = new_use;
            if (script.g_script_success) {
                const new_succ = script.runTriggerScript(obj_magic.script_on_success, 0);
                global.gpg.g.objects[w_magic].data[2] = new_succ;
                if (script.g_script_success) {
                    const magic_num = global.gpg.g.objects[w_magic].magic().magic_number;
                    const cost = global.gpg.g.magics[magic_num].cost_mp;
                    const role = global.gpg.party[w].player_role;
                    if (global.gpg.g.player_roles.mp[role] >= cost)
                        global.gpg.g.player_roles.mp[role] -= cost;
                }
            }
            if (global.gpg.need_to_fade_in) {
                palette.fadeIn(@intCast(global.gpg.num_palette), global.gpg.night_palette, 1);
                global.gpg.need_to_fade_in = false;
            }
        } else {
            var w_player: u16 = 0;
            while (w_player != ui.MENUITEM_VALUE_CANCELLED) {
                if (util.shouldQuit()) return;

                // Redraw player info boxes.
                var y: i32 = 45;
                var i: u32 = 0;
                while (i <= global.gpg.max_party_member_index) : (i += 1) {
                    uibattle.playerInfoBox(global.palXY(@intCast(y), 165), global.gpg.party[i].player_role);
                    y += 78;
                }

                video.restoreScreen();

                if (palcommon.spriteGetFrame(ui.sprite_ui, SPRITENUM_CURSOR_UP)) |bmp| {
                    _ = palcommon.rleBlitToSurface(bmp, &video.screen, global.palXY(@intCast(75 + 78 * @as(i32, w_player)), 158));
                }
                video.updateScreen(null);

                while (true) {
                    if (util.shouldQuit()) return;
                    input.clearKeyState();
                    input.processEvent();
                    const k = input.state.key_press;

                    if ((k & input.KEY_MENU) != 0) {
                        w_player = ui.MENUITEM_VALUE_CANCELLED;
                        break;
                    } else if ((k & input.KEY_SEARCH) != 0) {
                        const cur_obj = global.gpg.g.objects[w_magic].magic();
                        const new_use = script.runTriggerScript(cur_obj.script_on_use, global.gpg.party[w_player].player_role);
                        global.gpg.g.objects[w_magic].data[3] = new_use;
                        if (script.g_script_success) {
                            const new_succ = script.runTriggerScript(cur_obj.script_on_success, global.gpg.party[w_player].player_role);
                            global.gpg.g.objects[w_magic].data[2] = new_succ;
                            if (script.g_script_success) {
                                const magic_num = global.gpg.g.objects[w_magic].magic().magic_number;
                                const cost = global.gpg.g.magics[magic_num].cost_mp;
                                const role = global.gpg.party[w].player_role;
                                if (global.gpg.g.player_roles.mp[role] >= cost) {
                                    global.gpg.g.player_roles.mp[role] -= cost;
                                }
                                if (global.gpg.g.player_roles.mp[role] < cost) {
                                    w_player = ui.MENUITEM_VALUE_CANCELLED;
                                }
                            }
                        }
                        break;
                    } else if ((k & (input.KEY_LEFT | input.KEY_UP)) != 0) {
                        if (w_player > 0) {
                            w_player -= 1;
                            break;
                        }
                    } else if ((k & (input.KEY_RIGHT | input.KEY_DOWN)) != 0) {
                        if (w_player < global.gpg.max_party_member_index) {
                            w_player += 1;
                            break;
                        }
                    }
                    util.delay(1);
                }
            }
        }

        // Redraw player info boxes after magic.
        var y: i32 = 45;
        var i: u32 = 0;
        while (i <= global.gpg.max_party_member_index) : (i += 1) {
            uibattle.playerInfoBox(global.palXY(@intCast(y), 165), global.gpg.party[i].player_role);
            y += 78;
        }
    }
}
