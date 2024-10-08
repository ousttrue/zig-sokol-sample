//------------------------------------------------------------------------------
//  noninterleaved-sapp.c
//  How to use non-interleaved vertex data (vertex components in
//  separate non-interleaved chunks in the same vertex buffers). Note
//  that only 4 separate chunks are currently possible because there
//  are 4 vertex buffer bind slots in sg_bindings, but you can keep
//  several related vertex components interleaved in the same chunk.
//------------------------------------------------------------------------------
const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const dbgui = @import("dbgui");
const shader = @import("noninterleaved-sapp.glsl.zig");
const rowmath = @import("rowmath");
const Mat4 = rowmath.Mat4;

const state = struct {
    var pass_action = sg.PassAction{};
    var pip = sg.Pipeline{};
    var bind = sg.Bindings{};
    var rx: f32 = 0.0;
    var ry: f32 = 0.0;
};

export fn init() void {
    sg.setup(.{
        .environment = sokol.glue.environment(),
        .logger = .{ .func = sokol.log.func },
    });
    dbgui.setup(sokol.app.sampleCount());

    // cube vertex buffer
    const vertices = [_]f32{
        // positions
        -1.0, -1.0, -1.0, 1.0,  -1.0, -1.0, 1.0,  1.0,  -1.0, -1.0, 1.0,  -1.0,
        -1.0, -1.0, 1.0,  1.0,  -1.0, 1.0,  1.0,  1.0,  1.0,  -1.0, 1.0,  1.0,
        -1.0, -1.0, -1.0, -1.0, 1.0,  -1.0, -1.0, 1.0,  1.0,  -1.0, -1.0, 1.0,
        1.0,  -1.0, -1.0, 1.0,  1.0,  -1.0, 1.0,  1.0,  1.0,  1.0,  -1.0, 1.0,
        -1.0, -1.0, -1.0, -1.0, -1.0, 1.0,  1.0,  -1.0, 1.0,  1.0,  -1.0, -1.0,
        -1.0, 1.0,  -1.0, -1.0, 1.0,  1.0,  1.0,  1.0,  1.0,  1.0,  1.0,  -1.0,

        // colors
        1.0,  0.5,  0.0,  1.0,  1.0,  0.5,  0.0,  1.0,  1.0,  0.5,  0.0,  1.0,
        1.0,  0.5,  0.0,  1.0,  0.5,  1.0,  0.0,  1.0,  0.5,  1.0,  0.0,  1.0,
        0.5,  1.0,  0.0,  1.0,  0.5,  1.0,  0.0,  1.0,  0.5,  0.0,  1.0,  1.0,
        0.5,  0.0,  1.0,  1.0,  0.5,  0.0,  1.0,  1.0,  0.5,  0.0,  1.0,  1.0,
        1.0,  0.5,  1.0,  1.0,  1.0,  0.5,  1.0,  1.0,  1.0,  0.5,  1.0,  1.0,
        1.0,  0.5,  1.0,  1.0,  0.5,  1.0,  1.0,  1.0,  0.5,  1.0,  1.0,  1.0,
        0.5,  1.0,  1.0,  1.0,  0.5,  1.0,  1.0,  1.0,  1.0,  1.0,  0.5,  1.0,
        1.0,  1.0,  0.5,  1.0,  1.0,  1.0,  0.5,  1.0,  1.0,  1.0,  0.5,  1.0,
    };
    state.bind.vertex_buffers[0] = sg.makeBuffer(.{
        .data = sg.asRange(&vertices),
    });
    state.bind.vertex_buffers[1] = state.bind.vertex_buffers[0];

    // fill the resource bindings, note how the same vertex
    // buffer is bound to the first two slots, and the vertex-buffer-offsets
    // are used to point to the position- and color-components.
    // position components are at start of buffer
    state.bind.vertex_buffer_offsets[0] = 0;
    // byte offset of color components in buffer
    state.bind.vertex_buffer_offsets[1] = 24 * 3 * @sizeOf(f32);

    // create an index buffer for the cube
    const indices = [_]u16{
        0,  1,  2,  0,  2,  3,
        6,  5,  4,  7,  6,  4,
        8,  9,  10, 8,  10, 11,
        14, 13, 12, 15, 14, 12,
        16, 17, 18, 16, 18, 19,
        22, 21, 20, 23, 22, 20,
    };
    state.bind.index_buffer = sg.makeBuffer(.{
        .type = .INDEXBUFFER,
        .data = sg.asRange(&indices),
    });

    // a shader and pipeline object
    var pip_desc = sg.PipelineDesc{
        .shader = sg.makeShader(shader.noninterleavedShaderDesc(sg.queryBackend())),
        .index_type = .UINT16,
        .cull_mode = .BACK,
        .depth = .{ .compare = .LESS_EQUAL, .write_enabled = true },
    };
    // note how the vertex components are pulled from different buffer bind slots
    //                 // positions come from vertex buffer slot 0
    pip_desc.layout.attrs[0] = .{
        .format = .FLOAT3,
        .buffer_index = 0,
    };
    // colors come from vertex buffer slot 1
    pip_desc.layout.attrs[1] = .{
        .format = .FLOAT4,
        .buffer_index = 1,
    };
    state.pip = sg.makePipeline(pip_desc);
}

export fn frame() void {
    // compute model-view-projection matrix for vertex shader
    const t: f32 = @as(f32, @floatCast(sokol.app.frameDuration())) * 60.0;
    const proj = Mat4.makePerspective(std.math.degreesToRadians(60.0), sokol.app.widthf() / sokol.app.heightf(), 0.01, 10.0);
    const view = Mat4.makeLookAt(
        .{ .x = 0.0, .y = 1.5, .z = 6.0 },
        .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .{ .x = 0.0, .y = 1.0, .z = 0.0 },
    );
    const view_proj = view.mul(proj);
    state.rx += 1.0 * t;
    state.ry += 2.0 * t;
    const rxm = Mat4.rotate(state.rx, .{ .x = 1.0, .y = 0.0, .z = 0.0 });
    const rym = Mat4.rotate(state.ry, .{ .x = 0.0, .y = 1.0, .z = 0.0 });
    const model = rxm.mul(rym);
    var vs_params = shader.VsParams{
        .mvp = model.mul(view_proj).m,
    };

    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sokol.glue.swapchain(),
    });
    sg.applyPipeline(state.pip);
    sg.applyBindings(state.bind);
    sg.applyUniforms(.VS, shader.SLOT_vs_params, sg.asRange(&vs_params));
    sg.draw(0, 36, 1);
    dbgui.draw();
    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    dbgui.shutdown();
    sg.shutdown();
}

pub fn main() void {
    sokol.app.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = dbgui.event,
        .width = 800,
        .height = 600,
        .sample_count = 4,
        .window_title = "Noninterleaved (sokol-app)",
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = sokol.log.func },
    });
}
