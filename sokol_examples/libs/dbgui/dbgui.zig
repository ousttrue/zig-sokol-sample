// The typical debug UI overlay useful for most sokol-app samples
const sokol = @import("sokol");
const simgui = sokol.imgui;

// static sgimgui_t sgimgui;

pub fn setup(sample_count: i32) void {
    // setup debug inspection header(s)
    // sgimgui_init(&sg_imgui, &(sgimgui_desc_t){0});

    // setup the sokol-imgui utility header
    simgui.setup(.{
        .sample_count = sample_count,
        .logger = .{ .func = sokol.log.func },
    });
}

pub fn shutdown() void {
    // sgimgui_discard(&sg_imgui);
    simgui.shutdown();
}

pub fn draw() void {
    simgui.newFrame(.{
        .width = sokol.app.width(),
        .height = sokol.app.height(),
        .delta_time = sokol.app.frameDuration(),
        .dpi_scale = sokol.app.dpiScale(),
    });
    // if (igBeginMainMenuBar()) {
    //     sgimgui_draw_menu(&sg_imgui, "sokol-gfx");
    //     igEndMainMenuBar();
    // }
    // sgimgui_draw(&sg_imgui);
    simgui.render();
}

pub export fn event(e: [*c]const sokol.app.Event) void {
    _ = simgui.handleEvent(e.*);
}

pub fn eventWithRetval(e: [*c]const sokol.app.Event) bool {
    _ = e;
    return false;
}
