const std = @import("std");
const ig = @import("cimgui");
const sokol = @import("sokol");
const sg = sokol.gfx;
const simgui = sokol.imgui;
// const scene = @import("cube_scene.zig");
const scene = @import("teapot_scene.zig");
const InputState = @import("input_state.zig").InputState;
const Camera = @import("camera.zig").Camera;
const RenderTarget = @import("rendertarget.zig").RenderTarget;

const state = struct {
    var pass_action = sg.PassAction{};
    var camera = Camera{};
    var rendertarget: ?RenderTarget = null;
};

pub fn get_or_create(width: i32, height: i32) ?RenderTarget {
    if (state.rendertarget) |rendertarget| {
        if (rendertarget.width == width and rendertarget.height == height) {
            return rendertarget;
        }
        // std.debug.print("destroy rendertarget\n", .{});
        rendertarget.deinit();
    }

    // std.debug.print("creae rendertarget: {} x {}\n", .{ width, height });
    const rendertarget = RenderTarget.init(width, height);
    state.rendertarget = rendertarget;
    return rendertarget;
}

// pub fn end_rendertarget() void {
//     sg.endPass();
// }

export fn init() void {
    // initialize sokol-gfx
    sg.setup(.{
        .environment = sokol.glue.environment(),
        .logger = .{ .func = sokol.log.func },
    });
    // initialize sokol-imgui
    simgui.setup(.{
        .logger = .{ .func = sokol.log.func },
    });
    sokol.gl.setup(.{
        .logger = .{ .func = sokol.log.func },
    });

    scene.setup();

    state.pass_action.colors[0] = .{
        // initial clear color
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.0, .g = 0.5, .b = 1.0, .a = 1.0 },
    };
}

export fn frame() void {
    // call simgui.newFrame() before any ImGui calls
    simgui.newFrame(.{
        .width = sokol.app.width(),
        .height = sokol.app.height(),
        .delta_time = sokol.app.frameDuration(),
        .dpi_scale = sokol.app.dpiScale(),
    });
    state.camera.update(InputState.from_imgui());

    // the offscreen pass, rendering an rotating, untextured donut into a render target image
    //=== UI CODE STARTS HERE
    ig.igShowDemoWindow(null);
    {
        ig.igSetNextWindowPos(.{ .x = 10, .y = 10 }, ig.ImGuiCond_Once, .{ .x = 0, .y = 0 });
        ig.igSetNextWindowSize(.{ .x = 400, .y = 100 }, ig.ImGuiCond_Once);
        _ = ig.igBegin("Hello Dear ImGui!", 0, ig.ImGuiWindowFlags_None);
        _ = ig.igColorEdit3("Background", &state.pass_action.colors[0].clear_value.r, ig.ImGuiColorEditFlags_None);
        ig.igEnd();
    }

    {
        ig.igPushStyleVar_Vec2(ig.ImGuiStyleVar_WindowPadding, .{ .x = 0, .y = 0 });
        defer ig.igPopStyleVar(1);
        var open_fbo = true;
        if (ig.igBegin("fbo", &open_fbo, ig.ImGuiWindowFlags_NoScrollbar | ig.ImGuiWindowFlags_NoScrollWithMouse)) {
            ig.igPushStyleVar_Vec2(ig.ImGuiStyleVar_FramePadding, .{ .x = 0, .y = 0 });
            defer ig.igPopStyleVar(1);
            var pos = ig.ImVec2{};
            ig.igGetCursorScreenPos(&pos);
            var size = ig.ImVec2{};
            ig.igGetContentRegionAvail(&size);

            if (size.x > 0 and size.y > 0) {
                // if (fbo_view.camera.set_viewport_cursor(
                //     pos.x,
                //     pos.y,
                //     size.x,
                //     size.y,
                //     cursor.x,
                //     cursor.y,
                // )) {
                //     fbo_view.update_projection_matrix();
                // }

                if (get_or_create(@intFromFloat(size.x), @intFromFloat(size.y))) |rendertarget| {
                    _ = ig.igImageButton(
                        "fbo",
                        simgui.imtextureid(rendertarget.image),
                        size,
                        .{ .x = 0, .y = 0 },
                        .{ .x = 1, .y = 1 },
                        .{ .x = 1, .y = 1, .z = 1, .w = 1 },
                        .{ .x = 1, .y = 1, .z = 1, .w = 1 },
                    );
                    // Custom_ButtonBehaviorMiddleRight();

                    // if (c.igIsItemActive()) {
                    //     fbo_view.update(
                    //         cursor_delta.x,
                    //         cursor_delta.y,
                    //         size.y,
                    //     );
                    // } else if (c.igIsItemHovered(0)) {
                    //     if (wheel.y != 0) {
                    //         fbo_view.camera_orbit.dolly(wheel.y);
                    //         fbo_view.update_view_matrix();
                    //     }
                    // }

                    sg.beginPass(rendertarget.pass);
                    scene.draw(state.camera, .OffScreen);
                    sg.endPass();

                    // {
                    //     fbo_view.begin_camera3D();
                    //     defer fbo_view.end_camera3D();
                    //
                    //     draw_frustum(root_view.frustum());
                    //     const start, const end = root_view.mouse_near_far();
                    //     c.DrawLine3D(tor(start), tor(end), c.YELLOW);
                    //     scene.draw();
                    // }
                }
            }
        }
        ig.igEnd();
    }
    //=== UI CODE ENDS HERE

    // call simgui.render() inside a sokol-gfx pass
    sg.beginPass(.{ .action = state.pass_action, .swapchain = sokol.glue.swapchain() });

    scene.draw(state.camera, .Display);

    simgui.render();

    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    simgui.shutdown();
    sokol.gl.shutdown();
    sg.shutdown();
}

export fn event(ev: [*c]const sokol.app.Event) void {
    // forward input events to sokol-imgui
    _ = simgui.handleEvent(ev.*);
}

pub fn main() void {
    sokol.app.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = event,
        .window_title = "sokol-zig + Dear Imgui",
        .width = 800,
        .height = 600,
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = sokol.log.func },
    });
}
