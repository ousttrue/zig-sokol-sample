//------------------------------------------------------------------------------
//  triangle-sapp.c
//  Simple 2D rendering from vertex buffer.
//------------------------------------------------------------------------------
const sokol = @import("sokol");
const sg = sokol.gfx;
const dbgui = @import("dbgui");
const shader = @import("triangle-sapp.glsl.zig");

// application state
const state = struct {
    var pip = sg.Pipeline{};
    var bind = sg.Bindings{};
    var pass_action = sg.PassAction{};
};

export fn init() void {
    sg.setup(.{
        .environment = sokol.glue.environment(),
        .logger = .{ .func = sokol.log.func },
    });
    dbgui.setup(sokol.app.sampleCount());

    // a vertex buffer with 3 vertices
    const vertices = [_]f32{
        // positions            // colors
        0.0,  0.5,  0.5, 1.0, 0.0, 0.0, 1.0,
        0.5,  -0.5, 0.5, 0.0, 1.0, 0.0, 1.0,
        -0.5, -0.5, 0.5, 0.0, 0.0, 1.0, 1.0,
    };
    state.bind.vertex_buffers[0] = sg.makeBuffer(.{
        .data = sg.asRange(&vertices),
        .label = "triangle-vertices",
    });

    // create shader from code-generated sg_shader_desc
    const shd = sg.makeShader(shader.triangleShaderDesc(sg.queryBackend()));

    // create a pipeline object (default render states are fine for triangle)
    var pip_desc = sg.PipelineDesc{
        .shader = shd,
        // if the vertex layout doesn't have gaps, don't need to provide strides and offsets
        .label = "triangle-pipeline",
    };
    pip_desc.layout.attrs[shader.ATTR_triangle_position].format = .FLOAT3;
    pip_desc.layout.attrs[shader.ATTR_triangle_color0].format = .FLOAT4;
    state.pip = sg.makePipeline(pip_desc);

    // a pass action to clear framebuffer to black
    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r=0.0, .g=0.0, .b=0.0, .a=1.0 },
    };
}

export fn frame() void {
    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sokol.glue.swapchain(),
    });
    sg.applyPipeline(state.pip);
    sg.applyBindings(state.bind);
    sg.draw(0, 3, 1);
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
        .width = 640,
        .height = 480,
        .window_title = "Triangle (sokol-app)",
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = sokol.log.func },
    });
}
