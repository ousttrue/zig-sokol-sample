const std = @import("std");
const builtin = @import("builtin");
const sokol = @import("sokol");

const NAME = "zig-sokol-sample";
const MAIN = "src/main.zig";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dep_sokol = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
        .with_sokol_imgui = true,
    });
    const dep_cimgui = b.dependency("cimgui", .{
        .target = target,
        .optimize = optimize,
    });
    // inject the cimgui header search path into the sokol C library compile step
    const cimgui_root = dep_cimgui.namedWriteFiles("cimgui").getDirectory();
    dep_sokol.artifact("sokol_clib").addIncludePath(cimgui_root);
    dep_sokol.artifact("sokol_clib").addCSourceFile(.{ .file = b.path("deps/cimgui//custom_button_behaviour.cpp") });

    // special case handling for native vs web build
    const compile = if (target.result.isWasm())
        buildWeb(b, target, optimize)
    else
        buildNative(b, target, optimize);

    compile.root_module.addImport("sokol", dep_sokol.module("sokol"));
    compile.root_module.addImport("cimgui", dep_cimgui.module("cimgui"));
    b.installArtifact(compile);

    if (target.result.isWasm()) {
        // create a build step which invokes the Emscripten linker
        const emsdk = dep_sokol.builder.dependency("emsdk", .{});
        const link_step = try sokol.emLinkStep(b, .{
            .lib_main = compile,
            .target = target,
            .optimize = optimize,
            .emsdk = emsdk,
            .use_webgl2 = true,
            .use_emmalloc = true,
            .use_filesystem = false,
            .shell_file_path = dep_sokol.path("src/sokol/web/shell.html").getPath(b),
            .extra_args = &.{"-sTOTAL_MEMORY=200MB"},
        });
        // ...and a special run step to start the web build output via 'emrun'
        const run = sokol.emRunStep(b, .{ .name = NAME, .emsdk = emsdk });
        run.step.dependOn(&link_step.step);
        b.step("run", "Run sample").dependOn(&run.step);

        const emsdk_incl_path = emsdk.path("upstream/emscripten/cache/sysroot/include");
        dep_cimgui.artifact("cimgui_clib").addSystemIncludePath(emsdk_incl_path);

        // all C libraries need to depend on the sokol library, when building for
        // WASM this makes sure that the Emscripten SDK has been setup before
        // C compilation is attempted (since the sokol C library depends on the
        // Emscripten SDK setup step)
        dep_cimgui.artifact("cimgui_clib").step.dependOn(&dep_sokol.artifact("sokol_clib").step);
    } else {
        compile.step.dependOn(buildShader(b, target, "src/teapot.glsl"));
    }
}

fn buildWeb(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const lib = b.addStaticLibrary(.{
        .name = NAME,
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path(MAIN),
    });
    return lib;
}

fn buildNative(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = NAME,
        .root_source_file = b.path(MAIN),
        .target = target,
        .optimize = optimize,
    });

    //
    // run
    //
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    b.step("run", "Run the app").dependOn(&run_cmd.step);

    //
    // test
    //
    const unit_tests = b.addTest(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/math.zig"),
    });
    b.step("test", "Run unit tests").dependOn(&b.addRunArtifact(unit_tests).step);

    return exe;
}

// a separate step to compile shaders, expects the shader compiler in ../sokol-tools-bin/
fn buildShader(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    comptime shader: []const u8,
) *std.Build.Step {
    const sokol_tools_bin_dir = "../../floooh/sokol-tools-bin/bin/";
    const optional_shdc: ?[:0]const u8 = comptime switch (builtin.os.tag) {
        .windows => "win32/sokol-shdc.exe",
        .linux => "linux/sokol-shdc",
        .macos => if (builtin.cpu.arch.isX86()) "osx/sokol-shdc" else "osx_arm64/sokol-shdc",
        else => null,
    };
    if (optional_shdc == null) {
        std.log.warn("unsupported host platform, skipping shader compiler step", .{});
        return;
    }
    const shdc_path = sokol_tools_bin_dir ++ optional_shdc.?;
    const shdc_step = b.step("shaders", "Compile shaders (needs ../../floooh/sokol-tools-bin)");
    const glsl = if (target.result.isDarwin()) "glsl410" else "glsl430";
    const slang = glsl ++ ":metal_macos:hlsl5:glsl300es:wgsl";
    const cmd = b.addSystemCommand(&.{
        shdc_path,
        "-i",
        shader,
        "-o",
        shader ++ ".zig",
        "-l",
        slang,
        "-f",
        "sokol_zig",
    });
    shdc_step.dependOn(&cmd.step);

    b.step("shader", "gen shader").dependOn(shdc_step);

    return shdc_step;
}
