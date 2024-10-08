//------------------------------------------------------------------------------
//  clear-sapp.c
//------------------------------------------------------------------------------
const sokol = @import("sokol");
const sg = sokol.gfx;
const dbgui = @import("dbgui");

var pass_action = sg.PassAction{};

export fn init() void {
    sg.setup(.{
        .environment = sokol.glue.environment(),
        .logger = .{ .func = sokol.log.func },
    });
    pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 1.0 },
    };
    dbgui.setup(sokol.app.sampleCount());
}

export fn frame() void {
    const g = pass_action.colors[0].clear_value.g + 0.01;
    pass_action.colors[0].clear_value.g = if (g > 1.0) 0.0 else g;
    sg.beginPass(.{
        .action = pass_action,
        .swapchain = sokol.glue.swapchain(),
    });
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
        // .event_cb = __dbgui_event,
        .width = 400,
        .height = 300,
        .window_title = "Clear (sokol app)",
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = sokol.log.func },
    });
}
