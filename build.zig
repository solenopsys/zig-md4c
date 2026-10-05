const std = @import("std");
const build_utils = @import("build_utils.zig");

fn buildForTarget(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    artifacts_dir: []const u8,
    hashes: *std.StringHashMap([]const u8),
    json_step: *std.Build.Step.Run,
) void {
    const target_str = build_utils.getTargetString(target);
    const lib_name = build_utils.getLibName(std.heap.page_allocator, "md4c", target_str);

    const lib = b.addLibrary(.{
        .name = lib_name,
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    lib.root_module.link_libc = true;
    const c_headers = b.addTranslateC(.{
        .root_source_file = b.path("src/c_imports.h"),
        .target = target,
        .optimize = optimize,
    });
    c_headers.addIncludePath(b.path("vendor/md4c-vendor/src"));
    lib.root_module.addImport("c", c_headers.createModule());

    const flags = &[_][]const u8{
        "-O2",
        "-fPIC",
        "-fvisibility=hidden",
        "-DMD4C_USE_UTF8",
    };

    lib.root_module.addCSourceFile(.{
        .file = b.path("vendor/md4c-vendor/src/md4c.c"),
        .flags = flags,
    });
    lib.root_module.addCSourceFile(.{
        .file = b.path("vendor/md4c-vendor/src/md4c-html.c"),
        .flags = flags,
    });
    lib.root_module.addCSourceFile(.{
        .file = b.path("vendor/md4c-vendor/src/entity.c"),
        .flags = flags,
    });

    lib.root_module.addIncludePath(b.path("vendor/md4c-vendor/src"));

    const install = b.addInstallArtifact(lib, .{});

    const hash_step = build_utils.HashAndMoveStep.create(
        b,
        lib_name,
        target_str,
        artifacts_dir,
        hashes,
    );
    hash_step.step.dependOn(&install.step);

    json_step.step.dependOn(&hash_step.step);
}

pub fn build(b: *std.Build) void {
    const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Prioritize performance, safety, or binary size") orelse .fast;
    const artifacts_dir = "../../artifacts/libs";
    const json_path = "current.json";

    const build_all = b.option(bool, "all", "Build for all supported targets") orelse false;

    if (build_all) {
        const hashes = build_utils.createHashMap(b);
        const json_step = build_utils.WriteJsonStep.create(b, hashes, json_path);

        for (build_utils.supported_targets) |query| {
            const target = b.resolveTargetQuery(query);
            buildForTarget(b, target, optimize, artifacts_dir, hashes, json_step);
        }

        b.default_step.dependOn(&json_step.step);
    } else {
        const target = b.standardTargetOptions(.{});

        const lib = b.addLibrary(.{
            .name = "md4c",
            .linkage = .dynamic,
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });

        lib.root_module.link_libc = true;
        const c_headers = b.addTranslateC(.{
            .root_source_file = b.path("src/c_imports.h"),
            .target = target,
            .optimize = optimize,
        });
        c_headers.addIncludePath(b.path("vendor/md4c-vendor/src"));
        lib.root_module.addImport("c", c_headers.createModule());

        const flags = &[_][]const u8{ "-O2", "-fPIC", "-fvisibility=hidden", "-DMD4C_USE_UTF8" };

        lib.root_module.addCSourceFile(.{
            .file = b.path("vendor/md4c-vendor/src/md4c.c"),
            .flags = flags,
        });
        lib.root_module.addCSourceFile(.{
            .file = b.path("vendor/md4c-vendor/src/md4c-html.c"),
            .flags = flags,
        });
        lib.root_module.addCSourceFile(.{
            .file = b.path("vendor/md4c-vendor/src/entity.c"),
            .flags = flags,
        });

        lib.root_module.addIncludePath(b.path("vendor/md4c-vendor/src"));

        b.installArtifact(lib);
    }
}
