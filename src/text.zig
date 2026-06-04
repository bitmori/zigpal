// Copyright (c) 2009-2011, Wei Mingzhi <whistler_wmz@users.sf.net>.
// Copyright (c) 2011-2026, SDLPAL development team.
// All rights reserved.
//
// This file is part of SDLPAL.
//
// SDLPAL is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License, version 3
// as published by the Free Software Foundation.
//
// Text and dialog system. SDLPAL converts everything to wide chars at load
// time and renders from there; we instead keep the raw BIG5/CP950 bytes and
// rely on font.zig to render two-byte BIG5 codes directly. Each "word"
// (in WORD.DAT) is a 10-byte trimmed BIG5 string. Each "message" (in M.MSG)
// is a variable-length BIG5 string located via the offset table in SSS chunk 3.

const std = @import("std");
const global = @import("global.zig");
const palcommon = @import("palcommon.zig");
const palette_mod = @import("palette.zig");
const video = @import("video.zig");
const util = @import("util.zig");
const input = @import("input.zig");
const font = @import("font.zig");

pub const FONT_COLOR_DEFAULT: u8 = 0x4F;
pub const FONT_COLOR_YELLOW: u8 = 0x2D;
pub const FONT_COLOR_RED: u8 = 0x1A;
pub const FONT_COLOR_CYAN: u8 = 0x8D;
pub const FONT_COLOR_CYAN_ALT: u8 = 0x8C;
pub const FONT_COLOR_RED_ALT: u8 = 0x17;

pub const DialogPosition = enum(u8) {
    upper = 0,
    center = 1,
    lower = 2,
    center_window = 3,
};

const WORD_SIZE: usize = 10;

pub const TextLib = struct {
    word_data: ?[]const u8 = null,
    n_words: u32 = 0,

    msg_data: ?[]const u8 = null,
    msg_offsets: []u32 = &.{},
    n_msgs: u32 = 0,

    dialog_icons: [282]u8 = undefined,

    current_font_color: u8 = FONT_COLOR_DEFAULT,
    icon: u8 = 0,
    pos_icon: u32 = 0,
    current_dialog_line: i32 = 0,
    delay_time: i32 = 3,
    pos_dialog_title: u32 = 0,
    pos_dialog_text: u32 = 0,
    dialog_position: DialogPosition = .upper,
    user_skip: bool = false,
    playing_rng: bool = false,
    dialog_shadow: i32 = 0,
};

pub var lib: TextLib = .{};

// PAL_InitText — load WORD.DAT/M.MSG buffers and decode the message offset table.
pub fn initText() !void {
    const word = global.res_buffers.word orelse return error.NoWordDat;
    const msg = global.res_buffers.msg orelse return error.NoMsg;
    const sss = global.gpg.f.sss orelse return error.NoSss;

    lib.word_data = word;
    lib.n_words = @intCast((word.len + WORD_SIZE - 1) / WORD_SIZE);
    if (lib.n_words < palcommon.MINIMAL_WORD_COUNT) lib.n_words = palcommon.MINIMAL_WORD_COUNT;

    lib.msg_data = msg;

    // SSS chunk 3 is the message-offset table (DWORD per entry).
    const off_data = try sss.getChunkData(3);
    const n_off = off_data.len / 4;
    if (n_off == 0) return error.EmptyMsgIndex;

    lib.msg_offsets = try global.allocator.alloc(u32, n_off);
    for (0..n_off) |i| {
        lib.msg_offsets[i] = std.mem.readInt(u32, off_data[i * 4 ..][0..4], .little);
    }
    lib.n_msgs = @intCast(n_off - 1);

    // DATA chunk 12 — dialog icons sprite.
    if (global.gpg.f.data) |data| {
        const icons = data.getChunkData(12) catch null;
        if (icons) |buf| {
            const len = @min(buf.len, lib.dialog_icons.len);
            @memcpy(lib.dialog_icons[0..len], buf[0..len]);
        }
    }

    lib.current_font_color = FONT_COLOR_DEFAULT;
    lib.icon = 0;
    lib.pos_icon = 0;
    lib.current_dialog_line = 0;
    lib.delay_time = 3;
    lib.pos_dialog_title = global.palXY(12, 8);
    lib.pos_dialog_text = global.palXY(44, 26);
    lib.dialog_position = .upper;
    lib.user_skip = false;
}

// PAL_GetWord — returns the trimmed 10-byte slice (raw BIG5).
pub fn getWord(num: u32) []const u8 {
    const data = lib.word_data orelse return &.{};
    if (num >= lib.n_words) return &.{};
    const start = num * WORD_SIZE;
    if (start >= data.len) return &.{};
    var end = @min(start + WORD_SIZE, data.len);
    while (end > start and data[end - 1] == ' ') end -= 1;
    return data[start..end];
}

// PAL_GetMsg — returns the message at the given index as raw BIG5 bytes.
pub fn getMsg(num: u32) []const u8 {
    const data = lib.msg_data orelse return &.{};
    if (num >= lib.n_msgs) return &.{};
    if (num + 1 >= lib.msg_offsets.len) return &.{};
    const start = lib.msg_offsets[num];
    const end = lib.msg_offsets[num + 1];
    if (start >= data.len or end > data.len or end < start) return &.{};
    return data[start..end];
}

// charWidth — pixel width of one logical char starting at byte `text[i]`.
fn charWidth(text: []const u8, i: usize) i32 {
    const b = text[i];
    if (b >= 0x80) return 16;
    return 8;
}

// nextChar — advance the byte index by one logical char, returning the (code, new_i).
fn nextChar(text: []const u8, i: usize) struct { code: u16, new_i: usize } {
    const b = text[i];
    if (b >= 0x80 and i + 1 < text.len) {
        const code: u16 = (@as(u16, b) << 8) | @as(u16, text[i + 1]);
        return .{ .code = code, .new_i = i + 2 };
    }
    return .{ .code = b, .new_i = i + 1 };
}

fn drawCharOnSurface(code: u16, surface: *palcommon.Surface, pos: palcommon.Pos, color: u8) void {
    if (code >= 0x80) {
        font.drawBig5(code, surface, pos, color);
    } else {
        font.drawAscii(@truncate(code), surface, pos, color);
    }
}

// PAL_DrawText — draw a raw BIG5/ASCII byte string on screen.
pub fn drawText(text: []const u8, pos: palcommon.Pos, color: u8, shadow: bool, update: bool) void {
    if (palcommon.palX(pos) >= 320) return;

    var x: i32 = palcommon.palX(pos);
    const y: i32 = palcommon.palY(pos);

    var i: usize = 0;
    while (i < text.len) {
        const start_i = i;
        const r = nextChar(text, i);
        const code = r.code;
        i = r.new_i;
        if (code == 0) break;
        const w = charWidth(text, start_i);

        if (shadow) {
            drawCharOnSurface(code, &video.screen, palcommon.palXY(@truncate(x + 1), @truncate(y)), 0);
            drawCharOnSurface(code, &video.screen, palcommon.palXY(@truncate(x), @truncate(y + 1)), 0);
            drawCharOnSurface(code, &video.screen, palcommon.palXY(@truncate(x + 1), @truncate(y + 1)), 0);
        }
        drawCharOnSurface(code, &video.screen, palcommon.palXY(@truncate(x), @truncate(y)), color);
        x += w;
    }

    if (update) video.updateScreen(null);
}

// --- Dialog system ---

// PAL_DialogSetDelayTime
pub fn dialogSetDelayTime(d: i32) void {
    lib.delay_time = d;
}

// PAL_StartDialog / PAL_StartDialogWithOffset
pub fn startDialog(dialog_location: DialogPosition, font_color: u8, num_char_face: u16, playing_rng: bool) void {
    startDialogWithOffset(dialog_location, font_color, num_char_face, playing_rng, 0, 0);
}

pub fn startDialogWithOffset(
    dialog_location: DialogPosition,
    font_color: u8,
    num_char_face: u16,
    playing_rng: bool,
    x_off: i32,
    y_off: i32,
) void {
    lib.icon = 0;
    lib.pos_icon = 0;
    lib.current_dialog_line = 0;
    lib.pos_dialog_title = global.palXY(12, 8);
    lib.user_skip = false;

    if (font_color != 0) lib.current_font_color = font_color;

    if (playing_rng and num_char_face != 0) {
        video.backupScreen();
        lib.playing_rng = true;
    }

    switch (dialog_location) {
        .upper => {
            if (num_char_face > 0) drawCharFace(num_char_face, .upper, x_off, y_off);
            lib.pos_dialog_title = global.palXY(if (num_char_face > 0) 80 else 12, 8);
            lib.pos_dialog_text = global.palXY(if (num_char_face > 0) 96 else 44, 26);
        },
        .center => {
            lib.pos_dialog_text = global.palXY(80, 40);
        },
        .lower => {
            if (num_char_face > 0) drawCharFace(num_char_face, .lower, x_off, y_off);
            lib.pos_dialog_title = global.palXY(if (num_char_face > 0) 4 else 12, 108);
            lib.pos_dialog_text = global.palXY(if (num_char_face > 0) 20 else 44, 126);
        },
        .center_window => {
            lib.pos_dialog_text = global.palXY(160, 40);
        },
    }

    lib.pos_dialog_title = global.palXyOffset(lib.pos_dialog_title, x_off, y_off);
    lib.pos_dialog_text = global.palXyOffset(lib.pos_dialog_text, x_off, y_off);
    lib.dialog_position = dialog_location;
}

fn drawCharFace(num_char_face: u16, where: DialogPosition, x_off: i32, y_off: i32) void {
    const rgm = global.gpg.f.rgm orelse return;
    const buf = rgm.getChunkData(num_char_face) catch return;
    if (buf.len == 0) return;

    const w = palcommon.rleGetWidth(buf);
    const h = palcommon.rleGetHeight(buf);
    const x: i32 = switch (where) {
        .upper => 48 - @divTrunc(@as(i32, w), 2) + x_off,
        .lower => 270 - @divTrunc(@as(i32, w), 2) + x_off,
        else => 0,
    };
    const y: i32 = switch (where) {
        .upper => 55 - @divTrunc(@as(i32, h), 2) + y_off,
        .lower => 144 - @divTrunc(@as(i32, h), 2) + y_off,
        else => 0,
    };
    const x_clamped: i32 = if (x < 0) 0 else x;
    const y_clamped: i32 = if (y < 0) 0 else y;
    _ = palcommon.rleBlitToSurface(buf, &video.screen, palcommon.palXY(@truncate(x_clamped), @truncate(y_clamped)));
    video.updateScreen(null);
}

// PAL_DialogWaitForKey — wait for any key, with palette shift on the icon area.
fn dialogWaitForKeyWithMaximumSeconds(max_seconds: f32) void {
    var palette_buf: [256]video.Color = video.current_palette;

    if (lib.dialog_position != .center_window and lib.dialog_position != .center) {
        // Show the icon
        const sprite_frame = palcommon.spriteGetFrame(lib.dialog_icons[0..], lib.icon);
        if (sprite_frame) |p| {
            _ = palcommon.rleBlitToSurface(p, &video.screen, lib.pos_icon);
            video.updateScreen(null);
        }
    }

    input.clearKeyState();

    const begin = util.getTicks();

    while (true) {
        if (util.shouldQuit()) return;
        util.delay(100);
        input.processEvent();

        if (lib.dialog_position != .center_window and lib.dialog_position != .center) {
            // Palette cycle on indices 0xF9..0xFE.
            const t = palette_buf[0xF9];
            var k: usize = 0xF9;
            while (k < 0xFE) : (k += 1) palette_buf[k] = palette_buf[k + 1];
            palette_buf[0xFE] = t;
            video.setPalette(palette_buf);
            video.updateScreen(null);
        }

        if (max_seconds > 0.0001 and @as(f32, @floatFromInt(util.getTicks() - begin)) > 1000.0 * max_seconds) break;
        if (input.state.key_press != 0) break;
    }

    if (lib.dialog_position != .center_window and lib.dialog_position != .center) {
        palette_mod.setPalette(@intCast(global.gpg.num_palette), global.gpg.night_palette);
        video.updateScreen(null);
    }

    input.clearKeyState();
    lib.user_skip = false;
}

fn dialogWaitForKey() void {
    dialogWaitForKeyWithMaximumSeconds(0);
}

// TEXT_DisplayText — draw one logical line of dialog text, handling escape codes.
// SDLPAL operates on wide chars and matches escape codes against wide chars,
// which is unambiguous. We work in raw BIG5 bytes, so a BIG5 trail byte that
// happens to equal an ASCII escape character (e.g. 0x2D '-') would be
// mis-interpreted. Guard by handling high-bit bytes (BIG5 lead) as opaque chars
// before the switch.
fn displayText(text: []const u8, x_in: i32, y: i32, is_dialog: bool) i32 {
    var x = x_in;
    var i: usize = 0;
    while (i < text.len) {
        const b = text[i];
        if (b >= 0x80) {
            const r = nextChar(text, i);
            drawOneChar(r.code, x, y, is_dialog);
            x += 16;
            i = r.new_i;
            perCharDelay(is_dialog);
            continue;
        }
        switch (b) {
            '-' => {
                if (lib.current_font_color == FONT_COLOR_CYAN)
                    lib.current_font_color = FONT_COLOR_DEFAULT
                else lib.current_font_color = FONT_COLOR_CYAN;
                i += 1;
            },
            '\'' => {
                if (lib.current_font_color == FONT_COLOR_RED)
                    lib.current_font_color = FONT_COLOR_DEFAULT
                else lib.current_font_color = FONT_COLOR_RED;
                i += 1;
            },
            '@' => {
                if (lib.current_font_color == FONT_COLOR_RED_ALT)
                    lib.current_font_color = FONT_COLOR_DEFAULT
                else lib.current_font_color = FONT_COLOR_RED_ALT;
                i += 1;
            },
            '"' => {
                if (!is_dialog) {
                    if (lib.current_font_color == FONT_COLOR_YELLOW)
                        lib.current_font_color = FONT_COLOR_DEFAULT
                    else lib.current_font_color = FONT_COLOR_YELLOW;
                }
                i += 1;
            },
            '$' => {
                // $NNN = set delay time. SDLPAL uses wcstol → parses 1-3
                // digits then halts at non-digit. We mirror that.
                var end = i + 1;
                while (end < text.len and text[end] >= '0' and text[end] <= '9') end += 1;
                if (end > i + 1) {
                    const v = std.fmt.parseInt(u32, text[i + 1 .. end], 10) catch 3;
                    lib.delay_time = @intCast(v * 10 / 7);
                }
                i = end;
            },
            '~' => {
                // ~NNN = pause for NNN ticks (then end the line).
                if (lib.user_skip) video.updateScreen(null);
                if (!is_dialog) {
                    var end = i + 1;
                    while (end < text.len and text[end] >= '0' and text[end] <= '9') end += 1;
                    if (end > i + 1) {
                        const v = std.fmt.parseInt(u32, text[i + 1 .. end], 10) catch 0;
                        util.delay(v * 80 / 7);
                    }
                }
                lib.current_dialog_line = -1;
                lib.user_skip = false;
                return x;
            },
            ')' => {
                lib.icon = 1;
                i += 1;
            },
            '(' => {
                lib.icon = 2;
                i += 1;
            },
            '\\' => {
                i += 1;
                if (i < text.len) {
                    const r = nextChar(text, i);
                    drawOneChar(r.code, x, y, is_dialog);
                    x += charWidth(text, i);
                    i = r.new_i;
                    perCharDelay(is_dialog);
                }
            },
            else => {
                const r = nextChar(text, i);
                drawOneChar(r.code, x, y, is_dialog);
                x += charWidth(text, i);
                i = r.new_i;
                perCharDelay(is_dialog);
            },
        }
    }
    return x;
}

fn drawOneChar(code: u16, x: i32, y: i32, is_dialog: bool) void {
    var color = lib.current_font_color;
    if (is_dialog and color == FONT_COLOR_DEFAULT) color = 0;
    const shadow = !is_dialog;
    if (shadow) {
        drawCharOnSurface(code, &video.screen, palcommon.palXY(@truncate(x + 1), @truncate(y)), 0);
        drawCharOnSurface(code, &video.screen, palcommon.palXY(@truncate(x), @truncate(y + 1)), 0);
        drawCharOnSurface(code, &video.screen, palcommon.palXY(@truncate(x + 1), @truncate(y + 1)), 0);
    }
    drawCharOnSurface(code, &video.screen, palcommon.palXY(@truncate(x), @truncate(y)), color);
    // Always update — retro_run on the other thread samples framebuffer every
    // frame, so we want each fully-drawn char visible right away. SDLPAL gates
    // the update on !fUserSkip to skip per-char surface flips when the user
    // accelerates with a key, but our split-thread model needs the live
    // framebuffer to stay coherent.
    if (!is_dialog) video.updateScreen(null);
}

fn perCharDelay(is_dialog: bool) void {
    if (!is_dialog and !lib.user_skip) {
        input.clearKeyState();
        util.delay(@intCast(lib.delay_time * 8));
        input.processEvent();
        if ((input.state.key_press & (input.KEY_SEARCH | input.KEY_MENU)) != 0) {
            lib.user_skip = true;
        }
    }
}

// PAL_ShowDialogText
pub fn showDialogText(text: []const u8) void {
    input.clearKeyState();
    lib.icon = 0;

    if (lib.current_dialog_line > 3) {
        dialogWaitForKey();
        lib.current_dialog_line = 0;
        video.restoreScreen();
        video.updateScreen(null);
    }

    const x = palcommon.palX(lib.pos_dialog_text);
    const y = palcommon.palY(lib.pos_dialog_text) + lib.current_dialog_line * 18;

    if (lib.dialog_position == .center_window) {
        // Center single-line window. nLen = how many half-chars wide.
        var len: i32 = 0;
        var i: usize = 0;
        while (i < text.len) {
            const b = text[i];
            if (b >= 0x80) {
                len += 16 / 8;
                i += 2;
            } else {
                len += 1;
                i += 1;
            }
        }
        const pos = palcommon.palXY(
            @truncate(palcommon.palX(lib.pos_dialog_text) - len * 4),
            palcommon.palY(lib.pos_dialog_text),
        );
        _ = @import("ui.zig").createSingleLineBoxWithShadow(pos, @intCast(@divTrunc(len + 1, 2)), false, lib.dialog_shadow);

        _ = displayText(text, palcommon.palX(pos) + 8 + ((len & 1) << 2), palcommon.palY(pos) + 10, true);
        video.updateScreen(null);

        dialogWaitForKeyWithMaximumSeconds(1.4);
        endDialog();
    } else {
        // Detect "name of speaker" line (ends with ':' or BIG5 colon 0xA1 0x47)
        const ends_with_colon = blk: {
            if (text.len == 0) break :blk false;
            if (text[text.len - 1] == ':') break :blk true;
            if (text.len >= 2 and text[text.len - 2] == 0xA1 and text[text.len - 1] == 0x47) break :blk true;
            break :blk false;
        };
        if (lib.current_dialog_line == 0 and lib.dialog_position != .center and ends_with_colon) {
            drawText(text, lib.pos_dialog_title, FONT_COLOR_CYAN_ALT, true, true);
        } else {
            if (!lib.playing_rng and lib.current_dialog_line == 0) {
                video.backupScreen();
            }
            const x_after = displayText(text, x, y, false);
            if (lib.user_skip) video.updateScreen(null);
            lib.pos_icon = palcommon.palXY(@truncate(x_after), @truncate(y));
            lib.current_dialog_line += 1;
        }
    }
}

// PAL_ClearDialog. SDLPAL doesn't restore here, but its main loop redraws
// between trigger scripts. To avoid stale speaker titles when one trigger
// switches dialog position (.upper → .lower), we restore + redraw the
// scene/battle background so any leftover title gets wiped.
pub fn clearDialog(wait_for_key: bool) void {
    if (lib.current_dialog_line > 0 and wait_for_key) {
        dialogWaitForKey();
        video.restoreScreen();
        if (global.gpg.in_battle) {
            const battle_mod = @import("battle.zig");
            battle_mod.battleMakeScene();
            @memcpy(&video.screen_pixels, &battle_mod.g_battle.scene_buf_pixels);
        } else {
            @import("scene.zig").makeScene();
        }
        video.updateScreen(null);
    }
    lib.current_dialog_line = 0;
    if (lib.dialog_position == .center) {
        lib.pos_dialog_title = global.palXY(12, 8);
        lib.pos_dialog_text = global.palXY(44, 26);
        lib.current_font_color = FONT_COLOR_DEFAULT;
        lib.dialog_position = .upper;
    }
}

// PAL_EndDialog
pub fn endDialog() void {
    clearDialog(true);
    lib.pos_dialog_title = global.palXY(12, 8);
    lib.pos_dialog_text = global.palXY(44, 26);
    lib.current_font_color = FONT_COLOR_DEFAULT;
    lib.dialog_position = .upper;
    lib.user_skip = false;
    lib.playing_rng = false;
}

// PAL_IsInDialog
pub fn isInDialog() bool {
    return lib.current_dialog_line != 0;
}
