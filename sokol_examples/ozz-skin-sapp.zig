//------------------------------------------------------------------------------
//  ozz-skin-sapp.c
//
//  Ozz-animation with GPU skinning.
//
//  https://guillaumeblanc.github.io/ozz-animation/
//
//  Joint palette data for vertex skinning is uploaded each frame to a dynamic
//  RGBA32F texture and sampled in the vertex shader to perform weighted
//  skinning with up to 4 influence joints per vertex.
//
//  Character instance matrices are stored in a vertex buffer.
//
//  Together this enables rendering many independently animated and positioned
//  characters in a single draw call via hardware instancing.
//------------------------------------------------------------------------------
const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const shader = @import("ozz-skin-sapp.glsl.zig");
const ozz_wrap = @import("ozz_wrap.zig");
const simgui = sokol.imgui;
const ig = @import("cimgui");
const rowmath = @import("rowmath");

// the upper limit for joint palette size is 256 (because the mesh joint indices
// are stored in packed byte-size vertex formats), but the example mesh only needs less than 64
const MAX_JOINTS = 64;

// this defines the size of the instance-buffer and height of the joint-texture
const MAX_INSTANCES = 512;

const Vertex = extern struct {
    position: [3]f32,
    normal: u32,
    joint_indices: u32,
    joint_weights: u32,
};

// per-instance data for hardware-instanced rendering includes the
// transposed 4x3 model-to-world matrix, and information where the
// joint palette is found in the joint texture
const Instance = struct {
    xxxx: [4]f32,
    yyyy: [4]f32,
    zzzz: [4]f32,
    joint_uv: [2]f32,
};

const state = struct {
    var ozz: ?*ozz_wrap.ozz_t = null;

    var pass_action = sg.PassAction{};
    var pip = sg.Pipeline{};
    var joint_texture = sg.Image{};
    var smp = sg.Sampler{};
    var bind = sg.Bindings{};

    var num_instances: u32 = 1; // current number of character instances
    var num_vertices: u32 = 0;
    var num_triangle_indices: u32 = 0;
    var joint_texture_width: c_int = 0; // in number of pixels
    var joint_texture_height: c_int = 0; // in number of pixels
    var joint_texture_pitch: c_int = 0; // in number of floats
    var orbit: rowmath.OrbitCamera = .{};
    var input: rowmath.InputState = .{};
    var draw_enabled: bool = true;
    const loaded = struct {
        var skeleton = false;
        var animation = false;
        var mesh = false;
        var failed = false;
    };
    const time = struct {
        var frame_time_ms: f64 = 0;
        var frame_time_sec: f64 = 0;
        var abs_time_sec: f64 = 0;
        var anim_eval_time: u64 = 0;
        var factor: f32 = 1.0;
        var paused = false;
    };
    const ui = struct {
        // sgimgui_t sgimgui;
        var joint_texture_shown = false;
        var joint_texture_scale: i32 = 4;
        var joint_texture = simgui.Image{};
    };
};

// IO buffers (we know the max file sizes upfront)
var skel_io_buffer: [32 * 1024]u8 = undefined;
var anim_io_buffer: [96 * 1024]u8 = undefined;
var mesh_io_buffer: [3 * 1024 * 1024]u8 = undefined;

// instance data buffer;
var instance_data: [MAX_INSTANCES]Instance = undefined;

// joint-matrix upload buffer, each joint consists of transposed 4x3 matrix
var joint_upload_buffer: [MAX_INSTANCES][MAX_JOINTS][3][4]f32 = undefined;

export fn init() void {
    state.ozz = ozz_wrap.OZZ_init();
    // setup sokol-gfx
    sg.setup(.{
        .environment = sokol.glue.environment(),
        .logger = .{ .func = sokol.log.func },
    });

    // setup sokol-time
    sokol.time.setup();

    // setup sokol-fetch
    sokol.fetch.setup(.{
        .max_requests = 3,
        .num_channels = 1,
        .num_lanes = 3,
        .logger = .{ .func = sokol.log.func },
    });

    // setup sokol-imgui
    simgui.setup(.{
        .logger = .{ .func = sokol.log.func },
    });
    //     sgimgui_desc_t sgimgui_desc = { };
    //     sgimgui_init(&state.ui.sgimgui, &sgimgui_desc);

    // initialize pass action for default-pass
    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
    };

    // vertex-skinning shader and pipeline object for 3d rendering, note the hardware-instanced vertex layout
    var pip_desc = sg.PipelineDesc{
        .shader = sg.makeShader(shader.skinnedShaderDesc(sg.queryBackend())),
    };
    pip_desc.layout.buffers[0].stride = @sizeOf(Vertex);
    pip_desc.layout.buffers[1].stride = @sizeOf(Instance);
    pip_desc.layout.buffers[1].step_func = .PER_INSTANCE;
    pip_desc.layout.attrs[shader.ATTR_vs_position].format = .FLOAT3;
    pip_desc.layout.attrs[shader.ATTR_vs_normal].format = .BYTE4N;
    pip_desc.layout.attrs[shader.ATTR_vs_jindices].format = .UBYTE4N;
    pip_desc.layout.attrs[shader.ATTR_vs_jweights].format = .UBYTE4N;
    pip_desc.layout.attrs[shader.ATTR_vs_inst_xxxx].format = .FLOAT4;
    pip_desc.layout.attrs[shader.ATTR_vs_inst_xxxx].buffer_index = 1;
    pip_desc.layout.attrs[shader.ATTR_vs_inst_yyyy].format = .FLOAT4;
    pip_desc.layout.attrs[shader.ATTR_vs_inst_yyyy].buffer_index = 1;
    pip_desc.layout.attrs[shader.ATTR_vs_inst_zzzz].format = .FLOAT4;
    pip_desc.layout.attrs[shader.ATTR_vs_inst_zzzz].buffer_index = 1;
    pip_desc.layout.attrs[shader.ATTR_vs_inst_joint_uv].format = .FLOAT2;
    pip_desc.layout.attrs[shader.ATTR_vs_inst_joint_uv].buffer_index = 1;
    pip_desc.index_type = .UINT16;
    // ozz mesh data appears to have counter-clock-wise face winding
    pip_desc.face_winding = .CCW;
    pip_desc.cull_mode = .BACK;
    pip_desc.depth.write_enabled = true;
    pip_desc.depth.compare = .LESS_EQUAL;
    state.pip = sg.makePipeline(pip_desc);

    // create a dynamic joint-palette texture and sampler
    state.joint_texture_width = MAX_JOINTS * 3;
    state.joint_texture_height = MAX_INSTANCES;
    state.joint_texture_pitch = state.joint_texture_width * 4;
    state.joint_texture = sg.makeImage(.{
        .width = state.joint_texture_width,
        .height = state.joint_texture_height,
        .num_mipmaps = 1,
        .pixel_format = .RGBA32F,
        .usage = .STREAM,
    });
    state.bind.vs.images[shader.SLOT_joint_tex] = state.joint_texture;

    state.smp = sg.makeSampler(.{
        .min_filter = .NEAREST,
        .mag_filter = .NEAREST,
        .wrap_u = .CLAMP_TO_EDGE,
        .wrap_v = .CLAMP_TO_EDGE,
    });
    state.bind.vs.samplers[shader.SLOT_smp] = state.smp;

    // create an sokol-imgui wrapper for the joint texture
    state.ui.joint_texture = simgui.makeImage(.{
        .image = state.joint_texture,
        .sampler = state.smp,
    });

    // create a static instance-data buffer, in this demo, character instances
    // don't move around and also are not clipped against the view volume,
    // so we can just initialize a static instance data buffer upfront
    init_instance_data();
    state.bind.vertex_buffers[1] = sg.makeBuffer(.{
        .type = .VERTEXBUFFER,
        .data = sg.asRange(&instance_data),
    });

    // start loading data
    _ = sokol.fetch.send(.{
        .path = "pab_skeleton.ozz",
        .callback = skel_data_loaded,
        .buffer = sokol.fetch.asRange(&skel_io_buffer),
    });
    _ = sokol.fetch.send(.{
        .path = "pab_crossarms.ozz",
        .callback = anim_data_loaded,
        .buffer = sokol.fetch.asRange(&anim_io_buffer),
    });
    _ = sokol.fetch.send(.{
        .path = "arnaud_mesh_4.ozz",
        .callback = mesh_data_loaded,
        .buffer = sokol.fetch.asRange(&mesh_io_buffer),
    });
}

// initialize the static instance data, since the character instances don't
// move around or are clipped against the view volume in this demo, the instance
// data is initialized once and lives in an immutable instance buffer
fn init_instance_data() void {
    //     assert((state.joint_texture_width > 0) && (state.joint_texture_height > 0));

    // initialize the character instance model-to-world matrices
    {
        var i: usize = 0;
        var x: c_int = 0;
        var y: c_int = 0;
        var dx: c_int = 0;
        var dy: c_int = 0;
        while (i < MAX_INSTANCES) : ({
            i += 1;
            x += dx;
            y += dy;
        }) {
            const inst = &instance_data[i];

            // a 3x4 transposed model-to-world matrix (only the x/z position is set)
            inst.xxxx[0] = 1.0;
            inst.xxxx[1] = 0.0;
            inst.xxxx[2] = 0.0;
            inst.xxxx[3] = @as(f32, @floatFromInt(x)) * 1.5;
            inst.yyyy[0] = 0.0;
            inst.yyyy[1] = 1.0;
            inst.yyyy[2] = 0.0;
            inst.yyyy[3] = 0.0;
            inst.zzzz[0] = 0.0;
            inst.zzzz[1] = 0.0;
            inst.zzzz[2] = 1.0;
            inst.zzzz[3] = @as(f32, @floatFromInt(y)) * 1.5;

            // at a corner?
            if (@abs(x) == @abs(y)) {
                if (x >= 0) {
                    // top-right corner: start a new ring
                    if (y >= 0) {
                        x += 1;
                        y += 1;
                        dx = 0;
                        dy = -1;
                    }
                    // bottom-right corner
                    else {
                        dx = -1;
                        dy = 0;
                    }
                } else {
                    // top-left corner
                    if (y >= 0) {
                        dx = 1;
                        dy = 0;
                    }
                    // bottom-left corner
                    else {
                        dx = 0;
                        dy = 1;
                    }
                }
            }
        }
    }

    // the skin_info vertex component contains information about where to find
    // the joint palette for this character instance in the joint texture
    const half_pixel_x = 0.5 / @as(f32, @floatFromInt(state.joint_texture_width));
    const half_pixel_y = 0.5 / @as(f32, @floatFromInt(state.joint_texture_height));
    for (0..MAX_INSTANCES) |i| {
        const inst = &instance_data[i];
        inst.joint_uv[0] = half_pixel_x;
        inst.joint_uv[1] = half_pixel_y + (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(state.joint_texture_height)));
    }
}

// compute skinning matrices, and upload into joint texture
fn update_joint_texture() void {
    const start_time = sokol.time.now();
    ozz_wrap.OZZ_update_joints(
        state.ozz,
        @intCast(state.num_instances),
        @floatCast(state.time.abs_time_sec),
        &joint_upload_buffer[0][0][0][0],
        MAX_JOINTS,
    );
    state.time.anim_eval_time = sokol.time.since(start_time);

    var img_data = sg.ImageData{};
    // FIXME: upload partial texture? (needs sokol-gfx fixes)
    img_data.subimage[0][0] = sg.asRange(&joint_upload_buffer);
    sg.updateImage(state.joint_texture, img_data);
}

export fn frame() void {
    sokol.fetch.dowork();

    state.time.frame_time_sec = sokol.app.frameDuration();
    state.time.frame_time_ms = sokol.app.frameDuration() * 1000.0;
    if (!state.time.paused) {
        state.time.abs_time_sec += state.time.frame_time_sec * state.time.factor;
    }

    state.input.screen_width = sokol.app.widthf();
    state.input.screen_height = sokol.app.heightf();
    state.orbit.frame(state.input);
    state.input.mouse_wheel = 0;

    simgui.newFrame(.{
        .width = sokol.app.width(),
        .height = sokol.app.height(),
        .delta_time = state.time.frame_time_sec,
        .dpi_scale = sokol.app.dpiScale(),
    });
    draw_ui();

    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sokol.glue.swapchain(),
    });

    if (state.loaded.animation and state.loaded.skeleton and state.loaded.mesh) {
        update_joint_texture();

        const vs_params = shader.VsParams{
            .view_proj = state.orbit.viewProjectionMatrix().m,
            .joint_pixel_width = 1.0 / @as(f32, @floatFromInt(state.joint_texture_width)),
        };
        sg.applyPipeline(state.pip);
        sg.applyBindings(state.bind);
        sg.applyUniforms(.VS, shader.SLOT_vs_params, sg.asRange(&vs_params));
        if (state.draw_enabled) {
            sg.draw(0, state.num_triangle_indices, state.num_instances);
        }
    }
    simgui.render();
    sg.endPass();
    sg.commit();
}

export fn input(e: [*c]const sokol.app.Event) void {
    if (simgui.handleEvent(e.*)) {
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

export fn cleanup() void {
    //     sgimgui_discard(&state.ui.sgimgui);
    simgui.shutdown();
    sokol.fetch.shutdown();
    sg.shutdown();

    // free C++ objects early, otherwise ozz-animation complains about memory leaks
    ozz_wrap.OZZ_shutdown(state.ozz);
}

fn draw_ui() void {
    //     if (ImGui::BeginMainMenuBar()) {
    //         sgimgui_draw_menu(&state.ui.sgimgui, "sokol-gfx");
    //         ImGui::EndMainMenuBar();
    //     }
    //     sgimgui_draw(&state.ui.sgimgui);
    ig.igSetNextWindowPos(.{ .x = 20, .y = 20 }, ig.ImGuiCond_Once, .{ .x = 0, .y = 0 });
    ig.igSetNextWindowSize(.{ .x = 220, .y = 150 }, ig.ImGuiCond_Once);
    ig.igSetNextWindowBgAlpha(0.35);
    if (ig.igBegin(
        "Controls",
        null,
        ig.ImGuiWindowFlags_NoDecoration | ig.ImGuiWindowFlags_AlwaysAutoResize,
    )) {
        if (state.loaded.failed) {
            ig.igText("Failed loading character data!");
        } else {
            // if (ig.igSliderInt(
            //     "Num Instances",
            //     &state.num_instances,
            //     1,
            //     MAX_INSTANCES,
            //     null,
            //     0,
            // )) {
            //     const dist_step = (state.camera.max_dist - state.camera.min_dist) / MAX_INSTANCES;
            //     state.camera.distance = state.camera.min_dist + dist_step * state.num_instances;
            // }
            _ = ig.igCheckbox("Enable Mesh Drawing", &state.draw_enabled);
            ig.igText("Frame Time: %.3fms\n", state.time.frame_time_ms);
            ig.igText("Anim Eval Time: %.3fms\n", sokol.time.ms(state.time.anim_eval_time));
            ig.igText(
                "Num Triangles: %d\n",
                (state.num_triangle_indices / 3) * state.num_instances,
            );
            // ig.igText(
            //     "Num Animated Joints: %d\n",
            //     state.num_skeleton_joints * state.num_instances,
            // );
            // ig.igText(
            //     "Num Skinning Joints: %d\n",
            //     state.num_skin_joints * state.num_instances,
            // );
            ig.igSeparator();
            ig.igText("Camera Controls:");
            ig.igText("  LMB + Mouse Move: Look");
            ig.igText("  Mouse Wheel: Zoom");
            // ig.igSliderFloat(
            //     "Distance",
            //     &state.camera.distance,
            //     state.camera.min_dist,
            //     state.camera.max_dist,
            //     "%.1f",
            //     1.0,
            // );
            // ig.igSliderFloat(
            //     "Latitude",
            //     &state.camera.latitude,
            //     state.camera.min_lat,
            //     state.camera.max_lat,
            //     "%.1f",
            //     1.0,
            // );
            // ig.igSliderFloat(
            //     "Longitude",
            //     &state.camera.longitude,
            //     0.0,
            //     360.0,
            //     "%.1f",
            //     1.0,
            // );
            ig.igSeparator();
            ig.igText("Time Controls:");
            _ = ig.igCheckbox("Paused", &state.time.paused);
            _ = ig.igSliderFloat(
                "Factor",
                &state.time.factor,
                0.0,
                10.0,
                "%.1f",
                1.0,
            );
            ig.igSeparator();
            if (ig.igButton("Toggle Joint Texture", .{ .x = 0, .y = 0 })) {
                state.ui.joint_texture_shown = !state.ui.joint_texture_shown;
            }
        }
    }
    if (state.ui.joint_texture_shown) {
        ig.igSetNextWindowPos(
            .{ .x = 20, .y = 300 },
            ig.ImGuiCond_Once,
            .{ .x = 0, .y = 0 },
        );
        ig.igSetNextWindowSize(.{ .x = 600, .y = 300 }, ig.ImGuiCond_Once);
        if (ig.igBegin("Joint Texture", &state.ui.joint_texture_shown, 0)) {
            _ = ig.igInputInt("##scale", &state.ui.joint_texture_scale, 0, 0, 0);
            ig.igSameLine(0, 0);
            if (ig.igButton("1x", .{ .x = 0, .y = 0 })) {
                state.ui.joint_texture_scale = 1;
            }
            ig.igSameLine(0, 0);
            if (ig.igButton("2x", .{ .x = 0, .y = 0 })) {
                state.ui.joint_texture_scale = 2;
            }
            ig.igSameLine(0, 0);
            if (ig.igButton("4x", .{ .x = 0, .y = 0 })) {
                state.ui.joint_texture_scale = 4;
            }
            // ig.igBeginChild(
            //     "##frame",
            //     .{ 0, 0 },
            //     true,
            //     ig.ImGuiWindowFlags_HorizontalScrollbar,
            // );
            ig.igImage(
                simgui.imtextureid(state.ui.joint_texture),
                .{
                    .x = @floatFromInt(state.joint_texture_width * state.ui.joint_texture_scale),
                    .y = @floatFromInt(state.joint_texture_height * state.ui.joint_texture_scale),
                },
                .{ .x = 0.0, .y = 0.0 },
                .{ .x = 1.0, .y = 1.0 },
                .{ .x = 1, .y = 1, .z = 1, .w = 1 },
                .{ .x = 0, .y = 0, .z = 0, .w = 0 },
            );
            // ig.igEndChild();
        }
        ig.igEnd();
    }
    ig.igEnd();
}

// FIXME: all loading code is much less efficient than it should be!
export fn skel_data_loaded(response: [*c]const sokol.fetch.Response) void {
    if (response.*.fetched) {
        std.debug.print("skel_data_loaded {} bytes\n", .{response.*.data.size});
        if (ozz_wrap.OZZ_load_skeleton(state.ozz, response.*.data.ptr, response.*.data.size)) {
            state.loaded.skeleton = true;
        } else {
            state.loaded.failed = true;
        }
    } else if (response.*.failed) {
        std.debug.print("skel_data_loaded fail\n", .{});
        state.loaded.failed = true;
    } else {
        unreachable;
    }
}

export fn anim_data_loaded(response: [*c]const sokol.fetch.Response) void {
    if (response.*.fetched) {
        std.debug.print("anim_data_loaded {} bytes\n", .{response.*.data.size});
        if (ozz_wrap.OZZ_load_animation(state.ozz, response.*.data.ptr, response.*.data.size)) {
            state.loaded.animation = true;
        } else {
            state.loaded.failed = true;
        }
    } else if (response.*.failed) {
        std.debug.print("anim_data_loaded fail\n", .{});
        state.loaded.failed = true;
    } else {
        unreachable;
    }
}

export fn mesh_data_loaded(response: [*c]const sokol.fetch.Response) void {
    if (response.*.fetched) {
        std.debug.print("mesh_data_loaded {} bytes\n", .{response.*.data.size});
        var vertices: [*c]ozz_wrap.vertex_t = undefined;
        var indices: [*c]u16 = undefined;
        if (ozz_wrap.OZZ_load_mesh(
            state.ozz,
            response.*.data.ptr,
            response.*.data.size,
            &vertices,
            @ptrCast(&state.num_vertices),
            &indices,
            @ptrCast(&state.num_triangle_indices),
        )) {
            defer ozz_wrap.OZZ_free(vertices);
            defer ozz_wrap.OZZ_free(indices);
            std.debug.print("vert({}): {}, idx: {}\n", .{
                @sizeOf(Vertex),
                state.num_vertices,
                state.num_triangle_indices,
            });
            std.debug.assert(state.num_vertices > 0);
            std.debug.assert(state.num_triangle_indices > 0);
            std.debug.assert(@sizeOf(Vertex) == 24);

            // create vertex- and index-buffer
            var vbuf_desc = sg.BufferDesc{};
            vbuf_desc.type = .VERTEXBUFFER;
            vbuf_desc.data.ptr = vertices;
            vbuf_desc.data.size = state.num_vertices * @sizeOf(Vertex);
            state.bind.vertex_buffers[0] = sg.makeBuffer(vbuf_desc);

            var ibuf_desc = sg.BufferDesc{};
            ibuf_desc.type = .INDEXBUFFER;
            ibuf_desc.data.ptr = indices;
            ibuf_desc.data.size = state.num_triangle_indices * @sizeOf(u16);
            state.bind.index_buffer = sg.makeBuffer(ibuf_desc);

            state.loaded.mesh = true;
        } else {
            state.loaded.failed = true;
        }
    } else if (response.*.failed) {
        std.debug.print("mesh_data_loaded fail\n", .{});
        state.loaded.failed = true;
    } else {
        unreachable;
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
        .sample_count = 4,
        .window_title = "ozz-skin-sapp.cc",
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = sokol.log.func },
    });
}
