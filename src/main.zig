const std = @import("std");
const builtin = @import("builtin");
const ig = @import("cimgui");
const sokol = @import("sokol");
const sg = sokol.gfx;
const simgui = sokol.imgui;
// const scene = @import("cube_scene.zig");
const scene = @import("teapot_scene.zig");
const InputState = @import("input_state.zig").InputState;
const RenderTarget = @import("rendertarget.zig").RenderTarget;
const linegeom = @import("linegeom.zig");
const tinygizmo = @import("tinygizmo");
const rowmath = @import("rowmath");
const Vec3 = rowmath.Vec3;
const Vec2 = rowmath.Vec2;
const Camera = @import("camera.zig").Camera;

fn draw_line(v0: Vec3, v1: Vec3) void {
    sokol.gl.v3f(v0.x, v0.y, v0.z);
    sokol.gl.v3f(v1.x, v1.y, v1.z);
}

fn is_contain(pos: ig.ImVec2, size: ig.ImVec2, p: ig.ImVec2) bool {
    return (p.x >= pos.x and p.x <= (pos.x + size.x)) and (p.y >= pos.y and p.y <= (pos.y + size.y));
}

fn draw_camera_frustum(camera: Camera, _cursor: ?Vec2) void {
    const frustom = camera.frustum();

    sokol.gl.pushMatrix();
    defer sokol.gl.popMatrix();
    sokol.gl.multMatrix(&camera.transform.localToWorld().m[0]);

    sokol.gl.beginLines();
    defer sokol.gl.end();
    sokol.gl.c3f(1, 1, 1);

    draw_line(frustom.far_top_left, frustom.far_top_right);
    draw_line(frustom.far_top_right, frustom.far_bottom_right);
    draw_line(frustom.far_bottom_right, frustom.far_bottom_left);
    draw_line(frustom.far_bottom_left, frustom.far_top_left);

    draw_line(frustom.near_top_left, frustom.near_top_right);
    draw_line(frustom.near_top_right, frustom.near_bottom_right);
    draw_line(frustom.near_bottom_right, frustom.near_bottom_left);
    draw_line(frustom.near_bottom_left, frustom.near_top_left);

    draw_line(Vec3.zero, frustom.far_top_left);
    draw_line(Vec3.zero, frustom.far_top_right);
    draw_line(Vec3.zero, frustom.far_bottom_left);
    draw_line(Vec3.zero, frustom.far_bottom_right);

    if (_cursor) |cursor| {
        sokol.gl.c3f(1, 1, 0);
        draw_line(Vec3.zero, .{
            .x = frustom.far_top_right.x * cursor.x,
            .y = frustom.far_top_right.y * cursor.y,
            .z = frustom.far_top_right.z,
        });
    }
}

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
    sgl_ctx: sokol.gl.Context = .{},

    fn update(self: *@This(), input: InputState) Vec2 {
        return self.camera.update(input);
    }

    fn begin(self: *@This(), _rendertarget: ?RenderTarget) void {
        if (_rendertarget) |rendertarget| {
            sg.beginPass(rendertarget.pass);
            sokol.gl.setContext(self.sgl_ctx);
        } else {
            sg.beginPass(.{
                .action = self.pass_action,
                .swapchain = sokol.glue.swapchain(),
            });
            sokol.gl.setContext(sokol.gl.defaultContext());
        }

        sokol.gl.defaults();
        sokol.gl.matrixModeProjection();
        sokol.gl.multMatrix(&self.camera.projection.m[0]);
        sokol.gl.matrixModeModelview();
        sokol.gl.multMatrix(&self.camera.transform.worldToLocal().m[0]);
    }

    fn end(self: *@This(), _rendertarget: ?RenderTarget) void {
        linegeom.grid();

        if (_rendertarget) |_| {
            sokol.gl.contextDraw(self.sgl_ctx);
        } else {
            sokol.gl.contextDraw(sokol.gl.defaultContext());
            simgui.render();
        }
        sg.endPass();
    }
};

const state = struct {
    var allocator: std.mem.Allocator = undefined;
    var display = RenderView{
        .camera = .{
            .near_clip = 0.5,
            .far_clip = 15,
            .transform = .{
                .translation = .{
                    .x = 0,
                    .y = 1,
                    .z = 5,
                },
            },
        },
    };
    var offscreen = RenderView{
        .camera = .{
            .transform = .{
                .translation = .{ .x = 0, .y = 1, .z = 15 },
            },
        },
    };
    var rendertarget: ?RenderTarget = null;
    var gizmo_ctx: tinygizmo.Context = undefined;
};

extern fn Custom_ButtonBehaviorMiddleRight() void;

pub fn get_or_create(width: i32, height: i32) ?RenderTarget {
    if (state.rendertarget) |rendertarget| {
        if (rendertarget.width == width and rendertarget.height == height) {
            return rendertarget;
        }
        rendertarget.deinit();
    }

    const rendertarget = RenderTarget.init(width, height);
    state.rendertarget = rendertarget;
    return rendertarget;
}

export fn init() void {
    // state.allocator = std.heap.page_allocator;
    // wasm
    state.allocator = std.heap.c_allocator;
    state.gizmo_ctx = tinygizmo.Context.init(state.allocator);

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

    // create a sokol-gl context compatible with the offscreen render pass
    // (specific color pixel format, no depth-stencil-surface, no MSAA)
    state.offscreen.sgl_ctx = sokol.gl.makeContext(.{
        .max_vertices = 65535,
        .max_commands = 65535,
        .color_format = .RGBA8,
        .depth_format = .DEPTH,
        .sample_count = 1,
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
    const display_cursor = state.display.update(InputState.from_imgui());
    var offscreen_cursor: Vec2 = undefined;

    const io = ig.igGetIO().*;
    if (!io.WantCaptureMouse) {
        state.gizmo_ctx.update(.{
            .viewport_size = .{ .x = io.DisplaySize.x, .y = io.DisplaySize.y },
            .mouse_left = io.MouseDown[ig.ImGuiMouseButton_Left],
            .ray = state.display.camera.ray(.{ .x = io.MousePos.x, .y = io.MousePos.y }),
            .cam_yFov = state.display.camera.yFov,
            .cam_dir = state.display.camera.transform.rotation.dirZ().negate(),
        });

        state.gizmo_ctx.rotation("first-example-gizmo", false, &scene.state.xform_a) catch @panic("transform a");
        state.gizmo_ctx.translation("second-example-gizmo", false, &scene.state.xform_b) catch @panic("transform b");
        const uniform = false;
        state.gizmo_ctx.scale("third-example-gizmo", &scene.state.xform_c, uniform) catch @panic("transform b");
    }

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

    var hover = false;
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
            hover = is_contain(pos, size, io.MousePos);

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
                    offscreen_cursor = state.offscreen.update(InputState.from_rendertarget(pos, size));

                    {
                        // render offscreen
                        state.offscreen.begin(rendertarget);
                        defer state.offscreen.end(rendertarget);

                        // grid
                        linegeom.grid();

                        scene.draw(state.offscreen.camera, .OffScreen);
                        draw_camera_frustum(state.display.camera, if (hover) null else display_cursor);
                    }
                }
            }
        }
        ig.igEnd();
    }
    //=== UI CODE ENDS HERE

    {
        // render background
        state.display.begin(null);
        defer state.display.end(null);

        // grid
        linegeom.grid();

        scene.draw(state.display.camera, .Display);
        draw_camera_frustum(state.offscreen.camera, if (hover) offscreen_cursor else null);
        for (state.gizmo_ctx.drawlist.items) |m| {
            sokol.gl.matrixModeModelview();
            sokol.gl.pushMatrix();
            defer sokol.gl.popMatrix();
            sokol.gl.multMatrix(&m.matrix.m[0]);
            sokol.gl.beginTriangles();
            defer sokol.gl.end();
            const color = m.color();
            sokol.gl.c4f(
                color.x,
                color.y,
                color.z,
                color.w,
            );
            for (m.mesh.triangles) |triangle| {
                for (triangle) |i| {
                    const p = m.mesh.vertices[i].position;
                    sokol.gl.v3f(p.x, p.y, p.z);
                }
            }
        }
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
