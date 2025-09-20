const std = @import("std");
const cimgui_build = @import("cimgui");
const emsdk_build = @import("emsdk-zig");
const opt_docking = true;
const cimgui_conf = cimgui_build.getConfig(opt_docking);

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("dbgui", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("libs/dbgui/dbgui.zig"),
    });

    const cimgui_dep = b.dependency("cimgui", .{
        .target = target,
        .optimize = optimize,
    });

    const sokol_dep = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
        .with_sokol_imgui = true,
    });
    const sokol_clib = sokol_dep.artifact("sokol_clib");
    sokol_clib.addIncludePath(cimgui_dep.path(cimgui_conf.include_dir));
    b.installArtifact(sokol_clib);

    const sokol = sokol_dep.module("sokol");
    b.modules.put("sokol", sokol) catch @panic("OOM");

    const cimgui = cimgui_dep.module(cimgui_conf.module_name);
    b.modules.put("cimgui", cimgui) catch @panic("OOM");
    b.installArtifact(cimgui_dep.artifact(cimgui_conf.clib_name));
}

pub const Options = struct {
    name: []const u8,
    mod: *std.Build.Module,
};

// this is the regular build for all native platforms, nothing surprising here
pub fn buildNative(b: *std.Build, opts: Options) !void {
    const exe = b.addExecutable(.{
        .name = opts.name,
        .root_module = opts.mod,
    });
    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    b.step("run", "run").dependOn(&run.step);
}

// for web builds, the Zig code needs to be built into a library and linked with the Emscripten linker
pub fn buildWeb(b: *std.Build, opts: Options, examples_dep: *std.Build.Dependency) !void {
    const lib = b.addLibrary(.{
        .name = opts.name,
        .root_module = opts.mod,
    });

    const emsdk_zig = examples_dep.builder.dependency("emsdk-zig", .{});
    const emsdk_dep = emsdk_zig.builder.dependency("emsdk", .{});
    const sysroot = emsdk_dep.path("upstream/emscripten/cache/sysroot/include");
    examples_dep.artifact("sokol_clib").addSystemIncludePath(sysroot);
    examples_dep.artifact(cimgui_conf.clib_name).addSystemIncludePath(sysroot);

    // create a build step which invokes the Emscripten linker
    const link_step = try emsdk_build.emLinkStep(b, emsdk_dep, .{
        .lib_main = lib,
        .target = opts.mod.resolved_target.?,
        .optimize = opts.mod.optimize.?,
        .use_webgl2 = true,
        .use_emmalloc = true,
        .use_filesystem = false,
        // .shell_file_path = opts.dep_sokol.path("src/sokol/web/shell.html"),
    });
    // attach Emscripten linker output to default install step
    b.getInstallStep().dependOn(&link_step.step);
    // ...and a special run step to start the web build output via 'emrun'
    // const run = sokol.emRunStep(b, .{ .name = opts.name, .emsdk = emsdk });
    // run.step.dependOn(&link_step.step);
    // b.step("run", "Run").dependOn(&run.step);
}
