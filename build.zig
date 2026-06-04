const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // The libretro core is built as a single module — all .zig files import each
    // other directly via @import("filename.zig"), so no explicit module wiring is
    // needed. The shared library is the sole build artifact for now.
    const libretro_module = b.createModule(.{
        .root_source_file = b.path("src/libretro_core.zig"),
        .target = target,
        .optimize = optimize,
    });
    libretro_module.addIncludePath(b.path("include"));

    const libretro_core = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "zigpal_libretro",
        .root_module = libretro_module,
    });
    b.installArtifact(libretro_core);
}
