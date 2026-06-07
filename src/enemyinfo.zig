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

// Word indices reused from playerstatus.zig.
const STATUS_LABEL_EXP: u16 = 2;
const STATUS_LABEL_LEVEL: u16 = 48;
const STATUS_LABEL_HP: u16 = 49;
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
        const x_lbl: i32 = 206;
        const y0: i32 = 6;
        const h: i32 = 19;
        var ri: i32 = 0;

        text.drawText(text.getWord(STATUS_LABEL_EXP), global.palXY(@truncate(x_lbl), @truncate(y0 + ri * h)), MENUITEM_COLOR, true, false);
        ri += 1;
        text.drawText(text.getWord(STATUS_LABEL_LEVEL), global.palXY(@truncate(x_lbl), @truncate(y0 + ri * h)), MENUITEM_COLOR, true, false);
        ri += 1;
        text.drawText(text.getWord(STATUS_LABEL_HP), global.palXY(@truncate(x_lbl), @truncate(y0 + ri * h)), MENUITEM_COLOR, true, false);
        ri += 1;
        custom_words.draw(.poison_def, x_lbl, y0 + ri * h, MENUITEM_COLOR);
        ri += 1;
        custom_words.draw(.monster_power, x_lbl, y0 + ri * h, MENUITEM_COLOR);
        ri += 1;
        custom_words.draw(.steal_item, x_lbl, y0 + ri * h, MENUITEM_COLOR);
        ri += 1;
        custom_words.draw(.atk_effect, x_lbl, y0 + ri * h, MENUITEM_COLOR);
        ri += 2; // gap before the elements row
        custom_words.draw(.five_elem, x_lbl, y0 + ri * h, MENUITEM_COLOR);

        // --- Numeric values column (242, 11+i*19) ---
        const x_val: i32 = 242;
        const y0v: i32 = 11;
        var vi: i32 = 0;
        ui.drawNumberEx(@intCast(e.e.exp), 5, global.palXY(@truncate(x_val + 16), @truncate(y0v + vi * h)), .yellow, .right);
        vi += 1;
        ui.drawNumberEx(@intCast(e.e.level), 3, global.palXY(@truncate(x_val + 6), @truncate(y0v + vi * h)), .yellow, .right);
        vi += 1;

        // HP / MaxHP — green when low and still collectable (lets you spot a steal target).
        const max_hp: u16 = global.gpg.g.enemies[global.gpg.g.objects[e.object_id].enemy().enemy_id].health;
        var hp_color: ui.NumColorEx = .yellow;
        if (@as(u32, e.e.health) * 4 < @as(u32, max_hp) and e.e.collect_value > 0) hp_color = .green;
        ui.drawNumberEx(@intCast(e.e.health), 5, global.palXY(@truncate(x_val), @truncate(y0v + vi * h)), hp_color, .right);
        if (palcommon.spriteGetFrame(ui.sprite_ui, SPRITENUM_SLASH)) |slash| {
            _ = palcommon.rleBlitToSurface(slash, &video.screen, global.palXY(@truncate(x_val + 29), @truncate(y0v + vi * h)));
        }
        ui.drawNumberEx(@intCast(max_hp), 5, global.palXY(@truncate(x_val + 26), @truncate(y0v + vi * h + 5)), .blue, .right);
        vi += 1;

        // 巫抗: 0..10 inverse — fork displays (10 - resistance) in the threshold colors.
        const mind: i32 = @intCast(global.gpg.g.objects[e.object_id].enemy().resistance_to_sorcery);
        ui.drawNumberEx(@intCast(@max(mind, 0)), 4, global.palXY(@truncate(x_val), @truncate(y0v + vi * h)), colorByVal(10 - mind), .right);
        vi += 1;
        ui.drawNumberEx(@intCast(e.e.collect_value), 4, global.palXY(@truncate(x_val), @truncate(y0v + vi * h)), .yellow, .right);
        vi += 1;
        ui.drawNumberEx(@intCast(e.e.n_steal_item), 4, global.palXY(@truncate(x_val), @truncate(y0v + vi * h)), .yellow, .right);
        const w_steal: u16 = if (e.e.steal_item != 0) e.e.steal_item else CASH_LABEL;
        text.drawText(text.getWord(w_steal), global.palXY(@truncate(x_val + 30), @truncate(y0v + vi * h - 5)), MENUITEM_COLOR_CONFIRMED, true, false);
        vi += 2; // matches the fork's gap before atk-effect

        if (e.e.attack_equiv_item != 0) {
            text.drawText(text.getWord(e.e.attack_equiv_item), global.palXY(@truncate(x_val + 32), @truncate(y0v + vi * h - 5)), MENUITEM_COLOR_CONFIRMED, true, false);
        }

        // --- Element resistance row ---
        const elem_y: i32 = 6 + (vi + 2) * h;
        const battlefield = &global.gpg.g.battlefields[global.gpg.num_battle_field];
        var elem: u32 = 0;
        while (elem < global.NUM_MAGIC_ELEMENTAL) : (elem += 1) {
            const cell_x: i32 = 209 + @as(i32, @intCast(elem)) * 16 - 6;
            const me: i32 = @as(i32, battlefield.magic_effect[elem]);
            const er: i32 = @as(i32, e.e.elem_resistance[elem]);
            const def_v: i32 = @max(10 + me - er, 0);
            if (palcommon.spriteGetFrame(ui.sprite_ui, SPRITENUM_SLASH)) |slash| {
                _ = palcommon.rleBlitToSurface(slash, &video.screen, global.palXY(@truncate(cell_x + 14 + @as(i32, @intCast(elem))), @truncate(elem_y)));
            }
            ui.drawNumberEx(@intCast(@max(def_v, 0)), 2, global.palXY(@truncate(cell_x + 3 + @as(i32, @intCast(elem))), @truncate(elem_y)), colorByVal(def_v), .mid);
        }
        // Physical resistance.
        const phy_x: i32 = 209 + @as(i32, global.NUM_MAGIC_ELEMENTAL) * 16 - 6;
        const phy_def: i32 = 10 - @as(i32, e.e.physical_resistance);
        ui.drawNumberEx(@intCast(@max(phy_def, 0)), 2, global.palXY(@truncate(phy_x + 3 + @as(i32, global.NUM_MAGIC_ELEMENTAL)), @truncate(elem_y)), colorByVal(phy_def), .mid);
        if (palcommon.spriteGetFrame(ui.sprite_ui, SPRITENUM_SLASH)) |slash| {
            _ = palcommon.rleBlitToSurface(slash, &video.screen, global.palXY(@truncate(phy_x + 14 + @as(i32, global.NUM_MAGIC_ELEMENTAL)), @truncate(elem_y)));
        }
        // Poison resistance.
        const poi_x: i32 = 209 + (1 + @as(i32, global.NUM_MAGIC_ELEMENTAL)) * 16 - 6;
        const poi_def: i32 = 10 - @as(i32, e.e.poison_resistance);
        ui.drawNumberEx(@intCast(@max(poi_def, 0)), 2, global.palXY(@truncate(poi_x + 3 + @as(i32, global.NUM_MAGIC_ELEMENTAL) + 1), @truncate(elem_y)), colorByVal(poi_def), .mid);

        // Background-chunk id (purple, top-right) and enemy index (yellow,
        // top-left). The fbp index is debug info — handy when you're
        // page-up/down'ing through battlefields to compare resistances.
        ui.drawNumberEx(bg_fbp_num, 2, global.palXY(304, @truncate(1 + (vi + 3) * h)), .purple, .right);
        ui.drawNumberEx(@intCast(battle.g_battle.exp_gained), 5, global.palXY(260, @truncate(1 + (vi + 3) * h)), .pale, .left);

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
