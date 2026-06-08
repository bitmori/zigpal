//! 魔改 — extended word labels.
//!
//! WORD.DAT only ships ~360 vanilla labels and we don't want to mutate the
//! borrowed buffer. These are UTF-8 strings drawn through the zpix BDF
//! font (objectdesc.drawAt) instead, so they coexist with the BIG5
//! getWord() path without touching it.
//!
//! Indices are referenced by name from the screens that use them
//! (playerstatus.zig for buff labels, enemyinfo.zig for the enemy panel).

const objectdesc = @import("objectdesc.zig");

pub const Label = enum(u8) {
    info = 0, // 情報
    poison_def, // 巫抗 (resistance to sorcery)
    monster_power, // 妖力 (collect value)
    steal_item, // 偷竊
    atk_effect, // 攻擊效果
    five_elem, // 風雷水火土劍毒
    puppet, // 傀儡
    bravery, // 天罡 (勇)
    protect, // 金剛 (護)
    haste, // 仙風 (捷)
    dual_attack, // 醉仙 (雙擊)
    battlefield_bg, // 戰場背景
    accumulated_exp, // 累積經驗
    exp_label, // 經驗值
    level_label, // 修行
    hp_label, // 體力
};

const TABLE = [_][]const u8{
    "情報",
    "巫抗",
    "妖力",
    "偷竊",
    "攻擊效果",
    "風/雷/水/火/土/劍/毒",
    "傀儡",
    "天罡",
    "金剛",
    "仙風",
    "醉仙",
    "戰場背景",
    "累積經驗",
    "經驗值",
    "修行",
    "體力",
};

pub fn get(label: Label) []const u8 {
    return TABLE[@intFromEnum(label)];
}

/// Draw a custom UTF-8 label at (x, y) using zpix.
pub fn draw(label: Label, x: i32, y: i32, color: u8) void {
    _ = objectdesc.drawAt(get(label), x, y, color);
}

/// Draw a row of CJK characters spaced at a fixed cell width (for column
/// headers that must align with numeric columns below). Separators like '/'
/// are skipped — only CJK glyphs are rendered, one per cell.
pub fn drawSpaced(label: Label, x: i32, y: i32, cell_w: i32, color: u8) void {
    const s = get(label);
    var cx = x;
    var i: usize = 0;
    while (i < s.len) {
        const r = objectdesc.decodeUtf8(s, i);
        if (r.cp == '/') {
            i += r.n;
            continue;
        }
        objectdesc.drawSingleCodepoint(r.cp, cx, y, color);
        cx += cell_w;
        i += r.n;
    }
}
