//------------------------------------------------------------------------------
//  quad-sapp.c
//  Simple 2D rendering with vertex- and index-buffer.
//------------------------------------------------------------------------------
const sokol = @import("sokol");
const sg = sokol.gfx;
const dbgui = @import("dbgui");
const shader = @import("quad-sapp.glsl.zig");

const state = struct {
    var pass_action = sg.PassAction{};
    var pip = sg.Pipeline{};
    var bind = sg.Bindings{};
};

export fn init() void {
    sg.setup(.{
        .environment = sokol.glue.environment(),
        .logger = .{ .func = sokol.log.func },
    });
    dbgui.setup(sokol.app.sampleCount());

    // a vertex buffer
    const vertices = [_]f32{
        // positions            colors
        -0.5, 0.5,  0.5, 1.0, 0.0, 0.0, 1.0,
        0.5,  0.5,  0.5, 0.0, 1.0, 0.0, 1.0,
        0.5,  -0.5, 0.5, 0.0, 0.0, 1.0, 1.0,
        -0.5, -0.5, 0.5, 1.0, 1.0, 0.0, 1.0,
    };
    state.bind.vertex_buffers[0] = sg.makeBuffer(.{
        .data = sg.asRange(&vertices),
        .label = "quad-vertices",
    });

    // an index buffer with 2 triangles
    const indices = [_]u16{ 0, 1, 2, 0, 2, 3 };
    state.bind.index_buffer = sg.makeBuffer(.{
        .usage = .{ .index_buffer = true },
        .data = sg.asRange(&indices),
        .label = "quad-indices",
    });

    // a shader (use separate shader sources here
    const shd = sg.makeShader(shader.quadShaderDesc(sg.queryBackend()));

    // a pipeline state object
    var pip_desc = sg.PipelineDesc{
        .shader = shd,
        .index_type = .UINT16,
        .label = "quad-pipeline",
    };
    pip_desc.layout.attrs[shader.ATTR_quad_position].format = .FLOAT3;
    pip_desc.layout.attrs[shader.ATTR_quad_color0].format = .FLOAT4;
    state.pip = sg.makePipeline(pip_desc);

    // default pass action
    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
    };
}

export fn frame() void {
    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sokol.glue.swapchain(),
    });
    sg.applyPipeline(state.pip);
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
        .window_title = "Quad (sokol-app)",
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = sokol.log.func },
    });
}
