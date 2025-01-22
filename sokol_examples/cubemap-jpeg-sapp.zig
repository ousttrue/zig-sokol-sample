//------------------------------------------------------------------------------
//  cubemap-jpeg-sapp.c
//
//  Load and render cubemap from individual jpeg files.
//------------------------------------------------------------------------------
const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const dbgui = @import("dbgui");
const rowmath = @import("rowmath");
const InputState = rowmath.InputState;
const OrbitCamera = rowmath.OrbitCamera;
const shader = @import("cubemap-jpeg-sapp.glsl.zig");
const stb_image = @import("stb_image");

const SG_CUBEFACE_NUM = @intFromEnum(sg.CubeFace.NUM);

const state = struct {
    var allocator: std.mem.Allocator = undefined;
    var input = InputState{};
    var orbit = OrbitCamera{};
    var pass_action = sg.PassAction{};
    var pip = sg.Pipeline{};
    var bind = sg.Bindings{};
    var load_count: u32 = 0;
    var load_failed = false;
    var pixels: []u8 = undefined;
};

// room for loading all cubemap faces in parallel
const FACE_WIDTH = 2048;
const FACE_HEIGHT = 2048;
const FACE_NUM_BYTES = FACE_WIDTH * FACE_HEIGHT * 4;

fn cubeface_range(face_index: sg.CubeFace) []u8 {
    const offset = @intFromEnum(face_index) * FACE_NUM_BYTES;
    return state.pixels[@intCast(offset)..@intCast(offset + FACE_NUM_BYTES)];
}

export fn init() void {
    state.allocator = std.heap.c_allocator;
    sg.setup(.{
        .environment = sokol.glue.environment(),
        .logger = .{ .func = sokol.log.func },
    });
    dbgui.setup(sokol.app.sampleCount());

    var debugtext_desc = sokol.debugtext.Desc{
        .logger = .{ .func = sokol.log.func },
    };
    debugtext_desc.fonts[0] = sokol.debugtext.fontOric();
    sokol.debugtext.setup(debugtext_desc);

    // allocate memory for pixel data (both as io buffer for JPEG data, and for the decoded pixel data)
    state.pixels = @ptrCast(state.allocator.alloc(u8, SG_CUBEFACE_NUM * FACE_NUM_BYTES) catch @panic("alloc pixels"));

    // pass action, clear to black
    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
    };

    const vertices = [_]f32{
        -1.0, -1.0, -1.0,
        1.0,  -1.0, -1.0,
        1.0,  1.0,  -1.0,
        -1.0, 1.0,  -1.0,

        -1.0, -1.0, 1.0,
        1.0,  -1.0, 1.0,
        1.0,  1.0,  1.0,
        -1.0, 1.0,  1.0,

        -1.0, -1.0, -1.0,
        -1.0, 1.0,  -1.0,
        -1.0, 1.0,  1.0,
        -1.0, -1.0, 1.0,

        1.0,  -1.0, -1.0,
        1.0,  1.0,  -1.0,
        1.0,  1.0,  1.0,
        1.0,  -1.0, 1.0,

        -1.0, -1.0, -1.0,
        -1.0, -1.0, 1.0,
        1.0,  -1.0, 1.0,
        1.0,  -1.0, -1.0,

        -1.0, 1.0,  -1.0,
        -1.0, 1.0,  1.0,
        1.0,  1.0,  1.0,
        1.0,  1.0,  -1.0,
    };
    state.bind.vertex_buffers[0] = sg.makeBuffer(.{
        .data = sg.asRange(&vertices),
        .label = "cubemap-vertices",
    });

    const indices = [_]u16{
        0,  1,  2,  0,  2,  3,
        6,  5,  4,  7,  6,  4,
        8,  9,  10, 8,  10, 11,
        14, 13, 12, 15, 14, 12,
        16, 17, 18, 16, 18, 19,
        22, 21, 20, 23, 22, 20,
    };
    state.bind.index_buffer = sg.makeBuffer(.{ .type = .INDEXBUFFER, .data = sg.asRange(&indices), .label = "cubemap-indices" });

    // allocate a texture handle, but initialize the texture later after data is loaded
    state.bind.images[shader.IMG_tex] = sg.allocImage();

    // a sampler object
    state.bind.samplers[shader.SMP_smp] = sg.makeSampler(.{
        .min_filter = .LINEAR,
        .mag_filter = .LINEAR,
        .label = "cubemap-sampler",
    });

    // a pipeline object
    var pip_desc = sg.PipelineDesc{
        .shader = sg.makeShader(shader.cubemapShaderDesc(sg.queryBackend())),
        .index_type = .UINT16,
        .depth = .{ .compare = .LESS_EQUAL, .write_enabled = true },
        .label = "cubemap-pipeline",
    };
    pip_desc.layout.attrs[shader.ATTR_cubemap_pos].format = .FLOAT3;
    state.pip = sg.makePipeline(pip_desc);

    // load 6 cubemap face image files (note: filenames are in same order as SG_CUBEFACE_*)
    const filenames = [SG_CUBEFACE_NUM][:0]const u8{
        "nb2_posx.jpg", "nb2_negx.jpg",
        "nb2_posy.jpg", "nb2_negy.jpg",
        "nb2_posz.jpg", "nb2_negz.jpg",
    };

    // setup sokol-fetch to load 6 faces in parallel
    sokol.fetch.setup(.{
        .max_requests = 6,
        .num_channels = 1,
        .num_lanes = SG_CUBEFACE_NUM,
        .logger = .{ .func = sokol.log.func },
    });
    for (0..SG_CUBEFACE_NUM) |i| {
        _ = sokol.fetch.send(.{
            .path = filenames[i],
            .callback = fetch_cb,
            .buffer = .{
                .ptr = &cubeface_range(@enumFromInt(i))[0],
                .size = cubeface_range(@enumFromInt(i)).len,
            },
        });
    }
}

export fn fetch_cb(response: [*c]const sokol.fetch.Response) void {
    if (response.*.fetched) {
        // decode loaded jpeg data
        var width: c_int = undefined;
        var height: c_int = undefined;
        var channels_in_file: c_int = undefined;
        const desired_channels: c_int = 4;
        const _decoded_pixels = stb_image.stbi_load_from_memory(
            @ptrCast(response.*.data.ptr),
            @intCast(response.*.data.size),
            &width,
            &height,
            &channels_in_file,
            desired_channels,
        );
        if (_decoded_pixels != null) {
            defer stb_image.stbi_image_free(_decoded_pixels);
            std.debug.assert(width == FACE_WIDTH);
            std.debug.assert(height == FACE_HEIGHT);
            // overwrite JPEG data with decoded pixel data
            const decoded_pixels = _decoded_pixels[0..FACE_NUM_BYTES];
            const dst: [*]u8 = @constCast(@ptrCast(response.*.buffer.ptr));
            std.mem.copyForwards(
                u8,
                dst[0..FACE_NUM_BYTES],
                decoded_pixels,
            );
            // all 6 faces loaded?
            state.load_count += 1;
            if (state.load_count == SG_CUBEFACE_NUM) {
                var image_desc = sg.ImageDesc{
                    .type = .CUBE,
                    .width = width,
                    .height = height,
                    .pixel_format = .RGBA8,
                    .label = "cubemap-image",
                };
                image_desc.data.subimage[@intFromEnum(sg.CubeFace.POS_X)][0] = sg.asRange(cubeface_range(sg.CubeFace.POS_X));
                image_desc.data.subimage[@intFromEnum(sg.CubeFace.NEG_X)][0] = sg.asRange(cubeface_range(sg.CubeFace.NEG_X));
                image_desc.data.subimage[@intFromEnum(sg.CubeFace.POS_Y)][0] = sg.asRange(cubeface_range(sg.CubeFace.POS_Y));
                image_desc.data.subimage[@intFromEnum(sg.CubeFace.NEG_Y)][0] = sg.asRange(cubeface_range(sg.CubeFace.NEG_Y));
                image_desc.data.subimage[@intFromEnum(sg.CubeFace.POS_Z)][0] = sg.asRange(cubeface_range(sg.CubeFace.POS_Z));
                image_desc.data.subimage[@intFromEnum(sg.CubeFace.NEG_Z)][0] = sg.asRange(cubeface_range(sg.CubeFace.NEG_Z));
                sg.initImage(state.bind.images[shader.IMG_tex], image_desc);
                state.allocator.free(state.pixels);
                state.pixels = &.{};
            }
        }
    } else if (response.*.failed) {
        state.load_failed = true;
    }
}

export fn frame() void {
    sokol.fetch.dowork();

    state.input.screen_width = sokol.app.widthf();
    state.input.screen_height = sokol.app.heightf();
    state.orbit.frame(state.input);
    state.input.mouse_wheel = 0;

    sokol.fetch.dowork();

    const vs_params = shader.VsParams{
        .mvp = state.orbit.viewProjectionMatrix().m,
    };

    sokol.debugtext.canvas(sokol.app.widthf() * 0.5, sokol.app.heightf() * 0.5);
    sokol.debugtext.origin(1, 1);
    if (state.load_failed) {
        sokol.debugtext.puts("LOAD FAILED!");
    } else if (state.load_count < 6) {
        sokol.debugtext.puts("LOADING ...");
    } else {
        sokol.debugtext.puts("LMB + move mouse to look around");
    }

    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sokol.glue.swapchain(),
    });
    sg.applyPipeline(state.pip);
    sg.applyBindings(state.bind);
    sg.applyUniforms(shader.UB_vs_params, sg.asRange(&vs_params));
    sg.draw(0, 36, 1);
    sokol.debugtext.draw();
    dbgui.draw();
    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    dbgui.shutdown();
    sokol.fetch.shutdown();
    sokol.debugtext.shutdown();
    sg.shutdown();
}

export fn input(e: [*c]const sokol.app.Event) void {
    if (dbgui.eventWithRetval(e)) {
        return;
    }
    switch (e.*.type) {
        .MOUSE_DOWN => {
            switch (e.*.mouse_button) {
                .LEFT => {
                    state.input.mouse_left = true;
                },
                .RIGHT => {
                    state.input.mouse_right = true;
                },
                .MIDDLE => {
                    state.input.mouse_middle = true;
                },
                .INVALID => {},
            }
        },
        .MOUSE_UP => {
            switch (e.*.mouse_button) {
                .LEFT => {
                    state.input.mouse_left = false;
                },
                .RIGHT => {
                    state.input.mouse_right = false;
                },
                .MIDDLE => {
                    state.input.mouse_middle = false;
                },
                .INVALID => {},
            }
        },
        .MOUSE_MOVE => {
            state.input.mouse_x = e.*.mouse_x;
            state.input.mouse_y = e.*.mouse_y;
        },
        .MOUSE_SCROLL => {
            state.input.mouse_wheel = e.*.scroll_y;
        },
        else => {},
    }
}

pub fn main() void {
    sokol.app.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = input,
        .width = 800,
        .height = 600,
        .sample_count = 1,
        .window_title = "cubemap-jpeg-sapp.c",
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = sokol.log.func },
    });
}
