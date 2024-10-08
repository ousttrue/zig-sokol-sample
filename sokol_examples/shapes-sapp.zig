//------------------------------------------------------------------------------
//  shapes-sapp.c
//  Simple sokol_shape.h demo.
//------------------------------------------------------------------------------
const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const shader = @import("shapes-sapp.glsl.zig");
const rowmath = @import("rowmath");
const Vec3 = rowmath.Vec3;
const Mat4 = rowmath.Mat4;

const Shape = struct {
    pos: Vec3 = .{ .x = 0, .y = 0, .z = 0 },
    draw: sokol.shape.ElementRange,
};

const ShapeType = enum(usize) {
    BOX,
    PLANE,
    SPHERE,
    CYLINDER,
    TORUS,
    NUM_SHAPES,
};

const state = struct {
    var pass_action = sg.PassAction{};
    var pip = sg.Pipeline{};
    var vbuf = sg.Buffer{};
    var ibuf = sg.Buffer{};
    var shapes: [@intFromEnum(ShapeType.NUM_SHAPES)]Shape = undefined;
    var vs_params: shader.VsParams = undefined;
    var rx: f32 = 0;
    var ry: f32 = 0;
};

export fn init() void {
    sg.setup(.{
        .environment = sokol.glue.environment(),
        .logger = .{ .func = sokol.log.func },
    });
    var debugtext_desc = sokol.debugtext.Desc{
        .logger = .{ .func = sokol.log.func },
    };
    debugtext_desc.fonts[0] = sokol.debugtext.fontOric();
    sokol.debugtext.setup(debugtext_desc);
    // __dbgui_setup(sapp_sample_count());

    // clear to black
    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
    };

    // shader and pipeline object
    var pip_desc = sg.PipelineDesc{
        .shader = sg.makeShader(shader.shapesShaderDesc(sg.queryBackend())),
        .index_type = .UINT16,
        .cull_mode = .NONE,
        .depth = .{ .compare = .LESS_EQUAL, .write_enabled = true },
    };
    pip_desc.layout.buffers[0] = sokol.shape.vertexBufferLayoutState();
    pip_desc.layout.attrs[0] = sokol.shape.positionVertexAttrState();
    pip_desc.layout.attrs[1] = sokol.shape.normalVertexAttrState();
    pip_desc.layout.attrs[2] = sokol.shape.texcoordVertexAttrState();
    pip_desc.layout.attrs[3] = sokol.shape.colorVertexAttrState();
    state.pip = sg.makePipeline(pip_desc);

    // shape positions
    state.shapes[@intFromEnum(ShapeType.BOX)].pos = .{ .x = -1.0, .y = 1.0, .z = 0.0 };
    state.shapes[@intFromEnum(ShapeType.PLANE)].pos = .{ .x = 1.0, .y = 1.0, .z = 0.0 };
    state.shapes[@intFromEnum(ShapeType.SPHERE)].pos = .{ .x = -2.0, .y = -1.0, .z = 0.0 };
    state.shapes[@intFromEnum(ShapeType.CYLINDER)].pos = .{ .x = 2.0, .y = -1.0, .z = 0.0 };
    state.shapes[@intFromEnum(ShapeType.TORUS)].pos = .{ .x = 0.0, .y = -1.0, .z = 0.0 };

    // generate shape geometries
    var vertices: [6 * 1024]sokol.shape.Vertex = undefined;
    var indices: [16 * 1024]u16 = undefined;
    var buf = sokol.shape.Buffer{
        .vertices = .{ .buffer = sokol.shape.asRange(&vertices) },
        .indices = .{ .buffer = sokol.shape.asRange(&indices) },
    };
    buf = sokol.shape.buildBox(buf, .{
        .width = 1.0,
        .height = 1.0,
        .depth = 1.0,
        .tiles = 10,
        .random_colors = true,
    });
    state.shapes[@intFromEnum(ShapeType.BOX)].draw = sokol.shape.elementRange(buf);
    buf = sokol.shape.buildPlane(buf, .{
        .width = 1.0,
        .depth = 1.0,
        .tiles = 10,
        .random_colors = true,
    });
    state.shapes[@intFromEnum(ShapeType.PLANE)].draw = sokol.shape.elementRange(buf);
    buf = sokol.shape.buildSphere(buf, .{
        .radius = 0.75,
        .slices = 36,
        .stacks = 20,
        .random_colors = true,
    });
    state.shapes[@intFromEnum(ShapeType.SPHERE)].draw = sokol.shape.elementRange(buf);
    buf = sokol.shape.buildCylinder(buf, .{
        .radius = 0.5,
        .height = 1.5,
        .slices = 36,
        .stacks = 10,
        .random_colors = true,
    });
    state.shapes[@intFromEnum(ShapeType.CYLINDER)].draw = sokol.shape.elementRange(buf);
    buf = sokol.shape.buildTorus(buf, .{
        .radius = 0.5,
        .ring_radius = 0.3,
        .rings = 36,
        .sides = 18,
        .random_colors = true,
    });
    state.shapes[@intFromEnum(ShapeType.TORUS)].draw = sokol.shape.elementRange(buf);
    std.debug.assert(buf.valid);

    // one vertex/index-buffer-pair for all shapes
    const vbuf_desc = sokol.shape.vertexBufferDesc(buf);
    const ibuf_desc = sokol.shape.indexBufferDesc(buf);
    state.vbuf = sg.makeBuffer(vbuf_desc);
    state.ibuf = sg.makeBuffer(ibuf_desc);
}

export fn frame() void {
    // help text
    sokol.debugtext.canvas(sokol.app.widthf() * 0.5, sokol.app.heightf() * 0.5);
    sokol.debugtext.pos(0.5, 0.5);
    sokol.debugtext.puts(
        \\press key to switch draw mode:
        \\
        \\  1: vertex normals
        \\  2: texture coords
        \\  3: vertex color
    );

    // view-projection matrix...
    const proj = Mat4.makePerspective(
        std.math.degreesToRadians(60.0),
        sokol.app.widthf() / sokol.app.heightf(),
        0.01,
        10.0,
    );
    const view = Mat4.makeLookAt(
        .{ .x = 0.0, .y = 1.5, .z = 6.0 },
        .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .{ .x = 0.0, .y = 1.0, .z = 0.0 },
    );
    const view_proj = view.mul(proj);

    // model-rotation matrix
    const t = sokol.app.frameDuration() * 60.0;
    state.rx += @floatCast(1.0 * t);
    state.ry += @floatCast(2.0 * t);
    const rxm = Mat4.rotate(state.rx, .{ .x = 1.0, .y = 0.0, .z = 0.0 });
    const rym = Mat4.rotate(state.ry, .{ .x = 0.0, .y = 1.0, .z = 0.0 });
    const rm = rxm.mul(rym);

    // render shapes...
    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sokol.glue.swapchain(),
    });
    sg.applyPipeline(state.pip);
    sg.applyBindings(.{
        .vertex_buffers = .{ state.vbuf, .{}, .{}, .{}, .{}, .{}, .{}, .{} },
        .index_buffer = state.ibuf,
    });
    for (0..@intFromEnum(ShapeType.NUM_SHAPES)) |i| {
        // per shape model-view-projection matrix
        const model = rm.mul(Mat4.translate(state.shapes[i].pos));
        state.vs_params.mvp = model.mul(view_proj).m;
        sg.applyUniforms(.VS, shader.SLOT_vs_params, sg.asRange(&state.vs_params));
        sg.draw(state.shapes[i].draw.base_element, state.shapes[i].draw.num_elements, 1);
    }
    sokol.debugtext.draw();
    // __dbgui_draw();
    sg.endPass();
    sg.commit();
}

export fn input(ev: [*c]const sokol.app.Event) void {
    if (ev.*.type == .KEY_DOWN) {
        switch (ev.*.key_code) {
            ._1 => {
                state.vs_params.draw_mode = 0.0;
            },
            ._2 => {
                state.vs_params.draw_mode = 1.0;
            },
            ._3 => {
                state.vs_params.draw_mode = 2.0;
            },
            else => {},
        }
    }
    // __dbgui_event(ev);
}

export fn cleanup() void {
    // __dbgui_shutdown();
    sokol.debugtext.shutdown();
    sg.shutdown();
}

pub fn main() void {
    sokol.app.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = input,
        .width = 800,
        .height = 600,
        .sample_count = 4,
        .window_title = "shapes-sapp.c",
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = sokol.log.func },
    });
}
