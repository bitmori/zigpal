const std = @import("std");
const palcommon = @import("palcommon.zig");
const MkfFile = palcommon.MkfFile;
const Io = std.Io;
const Dir = Io.Dir;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    _ = io;
    const allocator: std.mem.Allocator = init.arena.allocator();
    _ = allocator;
    const data = @embedFile("../resources/pal/DATA.MKF");
    const mkf = MkfFile.fromMemory(data);
    const sprite = mkf.getChunkData(9) catch return;

    for (0..9) |i| {
        if (palcommon.spriteGetFrame(sprite, @intCast(i))) |frame| {
            const w = palcommon.rleGetWidth(frame);
            const h = palcommon.rleGetHeight(frame);
            std.debug.print("Frame {d}: {d}x{d}\n", .{ i, w, h });
        }
    }
}
