//! 魔改 — full-screen enemy stat panel (《情報》).
//!
//! Mirrors PAL_EnemyStatus from the SDLPAL fork. From the misc submenu's
//! 情報 entry the player can flip through every alive enemy in the
//! current encounter and inspect: HP / MaxHP, EXP, level, sorcery
//! resistance, drop value, steal slot, attack-equiv item, per-element
//! resistance vs the battlefield, physical / poison resistance, stored
//! cash, encounter background id (page-up/down lets you preview
//! alternate battlefields just like the fork).

const std = @import("std");
const global = @import("global.zig");
const palcommon = @import("palcommon.zig");
const video = @import("video.zig");
const ui = @import("ui.zig");
const text = @import("text.zig");
const input = @import("input.zig");
const util = @import("util.zig");
const battle = @import("battle.zig");
const yj1 = @import("yj1.zig");
const custom_words = @import("custom_words.zig");

const CASH_LABEL: u16 = 21;

const SPRITENUM_SLASH: i32 = 39;
const MENUITEM_COLOR_CONFIRMED = ui.MENUITEM_COLOR_CONFIRMED;
const MENUITEM_COLOR = ui.MENUITEM_COLOR;

// 三档颜色阈值,跟 SDLPAL fork 一致:>=6 cyan,<=3 red,中间 yellow。
fn colorByVal(v: i32) ui.NumColorEx {
    if (v >= 6) return .cyan;
    if (v <= 3) return .red;
    return .yellow;
}

fn drawBackground(fbp_num: u32) void {
    const fbp = global.gpg.f.fbp orelse return;
    const compressed = fbp.getChunkData(fbp_num) catch return;
    const decomp_size = fbp.getDecompressedSize(fbp_num, false) catch return;
    const buf = global.allocator.alloc(u8, decomp_size) catch return;
    defer global.allocator.free(buf);
    _ = yj1.decompress(compressed, buf) catch return;
    _ = palcommon.fbpBlitToSurface(buf, &video.screen);
}

fn drawEnemy(idx: u32) void {
    const e = &battle.g_battle.enemies[idx];
    const sprite = e.sprite orelse return;
    const frame = palcommon.spriteGetFrame(sprite, @intCast(e.current_frame)) orelse return;
    const x: i32 = @as(i32, global.palX(e.pos)) - @divTrunc(palcommon.rleGetWidth(frame), 2);
    const y: i32 = @as(i32, global.palY(e.pos)) - palcommon.rleGetHeight(frame);
    _ = palcommon.rleBlitToSurface(frame, &video.screen, global.palXY(@truncate(x), @truncate(y)));
}

fn fbpChunkCount() u32 {
    const fbp = global.gpg.f.fbp orelse return 1;
    return fbp.getChunkCount() catch 1;
}

/// Skip past dead / empty slots in a given direction. Returns -1 if no
/// alive slot remains in that direction.
fn nextAlive(start: i32, dir: i32) i32 {
    var i = start;
    while (i >= 0 and i < @as(i32, global.MAX_ENEMIES_IN_TEAM)) {
        const e = &battle.g_battle.enemies[@intCast(i)];
        if (e.object_id != 0 and e.e.health != 0) return i;
        i += dir;
    }
    return -1;
}

/// Top-level: open the 情報 panel and let the player browse enemies until
/// they cancel. Caller must already be inside the battle UI loop (i.e.
/// rgEnemy is populated).
pub fn show() void {
    if (battle.g_battle.max_enemy_index < 0) return;
    var current: i32 = nextAlive(0, 1);
    if (current < 0) return;

    var bg_fbp_num: u32 = global.gpg.num_battle_field;
    const max_fbp: u32 = fbpChunkCount();

    while (current >= 0) {
        if (util.shouldQuit()) return;

        const e = &battle.g_battle.enemies[@intCast(current)];

        drawBackground(bg_fbp_num);
        drawEnemy(@intCast(current));

        // --- Left-side label column ---
        // h=16 (zpix 12px + 4px gap). 10 rows fit in ~160px leaving room for bottom.
        const x_lbl: i32 = 206;
        const y0: i32 = 8;
        const h: i32 = 16;

        custom_words.draw(.exp_label, x_lbl, y0 + 0 * h, MENUITEM_COLOR);
        custom_words.draw(.level_label, x_lbl, y0 + 1 * h, MENUITEM_COLOR);
        custom_words.draw(.hp_label, x_lbl, y0 + 2 * h, MENUITEM_COLOR);
        custom_words.draw(.poison_def, x_lbl, y0 + 3 * h, MENUITEM_COLOR);
        custom_words.draw(.monster_power, x_lbl, y0 + 4 * h, MENUITEM_COLOR);
        custom_words.draw(.steal_item, x_lbl, y0 + 5 * h, MENUITEM_COLOR);
        custom_words.draw(.atk_effect, x_lbl, y0 + 6 * h, MENUITEM_COLOR);

        // Element column parameters (shared by header and numbers).
        const elem_col_w: i32 = 16;
        const elem_x0: i32 = 206;

        // Element header: 7 glyphs, row 9 (rows 6-7 have item names).
        custom_words.drawSpaced(.five_elem, elem_x0, y0 + 9 * h + 4, elem_col_w, MENUITEM_COLOR);

        // --- Numeric values column ---
        const x_val: i32 = 242;
        const y0v: i32 = y0 + 4; // baseline offset for 8px-tall number sprites

        ui.drawNumberEx(@intCast(e.e.exp), 5, global.palXY(@truncate(x_val + 16), @truncate(y0v + 0 * h)), .yellow, .right);
        ui.drawNumberEx(@intCast(e.e.level), 3, global.palXY(@truncate(x_val + 6), @truncate(y0v + 1 * h)), .yellow, .right);

        // HP / MaxHP
        const max_hp: u16 = global.gpg.g.enemies[global.gpg.g.objects[e.object_id].enemy().enemy_id].health;
        var hp_color: ui.NumColorEx = .yellow;
        if (@as(u32, e.e.health) * 4 < @as(u32, max_hp) and e.e.collect_value > 0) hp_color = .green;
        ui.drawNumberEx(@intCast(e.e.health), 5, global.palXY(@truncate(x_val), @truncate(y0v + 2 * h)), hp_color, .right);
        if (palcommon.spriteGetFrame(ui.sprite_ui, SPRITENUM_SLASH)) |slash| {
            _ = palcommon.rleBlitToSurface(slash, &video.screen, global.palXY(@truncate(x_val + 29), @truncate(y0v + 2 * h)));
        }
        ui.drawNumberEx(@intCast(max_hp), 5, global.palXY(@truncate(x_val + 26), @truncate(y0v + 2 * h + 5)), .blue, .right);

        // 巫抗
        const mind: i32 = @intCast(global.gpg.g.objects[e.object_id].enemy().resistance_to_sorcery);
        ui.drawNumberEx(@intCast(@max(mind, 0)), 4, global.palXY(@truncate(x_val), @truncate(y0v + 3 * h)), colorByVal(10 - mind), .right);
        // 妖力
        ui.drawNumberEx(@intCast(e.e.collect_value), 4, global.palXY(@truncate(x_val), @truncate(y0v + 4 * h)), .yellow, .right);
        // 偷竊 — number + item name on same row, name to the right of number.
        ui.drawNumberEx(@intCast(e.e.n_steal_item), 4, global.palXY(@truncate(x_val), @truncate(y0v + 5 * h)), .yellow, .right);
        const w_steal: u16 = if (e.e.steal_item != 0) e.e.steal_item else CASH_LABEL;
        text.drawText(text.getWord(w_steal), global.palXY(@truncate(x_val + 30), @truncate(y0 + 5 * h)), MENUITEM_COLOR_CONFIRMED, true, false);

        // 攻擊效果 — item name on row 7, same x position.
        if (e.e.attack_equiv_item != 0) {
            text.drawText(text.getWord(e.e.attack_equiv_item), global.palXY(@truncate(x_val + 30), @truncate(y0 + 7 * h)), MENUITEM_COLOR_CONFIRMED, true, false);
        }

        // --- Element resistance numbers (row 10, below header at row 9) ---
        const elem_y: i32 = y0v + 10 * h + 4;
        const battlefield = &global.gpg.g.battlefields[global.gpg.num_battle_field];

        var col: u32 = 0;
        while (col < global.NUM_MAGIC_ELEMENTAL + 2) : (col += 1) {
            const cell_x: i32 = elem_x0 + @as(i32, @intCast(col)) * elem_col_w;
            var def_v: i32 = 0;
            if (col < global.NUM_MAGIC_ELEMENTAL) {
                const me: i32 = @as(i32, battlefield.magic_effect[col]);
                const er: i32 = @as(i32, e.e.elem_resistance[col]);
                def_v = @max(10 + me - er, 0);
            } else if (col == global.NUM_MAGIC_ELEMENTAL) {
                def_v = 10 - @as(i32, e.e.physical_resistance);
            } else {
                def_v = 10 - @as(i32, e.e.poison_resistance);
            }
            if (palcommon.spriteGetFrame(ui.sprite_ui, SPRITENUM_SLASH)) |slash| {
                _ = palcommon.rleBlitToSurface(slash, &video.screen, global.palXY(@truncate(cell_x + 11), @truncate(elem_y)));
            }
            ui.drawNumberEx(@intCast(@max(def_v, 0)), 2, global.palXY(@truncate(cell_x), @truncate(elem_y)), colorByVal(def_v), .mid);
        }

        // --- Bottom debug line (pinned near screen bottom) ---
        custom_words.draw(.accumulated_exp, 150, 186, ui.MENUITEM_COLOR);
        ui.drawNumberEx(@intCast(battle.g_battle.exp_gained), 5, global.palXY(206, 190), .pale, .left);
        custom_words.draw(.battlefield_bg, 256, 186, ui.MENUITEM_COLOR);
        ui.drawNumberEx(bg_fbp_num, 2, global.palXY(308, 190), .purple, .right);

        // Cash awarded (bottom-left).
        text.drawText(text.getWord(CASH_LABEL), global.palXY(3, 180), MENUITEM_COLOR, true, false);
        ui.drawNumberEx(@intCast(e.e.cash), 6, global.palXY(40, 185), .yellow, .left);

        // Enemy name + slot index (top-left).
        text.drawText(text.getWord(e.object_id), global.palXY(20, 6), MENUITEM_COLOR_CONFIRMED, true, false);
        ui.drawNumberEx(@intCast(current + 1), 1, global.palXY(10, 11), .yellow, .right);

        // Active poisons on the enemy.
        var py: i32 = 6 + 19;
        var pj: u32 = 0;
        while (pj < global.MAX_POISONS) : (pj += 1) {
            const w = e.poisons[pj].poison_id;
            if (w != 0) {
                const c: u8 = @intCast((global.gpg.g.objects[w].poison().color + 10) & 0xFF);
                text.drawText(text.getWord(w), global.palXY(20, @truncate(py)), c, true, false);
                py += 19;
            }
        }

        video.updateScreen(null);

        input.clearKeyState();
        while (true) {
            if (util.shouldQuit()) return;
            util.delay(1);
            input.processEvent();
            const k = input.state.key_press;
            if (k == 0) continue;

            if ((k & input.KEY_MENU) != 0) return;
            if ((k & (input.KEY_LEFT | input.KEY_UP)) != 0) {
                const next = nextAlive(current - 1, -1);
                if (next < 0) return; // off the left end exits, like the fork
                current = next;
                break;
            }
            if ((k & (input.KEY_RIGHT | input.KEY_DOWN | input.KEY_SEARCH)) != 0) {
                const next = nextAlive(current + 1, 1);
                if (next < 0) return;
                current = next;
                break;
            }
            if ((k & input.KEY_PGDN) != 0) {
                bg_fbp_num = (bg_fbp_num + 1) % max_fbp;
                break;
            }
            if ((k & input.KEY_PGUP) != 0) {
                bg_fbp_num = if (bg_fbp_num == 0) max_fbp - 1 else bg_fbp_num - 1;
                break;
            }
        }
    }
}
