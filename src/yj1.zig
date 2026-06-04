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
// Portions based on PalLibrary by Lou Yihua <louyihua@21cn.com>.
// Copyright (c) 2006-2007, Lou Yihua.
//
// Ported to Zig from C.

const std = @import("std");

const TreeNode = struct {
    value: u8,
    leaf: bool,
    // level: u16,
    // weight: u32,
    // parent: ?*TreeNode,
    left: ?*TreeNode,
    right: ?*TreeNode,
};

const FileHeader = extern struct {
    signature: u32 align(1),
    uncompressed_length: u32 align(1),
    compressed_length: u32 align(1),
    block_count: u16 align(1),
    unknown: u8,
    huffman_tree_length: u8,
};

const BlockHeader = extern struct {
    uncompressed_length: u16 align(1),
    compressed_length: u16 align(1),
    lzss_repeat_table: [4]u16 align(1),
    lzss_offset_code_length_table: [4]u8,
    lzss_repeat_code_length_table: [3]u8,
    code_count_code_length_table: [3]u8,
    code_count_table: [2]u8,
};

fn getBits(src: [*]const u8, bitptr: *u32, count: u32) u32 {
    const byte_offset = (bitptr.* >> 4) << 1;
    const bptr = @as(u4, @intCast(bitptr.* & 0xf));
    bitptr.* += count;

    const temp = src[byte_offset..];
    const word0 = std.mem.readInt(u16, temp[0..2], .little);
    const word1 = std.mem.readInt(u16, temp[2..4], .little);

    if (count > 16 - @as(u32, bptr)) {
        const remaining: u5 = @intCast(count + @as(u32, bptr) - 16);
        const mask: u16 = @as(u16, 0xffff) >> bptr;
        return (@as(u32, word0 & mask) << remaining) | (@as(u32, word1) >> (@as(u5, 16) - remaining));
    } else {
        const shift_count: u5 = @intCast(16 - count);
        return @as(u32, (word0 << bptr)) >> shift_count;
    }
}

fn getLoop(src: [*]const u8, bitptr: *u32, header: *const BlockHeader) u16 {
    if (getBits(src, bitptr, 1) != 0) {
        return header.code_count_table[0];
    } else {
        const temp = getBits(src, bitptr, 2);
        if (temp != 0) {
            return @intCast(getBits(src, bitptr, header.code_count_code_length_table[temp - 1]));
        } else {
            return header.code_count_table[1];
        }
    }
}

fn getCount(src: [*]const u8, bitptr: *u32, header: *const BlockHeader) u16 {
    const temp: u16 = @intCast(getBits(src, bitptr, 2));
    if (temp != 0) {
        if (getBits(src, bitptr, 1) != 0) {
            return @intCast(getBits(src, bitptr, header.lzss_repeat_code_length_table[temp - 1]));
        } else {
            return std.mem.littleToNative(u16, header.lzss_repeat_table[temp]);
        }
    } else {
        return std.mem.littleToNative(u16, header.lzss_repeat_table[0]);
    }
}

pub fn decompress(source: []const u8, destination: []u8) !u32 {
    if (source.len < @sizeOf(FileHeader)) return error.InvalidData;

    const hdr: *const FileHeader = @ptrCast(@alignCast(source.ptr));
    const signature = std.mem.littleToNative(u32, hdr.signature);
    const uncompressed_length = std.mem.littleToNative(u32, hdr.uncompressed_length);
    const block_count = std.mem.littleToNative(u16, hdr.block_count);

    if (signature != 0x315f4a59) return error.InvalidSignature;
    if (uncompressed_length > destination.len) return error.DestinationTooSmall;

    var src = source.ptr;

    const tree_len: u16 = @as(u16, hdr.huffman_tree_length) * 2;
    var tree_bitptr: u32 = 0;
    const flag: [*]const u8 = src + 16 + tree_len;

    // FileHeader.huffman_tree_length is u8, tree_len = huffman_tree_length * 2, +1 for root
    var tree_buf: [std.math.maxInt(u8) * 2 + 1]TreeNode = undefined;
    const root = &tree_buf;
    root[0] = .{ .leaf = false, .value = 0, .left = &root[1], .right = &root[2] };

    for (1..@as(usize, tree_len) + 1) |i| {
        const is_leaf = getBits(flag, &tree_bitptr, 1) == 0;
        const value = src[15 + i];
        if (is_leaf) {
            root[i] = .{ .leaf = true, .value = value, .left = null, .right = null };
        } else {
            const child_idx = @as(usize, value) * 2 + 1;
            root[i] = .{ .leaf = false, .value = value, .left = &root[child_idx], .right = &root[child_idx + 1] };
        }
    }

    const flag_bytes: usize = if ((tree_len & 0xf) != 0) (@as(usize, tree_len >> 4) + 1) << 1 else @as(usize, tree_len >> 4) << 1;
    src += 16 + @as(usize, tree_len) + flag_bytes;

    var dest_offset: usize = 0;

    for (0..block_count) |_| {
        const header: *const BlockHeader = @ptrCast(@alignCast(src));
        src += 4;

        const compressed_length = std.mem.littleToNative(u16, header.compressed_length);
        if (compressed_length == 0) {
            const hul = std.mem.littleToNative(u16, header.uncompressed_length);
            for (0..hul) |_| {
                destination[dest_offset] = src[0];
                dest_offset += 1;
                src += 1;
            }
            continue;
        }

        src += 20;
        var bitptr: u32 = 0;

        outer: while (true) {
            var loop: u16 = getLoop(src, &bitptr, header);
            if (loop == 0) break;

            for (0..loop) |_| {
                var node: *const TreeNode = &root[0];
                while (!node.leaf) {
                    if (getBits(src, &bitptr, 1) != 0) {
                        node = node.right.?;
                    } else {
                        node = node.left.?;
                    }
                }
                destination[dest_offset] = node.value;
                dest_offset += 1;
            }

            loop = getLoop(src, &bitptr, header);
            if (loop == 0) break :outer;

            for (0..loop) |_| {
                const count = getCount(src, &bitptr, header);
                var pos = getBits(src, &bitptr, 2);
                pos = getBits(src, &bitptr, header.lzss_offset_code_length_table[pos]);

                for (0..count) |_| {
                    destination[dest_offset] = destination[dest_offset - pos];
                    dest_offset += 1;
                }
            }
        }

        src = @as([*]const u8, @ptrCast(header)) + compressed_length;
    }

    return uncompressed_length;
}

pub const DecompressError = error{
    InvalidData,
    InvalidSignature,
    DestinationTooSmall,
};
