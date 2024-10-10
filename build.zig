const std = @import("std");
const builtin = @import("builtin");
const build_example = @import("build_example.zig");
const emsdk_zig = @import("emsdk-zig");

const WASM_ARGS = [_][]const u8{
    // default 64MB
    "-sSTACK_SIZE=256MB",
    // must STACK_SIZE < TOTAL_MEMORY
    "-sTOTAL_MEMORY=1024MB",
    "-sUSE_OFFSET_CONVERTER=1",
    "-sSTB_IMAGE=1",
    "-Wno-limited-postlink-optimizations",
};

const WASM_ARGS_DEBUG = [_][]const u8{
    "-g",
    "-sASSERTIONS",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const deps = Deps.init(b, target, optimize);

    for (build_example.examples) |example| {

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
}

const Deps = struct {
    rowmath_dep: *std.Build.Dependency,
    rowmath: *std.Build.Module,
    sokol_dep: *std.Build.Dependency,
    cimgui_dep: *std.Build.Dependency,
    dbgui: *std.Build.Module,
    emsdk_dep: *std.Build.Dependency,
    stbi_dep: *std.Build.Dependency,

    fn init(
        b: *std.Build,
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
    ) @This() {
        const rowmath_dep = b.dependency("rowmath", .{});
        const rowmath = rowmath_dep.module("rowmath");

        const sokol_dep = b.dependency("sokol", .{
            .target = target,
            .optimize = optimize,
            .with_sokol_imgui = true,
        });
        const cimgui_dep = b.dependency("cimgui", .{
            .target = target,
            .optimize = optimize,
        });
        // inject the cimgui header search path into the sokol C library compile step
        const cimgui_root = cimgui_dep.namedWriteFiles("cimgui").getDirectory();
        sokol_dep.artifact("sokol_clib").addIncludePath(cimgui_root);
        sokol_dep.artifact("sokol_clib").addCSourceFile(.{ .file = b.path("deps/cimgui//custom_button_behaviour.cpp") });

        const dbgui = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("sokol_examples/libs/dbgui/dbgui.zig"),
        });
        dbgui.addImport("sokol", sokol_dep.module("sokol"));

        const emsdk_dep = b.dependency("emsdk-zig", .{}).builder.dependency("emsdk", .{});

        const stbi_dep = b.dependency("stb_image", .{
            .target = target,
            .optimize = optimize,
        });

        return .{
            .emsdk_dep = emsdk_dep,
            .rowmath_dep = rowmath_dep,
            .rowmath = rowmath,
            .sokol_dep = sokol_dep,
            .cimgui_dep = cimgui_dep,
            .dbgui = dbgui,
            .stbi_dep = stbi_dep,
        };
    }

    fn inject(
        self: @This(),
        compile: *std.Build.Step.Compile,
    ) void {
        compile.root_module.addImport("sokol", self.sokol_dep.module("sokol"));
        compile.root_module.addImport("cimgui", self.cimgui_dep.module("cimgui"));
        compile.root_module.addImport("rowmath", self.rowmath);
        compile.root_module.addImport("dbgui", self.dbgui);
        compile.root_module.addImport("stb_image", &self.stbi_dep.artifact("stb_image").root_module);
    }

    fn linkWasm(
        self: @This(),
        b: *std.Build,
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
        compile: *std.Build.Step.Compile,
    ) void {
        const emsdk_incl_path = self.emsdk_dep.path("upstream/emscripten/cache/sysroot/include");
        self.cimgui_dep.artifact("cimgui_clib").addSystemIncludePath(emsdk_incl_path);

        // all C libraries need to depend on the sokol library, when building for
        // WASM this makes sure that the Emscripten SDK has been setup before
        // C compilation is attempted (since the sokol C library depends on the
        // Emscripten SDK setup step)
        self.cimgui_dep.artifact("cimgui_clib").step.dependOn(
            &self.sokol_dep.artifact("sokol_clib").step,
        );

        // create a build step which invokes the Emscripten linker
        const emcc = try emsdk_zig.emLinkCommand(b, self.emsdk_dep, .{
            .lib_main = compile,
            .target = target,
            .optimize = optimize,
            .use_webgl2 = true,
            .use_emmalloc = true,
            .use_filesystem = true,
            .shell_file_path = self.sokol_dep.path("src/sokol/web/shell.html").getPath(b),
            .release_use_closure = false,
            .extra_before = if (optimize == .Debug)
                &(WASM_ARGS ++ WASM_ARGS_DEBUG)
            else
                &WASM_ARGS,
        });

        emcc.addArg("-o");
        const out_file = emcc.addOutputFileArg(b.fmt("{s}.html", .{compile.name}));

        // the emcc linker creates 3 output files (.html, .wasm and .js)
        const install = b.addInstallDirectory(.{
            .source_dir = out_file.dirname(),
            .install_dir = .prefix,
            .install_subdir = "web",
        });
        install.step.dependOn(&emcc.step);
        b.getInstallStep().dependOn(&install.step);
    }
};

// a separate step to compile shaders, expects the shader compiler in ../sokol-tools-bin/
fn buildShader(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    shader: []const u8,
) *std.Build.Step {
    const optional_shdc = comptime switch (builtin.os.tag) {
        .windows => "win32/sokol-shdc.exe",
        .linux => "linux/sokol-shdc",
        .macos => if (builtin.cpu.arch.isX86()) "osx/sokol-shdc" else "osx_arm64/sokol-shdc",
        else => @panic("unsupported host platform, skipping shader compiler step"),
    };
    const tools = b.dependency("sokol-tools-bin", .{});
    const shdc_path = tools.path(b.pathJoin(&.{ "bin", optional_shdc })).getPath(b);
    const glsl = if (target.result.isDarwin()) "glsl410" else "glsl430";
    const slang = glsl ++ ":metal_macos:hlsl5:glsl300es:wgsl";
    return &b.addSystemCommand(&.{
        shdc_path,
        "-i",
        shader,
        "-o",
        b.fmt("{s}.zig", .{shader}),
        "-l",
        slang,
        "-f",
        "sokol_zig",
    }).step;
}
