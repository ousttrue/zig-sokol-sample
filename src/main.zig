const ig = @import("cimgui");
const sokol = @import("sokol");
const sg = sokol.gfx;
const simgui = sokol.imgui;
// const scene = @import("cube_scene.zig");
const scene = @import("teapot_scene.zig");
const InputState = @import("input_state.zig").InputState;
const Camera = @import("camera.zig").Camera;

const state = struct {
    var offscreen = sg.Pass{};
    var pass_action = sg.PassAction{};
    var camera = Camera{};
    var color_img = simgui.Image{};
};

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

    state.pass_action.colors[0] =
        .{
        // initial clear color
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.0, .g = 0.5, .b = 1.0, .a = 1.0 },
    };

    // setup a render pass struct with one color and one depth render attachment image
    // NOTE: we need to explicitly set the sample count in the attachment image objects,
    // because the offscreen pass uses a different sample count than the display render pass
    // (the display render pass is multi-sampled, the offscreen pass is not)
    const color_img = sg.makeImage(.{
        .render_target = true,
        .width = 256,
        .height = 256,
        .pixel_format = .RGBA8,
        .sample_count = 1,
        .label = "color-image",
    });
    const depth_img = sg.makeImage(.{
        .render_target = true,
        .width = 256,
        .height = 256,
        .pixel_format = .DEPTH,
        .sample_count = 1,
        .label = "depth-image",
    });
    var attachments_desc = sg.AttachmentsDesc{
        .depth_stencil = .{ .image = depth_img },
        .label = "offscreen-attachments",
    };
    attachments_desc.colors[0] = .{ .image = color_img };
    state.offscreen.attachments = sg.makeAttachments(attachments_desc);
    state.offscreen.action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.25, .g = 0.25, .b = 0.25, .a = 1.0 },
    };
    state.offscreen.label = "offscreen-pass";
    state.color_img = simgui.makeImage(.{
        .image = color_img,
    });
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
    sg.beginPass(state.offscreen);
    scene.draw(state.camera, .OffScreen);
    sg.endPass();

    //=== UI CODE STARTS HERE
    ig.igShowDemoWindow(null);
    {
        ig.igSetNextWindowPos(.{ .x = 10, .y = 10 }, ig.ImGuiCond_Once, .{ .x = 0, .y = 0 });
        ig.igSetNextWindowSize(.{ .x = 400, .y = 100 }, ig.ImGuiCond_Once);
        _ = ig.igBegin("Hello Dear ImGui!", 0, ig.ImGuiWindowFlags_None);
        _ = ig.igColorEdit3("Background", &state.pass_action.colors[0].clear_value.r, ig.ImGuiColorEditFlags_None);
        ig.igEnd();
    }

    if (ig.igBegin("view", null, 0)) {
        // const pos = ig.igGetCursorScreenPos();
        var size: ig.ImVec2 = undefined;
        ig.igGetContentRegionAvail(&size);
        _ = ig.igImage(
            simgui.imtextureid(state.color_img),
            size,
            .{ .x = 0, .y = 0 },
            .{ .x = 1, .y = 1 },
            .{ .x = 1, .y = 1, .z = 1, .w = 1 },
            .{ .x = 1, .y = 1, .z = 1, .w = 1 },
        );
    }
    ig.igEnd();
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
