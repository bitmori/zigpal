//! Creative VOC sound-file parser. The Pal series uses 8-bit unsigned mono
//! samples in a single block-type-1 chunk; we don't support the streaming /
//! looping / silence block types, matching SDLPAL's sound.c:160 implementation.

const std = @import("std");

pub const Voc = struct {
    /// Sample rate in Hz, rounded to the nearest 100 like SDLPAL does
    /// (sound.c:217). The VOC format stores rate as a divisor of 1MHz.
    rate: u32,
    /// 8-bit unsigned PCM samples. Sub-slice into the original VOC blob —
    /// caller owns lifetime.
    samples: []const u8,
};

/// Parse the leading VOC header + first type-0x01 sound block. Returns null
/// if the buffer isn't a recognisable VOC, the data offset is past EOF, or
/// the only block isn't 8-bit (we don't decode 16-bit / ADPCM variants).
pub fn parse(data: []const u8) ?Voc {
    if (data.len < 0x1A) return null;
    if (!std.mem.eql(u8, data[0..0x14], "Creative Voice File\x1A")) return null;

    const data_offset: usize = std.mem.readInt(u16, data[0x14..0x16], .little);
    if (data_offset >= data.len) return null;

    var p: usize = data_offset;
    var remaining: usize = data.len - data_offset;

    while (remaining > 0 and data[p] != 0) {
        if (remaining < 4) return null;
        const block_type = data[p];
        const block_len: usize = @as(usize, data[p + 1]) |
            (@as(usize, data[p + 2]) << 8) |
            (@as(usize, data[p + 3]) << 16);
        if (remaining < block_len + 4) return null;

        if (block_type == 0x01) {
            // Sound Data block:
            //   byte 4: time-constant (rate divisor)
            //   byte 5: codec; 0 = unsigned 8-bit PCM (the only one we support)
            if (data[p + 5] != 0) return null;
            const tc: u32 = data[p + 4];
            // SDLPAL rounds the rate up to the next 100 Hz so the resampler
            // factor lands on a clean fraction.
            const raw_hz: u32 = 1_000_000 / (256 - tc);
            const rate: u32 = ((raw_hz + 99) / 100) * 100;

            const sample_off = p + 6;
            const sample_len = block_len - 2;
            return .{
                .rate = rate,
                .samples = data[sample_off .. sample_off + sample_len],
            };
        }

        p += block_len + 4;
        remaining -= block_len + 4;
    }
    return null;
}
