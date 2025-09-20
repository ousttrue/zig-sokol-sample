//------------------------------------------------------------------------------
//  https://github.com/floooh/sokol-samples/blob/master/sapp/triangle-bufferless-sapp.c
//
//  Rendering a triangle without buffers (instead define the vertex data
//  as constants in the shader).
//------------------------------------------------------------------------------
const sokol = @import("sokol");
const sg = sokol.gfx;
const dbgui = @import("dbgui");
const shader = @import("triangle-bufferless-sapp.glsl.zig");

const state = struct {
    var pip = sg.Pipeline{};
    var pass_action = sg.PassAction{};
};

export fn init() void {
    sg.setup(.{
        .environment = sokol.glue.environment(),
        .logger = .{ .func = sokol.log.func },
    });
    dbgui.setup(sokol.app.sampleCount());

    // look ma, no vertex buffer!

    // create a shader object
    const shd = sg.makeShader(shader.triangleShaderDesc(sg.queryBackend()));

    // ...and a pipeline object, note that there's no vertex layout since there's
    // no vertex data passed into the shader.
    // All other pipeline attributes can be left to their defaults for a 2D triangle
    // to show up.
    state.pip = sg.makePipeline(.{ .shader = shd });

    // setup pass action to clear to black
    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
    };
}

export fn frame() void {
    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sokol.glue.swapchain(),
    });
    sg.applyPipeline(state.pip);
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
        .window_title = "triangle-bufferless-sapp.c",
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = sokol.log.func },
    });
}
