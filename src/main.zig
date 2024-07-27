const std = @import("std");
const builtin = @import("builtin");
const ig = @import("cimgui");
const sokol = @import("sokol");
const sg = sokol.gfx;
const simgui = sokol.imgui;
// const scene = @import("cube_scene.zig");
const scene = @import("teapot_scene.zig");
const InputState = @import("input_state.zig");
const rendertarget = @import("rendertarget.zig");
const linegeom = @import("linegeom.zig");
const tinygizmo = @import("tinygizmo");
const rowmath = @import("rowmath");
const Vec3 = rowmath.Vec3;
const Vec2 = rowmath.Vec2;
const Camera = @import("camera.zig").Camera;

const state = struct {
    var allocator: std.mem.Allocator = undefined;
    var display = rendertarget.RenderView{
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
    var offscreen = rendertarget.RenderView{
        .camera = .{
            .transform = .{
                .translation = .{ .x = 0, .y = 1, .z = 15 },
            },
        },
    };
    var gizmo_ctx: tinygizmo.Context = .{};
    var gizmo_a: tinygizmo.TranslationContext = .{};
    var gizmo_b: tinygizmo.RotationContext = .{};
    var gizmo_c: tinygizmo.ScalingContext = .{};
    var drawlist: std.ArrayList(tinygizmo.Renderable) = undefined;
};

fn draw_line(v0: Vec3, v1: Vec3) void {
    sokol.gl.v3f(v0.x, v0.y, v0.z);
    sokol.gl.v3f(v1.x, v1.y, v1.z);
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

    draw_line(Vec3.ZERO, frustom.far_top_left);
    draw_line(Vec3.ZERO, frustom.far_top_right);
    draw_line(Vec3.ZERO, frustom.far_bottom_left);
    draw_line(Vec3.ZERO, frustom.far_bottom_right);

    if (_cursor) |cursor| {
        sokol.gl.c3f(1, 1, 0);
        draw_line(Vec3.ZERO, .{
            .x = frustom.far_top_right.x * cursor.x,
            .y = frustom.far_top_right.y * cursor.y,
            .z = frustom.far_top_right.z,
        });
    }
}

fn draw_gizmo(drawlist: []const tinygizmo.Renderable) void {
    for (drawlist) |m| {
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

export fn init() void {
    // state.allocator = std.heap.page_allocator;
    // wasm
    state.allocator = std.heap.c_allocator;

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

    state.drawlist = std.ArrayList(tinygizmo.Renderable).init(state.allocator);
}

pub fn input_from_imgui() InputState {
    const io = ig.igGetIO().*;
    var input = InputState{
        .screen_width = io.DisplaySize.x,
        .screen_height = io.DisplaySize.y,
        .mouse_x = io.MousePos.x,
        .mouse_y = io.MousePos.y,
    };

    if (!io.WantCaptureMouse) {
        input.mouse_left = io.MouseDown[ig.ImGuiMouseButton_Left];
        input.mouse_right = io.MouseDown[ig.ImGuiMouseButton_Right];
        input.mouse_middle = io.MouseDown[ig.ImGuiMouseButton_Middle];
        input.mouse_wheel = io.MouseWheel;
    }

    return input;
}

export fn frame() void {
    // call simgui.newFrame() before any ImGui calls
    simgui.newFrame(.{
        .width = sokol.app.width(),
        .height = sokol.app.height(),
        .delta_time = sokol.app.frameDuration(),
        .dpi_scale = sokol.app.dpiScale(),
    });
    const display_cursor = state.display.update(input_from_imgui());
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

        state.drawlist.clearRetainingCapacity();
        state.gizmo_a.translation(state.gizmo_ctx, &state.drawlist, false, &scene.state.xform_a) catch @panic("transform a");
        state.gizmo_b.rotation(state.gizmo_ctx, &state.drawlist, false, &scene.state.xform_b) catch @panic("transform b");
        const uniform = false;
        state.gizmo_c.scale(state.gizmo_ctx, &state.drawlist, &scene.state.xform_c, uniform) catch @panic("transform b");
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
        if (ig.igBegin(
            "fbo",
            &open_fbo,
            ig.ImGuiWindowFlags_NoScrollbar | ig.ImGuiWindowFlags_NoScrollWithMouse,
        )) {
            if (state.offscreen.beginImageButton()) |render_context| {
                defer state.offscreen.endImageButton();
                hover = render_context.hover;
                offscreen_cursor = render_context.cursor;

                // grid
                linegeom.grid();

                scene.draw(state.offscreen.camera, .OffScreen);
                draw_camera_frustum(state.display.camera, if (hover) null else display_cursor);
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
        draw_gizmo(state.drawlist.items);
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
