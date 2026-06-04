// BDF bitmap font loader
// Supports variable-width glyphs indexed by Unicode codepoint.

const std = @import("std");
const palcommon = @import("palcommon.zig");

pub const Glyph = struct {
    data: [32]u8 = [_]u8{0} ** 32, // max 16 rows x 2 bytes
    width: u8 = 0,
    height: u8 = 0,
    bbx_w: u8 = 0,
    bbx_h: u8 = 0,
    bbx_x: i8 = 0,
    bbx_y: i8 = 0,
    dwidth: u8 = 0,
};

pub const BdfFont = struct {
    glyphs: []Glyph,
    codepoints: []u32,
    count: usize,
    font_height: u8,

    pub fn lookup(self: *const BdfFont, codepoint: u32) ?*const Glyph {
        for (0..self.count) |i| {
            if (self.codepoints[i] == codepoint) return &self.glyphs[i];
        }
        return null;
    }

    pub fn charWidth(self: *const BdfFont, codepoint: u32) u8 {
        const g = self.lookup(codepoint) orelse return 0;
        return g.dwidth;
    }

    pub fn drawCodepoint(
        self: *const BdfFont,
        codepoint: u32,
        surface: *palcommon.Surface,
        x: i32,
        y: i32,
        color: u8,
    ) i32 {
        const glyph = self.lookup(codepoint) orelse return self.font_height / 2;
        // Glyph baseline is at y + (font_ascent). FONT_ASCENT for zpix is 10.
        // BDF bbx_y is the offset of the bottom of the bitmap above the baseline.
        const baseline: i32 = y + 10;
        const dst_y0: i32 = baseline - @as(i32, glyph.bbx_y) - @as(i32, glyph.bbx_h);
        const dst_x0: i32 = x + @as(i32, glyph.bbx_x);

        const bytes_per_row: usize = if (glyph.bbx_w <= 8) 1 else 2;
        var row: usize = 0;
        while (row < glyph.height) : (row += 1) {
            const dy = dst_y0 + @as(i32, @intCast(row));
            if (dy < 0 or dy >= surface.h) continue;
            const row_bytes = glyph.data[row * 2 .. row * 2 + bytes_per_row];
            var col: usize = 0;
            while (col < glyph.bbx_w) : (col += 1) {
                const byte_idx = col / 8;
                const bit = @as(u3, @intCast(7 - (col % 8)));
                const set = (row_bytes[byte_idx] >> bit) & 1 == 1;
                if (!set) continue;
                const dx = dst_x0 + @as(i32, @intCast(col));
                if (dx < 0 or dx >= surface.w) continue;
                surface.pixels[@intCast(dy * surface.pitch + dx)] = color;
            }
        }
        return @as(i32, glyph.dwidth);
    }

    // drawAscii — draws a NUL-free ASCII string, returns x advance.
    pub fn drawAscii(
        self: *const BdfFont,
        text: []const u8,
        surface: *palcommon.Surface,
        x: i32,
        y: i32,
        color: u8,
    ) i32 {
        var cx = x;
        for (text) |ch| {
            cx += self.drawCodepoint(ch, surface, cx, y, color);
        }
        return cx;
    }
};

fn parseIntFromLine(line: []const u8, prefix_len: usize) ?i32 {
    var s = line[prefix_len..];
    while (s.len > 0 and s[0] == ' ') s = s[1..];
    var end: usize = 0;
    while (end < s.len and s[end] != ' ' and s[end] != '\n' and s[end] != '\r') end += 1;
    return std.fmt.parseInt(i32, s[0..end], 10) catch null;
}

pub fn load(data: []const u8, allocator: std.mem.Allocator) !BdfFont {
    // First pass: count chars
    var char_count: usize = 0;
    {
        var i: usize = 0;
        while (i < data.len) {
            const line_start = i;
            while (i < data.len and data[i] != '\n') i += 1;
            if (i < data.len) i += 1;
            const line = data[line_start .. i - 1];
            if (line.len >= 9 and std.mem.eql(u8, line[0..9], "STARTCHAR")) {
                char_count += 1;
            }
        }
    }

    const glyphs = try allocator.alloc(Glyph, char_count);
    const codepoints = try allocator.alloc(u32, char_count);

    var idx: usize = 0;
    var state: enum { header, char_meta, bitmap } = .header;
    var current_glyph: Glyph = .{};
    var current_cp: u32 = 0;
    var bitmap_row: usize = 0;
    var font_height: u8 = 12;

    var i: usize = 0;
    while (i < data.len) {
        const line_start = i;
        while (i < data.len and data[i] != '\n') i += 1;
        const line_end = if (i > line_start and data[i - 1] == '\r') i - 1 else i;
        if (i < data.len) i += 1;
        const line = data[line_start..line_end];

        switch (state) {
            .header => {
                if (line.len >= 4 and std.mem.eql(u8, line[0..4], "SIZE")) {
                    if (parseIntFromLine(line, 4)) |sz| {
                        font_height = @intCast(sz);
                    }
                } else if (line.len >= 9 and std.mem.eql(u8, line[0..9], "STARTCHAR")) {
                    state = .char_meta;
                    current_glyph = .{};
                    current_cp = 0;
                    bitmap_row = 0;
                }
            },
            .char_meta => {
                if (line.len >= 8 and std.mem.eql(u8, line[0..8], "ENCODING")) {
                    if (parseIntFromLine(line, 8)) |enc| {
                        current_cp = @intCast(enc);
                    }
                } else if (line.len >= 6 and std.mem.eql(u8, line[0..6], "DWIDTH")) {
                    if (parseIntFromLine(line, 6)) |dw| {
                        current_glyph.dwidth = @intCast(dw);
                    }
                } else if (line.len >= 3 and std.mem.eql(u8, line[0..3], "BBX")) {
                    var s = line[3..];
                    var vals: [4]i32 = .{ 0, 0, 0, 0 };
                    for (0..4) |vi| {
                        while (s.len > 0 and s[0] == ' ') s = s[1..];
                        var end: usize = 0;
                        while (end < s.len and s[end] != ' ' and s[end] != '\n' and s[end] != '\r') end += 1;
                        vals[vi] = std.fmt.parseInt(i32, s[0..end], 10) catch 0;
                        s = s[end..];
                    }
                    current_glyph.bbx_w = @intCast(vals[0]);
                    current_glyph.bbx_h = @intCast(vals[1]);
                    current_glyph.bbx_x = @intCast(vals[2]);
                    current_glyph.bbx_y = @intCast(vals[3]);
                } else if (line.len >= 6 and std.mem.eql(u8, line[0..6], "BITMAP")) {
                    state = .bitmap;
                    bitmap_row = 0;
                }
            },
            .bitmap => {
                if (line.len >= 7 and std.mem.eql(u8, line[0..7], "ENDCHAR")) {
                    current_glyph.height = @intCast(bitmap_row);
                    current_glyph.width = current_glyph.bbx_w;
                    if (idx < char_count) {
                        glyphs[idx] = current_glyph;
                        codepoints[idx] = current_cp;
                        idx += 1;
                    }
                    state = .header;
                } else {
                    if (bitmap_row < 16 and line.len >= 2) {
                        const hex_len = @min(line.len, 4);
                        const val = std.fmt.parseInt(u16, line[0..hex_len], 16) catch 0;
                        if (hex_len <= 2) {
                            current_glyph.data[bitmap_row * 2] = @intCast(val);
                        } else {
                            current_glyph.data[bitmap_row * 2] = @intCast(val >> 8);
                            current_glyph.data[bitmap_row * 2 + 1] = @intCast(val & 0xFF);
                        }
                        bitmap_row += 1;
                    }
                }
            },
        }
    }

    return .{
        .glyphs = glyphs,
        .codepoints = codepoints,
        .count = idx,
        .font_height = font_height,
    };
}
