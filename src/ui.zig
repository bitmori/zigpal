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
const util = @import("util.zig");
const input = @import("input.zig");

pub const CHUNKNUM_SPRITEUI: u32 = 9;

// Menu item colors (from ui.h)
pub const MENUITEM_COLOR: u8 = 0x4F;
pub const MENUITEM_COLOR_INACTIVE: u8 = 0x18;
pub const MENUITEM_COLOR_CONFIRMED: u8 = 0x2C;
pub const MENUITEM_COLOR_SELECTED_INACTIVE: u8 = 0x1C;
pub const MENUITEM_COLOR_SELECTED_FIRST: u8 = 0xF9;
pub const MENUITEM_COLOR_SELECTED_TOTALNUM: u32 = 6;
pub const MENUITEM_COLOR_EQUIPPEDITEM: u8 = 0xC8;

pub const MENUITEM_VALUE_CANCELLED: u16 = 0xFFFF;

// PAL_GetMenuItemColorSelected — palette index that cycles for highlighted menu items.
pub fn menuItemColorSelected() u8 {
    const t = util.getTicks() / (600 / MENUITEM_COLOR_SELECTED_TOTALNUM);
    return MENUITEM_COLOR_SELECTED_FIRST + @as(u8, @intCast(t % MENUITEM_COLOR_SELECTED_TOTALNUM));
}

pub const NumColor = enum(u8) {
    yellow = 0,
    blue = 1,
    cyan = 2,
};

pub const NumAlign = enum(u8) {
    left = 0,
    mid = 1,
    right = 2,
};

pub const MenuItem = struct {
    value: u16,
    num_word: u16,
    enabled: bool,
    pos: palcommon.Pos,
};

pub const ItemChangedCallback = ?*const fn (current: u16) void;

pub var sprite_ui: []const u8 = &.{};
var sprite_ui_buf: ?[]u8 = null;

pub const Box = struct {
    pos: palcommon.Pos,
    width: u16,
    height: u16,
    saved_area: ?[]u8,
};

// PAL_InitUI — load the UI sprite from DATA.MKF chunk 9.
pub fn initUI() !void {
    const data = global.gpg.f.data orelse return error.NoData;
    const chunk = try data.getChunkData(CHUNKNUM_SPRITEUI);
    sprite_ui_buf = try global.allocator.dupe(u8, chunk);
    sprite_ui = sprite_ui_buf.?;
}

// PAL_FreeUI
pub fn freeUI() void {
    if (sprite_ui_buf) |buf| {
        global.allocator.free(buf);
        sprite_ui_buf = null;
        sprite_ui = &.{};
    }
}

fn saveScreenArea(rect: SDLRect) ?[]u8 {
    const buf = global.allocator.alloc(u8, @as(usize, @intCast(rect.w)) * @as(usize, @intCast(rect.h))) catch return null;
    var dst_idx: usize = 0;
    var y: i32 = rect.y;
    while (y < rect.y + rect.h) : (y += 1) {
        if (y < 0 or y >= video.screen.h) {
            for (0..@intCast(rect.w)) |_| {
                buf[dst_idx] = 0;
                dst_idx += 1;
            }
            continue;
        }
        var x: i32 = rect.x;
        while (x < rect.x + rect.w) : (x += 1) {
            if (x < 0 or x >= video.screen.w) {
                buf[dst_idx] = 0;
            } else {
                buf[dst_idx] = video.screen.pixels[@intCast(y * video.screen.pitch + x)];
            }
            dst_idx += 1;
        }
    }
    return buf;
}

fn restoreScreenArea(box: *const Box) void {
    const sa = box.saved_area orelse return;
    const x0 = palcommon.palX(box.pos);
    const y0 = palcommon.palY(box.pos);
    var src_idx: usize = 0;
    var y: i32 = y0;
    while (y < y0 + @as(i32, box.height)) : (y += 1) {
        if (y < 0 or y >= video.screen.h) {
            src_idx += @intCast(box.width);
            continue;
        }
        var x: i32 = x0;
        while (x < x0 + @as(i32, box.width)) : (x += 1) {
            if (x >= 0 and x < video.screen.w) {
                video.screen.pixels[@intCast(y * video.screen.pitch + x)] = sa[src_idx];
            }
            src_idx += 1;
        }
    }
}

const SDLRect = struct { x: i32, y: i32, w: i32, h: i32 };

fn createBoxInternal(rect: SDLRect) ?Box {
    return .{
        .pos = palcommon.palXY(@truncate(rect.x), @truncate(rect.y)),
        .width = @intCast(rect.w),
        .height = @intCast(rect.h),
        .saved_area = saveScreenArea(rect),
    };
}

// PAL_CreateBox / PAL_CreateBoxWithShadow
pub fn createBox(pos: palcommon.Pos, n_rows: i32, n_cols: i32, style: i32, save_screen: bool) ?Box {
    return createBoxWithShadow(pos, n_rows, n_cols, style, save_screen, 6);
}

pub fn createBoxWithShadow(
    pos: palcommon.Pos,
    n_rows_in: i32,
    n_cols_in: i32,
    style: i32,
    save_screen: bool,
    shadow_offset: i32,
) ?Box {
    var border: [3][3]?[]const u8 = undefined;
    for (0..3) |i| {
        for (0..3) |j| {
            border[i][j] = palcommon.spriteGetFrame(sprite_ui, @intCast(@as(i32, @intCast(i * 3 + j)) + style * 9));
        }
    }

    var rect: SDLRect = .{
        .x = palcommon.palX(pos),
        .y = palcommon.palY(pos),
        .w = 0,
        .h = 0,
    };

    for (0..3) |i| {
        if (i == 1) {
            rect.w += @as(i32, palcommon.rleGetWidth(border[0][i].?)) * n_cols_in;
            rect.h += @as(i32, palcommon.rleGetHeight(border[i][0].?)) * n_rows_in;
        } else {
            rect.w += palcommon.rleGetWidth(border[0][i].?);
            rect.h += palcommon.rleGetHeight(border[i][0].?);
        }
    }
    rect.w += shadow_offset;
    rect.h += shadow_offset;

    var box: ?Box = null;
    if (save_screen) box = createBoxInternal(rect);

    const n_rows: i32 = n_rows_in + 2;
    const n_cols: i32 = n_cols_in + 2;

    var ry: i32 = rect.y;
    var i: i32 = 0;
    while (i < n_rows) : (i += 1) {
        var x: i32 = rect.x;
        const m: usize = if (i == 0) 0 else if (i == n_rows - 1) 2 else 1;
        var j: i32 = 0;
        while (j < n_cols) : (j += 1) {
            const n: usize = if (j == 0) 0 else if (j == n_cols - 1) 2 else 1;
            const bmp = border[m][n] orelse continue;
            _ = palcommon.rleBlitToSurfaceWithShadow(bmp, &video.screen, palcommon.palXY(@truncate(x + shadow_offset), @truncate(ry + shadow_offset)), true);
            _ = palcommon.rleBlitToSurface(bmp, &video.screen, palcommon.palXY(@truncate(x), @truncate(ry)));
            x += @as(i32, palcommon.rleGetWidth(bmp));
        }
        ry += @as(i32, palcommon.rleGetHeight(border[m][0].?));
    }

    return box;
}

// PAL_CreateSingleLineBox / PAL_CreateSingleLineBoxWithShadow
pub fn createSingleLineBox(pos: palcommon.Pos, n_len: i32, save_screen: bool) ?Box {
    return createSingleLineBoxWithShadow(pos, n_len, save_screen, 6);
}

pub fn createSingleLineBoxWithShadow(pos: palcommon.Pos, n_len: i32, save_screen: bool, shadow_offset: i32) ?Box {
    const SPR_LEFT: i32 = 44;
    const SPR_MID: i32 = 45;
    const SPR_RIGHT: i32 = 46;

    const left = palcommon.spriteGetFrame(sprite_ui, SPR_LEFT) orelse return null;
    const mid = palcommon.spriteGetFrame(sprite_ui, SPR_MID) orelse return null;
    const right = palcommon.spriteGetFrame(sprite_ui, SPR_RIGHT) orelse return null;

    var rect: SDLRect = .{
        .x = palcommon.palX(pos),
        .y = palcommon.palY(pos),
        .w = @as(i32, palcommon.rleGetWidth(left)) + @as(i32, palcommon.rleGetWidth(right)) + @as(i32, palcommon.rleGetWidth(mid)) * n_len,
        .h = palcommon.rleGetHeight(left),
    };
    rect.w += shadow_offset;
    rect.h += shadow_offset;

    var box: ?Box = null;
    if (save_screen) box = createBoxInternal(rect);

    const x_saved = rect.x;

    // Shadow pass
    _ = palcommon.rleBlitToSurfaceWithShadow(left, &video.screen, palcommon.palXY(@truncate(rect.x + shadow_offset), @truncate(rect.y + shadow_offset)), true);
    rect.x += @as(i32, palcommon.rleGetWidth(left));
    var k: i32 = 0;
    while (k < n_len) : (k += 1) {
        _ = palcommon.rleBlitToSurfaceWithShadow(mid, &video.screen, palcommon.palXY(@truncate(rect.x + shadow_offset), @truncate(rect.y + shadow_offset)), true);
        rect.x += @as(i32, palcommon.rleGetWidth(mid));
    }
    _ = palcommon.rleBlitToSurfaceWithShadow(right, &video.screen, palcommon.palXY(@truncate(rect.x + shadow_offset), @truncate(rect.y + shadow_offset)), true);

    rect.x = x_saved;
    // Foreground pass
    _ = palcommon.rleBlitToSurface(left, &video.screen, pos);
    rect.x += @as(i32, palcommon.rleGetWidth(left));
    k = 0;
    while (k < n_len) : (k += 1) {
        _ = palcommon.rleBlitToSurface(mid, &video.screen, palcommon.palXY(@truncate(rect.x), @truncate(rect.y)));
        rect.x += @as(i32, palcommon.rleGetWidth(mid));
    }
    _ = palcommon.rleBlitToSurface(right, &video.screen, palcommon.palXY(@truncate(rect.x), @truncate(rect.y)));

    return box;
}

// PAL_DeleteBox — restore the saved screen area.
pub fn deleteBox(box: ?Box) void {
    var b = box orelse return;
    restoreScreenArea(&b);
    if (b.saved_area) |sa| global.allocator.free(sa);
}

// PAL_DrawNumber — draw an integer using the UI sprite digits.
pub fn drawNumber(num_in: u32, length_in: u32, pos: palcommon.Pos, color: NumColor, align_: NumAlign) void {
    const base: i32 = switch (color) {
        .blue => 29,
        .cyan => 56,
        .yellow => 19,
    };
    var bitmaps: [10]?[]const u8 = undefined;
    var i: i32 = 0;
    while (i < 10) : (i += 1) {
        bitmaps[@intCast(i)] = palcommon.spriteGetFrame(sprite_ui, base + i);
    }

    var n_actual: u32 = 0;
    var t: u32 = num_in;
    while (t > 0) {
        t /= 10;
        n_actual += 1;
    }
    if (n_actual > length_in) n_actual = length_in;
    if (n_actual == 0) n_actual = 1;

    var x: i32 = @as(i32, palcommon.palX(pos)) - 6;
    const y: i32 = palcommon.palY(pos);

    switch (align_) {
        .left => x += 6 * @as(i32, @intCast(n_actual)),
        .mid => x += 3 * @as(i32, @intCast(length_in + n_actual)),
        .right => x += 6 * @as(i32, @intCast(length_in)),
    }

    var num = num_in;
    var k = n_actual;
    while (k > 0) : (k -= 1) {
        if (bitmaps[num % 10]) |bmp| {
            _ = palcommon.rleBlitToSurface(bmp, &video.screen, palcommon.palXY(@truncate(x), @truncate(y)));
        }
        x -= 6;
        num /= 10;
    }
}

// PAL_TextWidth — pixel width of a raw BIG5/ASCII byte string.
pub fn textWidth(text: []const u8) i32 {
    var w: i32 = 0;
    var i: usize = 0;
    while (i < text.len) {
        const b = text[i];
        if (b >= 0x80 and i + 1 < text.len) {
            w += 16;
            i += 2;
        } else {
            w += 8;
            i += 1;
        }
    }
    return w;
}

// PAL_WordWidth — width of word `idx` in number of full-width characters.
pub fn wordWidth(idx: u32) i32 {
    const text = @import("text.zig").getWord(idx);
    return @divTrunc(textWidth(text) + 8, 16);
}

// PAL_WordMaxWidth — max full-width-char width across [first, first+n).
pub fn wordMaxWidth(first: u32, n: u32) i32 {
    var r: i32 = 0;
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const w = wordWidth(first + i);
        if (w > r) r = w;
    }
    return r;
}

// PAL_MenuTextMaxWidth — max full-width-char width among menu labels.
pub fn menuTextMaxWidth(items: []const MenuItem) i32 {
    var r: i32 = 0;
    for (items) |it| {
        const w = wordWidth(it.num_word);
        if (w > r) r = w;
    }
    return r;
}

fn drawMenuLabel(item: MenuItem, color: u8) void {
    const text_mod = @import("text.zig");
    const word = text_mod.getWord(item.num_word);
    text_mod.drawText(word, item.pos, color, true, true);
}

// PAL_ReadMenu — perform a menu and return the selected value or
// MENUITEM_VALUE_CANCELLED if the user pressed kKeyMenu.
pub fn readMenu(
    on_change: ItemChangedCallback,
    items: []const MenuItem,
    default_idx: u16,
    label_color: u8,
) u16 {
    var current: u16 = if (default_idx < items.len) default_idx else 0;

    // Draw all menu items.
    for (items, 0..) |it, i| {
        var color = label_color;
        if (!it.enabled) {
            color = if (i == current) MENUITEM_COLOR_SELECTED_INACTIVE else MENUITEM_COLOR_INACTIVE;
        }
        drawMenuLabel(it, color);
    }
    video.updateScreen(null);

    if (on_change) |cb| cb(items[default_idx].value);

    while (true) {
        if (util.shouldQuit()) return MENUITEM_VALUE_CANCELLED;
        input.clearKeyState();

        // Redraw the selected item if needed (cycles the highlight palette).
        if (items[current].enabled) {
            drawMenuLabel(items[current], menuItemColorSelected());
        }

        input.processEvent();
        const k = input.state.key_press;

        if ((k & (input.KEY_DOWN | input.KEY_RIGHT)) != 0) {
            // Dehighlight current.
            const dec_color: u8 = if (items[current].enabled) label_color else MENUITEM_COLOR_INACTIVE;
            drawMenuLabel(items[current], dec_color);

            current += 1;
            if (current >= items.len) current = 0;

            const new_color: u8 = if (items[current].enabled)
                menuItemColorSelected()
            else
                MENUITEM_COLOR_SELECTED_INACTIVE;
            drawMenuLabel(items[current], new_color);
            video.updateScreen(null);

            if (on_change) |cb| cb(items[current].value);
        } else if ((k & (input.KEY_UP | input.KEY_LEFT)) != 0) {
            const dec_color: u8 = if (items[current].enabled) label_color else MENUITEM_COLOR_INACTIVE;
            drawMenuLabel(items[current], dec_color);

            if (current > 0) {
                current -= 1;
            } else {
                current = @intCast(items.len - 1);
            }

            const new_color: u8 = if (items[current].enabled)
                menuItemColorSelected()
            else
                MENUITEM_COLOR_SELECTED_INACTIVE;
            drawMenuLabel(items[current], new_color);
            video.updateScreen(null);

            if (on_change) |cb| cb(items[current].value);
        } else if ((k & input.KEY_MENU) != 0) {
            const dec_color: u8 = if (items[current].enabled) label_color else MENUITEM_COLOR_INACTIVE;
            drawMenuLabel(items[current], dec_color);
            video.updateScreen(null);
            return MENUITEM_VALUE_CANCELLED;
        } else if ((k & input.KEY_SEARCH) != 0) {
            if (items[current].enabled) {
                drawMenuLabel(items[current], MENUITEM_COLOR_CONFIRMED);
                video.updateScreen(null);
                return items[current].value;
            }
        }

        util.delay(50);
    }
}
