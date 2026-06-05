const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // pal-adplug — OPL+RIX subset of adplug, fetched from GitHub via
    // build.zig.zon. We compile its C/C++ sources directly with zig's bundled
    // clang so we don't need cmake or make on the host (matters for libretro
    // CI matrices).
    const pal_adplug_dep_pkg = b.dependency("pal_adplug", .{});
    const pal_adplug_root = pal_adplug_dep_pkg.path("");
    const pal_adplug_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    pal_adplug_module.addIncludePath(pal_adplug_dep_pkg.path("include"));
    pal_adplug_module.addIncludePath(pal_adplug_dep_pkg.path("src/adplug"));
    const pal_adplug_dep = b.addLibrary(.{
        .linkage = .static,
        .name = "pal_adplug",
        .root_module = pal_adplug_module,
    });

    // DOSBox's dbopl.cpp.h computes member offsets via `Chip* chip = 0; &chip->chan[i]`
    // (a hand-rolled offsetof). That's UB by the C++ standard, and Zig's default
    // -fsanitize=undefined turns the null-deref into a runtime trap that fires
    // before the OPL chip is even instantiated. Disable UBSan for the whole
    // pal-adplug compile — SDLPAL's stock clang builds also don't enable it.
    const cxx_flags = &[_][]const u8{
        "-std=c++11",
        "-fPIC",
        "-fno-sanitize=undefined",
        "-Wno-sign-compare",
        "-Wno-unused-parameter",
        "-Wno-parentheses",
        "-Wno-unused-but-set-variable",
        "-Wno-unused-variable",
        "-Wno-nontrivial-memcall",
    };
    const c_flags = &[_][]const u8{
        "-fPIC",
        "-fno-sanitize=undefined",
        "-Wno-sign-compare",
        "-Wno-unused-parameter",
    };

    pal_adplug_module.addCSourceFiles(.{
        .root = pal_adplug_root,
        .files = &.{
            "src/pal_adplug.cpp",
            "src/adplug/binio.cpp",
            "src/adplug/binfile.cpp",
            "src/adplug/fprovide.cpp",
            "src/adplug/player.cpp",
            "src/adplug/rix.cpp",
            "src/adplug/emuopls.cpp",
            "src/adplug/dosbox_opls.cpp",
            "src/adplug/mame_opls.cpp",
            "src/adplug/surroundopl.cpp",
        },
        .flags = cxx_flags,
        .language = .cpp,
    });
    pal_adplug_module.addCSourceFiles(.{
        .root = pal_adplug_root,
        .files = &.{
            "src/adplug/nuked_opl.c",
            "src/resampler.c",
        },
        .flags = c_flags,
    });

    // The libretro core is built as a single module — all .zig files import each
    // other directly via @import("filename.zig"), so no explicit module wiring is
    // needed. The shared library is the sole build artifact for now.
    const libretro_module = b.createModule(.{
        .root_source_file = b.path("src/libretro_core.zig"),
        .target = target,
        .optimize = optimize,
    });
    libretro_module.addIncludePath(b.path("include"));
    libretro_module.addIncludePath(pal_adplug_dep_pkg.path("include"));
    // resampler.h is private to pal-adplug but the SFX mixer wants the same
    // sinc resampler SDLPAL uses, so reach in. The symbols are already
    // exported from libpal_adplug.a as part of the BGM build.
    libretro_module.addIncludePath(pal_adplug_dep_pkg.path("src"));

    const libretro_core = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "zigpal_libretro",
        .root_module = libretro_module,
    });
    libretro_module.linkLibrary(pal_adplug_dep);
    b.installArtifact(libretro_core);
}
