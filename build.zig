const std = @import("std");
const build_example = @import("build_example.zig");
const buildShader = @import("build_shader.zig").buildShader;
const Deps = @import("Deps.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const deps = Deps.init(b, target, optimize);
    for (build_example.examples) |example| {
        buildExample(b, target, optimize, deps, example);
    }
}

fn buildExample(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    deps: Deps,
    example: build_example.Example,
) void {
    // special case handling for native vs web build
    const compile = if (target.result.isWasm()) blk: {
        const lib = b.addStaticLibrary(.{
            .name = example.name,
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path(example.root_source),
        });
        break :blk lib;
    } else blk: {
        const exe = b.addExecutable(.{
            .name = example.name,
            .root_source_file = b.path(example.root_source),
            .target = target,
            .optimize = optimize,
        });
        break :blk exe;
    };

    if (example.shader) |shader| {
        compile.step.dependOn(buildShader(b, target, shader));
    }
    for (example.assets) |asset| {
        const install_asset = b.addInstallFile(b.path(asset.from), b.fmt("web/{s}", .{asset.to}));
        compile.step.dependOn(&install_asset.step);
    }

    deps.inject(compile);

    if (target.result.isWasm()) {
        deps.linkWasm(b, target, optimize, compile);
    } else {
        const install = b.addInstallArtifact(compile, .{});
        b.getInstallStep().dependOn(&install.step);

        const run = b.addRunArtifact(compile);
        run.step.dependOn(&install.step);
        run.setCwd(b.path("zig-out/web"));
        b.step(
            b.fmt("run-{s}", .{example.name}),
            b.fmt("Run {s}", .{example.name}),
        ).dependOn(&run.step);
    }
}
