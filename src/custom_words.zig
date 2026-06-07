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
};

const TABLE = [_][]const u8{
    "情報",
    "巫抗",
    "妖力",
    "偷竊",
    "攻擊效果",
    "風雷水火土劍毒",
    "傀儡",
    "天罡",
    "金剛",
    "仙風",
    "醉仙",
};

pub fn get(label: Label) []const u8 {
    return TABLE[@intFromEnum(label)];
}

/// Draw a custom UTF-8 label at (x, y) using zpix.
pub fn draw(label: Label, x: i32, y: i32, color: u8) void {
    _ = objectdesc.drawAt(get(label), x, y, color);
}
