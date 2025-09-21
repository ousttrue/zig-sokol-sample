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
