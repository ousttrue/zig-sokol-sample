//------------------------------------------------------------------------------
//  shapes-transform-sapp.c
//
//  Demonstrates merging multiple transformed shapes into a single draw-shape
//  with sokol_shape.h
//------------------------------------------------------------------------------
const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const dbgui = @import("dbgui");
const shd = @import("shapes-transform-sapp.glsl.zig");
const rowmath = @import("rowmath");
// const zshape = @import("zshape.zig");
const zshape = sokol.shape;

const state = struct {
    var pass_action = sg.PassAction{};
    var pip = sg.Pipeline{};
    var bind = sg.Bindings{};
    var elms = sokol.shape.ElementRange{};
    var vs_params: shd.VsParams = undefined;
    var rx: f32 = 0;
    var ry: f32 = 0;
};

var vertices = [1]zshape.Vertex{.{}} ** (6 * 1024);
var indices = [1]u16{0} ** (16 * 1024);

export fn init() void {
    sg.setup(.{
        .environment = sokol.glue.environment(),
        .logger = .{ .func = sokol.log.func },
    });
    // sokol.debugtext.setup(.{
    //     .fonts = .{ sokol.debugtext.fontOric(), .{}, .{}, .{}, .{}, .{}, .{}, .{} },
    //     .logger = .{ .func = sokol.log.func },
    // });
    dbgui.setup(sokol.app.sampleCount());

    // clear to black
    state.pass_action = .{ .colors = .{
        .{
            .load_action = .CLEAR,
            .clear_value = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
        },
        .{},
        .{},
        .{},
    } };

    // shader and pipeline object
    var pip_desc = sg.PipelineDesc{
        .shader = sg.makeShader(shd.shapesShaderDesc(sg.queryBackend())),
        .index_type = .UINT16,
        .cull_mode = .NONE,
        .depth = .{ .compare = .LESS_EQUAL, .write_enabled = true },
    };
    pip_desc.layout.buffers[0] = zshape.vertexBufferLayoutState();
    pip_desc.layout.attrs[0] = zshape.positionVertexAttrState();
    pip_desc.layout.attrs[1] = zshape.normalVertexAttrState();
    pip_desc.layout.attrs[2] = zshape.texcoordVertexAttrState();
    pip_desc.layout.attrs[3] = zshape.colorVertexAttrState();
    state.pip = sg.makePipeline(pip_desc);

    // generate merged shape geometries
    var buf: zshape.Buffer = .{};
    buf.vertices.buffer = sokol.shape.asRange(&vertices);
    buf.indices.buffer = sokol.shape.asRange(&indices);

    // transform matrices for the shapes
    const box_transform = rowmath.Mat4.makeTranslation(.{ .x = -1.0, .y = 0.0, .z = 1.0 });
    // const sphere_transform = rowmath.Mat4.translate(.{ .x = 1.0, .y = 0.0, .z = 1.0 });
    // const cylinder_transform = rowmath.Mat4.translate(.{ .x = -1.0, .y = 0.0, .z = -1.0 });
    // const torus_transform = rowmath.Mat4.translate(.{ .x = 1.0, .y = 0.0, .z = -1.0 });

    // build the shapes...
    buf = zshape.buildBox(buf, .{
        .width = 1.0,
        .height = 1.0,
        .depth = 1.0,
        .tiles = 10,
        .random_colors = true,
        .transform = zshape.mat4(&box_transform.m[0]),
    });
    // buf = zshape.buildSphere(buf, .{
    //     .merge = true,
    //     .radius = 0.75,
    //     .slices = 36,
    //     .stacks = 20,
    //     .random_colors = true,
    //     .transform = zshape.Mat4.init(sphere_transform.m),
    // });
    // buf = zshape.buildCylinder(buf, .{
    //     .merge = true,
    //     .radius = 0.5,
    //     .height = 1.0,
    //     .slices = 36,
    //     .stacks = 10,
    //     .random_colors = true,
    //     .transform = zshape.Mat4.init(cylinder_transform.m),
    // });
    // buf = zshape.buildTorus(buf, .{
    //     .merge = true,
    //     .radius = 0.5,
    //     .ring_radius = 0.3,
    //     .rings = 36,
    //     .sides = 18,
    //     .random_colors = true,
    //     .transform = zshape.Mat4.init(torus_transform.m),
    // });
    // std.debug.assert(buf.valid);

    // extract element range for sg_draw()
    state.elms = sokol.shape.elementRange(@as(*sokol.shape.Buffer, @ptrCast(&buf)).*);

    // and finally create the vertex- and index-buffer
    const vbuf_desc = zshape.vertexBufferDesc(buf);
    const ibuf_desc = zshape.indexBufferDesc(buf);
    state.bind.vertex_buffers[0] = sg.makeBuffer(vbuf_desc);
    state.bind.index_buffer = sg.makeBuffer(ibuf_desc);
}

export fn frame() void {
    // help text
    // sokol.debugtext.canvas(sokol.app.widthf() * 0.5, sokol.app.heightf() * 0.5);
    // sokol.debugtext.pos(0.5, 0.5);
    // sokol.debugtext.puts(
    //     \\press key to switch draw mode:
    //     \\
    //     \\  1: vertex normals
    //     \\  2: texture coords
    //     \\  3: vertex color
    // );

    // build model-view-projection matrix
    const t = (sokol.app.frameDuration() * 60.0);
    state.rx += 1.0 * @as(f32, @floatCast(t));
    state.ry += 2.0 * @as(f32, @floatCast(t));
    const proj = rowmath.Mat4.makePerspective(
        std.math.degreesToRadians(60.0),
        sokol.app.widthf() / sokol.app.heightf(),
        0.01,
        10.0,
    );
    const view = rowmath.Mat4.makeLookAt(
        .{ .x = 0.0, .y = 1.5, .z = 6.0 },
        .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .{ .x = 0.0, .y = 1.0, .z = 0.0 },
    );
    const view_proj = view.mul(proj);
    const rxm = rowmath.Mat4.makeRotation(state.rx, .{ .x = 1.0, .y = 0.0, .z = 0.0 });
    const rym = rowmath.Mat4.makeRotation(state.ry, .{ .x = 0.0, .y = 1.0, .z = 0.0 });
    const model = rxm.mul(rym);
    state.vs_params.mvp = model.mul(view_proj).m;

    // render the single shape
    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sokol.glue.swapchain(),
    });
    sg.applyPipeline(state.pip);
    sg.applyBindings(state.bind);
    sg.applyUniforms(shd.UB_vs_params, sg.asRange(&state.vs_params));
    sg.draw(state.elms.base_element, state.elms.num_elements, 1);

    // render help text and finish frame
    // sokol.debugtext.draw();
    dbgui.draw();
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
    dbgui.event(ev);
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
        .event_cb = input,
        .width = 800,
        .height = 600,
        .sample_count = 4,
        .window_title = "shapes-transform-sapp.c",
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = sokol.log.func },
    });
}
