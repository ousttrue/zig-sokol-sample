const std = @import("std");
const sokol_build = @import("sokol");
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

    const rowmath_dep = b.dependency("rowmath", .{
        .target = target,
        .optimize = optimize,
    });
    const rowmath = rowmath_dep.module("rowmath");
    b.modules.put("rowmath", rowmath) catch @panic("OOM");

    const stb_image_dep = b.dependency("stb_image", .{
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(stb_image_dep.artifact("stb_image"));
}

pub const Options = struct {
    name: []const u8,
    mod: *std.Build.Module,
    shaders: []const []const u8 = &.{},
};

fn generateShaders(
    b: *std.Build,
    examples_dep: *std.Build.Dependency,
    shaders: []const []const u8,
    compile: *std.Build.Step.Compile,
) !void {
    // extract shdc dependency from sokol dependency
    const sokol_dep = examples_dep.builder.dependency("sokol", .{});
    const shdc_dep = sokol_dep.builder.dependency("shdc", .{});
    for (shaders) |shader| {
        // call shdc.createSourceFile() helper function, this returns a `!*Build.Step`:
        const shdc_step = try sokol_build.shdc.createSourceFile(b, .{
            .shdc_dep = shdc_dep,
            .input = shader,
            .output = b.fmt("{s}.zig", .{shader}),
            .slang = .{
                // .glsl430 = true,
                .hlsl5 = true,
            },
        });
        // add the shader compilation step as dependency to the build step
        // which requires the generated Zig source file
        compile.step.dependOn(shdc_step);
    }
}

// this is the regular build for all native platforms, nothing surprising here
pub fn buildNative(b: *std.Build, examples_dep: *std.Build.Dependency, opts: Options) !void {
    const exe = b.addExecutable(.{
        .name = opts.name,
        .root_module = opts.mod,
    });
    b.installArtifact(exe);

    try generateShaders(b, examples_dep, opts.shaders, exe);

    const run = b.addRunArtifact(exe);
    b.step("run", "run").dependOn(&run.step);
}

// for web builds, the Zig code needs to be built into a library and linked with the Emscripten linker
pub fn buildWeb(b: *std.Build, examples_dep: *std.Build.Dependency, opts: Options) !void {
    const lib = b.addLibrary(.{
        .name = opts.name,
        .root_module = opts.mod,
    });
    try generateShaders(b, examples_dep, opts.shaders, lib);

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
