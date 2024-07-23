const std = @import("std");
const builtin = @import("builtin");
const ig = @import("cimgui");
const sokol = @import("sokol");
const sg = sokol.gfx;
const simgui = sokol.imgui;
// const scene = @import("cube_scene.zig");
const scene = @import("teapot_scene.zig");
const InputState = @import("input_state.zig").InputState;
const Camera = @import("camera.zig").Camera;
const RenderTarget = @import("rendertarget.zig").RenderTarget;
const linegeom = @import("linegeom.zig");

const RenderView = struct {
    camera: Camera = Camera{},
    pip: sg.Pipeline = .{},
    pass_action: sg.PassAction = .{
        .colors = .{
            .{
                // initial clear color
                .load_action = .CLEAR,
                .clear_value = .{ .r = 0.0, .g = 0.5, .b = 1.0, .a = 1.0 },
            },
            .{},
            .{},
            .{},
        },
    },

    fn update(self: *@This(), input: InputState) void {
        self.camera.update(input);
    }

    fn begin(self: *@This(), _rendertarget: ?RenderTarget) void {
        if (_rendertarget) |rendertarget| {
            sg.beginPass(rendertarget.pass);
        } else {
            sokol.gl.defaults();
            sokol.gl.matrixModeProjection();
            sokol.gl.sgl_mult_matrix(&self.camera.projection.m[0]);
            sokol.gl.matrixModeModelview();
            sokol.gl.sgl_mult_matrix(&self.camera.transform.worldToLocal().m[0]);

            sg.beginPass(.{
                .action = self.pass_action,
                .swapchain = sokol.glue.swapchain(),
            });
        }
    }

    fn end(_: *@This(), _rendertarget: ?RenderTarget) void {
        if (_rendertarget) |_| {
            //
        } else {
            simgui.render();
            sokol.gl.draw();
        }
        sg.endPass();
    }
};

const state = struct {
    var display = RenderView{};
    var offscreen = RenderView{};
    var rendertarget: ?RenderTarget = null;
};

extern fn Custom_ButtonBehaviorMiddleRight() void;

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
}

export fn frame() void {
    // call simgui.newFrame() before any ImGui calls
    simgui.newFrame(.{
        .width = sokol.app.width(),
        .height = sokol.app.height(),
        .delta_time = sokol.app.frameDuration(),
        .dpi_scale = sokol.app.dpiScale(),
    });
    state.display.update(InputState.from_imgui());

    // the offscreen pass, rendering an rotating, untextured donut into a render target image
    //=== UI CODE STARTS HERE
    ig.igShowDemoWindow(null);
    {
        ig.igSetNextWindowPos(.{ .x = 10, .y = 10 }, ig.ImGuiCond_Once, .{ .x = 0, .y = 0 });
        ig.igSetNextWindowSize(.{ .x = 400, .y = 100 }, ig.ImGuiCond_Once);
        _ = ig.igBegin("Hello Dear ImGui!", 0, ig.ImGuiWindowFlags_None);
        _ = ig.igColorEdit3("Background", &state.display.pass_action.colors[0].clear_value.r, ig.ImGuiColorEditFlags_None);
        ig.igEnd();
    }

    {
        ig.igSetNextWindowPos(.{ .x = 10, .y = 100 }, ig.ImGuiCond_Once, .{ .x = 0, .y = 0 });
        ig.igSetNextWindowSize(.{ .x = 256, .y = 256 }, ig.ImGuiCond_Once);
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
                if (get_or_create(@intFromFloat(size.x), @intFromFloat(size.y))) |rendertarget| {
                    _ = ig.igImageButton(
                        "fbo",
                        simgui.imtextureid(rendertarget.image),
                        size,
                        .{ .x = 0, .y = if (builtin.os.tag == .emscripten) 1 else 0 },
                        .{ .x = 1, .y = if (builtin.os.tag == .emscripten) 0 else 1 },
                        .{ .x = 1, .y = 1, .z = 1, .w = 1 },
                        .{ .x = 1, .y = 1, .z = 1, .w = 1 },
                    );

                    Custom_ButtonBehaviorMiddleRight();
                    state.offscreen.update(InputState.from_rendertarget(pos, size));
                    {
                        state.offscreen.begin(rendertarget);
                        defer state.offscreen.end(rendertarget);
                        scene.draw(state.offscreen.camera, .OffScreen);
                    }
                }
            }
        }
        ig.igEnd();
    }
    //=== UI CODE ENDS HERE

    // call simgui.render() inside a sokol-gfx pass
    {
        state.display.begin(null);
        defer state.display.end(null);
        scene.draw(state.offscreen.camera, .Display);
        linegeom.grid();
    }
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
