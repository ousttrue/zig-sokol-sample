const std = @import("std");

pub const Example = struct {
    name: []const u8,
    root_source: []const u8,
    shader: ?[]const u8 = null,
};

pub const examples = [_]Example{
    .{
        .name = "clear",
        .root_source = "sokol_examples/clear-sapp.zig",
    },
    .{
        .name = "triangle",
        .root_source = "sokol_examples/triangle-sapp.zig",
        .shader = "sokol_examples/triangle-sapp.glsl",
    },
    .{
        .name = "triangle-bufferless",
        .root_source = "sokol_examples/triangle-bufferless-sapp.zig",
        .shader = "sokol_examples/triangle-bufferless-sapp.glsl",
    },
    .{
        .name = "quad",
        .root_source = "sokol_examples/quad-sapp.zig",
        .shader = "sokol_examples/quad-sapp.glsl",
    },
    .{
        .name = "bufferoffsets",
        .root_source = "sokol_examples/bufferoffsets-sapp.zig",
        .shader = "sokol_examples/bufferoffsets-sapp.glsl",
    },
    .{
        .name = "cube",
        .root_source = "sokol_examples/cube-sapp.zig",
        .shader = "sokol_examples/cube-sapp.glsl",
    },
    .{
        .name = "noninterleaved",
        .root_source = "sokol_examples/noninterleaved-sapp.zig",
        .shader = "sokol_examples/noninterleaved-sapp.glsl",
    },
    .{
        .name = "texcube",
        .root_source = "sokol_examples/texcube-sapp.zig",
        .shader = "sokol_examples/texcube-sapp.glsl",
    },
    // - [ ] [vertexpull](sokol_examples/vertexpull-sapp.zig)
    // - [ ] [sbuftex](sokol_examples/sbuftex-sapp.zig)
    .{
        .name = "shapes",
        .root_source = "sokol_examples/shapes-sapp.zig",
        .shader = "sokol_examples/shapes-sapp.glsl",
    },
    .{
        .name = "shapes-transform",
        .root_source = "sokol_examples/shapes-transform-sapp.zig",
        .shader = "sokol_examples/shapes-transform-sapp.glsl",
    },
    .{
        .name = "offscreen",
        .root_source = "sokol_examples/offscreen-sapp.zig",
        .shader = "sokol_examples/offscreen-sapp.glsl",
    },
    // - [ ] [offscreen-msaa](sokol_examples/offscreen-msaa-sapp.zig)
    .{
        .name = "instancing",
        .root_source = "sokol_examples/instancing-sapp.zig",
        .shader = "sokol_examples/instancing-sapp.glsl",
    },
    // - [ ] [instancing-pull](sokol_examples/instancing-pull-sapp.zig)
    // - [ ] [mrt](sokol_examples/mrt-sapp.zig)
    // - [ ] [mrt-pixelformats](sokol_examples/mrt-pixelformats-sapp.zig)
    // - [ ] [arraytex](sokol_examples/arraytex-sapp.zig)
    // - [ ] [tex3d](sokol_examples/tex3d-sapp.zig)
    // - [ ] [dyntex3d](sokol_examples/dyntex3d-sapp.zig)
    // - [ ] [dyntex](sokol_examples/dyntex-sapp.zig)
    // - [ ] [basisu](sokol_examples/basisu-sapp.zig)
    // - [ ] [cubemap-jpeg](sokol_examples/cubemap-jpeg-sapp.zig)
    // - [ ] [cubemaprt](sokol_examples/cubemaprt-sapp.zig)
    // - [ ] [miprender](sokol_examples/miprender-sapp.zig)
    // - [ ] [layerrender](sokol_examples/layerrender-sapp.zig)
    // - [ ] [primtypes](sokol_examples/primtypes-sapp.zig)
    // - [ ] [uvwrap](sokol_examples/uvwrap-sapp.zig)
    // - [ ] [mipmap](sokol_examples/mipmap-sapp.zig)
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
