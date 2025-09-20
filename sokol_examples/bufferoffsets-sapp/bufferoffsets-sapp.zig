//------------------------------------------------------------------------------
//  bufferoffsets-sapp.c
//  Render separate geometries in vertex- and index-buffers with
//  buffer offsets.
//------------------------------------------------------------------------------
const sokol = @import("sokol");
const sg = sokol.gfx;
const dbgui = @import("dbgui");
const shader = @import("bufferoffsets-sapp.glsl.zig");

const state = struct {
    var pass_action = sg.PassAction{};
    var pip = sg.Pipeline{};
    var bind = sg.Bindings{};
};

const Vertex = struct {
    f32,
    f32,
    f32,
    f32,
    f32,
};

export fn init() void {
    sg.setup(.{
        .environment = sokol.glue.environment(),
        .logger = .{ .func = sokol.log.func },
    });
    dbgui.setup(sokol.app.sampleCount());

    // a 2D triangle and quad in 1 vertex buffer and 1 index buffer
    const vertices = [_]Vertex{
        // triangle
        .{ 0.0, 0.55, 1.0, 0.0, 0.0 },
        .{ 0.25, 0.05, 0.0, 1.0, 0.0 },
        .{ -0.25, 0.05, 0.0, 0.0, 1.0 },

        // quad
        .{ -0.25, -0.05, 0.0, 0.0, 1.0 },
        .{ 0.25, -0.05, 0.0, 1.0, 0.0 },
        .{ 0.25, -0.55, 1.0, 0.0, 0.0 },
        .{ -0.25, -0.55, 1.0, 1.0, 0.0 },
    };
    const indices = [_]u16{
        0, 1, 2,
        //
        0, 1, 2,
        0, 2, 3,
    };
    state.bind.vertex_buffers[0] = sg.makeBuffer(.{
        .data = sg.asRange(&vertices),
        .label = "vertex-buffer",
    });
    state.bind.index_buffer = sg.makeBuffer(.{
        .usage = .{ .index_buffer = true },
        .data = sg.asRange(&indices),
        .label = "index-buffer",
    });

    // a shader and pipeline to render 2D shapes
    var pip_desc = sg.PipelineDesc{
        .shader = sg.makeShader(shader.bufferoffsetsShaderDesc(sg.queryBackend())),
        .index_type = .UINT16,
        .label = "pipeline",
    };
    pip_desc.layout.attrs[0].format = .FLOAT2;
    pip_desc.layout.attrs[1].format = .FLOAT3;
    state.pip = sg.makePipeline(pip_desc);

    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.5, .g = 0.5, .b = 1.0, .a = 1.0 },
    };
}

export fn frame() void {
    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sokol.glue.swapchain(),
    });
    sg.applyPipeline(state.pip);
    // render the triangle
    state.bind.vertex_buffer_offsets[0] = 0;
    state.bind.index_buffer_offset = 0;
    sg.applyBindings(state.bind);
    sg.draw(0, 3, 1);
    // render the quad
    state.bind.vertex_buffer_offsets[0] = 3 * @sizeOf(Vertex);
    state.bind.index_buffer_offset = 3 * @sizeOf(u16);
    sg.applyBindings(state.bind);
    sg.draw(0, 6, 1);
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
        .window_title = "Buffer Offsets (sokol-app)",
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = sokol.log.func },
    });
}
