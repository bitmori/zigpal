// Debug visualization overlay.
//
// Inspired by SDLPAL's PAL_ShowSearchTriggerRange (paldebug.c) but extended to
// show:
//   - per-tile passability (red = blocked, green = clear) and event coverage
//   - event-object positions with trigger-mode markers
//   - top-left status line: scene/map/coords (rendered with zpix BDF font)
//
// Toggle with F1 in the libretro frontend.

const std = @import("std");
const global = @import("global.zig");
const palcommon = @import("palcommon.zig");
const video = @import("video.zig");
const map_mod = @import("map.zig");
const bdf = @import("bdf.zig");
const res_mod = @import("res.zig");
const util = @import("util.zig");

pub var enabled: bool = false;
var font: ?bdf.BdfFont = null;
var font_loaded: bool = false;

// Palette indices we use for overlay colors. These vary slightly per scene
// palette but the rough hues hold across the game's palettes.
const COLOR_BLOCKED: u8 = 0x1A; // red-ish
const COLOR_CLEAR: u8 = 0x2C; // greenish
const COLOR_EVENT_TOUCH: u8 = 0x9F; // yellow
const COLOR_EVENT_SEARCH: u8 = 0x8D; // cyan
const COLOR_PARTY: u8 = 0xFF; // bright
const COLOR_TEXT: u8 = 0xFF;
const COLOR_TEXT_SHADOW: u8 = 0x00;

// Try to load the zpix BDF the first time the overlay is enabled. If it isn't
// in the system/pal directory, debug text just falls back to drawing nothing.
pub fn ensureFont() void {
    if (font_loaded) return;
    font_loaded = true;

    const sys_dir = @import("libretro_core.zig").system_dir orelse return;

    var path_buf: [4096]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/pal/zpix.bdf\x00", .{sys_dir}) catch return;
    const path_z: [*:0]const u8 = path_buf[0 .. path.len - 1 :0];

    const buf = util.readFileFully(path_z, global.allocator) orelse return;
    defer global.allocator.free(buf);

    const f = bdf.load(buf, global.allocator) catch return;
    font = f;
}

// Toggle helper used by the input layer (main thread polls keyboard).
pub fn toggle() void {
    enabled = !enabled;
    if (enabled) ensureFont();
}

// Cross-thread "show debug menu" flag — Right Shift now opens a custom menu
// on the next game tick (instead of toggling the overlay directly). The menu
// itself runs on the game thread so it can call into ui.readMenu safely.
pub var menu_request: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

pub fn requestMenu() void {
    menu_request.store(true, .monotonic);
}

pub fn pollMenuRequest() void {
    if (!menu_request.swap(false, .monotonic)) return;
    showMenu();
}

// The debug menu — drawn directly with the zpix BDF since these labels
// aren't in the WORD.DAT table.
const MenuEntry = struct { label: []const u8, action: *const fn () void };
// Labels are stored as BIG5 byte strings so they can be rendered with
// SDLPAL's 16x16 built-in font (text.drawText).
const menu_entries = [_]MenuEntry{
    .{ .label = "\xb4\x4d\xc2\xdc", .action = actionToggleOverlay }, // 尋蹤
    .{ .label = "\xae\xf0\xbe\xae", .action = actionOpenPawnShop }, // 氣凝
    .{ .label = "\xc2\xc3\xaf\x75", .action = actionRandomShop }, // 藏真
    .{ .label = "\xaf\xab\xb1\xc2", .action = actionLearnMagic }, // 神授 (匯 not in wor16 font)
    .{ .label = "\xb6\x69\xc4\x5f", .action = actionGetItem }, // 進寶
    .{ .label = "\xab\x4c\xbc\x76", .action = actionPartyEdit }, // 俠影
    .{ .label = "\xb7\xd2\xbe\xd4", .action = actionStartBattle }, // 煉戰 (魄 not in wor16 font)
    .{ .label = "\xa5\x7e\xa8\xe5", .action = actionHack }, // 外典 — JSON-driven cheats
};

fn actionHack() void {
    @import("hack.zig").runMenu();
}

fn actionStartBattle() void {
    const team = pickEnemyTeam() orelse return;
    _ = @import("battle.zig").startBattle(team, false);
}

// Enemy-team picker — same 3×7 layout as itemSelectMenuUpdate (itemmenu.zig:104).
// Each cell shows the team leader's name followed by the team ID.
fn pickEnemyTeam() ?u16 {
    const ui = @import("ui.zig");
    const text = @import("text.zig");
    const palcommon_mod = @import("palcommon.zig");
    const video_mod = @import("video.zig");
    const input_mod = @import("input.zig");
    const util_mod = @import("util.zig");

    const SPRITENUM_CURSOR: i32 = 69;

    var ids: [4096]u16 = undefined;
    var n_total: usize = 0;
    const total_teams: u32 = @intCast(global.gpg.g.enemy_teams.len);
    var t: u32 = 1;
    while (t < total_teams and n_total < ids.len) : (t += 1) {
        if (global.gpg.g.enemy_teams[t].enemy[0] != 0 and
            global.gpg.g.enemy_teams[t].enemy[0] != 0xFFFF)
        {
            ids[n_total] = @intCast(t);
            n_total += 1;
        }
    }
    if (n_total == 0) return null;
    const n: i32 = @intCast(n_total);

    // Same magic numbers as itemSelectMenuUpdate (itemmenu.zig:104-110).
    const word_length: i32 = 10;
    const items_per_line: i32 = @divTrunc(32, word_length); // 3
    const item_text_width: i32 = 8 * word_length + 20; // 100
    const lines_per_page: i32 = 7;
    const cursor_x_offset: i32 = @divTrunc(word_length * 5, 2);
    const page_line_offset: i32 = @divTrunc(lines_per_page + 1, 2);

    video_mod.backupScreen();

    var current: i32 = 0;
    var dw_time = util_mod.getTicks();
    while (true) {
        if (util_mod.shouldQuit()) break;
        video_mod.restoreScreen();

        _ = ui.createBoxWithShadow(global.palXY(2, 0), lines_per_page - 1, 17, 1, false, 0);

        var i: i32 = @divTrunc(current, items_per_line) * items_per_line - items_per_line * page_line_offset;
        if (i < 0) i = 0;

        var j: i32 = 0;
        outer: while (j < lines_per_page) : (j += 1) {
            var k: i32 = 0;
            while (k < items_per_line) : (k += 1) {
                if (i >= n) break :outer;
                const team_id = ids[@intCast(i)];
                const color: u8 = if (i == current) ui.menuItemColorSelected() else ui.MENUITEM_COLOR;
                // Same coordinates as itemSelectMenuUpdate (itemmenu.zig:183).
                const x: i32 = 15 + k * item_text_width;
                const y: i32 = 12 + j * 18;

                // Leader's name (acts like the item word).
                const first_enemy_obj = global.gpg.g.enemy_teams[team_id].enemy[0];
                if (first_enemy_obj != 0) {
                    text.drawText(
                        text.getWord(first_enemy_obj),
                        global.palXY(@truncate(x), @truncate(y)),
                        color,
                        true,
                        false,
                    );
                }
                // Team ID right after the leader's name. Names are at most 4
                // BIG5 chars (= 64px); shift one full BIG5 char (16px) right
                // beyond the previous landing spot so the digits clear the
                // last name glyph.
                ui.drawNumber(
                    team_id,
                    4,
                    global.palXY(@truncate(x + 8 * word_length / 2 + 12 + 16), @truncate(y + 4)),
                    .cyan,
                    .left,
                );

                if (i == current) {
                    if (palcommon_mod.spriteGetFrame(ui.sprite_ui, SPRITENUM_CURSOR)) |bmp| {
                        _ = palcommon_mod.rleBlitToSurface(
                            bmp,
                            &video_mod.screen,
                            global.palXY(@truncate(x + cursor_x_offset), @truncate(y + 10)),
                        );
                    }
                }
                i += 1;
            }
        }

        // Composition for the highlighted team — same color as the item-menu
        // description (itemmenu.zig:234, DESCTEXT_COLOR = 0x3C). 3 names per
        // line × 2 lines fits all 5 slots.
        const DESCTEXT_COLOR: u8 = 0x3C;
        // BIG5: 召喚 = a5\x6c b3\x58 — placeholder shown when a slot's enemy
        // index is 0 (script-summoned mid-battle, no fixed unit). 0xFFFF
        // means the slot is unused/empty.
        const SUMMON_LABEL: []const u8 = "\xa5\x6c\xb3\x58";
        const cur_team = &global.gpg.g.enemy_teams[ids[@intCast(current)]];
        var slot: usize = 0;
        while (slot < global.MAX_ENEMIES_IN_TEAM) : (slot += 1) {
            const enemy_obj = cur_team.enemy[slot];
            if (enemy_obj == 0xFFFF) continue;
            const row: i32 = @intCast(slot / 3);
            const col: i32 = @intCast(slot % 3);
            const sx: i32 = 15 + col * 96;
            const sy: i32 = 158 + row * 18;
            const label: []const u8 = if (enemy_obj == 0) SUMMON_LABEL else text.getWord(enemy_obj);
            text.drawText(
                label,
                global.palXY(@truncate(sx), @truncate(sy)),
                DESCTEXT_COLOR,
                true,
                false,
            );
        }

        video_mod.updateScreen(null);

        while (util_mod.getTicks() < dw_time) {
            input_mod.processEvent();
            if (input_mod.state.key_press != 0) break;
            util_mod.delay(5);
            if (util_mod.shouldQuit()) break;
        }
        dw_time = util_mod.getTicks() + global.FRAME_TIME;

        const k = input_mod.state.key_press;
        input_mod.clearKeyState();

        // Same key semantics as itemSelectMenuUpdate.
        var item_delta: i32 = 0;
        if ((k & input_mod.KEY_UP) != 0) {
            item_delta = -items_per_line;
        } else if ((k & input_mod.KEY_DOWN) != 0) {
            item_delta = items_per_line;
        } else if ((k & input_mod.KEY_LEFT) != 0) {
            item_delta = -1;
        } else if ((k & input_mod.KEY_RIGHT) != 0) {
            item_delta = 1;
        } else if ((k & input_mod.KEY_PGUP) != 0) {
            item_delta = -(items_per_line * lines_per_page);
        } else if ((k & input_mod.KEY_PGDN) != 0) {
            item_delta = items_per_line * lines_per_page;
        } else if ((k & input_mod.KEY_HOME) != 0) {
            item_delta = -current;
        } else if ((k & input_mod.KEY_END) != 0) {
            item_delta = n - current - 1;
        } else if ((k & input_mod.KEY_SEARCH) != 0) {
            video_mod.restoreScreen();
            video_mod.updateScreen(null);
            return ids[@intCast(current)];
        } else if ((k & input_mod.KEY_MENU) != 0) break;

        if (current + item_delta < 0) {
            current = 0;
        } else if (current + item_delta >= n) {
            current = n - 1;
        } else {
            current += item_delta;
        }
    }
    video_mod.restoreScreen();
    video_mod.updateScreen(null);
    return null;
}

fn actionToggleOverlay() void {
    enabled = !enabled;
    if (enabled) ensureFont();
}

fn actionOpenPawnShop() void {
    @import("shop.zig").sellMenu();
}

fn actionRandomShop() void {
    const util_mod = @import("util.zig");
    const n_stores: u32 = @intCast(global.gpg.g.stores.len);
    if (n_stores == 0) return;
    var attempts: u32 = 0;
    while (attempts < 64) : (attempts += 1) {
        const idx: u32 = @intCast(util_mod.randomLong(0, @intCast(n_stores - 1)));
        if (global.gpg.g.stores[idx].items[0] != 0) {
            global.gpg.cash +%= 10000;
            @import("shop.zig").buyMenu(@intCast(idx));
            return;
        }
    }
}

fn actionLearnMagic() void {
    const role_idx = pickPartyMember() orelse return;
    const role = global.gpg.party[role_idx].player_role;
    var ids: [global.MAX_OBJECTS]u16 = undefined;
    var n: usize = 0;
    var oid: u16 = 1;
    while (oid < global.MAX_OBJECTS) : (oid += 1) {
        if (isMagicObject(oid)) {
            ids[n] = oid;
            n += 1;
        }
    }
    if (n == 0) return;
    const w = @import("magicmenu.zig").magicSelectionMenuFromList(ids[0..n]);
    if (w == 0) return;
    _ = global.addMagic(role, w);
}

fn actionGetItem() void {
    var ids: [global.MAX_OBJECTS]u16 = undefined;
    var n: usize = 0;
    var oid: u16 = 1;
    while (oid < global.MAX_OBJECTS) : (oid += 1) {
        if (isItemObject(oid)) {
            ids[n] = oid;
            n += 1;
        }
    }
    if (n == 0) return;
    const w = @import("itemmenu.zig").itemSelectMenuFromList(ids[0..n]);
    if (w == 0) return;
    const owned: u32 = global.getItemAmount(w);
    const room: u32 = if (owned >= 99) 0 else 99 - owned;
    if (room == 0) return;
    const qty = @import("uigame.zig").amountSelect(room);
    if (qty == 0) return;
    if (!@import("uigame.zig").confirmMenu()) return;
    _ = global.addItemToInventory(w, @intCast(qty));
}

fn actionPartyEdit() void {
    partyEditMenu();
}

// SDLPAL Object is a union over 6 words; the only reliable way to tell apart
// items / magics / enemies / poisons is the reserved-slot pattern:
//   ITEM_DOS:    data[0..5] = bitmap, price, onUse, onEquip, onThrow, flags
//   MAGIC_DOS:   data[0..5] = magicNum,  0,    onSuccess, onUse, 0,   flags
//   ENEMY:       data[0..4] = enemyID, resistance, onTurnStart, onBattleEnd, onReady
//   POISON:      data[0..4] = level, color, playerScript, 0, enemyScript
// Type filtering is driven by desc.json's "<id>|<type>" tagged keys. Entries
// without a type tag (or that aren't in desc.json at all) are treated as
// "other" and don't show up in either picker.
fn isMagicObject(id: u16) bool {
    return @import("objectdesc.zig").getType(id) == .magic;
}

fn isItemObject(id: u16) bool {
    return @import("objectdesc.zig").getType(id) == .item;
}

// Pick one of the active party members — same UI as inGameMagicMenu's
// player picker (magicmenu.zig:344): player info boxes along the bottom +
// a names list rendered with the standard ui.readMenu chrome.
fn pickPartyMember() ?u32 {
    const ui = @import("ui.zig");
    const uibattle = @import("uibattle.zig");

    const n: u32 = @as(u32, global.gpg.max_party_member_index) + 1;
    if (n == 0) return null;

    // Player info boxes along the bottom.
    var x: i32 = 45;
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        uibattle.playerInfoBox(global.palXY(@intCast(x), 165), global.gpg.party[i].player_role);
        x += 78;
    }

    // Names list.
    var menu_items: [global.MAX_PLAYERS_IN_PARTY]ui.MenuItem = undefined;
    var y: i32 = 75;
    i = 0;
    while (i < n) : (i += 1) {
        const role = global.gpg.party[i].player_role;
        menu_items[i] = .{
            .value = @intCast(i),
            .num_word = global.gpg.g.player_roles.name[role],
            .enabled = global.gpg.g.player_roles.hp[role] > 0,
            .pos = global.palXY(48, @intCast(y)),
        };
        y += 18;
    }
    const items_slice = menu_items[0..n];
    _ = ui.createBox(global.palXY(35, 62), @intCast(n - 1), ui.menuTextMaxWidth(items_slice) - 1, 0, false);

    const ret = ui.readMenu(null, items_slice, 0, ui.MENUITEM_COLOR);
    if (ret == ui.MENUITEM_VALUE_CANCELLED) return null;
    return @intCast(ret);
}

fn partyEditMenu() void {
    const ui = @import("ui.zig");
    const text = @import("text.zig");
    const video_mod = @import("video.zig");
    const input_mod = @import("input.zig");
    const util_mod = @import("util.zig");

    video_mod.backupScreen();

    // BIG5: 在隊 = b3\x71b6\xa4 ; 形象 = a7\xceb6\x48 — encoded as raw bytes.
    const HDR_IN_PARTY: []const u8 = "\xa6\x62\xb6\xa4";
    const HDR_SPRITE: []const u8 = "\xa7\xce\xb6\x48";
    const HDR_COLOR: u8 = ui.MENUITEM_COLOR_INACTIVE;

    var current: u32 = 0;
    var dw_time = util_mod.getTicks();
    while (true) {
        if (util_mod.shouldQuit()) break;
        video_mod.restoreScreen();
        _ = ui.createBox(global.palXY(20, 30), 7, 14, 1, false);

        // Header row.
        const hdr_y: i32 = 50;
        text.drawText(HDR_IN_PARTY, global.palXY(40 + 70, @truncate(hdr_y)), HDR_COLOR, true, false);
        text.drawText(HDR_SPRITE, global.palXY(40 + 145, @truncate(hdr_y)), HDR_COLOR, true, false);

        var i: u32 = 0;
        while (i < global.MAX_PLAYER_ROLES) : (i += 1) {
            const x: i32 = 40;
            const y: i32 = 68 + @as(i32, @intCast(i)) * 18;
            const color: u8 = if (i == current) ui.menuItemColorSelected() else ui.MENUITEM_COLOR;
            text.drawText(text.getWord(global.gpg.g.player_roles.name[i]), global.palXY(@truncate(x), @truncate(y)), color, true, false);

            const slot: i32 = playerSlot(@intCast(i));
            if (slot >= 0) {
                ui.drawNumber(@intCast(slot + 1), 1, global.palXY(@truncate(x + 80), @truncate(y + 4)), .yellow, .right);
            }
            ui.drawNumber(global.gpg.g.player_roles.sprite_num[i], 4, global.palXY(@truncate(x + 145 + 32), @truncate(y + 4)), .cyan, .right);
        }

        video_mod.updateScreen(null);

        while (util_mod.getTicks() < dw_time) {
            input_mod.processEvent();
            if (input_mod.state.key_press != 0) break;
            util_mod.delay(5);
            if (util_mod.shouldQuit()) break;
        }
        dw_time = util_mod.getTicks() + global.FRAME_TIME;

        const k = input_mod.state.key_press;
        input_mod.clearKeyState();

        if ((k & input_mod.KEY_UP) != 0) {
            if (current == 0) current = global.MAX_PLAYER_ROLES - 1 else current -= 1;
        } else if ((k & input_mod.KEY_DOWN) != 0) {
            current = (current + 1) % global.MAX_PLAYER_ROLES;
        } else if ((k & input_mod.KEY_LEFT) != 0) {
            global.gpg.g.player_roles.sprite_num[current] -%= 1;
            global.setLoadFlags(global.LOAD_PLAYER_SPRITE);
        } else if ((k & input_mod.KEY_RIGHT) != 0) {
            global.gpg.g.player_roles.sprite_num[current] +%= 1;
            global.setLoadFlags(global.LOAD_PLAYER_SPRITE);
        } else if ((k & input_mod.KEY_SEARCH) != 0) {
            togglePartyMember(@intCast(current));
            global.setLoadFlags(global.LOAD_PLAYER_SPRITE);
        } else if ((k & input_mod.KEY_MENU) != 0) break;
    }

    video_mod.restoreScreen();
    video_mod.updateScreen(null);
    global.setLoadFlags(global.LOAD_PLAYER_SPRITE);
}

fn playerSlot(role: u16) i32 {
    var i: u32 = 0;
    while (i <= global.gpg.max_party_member_index) : (i += 1) {
        if (global.gpg.party[i].player_role == role) return @intCast(i);
    }
    return -1;
}

fn togglePartyMember(role: u16) void {
    const slot = playerSlot(role);
    if (slot >= 0) {
        if (global.gpg.max_party_member_index == 0) return; // can't remove last
        var i: u32 = @intCast(slot);
        while (i < global.gpg.max_party_member_index) : (i += 1) {
            global.gpg.party[i] = global.gpg.party[i + 1];
        }
        global.gpg.max_party_member_index -= 1;
    } else {
        if (@as(u32, global.gpg.max_party_member_index) + 1 >= global.MAX_PLAYERS_IN_PARTY) return;
        global.gpg.max_party_member_index += 1;
        global.gpg.party[global.gpg.max_party_member_index] = .{
            .player_role = role,
            .x = 0,
            .y = 0,
            .frame = 0,
            .image_offset = 0,
        };
    }
}

fn showMenu() void {
    const ui = @import("ui.zig");
    const text = @import("text.zig");
    const video_mod = @import("video.zig");
    const input_mod = @import("input.zig");
    const util_mod = @import("util.zig");

    video_mod.backupScreen();

    // Match the layout SDLPAL uses for PAL_InGameMenu (uigame.c:507): items
    // start 13px in from the box origin and stride 18px vertically. Two BIG5
    // chars need n_cols-1 = 1 (~32px content + ~16px borders).
    const box_x: i32 = 16;
    const box_y: i32 = 28;
    const cols_minus_1: i32 = 1;
    const rows_minus_1: i32 = @as(i32, @intCast(menu_entries.len)) - 1;
    const ROW_H: i32 = 18;
    const PAD_X: i32 = 13;
    const PAD_Y: i32 = 13;

    _ = ui.createBox(
        global.palXY(@truncate(box_x), @truncate(box_y)),
        rows_minus_1,
        cols_minus_1,
        0,
        false,
    );

    var current: usize = 0;
    input_mod.clearKeyState();
    var dw_time = util_mod.getTicks();

    while (true) {
        if (util_mod.shouldQuit()) break;

        // Re-blit the box every frame so the highlight cycle redraws.
        var i: usize = 0;
        while (i < menu_entries.len) : (i += 1) {
            const color: u8 = if (i == current) ui.menuItemColorSelected() else ui.MENUITEM_COLOR;
            const e = menu_entries[i];
            const x: i32 = box_x + PAD_X;
            const y: i32 = box_y + PAD_Y + @as(i32, @intCast(i)) * ROW_H;
            text.drawText(e.label, global.palXY(@truncate(x), @truncate(y)), color, true, false);
        }
        video_mod.updateScreen(null);

        while (util_mod.getTicks() < dw_time) {
            input_mod.processEvent();
            if (input_mod.state.key_press != 0) break;
            util_mod.delay(5);
            if (util_mod.shouldQuit()) {
                video_mod.restoreScreen();
                video_mod.updateScreen(null);
                return;
            }
        }
        dw_time = util_mod.getTicks() + global.FRAME_TIME;

        const k = input_mod.state.key_press;
        input_mod.clearKeyState();

        if ((k & (input_mod.KEY_UP | input_mod.KEY_LEFT)) != 0) {
            if (current == 0) current = menu_entries.len - 1 else current -= 1;
        } else if ((k & (input_mod.KEY_DOWN | input_mod.KEY_RIGHT)) != 0) {
            current = (current + 1) % menu_entries.len;
        } else if ((k & input_mod.KEY_SEARCH) != 0) {
            menu_entries[current].action();
            break;
        } else if ((k & input_mod.KEY_MENU) != 0) {
            break;
        }

        input_mod.processEvent();
    }

    video_mod.restoreScreen();
    video_mod.updateScreen(null);
    input_mod.clearKeyState();
}

// drawPixel — guarded one-pixel set on the 320x200 indexed surface.
fn drawPixel(x: i32, y: i32, color: u8) void {
    if (x < 0 or x >= video.screen.w or y < 0 or y >= video.screen.h) return;
    video.screen.pixels[@intCast(y * video.screen.pitch + x)] = color;
}

fn drawHLine(x0: i32, x1: i32, y: i32, color: u8) void {
    var x = x0;
    while (x <= x1) : (x += 1) drawPixel(x, y, color);
}

fn drawVLine(x: i32, y0: i32, y1: i32, color: u8) void {
    var y = y0;
    while (y <= y1) : (y += 1) drawPixel(x, y, color);
}

fn drawRect(x: i32, y: i32, w: i32, h: i32, color: u8) void {
    drawHLine(x, x + w - 1, y, color);
    drawHLine(x, x + w - 1, y + h - 1, color);
    drawVLine(x, y, y + h - 1, color);
    drawVLine(x + w - 1, y, y + h - 1, color);
}

// Draw the 32×16 isometric tile diamond outline. Corners are top (16,0),
// right (32,8), bottom (16,16), left (0,8). Slope is 2:1, so we iterate
// horizontally and floor-divide x by 2 to get y — that keeps the line
// contiguous (otherwise it shows up as a dashed pattern).
fn drawTileDiamond(sx: i32, sy: i32, color: u8) void {
    var dx: i32 = 0;
    while (dx <= 16) : (dx += 1) {
        const dy: i32 = @divTrunc(dx, 2);
        // top half (apex at sy+0)
        drawPixel(sx + 16 - dx, sy + dy, color);
        drawPixel(sx + 16 + dx, sy + dy, color);
        // bottom half (apex at sy+16)
        drawPixel(sx + 16 - dx, sy + 16 - dy, color);
        drawPixel(sx + 16 + dx, sy + 16 - dy, color);
    }
}

// Draw a text string with a 1px black drop shadow for readability.
fn drawText(text: []const u8, x: i32, y: i32) void {
    const f = if (font) |*p| p else return;
    _ = f.drawAscii(text, &video.screen, x + 1, y + 1, COLOR_TEXT_SHADOW);
    _ = f.drawAscii(text, &video.screen, x, y, COLOR_TEXT);
}

// drawOverlay — invoked at the end of PAL_MakeScene when `enabled` is true.
pub fn drawOverlay() void {
    if (!enabled) return;
    ensureFont();

    const m = res_mod.getCurrentMap() orelse return;
    drawTileGrid(m);
    drawEventObjects();
    drawPartyMarker();
    drawStatusLine();
}

// Tile coordinates in SDLPAL's map are: 64 x 128, tile 32x16 px, with two
// "halves" h=0 (offset 0,0) and h=1 (offset 16,8). Visible viewport is 320x200
// in scene coordinates (== gpScreen). We translate world->screen via the
// viewport offset.
fn drawTileGrid(m: *const map_mod.PalMap) void {
    const view_x: i32 = global.palX(global.gpg.viewport);
    const view_y: i32 = global.palY(global.gpg.viewport);

    // World tile range covering the visible 320x200 + a little padding.
    const x0: i32 = @divTrunc(view_x, 32) - 1;
    const x1: i32 = @divTrunc(view_x + 320, 32) + 2;
    const y0: i32 = @divTrunc(view_y, 16) - 1;
    const y1: i32 = @divTrunc(view_y + 200, 16) + 2;

    var ty: i32 = y0;
    while (ty < y1) : (ty += 1) {
        if (ty < 0 or ty >= 128) continue;
        var tx: i32 = x0;
        while (tx < x1) : (tx += 1) {
            if (tx < 0 or tx >= 64) continue;
            var h: i32 = 0;
            while (h < 2) : (h += 1) {
                // Match SDLPAL's PAL_MapBlitToSurface: each tile sprite's
                // top-left corner is at (x*32 + h*16 - 16, y*16 + h*8 - 8) in
                // world coordinates. The diamond inscribed in that 32×16 box
                // has its *center* exactly at (x*32 + h*16, y*16 + h*8).
                const wx: i32 = tx * 32 + h * 16 - 16;
                const wy: i32 = ty * 16 + h * 8 - 8;
                const sx = wx - view_x;
                const sy = wy - view_y;

                if (map_mod.tileIsBlocked(m, @intCast(tx), @intCast(ty), @intCast(h))) {
                    drawTileDiamond(sx, sy, COLOR_BLOCKED);
                }
            }
        }
    }
}

fn drawEventObjects() void {
    const view_x: i32 = global.palX(global.gpg.viewport);
    const view_y: i32 = global.palY(global.gpg.viewport);
    const scene_idx: usize = @as(usize, global.gpg.num_scene) - 1;
    const start: u32 = global.gpg.g.scenes[scene_idx].event_object_index + 1;
    const end: u32 = global.gpg.g.scenes[scene_idx + 1].event_object_index;

    var i: u32 = start;
    while (i <= end) : (i += 1) {
        const eo = &global.gpg.g.event_objects[i - 1];
        if (eo.state == 0) continue; // hidden

        const ex: i32 = @bitCast(@as(u32, eo.x));
        const ey: i32 = @bitCast(@as(u32, eo.y));
        const sx = ex - view_x;
        const sy = ey - view_y;
        if (sx < -16 or sx >= 320 + 16 or sy < -16 or sy >= 200 + 16) continue;

        const color: u8 = if (eo.trigger_mode >= global.TRIGGER_TOUCH_NEAR) COLOR_EVENT_TOUCH else COLOR_EVENT_SEARCH;
        drawRect(sx - 6, sy - 8, 13, 13, color);

        // Print event-object index as a tiny number above the box.
        var buf: [16]u8 = undefined;
        const slice = std.fmt.bufPrint(&buf, "{d}", .{i}) catch continue;
        drawText(slice, sx - 6, sy - 18);
    }
}

fn drawPartyMarker() void {
    const x: i32 = global.palX(global.gpg.party_offset);
    const y: i32 = global.palY(global.gpg.party_offset);
    drawRect(x - 4, y - 6, 9, 9, COLOR_PARTY);
    drawPixel(x, y, COLOR_PARTY);
}

fn drawStatusLine() void {
    const scene_idx: usize = @as(usize, global.gpg.num_scene) - 1;
    const map_num = global.gpg.g.scenes[scene_idx].map_num;
    const wx: i32 = global.palX(global.gpg.viewport) + global.palX(global.gpg.party_offset);
    const wy: i32 = global.palY(global.gpg.viewport) + global.palY(global.gpg.party_offset);
    const dir = global.gpg.party_direction;

    var buf: [128]u8 = undefined;
    const dir_s: []const u8 = switch (dir) {
        0 => "S",
        1 => "W",
        2 => "N",
        3 => "E",
        else => "?",
    };
    const line = std.fmt.bufPrint(&buf, "SCN={d} MAP={d} XY=({d},{d}) D={s}", .{ global.gpg.num_scene, map_num, wx, wy, dir_s }) catch return;
    drawText(line, 2, 2);

    // Tile coords below.
    const tx = @divTrunc(wx, 32);
    const ty = @divTrunc(wy, 16);
    const line2 = std.fmt.bufPrint(&buf, "TILE=({d},{d})", .{ tx, ty }) catch return;
    drawText(line2, 2, 14);
}
