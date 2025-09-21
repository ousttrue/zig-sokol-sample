const std = @import("std");

pub const Asset = struct {
    from: []const u8,
    to: []const u8,
};

pub const Example = struct {
    name: []const u8,
    root_source: []const u8,
    shader: ?[]const u8 = null,
    assets: []const Asset = &.{},
};

pub const examples = [_]Example{
    // - [ ] [cubemaprt](sokol_examples/cubemaprt-sapp.zig)
    // - [ ] [miprender](sokol_examples/miprender-sapp.zig)
    // - [ ] [layerrender](sokol_examples/layerrender-sapp.zig)
    // - [ ] [primtypes](sokol_examples/primtypes-sapp.zig)
    // - [ ] [uvwrap](sokol_examples/uvwrap-sapp.zig)
    .{
        .name = "mipmap",
        .root_source = "sokol_examples/mipmap-sapp.zig",
        .shader = "sokol_examples/mipmap-sapp.glsl",
    },
    // - [ ] [uniformtypes](sokol_examples/uniformtypes-sapp.zig)
    // - [ ] [blend](sokol_examples/blend-sapp.zig)
    // - [ ] [sdf](sokol_examples/sdf-sapp.zig)
    // - [ ] [shadows](sokol_examples/shadows-sapp.zig)
    // - [ ] [shadows-depthtex](sokol_examples/shadows-depthtex-sapp.zig)
    // - [ ] [imgui](sokol_examples/imgui-sapp.zig)
    // - [ ] [imgui-dock](sokol_examples/imgui-dock-sapp.zig)
    // - [ ] [imgui-highdpi](sokol_examples/imgui-highdpi-sapp.zig)
    // - [ ] [cimgui](sokol_examples/cimgui-sapp.zig)
    // - [ ] [imgui-images](sokol_examples/imgui-images-sapp.zig)
    // - [ ] [imgui-usercallback](sokol_examples/imgui-usercallback-sapp.zig)
    // - [ ] [nuklear](sokol_examples/nuklear-sapp.zig)
    // - [ ] [nuklear-images](sokol_examples/nuklear-images-sapp.zig)
    // - [ ] [sgl-microui](sokol_examples/sgl-microui-sapp.zig)
    // - [ ] [fontstash](sokol_examples/fontstash-sapp.zig)
    // - [ ] [fontstash-layers](sokol_examples/fontstash-layers-sapp.zig)
    // - [ ] [debugtext](sokol_examples/debugtext-sapp.zig)
    // - [ ] [debugtext-printf](sokol_examples/debugtext-printf-sapp.zig)
    // - [ ] [debugtext-userfont](sokol_examples/debugtext-userfont-sapp.zig)
    // - [ ] [debugtext-context](sokol_examples/debugtext-context-sapp.zig)
    // - [ ] [debugtext-layers](sokol_examples/debugtext-layers-sapp.zig)
    // - [ ] [events](sokol_examples/events-sapp.zig)
    // - [ ] [icon](sokol_examples/icon-sapp.zig)
    .{
        .name = "droptest",
        .root_source = "sokol_examples/droptest-sapp.zig",
    },
    // - [ ] [pixelformats](sokol_examples/pixelformats-sapp.zig)
    // - [ ] [drawcallperf](sokol_examples/drawcallperf-sapp.zig)
    // - [ ] [saudio](sokol_examples/saudio-sapp.zig)
    // - [ ] [modplay](sokol_examples/modplay-sapp.zig)
    // - [ ] [noentry](sokol_examples/noentry-sapp.zig)
    // - [ ] [restart](sokol_examples/restart-sapp.zig)
    // - [ ] [sgl](sokol_examples/sgl-sapp.zig)
    .{
        .name = "sgl-lines",
        .root_source = "sokol_examples/sgl-lines-sapp.zig",
    },
    // - [ ] [sgl-points](sokol_examples/sgl-points-sapp.zig)
    // - [ ] [sgl-context](sokol_examples/sgl-context-sapp.zig)
    // - [ ] [loadpng](sokol_examples/loadpng-sapp.zig)
    // - [ ] [plmpeg](sokol_examples/plmpeg-sapp.zig)
    // cgltf
    // .{
    //     .name = "ozz-anim",
    //     .root_source = "sokol_examples/ozz-anim-sapp.zig",
    //     .sidemodule = true,
    // },
    // .{
    //     .name = "ozz-skin",
    //     .root_source = "sokol_examples/ozz-skin-sapp.zig",
    //     .sidemodule = true,
    //     .shader = "sokol_examples/ozz-skin-sapp.glsl",
    // },
    // - [ ] [ozz-storagebuffer](sokol_examples/ozz-storagebuffer-sapp.zig)
    // - [ ] [shdfeatures](sokol_examples/shdfeatures-sapp.zig)
    // - [ ] [spine-simple](sokol_examples/spine-simple-sapp.zig)
    // - [ ] [spine-inspector](sokol_examples/spine-inspector-sapp.zig)
    // - [ ] [spine-layers](sokol_examples/spine-layers-sapp.zig)
    // - [ ] [spine-skinsets](sokol_examples/spine-skinsets-sapp.zig)
    // - [ ] [spine-switch-skinsets](sokol_examples/spine-switch-skinsets-sapp.zig)
};
