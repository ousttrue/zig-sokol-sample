//------------------------------------------------------------------------------
//  offscreen-sapp.c
//  Render to a offscreen rendertarget texture without multisampling, and
//  use this texture for rendering to the display (with multisampling).
//------------------------------------------------------------------------------
const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const rowmath = @import("rowmath");
const Mat4 = rowmath.Mat4;
const dbgui = @import("dbgui");
const shader = @import("offscreen-sapp.glsl.zig");

const OFFSCREEN_PIXEL_FORMAT = sg.PixelFormat.RGBA8;
const OFFSCREEN_SAMPLE_COUNT = 1;
const DISPLAY_SAMPLE_COUNT = 4;

const state = struct {
    const offscreen = struct {
        var pass = sg.Pass{};
        var pip = sg.Pipeline{};
        var bind = sg.Bindings{};
    };
    const display = struct {
        var pass_action = sg.PassAction{};
        var pip = sg.Pipeline{};
        var bind = sg.Bindings{};
    };
    var donut = sokol.shape.ElementRange{};
    var sphere = sokol.shape.ElementRange{};
    var rx: f32 = 0;
    var ry: f32 = 0;
};

export fn init() void {
    sg.setup(.{
        .environment = sokol.glue.environment(),
        .logger = .{ .func = sokol.log.func },
    });
    dbgui.setup(sokol.app.sampleCount());

    // default pass action: clear to blue-ish
    state.display.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.25, .g = 0.45, .b = 0.65, .a = 1.0 },
    };

    // setup a render pass struct with one color and one depth render attachment image
    // NOTE: we need to explicitly set the sample count in the attachment image objects,
    // because the offscreen pass uses a different sample count than the display render pass
    // (the display render pass is multi-sampled, the offscreen pass is not)
    var img_desc = sg.ImageDesc{
        .render_target = true,
        .width = 256,
        .height = 256,
        .pixel_format = OFFSCREEN_PIXEL_FORMAT,
        .sample_count = OFFSCREEN_SAMPLE_COUNT,
        .label = "color-image",
    };
    const color_img = sg.makeImage(img_desc);
    img_desc.pixel_format = .DEPTH;
    img_desc.label = "depth-image";
    const depth_img = sg.makeImage(img_desc);
    var attachments_desc = sg.AttachmentsDesc{
        .depth_stencil = .{ .image = depth_img },
        .label = "offscreen-attachments",
    };
    attachments_desc.colors[0].image = color_img;
    state.offscreen.pass.attachments = sg.makeAttachments(attachments_desc);
    state.offscreen.pass.action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.25, .g = 0.25, .b = 0.25, .a = 1.0 },
    };
    state.offscreen.pass.label = "offscreen-pass";

    // a donut shape which is rendered into the offscreen render target, and
    // a sphere shape which is rendered into the default framebuffer
    var vertices = [1]sokol.shape.Vertex{.{}} ** 4000;
    var indices = [1]u16{0} ** 24000;
    var buf = sokol.shape.Buffer{
        .vertices = .{ .buffer = sokol.shape.asRange(&vertices) },
        .indices = .{ .buffer = sokol.shape.asRange(&indices) },
    };
    buf = sokol.shape.buildTorus(buf, .{
        .radius = 0.5,
        .ring_radius = 0.3,
        .sides = 20,
        .rings = 36,
    });
    state.donut = sokol.shape.elementRange(buf);
    buf = sokol.shape.buildSphere(buf, .{
        .radius = 0.5,
        .slices = 72,
        .stacks = 40,
    });
    state.sphere = sokol.shape.elementRange(buf);

    var vbuf_desc = sokol.shape.vertexBufferDesc(buf);
    var ibuf_desc = sokol.shape.indexBufferDesc(buf);
    vbuf_desc.label = "shape-vbuf";
    ibuf_desc.label = "shape-ibuf";
    const vbuf = sg.makeBuffer(vbuf_desc);
    const ibuf = sg.makeBuffer(ibuf_desc);

    // pipeline-state-object for offscreen-rendered donut
    // NOTE: we need to explicitly set the sample_count here because
    // the offscreen pass uses a different sample count than the default
    // pass (the display pass is multi-sampled, but the offscreen pass isn't)
    {
        var pip_desc = sg.PipelineDesc{
            .shader = sg.makeShader(shader.offscreenShaderDesc(sg.queryBackend())),
            .index_type = .UINT16,
            .cull_mode = .BACK,
            .sample_count = OFFSCREEN_SAMPLE_COUNT,
            .depth = .{
                .pixel_format = .DEPTH,
                .compare = .LESS_EQUAL,
                .write_enabled = true,
            },
            .label = "offscreen-pipeline",
        };
        pip_desc.layout.buffers[0] = sokol.shape.vertexBufferLayoutState();
        pip_desc.layout.attrs[shader.ATTR_vs_offscreen_position] = sokol.shape.positionVertexAttrState();
        pip_desc.layout.attrs[shader.ATTR_vs_offscreen_normal] = sokol.shape.normalVertexAttrState();
        pip_desc.colors[0].pixel_format = OFFSCREEN_PIXEL_FORMAT;
        state.offscreen.pip = sg.makePipeline(pip_desc);
    }

    // and another pipeline-state-object for the default pass
    {
        var pip_desc = sg.PipelineDesc{
            .shader = sg.makeShader(shader.defaultShaderDesc(sg.queryBackend())),
            .index_type = .UINT16,
            .cull_mode = .BACK,
            .depth = .{ .compare = .LESS_EQUAL, .write_enabled = true },
            .label = "default-pipeline",
        };
        pip_desc.layout.buffers[0] = sokol.shape.vertexBufferLayoutState();
        pip_desc.layout.attrs[shader.ATTR_vs_default_position] = sokol.shape.positionVertexAttrState();
        pip_desc.layout.attrs[shader.ATTR_vs_default_normal] = sokol.shape.normalVertexAttrState();
        pip_desc.layout.attrs[shader.ATTR_vs_default_texcoord0] = sokol.shape.texcoordVertexAttrState();
        state.display.pip = sg.makePipeline(pip_desc);
    }

    // a sampler object for sampling the render target texture
    const smp = sg.makeSampler(.{
        .min_filter = .LINEAR,
        .mag_filter = .LINEAR,
        .wrap_u = .REPEAT,
        .wrap_v = .REPEAT,
    });

    // the resource bindings for rendering a non-textured shape into offscreen render target
    state.offscreen.bind.vertex_buffers[0] = vbuf;
    state.offscreen.bind.index_buffer = ibuf;

    // resource bindings to render a textured shape, using the offscreen render target as texture
    state.display.bind.vertex_buffers[0] = vbuf;
    state.display.bind.index_buffer = ibuf;
    state.display.bind.fs.images[shader.SLOT_tex] = color_img;
    state.display.bind.fs.samplers[shader.SLOT_smp] = smp;
}

// helper function to compute model-view-projection matrix
fn compute_mvp(rx: f32, ry: f32, aspect: f32, eye_dist: f32) Mat4 {
    const proj = Mat4.makePerspective(std.math.degreesToRadians(45.0), aspect, 0.01, 10.0);
    const view = Mat4.makeLookAt(
        .{ .x = 0.0, .y = 0.0, .z = eye_dist },
        .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .{ .x = 0.0, .y = 1.0, .z = 0.0 },
    );
    const view_proj = view.mul(proj);
    const rxm = Mat4.rotate(rx, .{ .x = 1.0, .y = 0.0, .z = 0.0 });
    const rym = Mat4.rotate(ry, .{ .x = 0.0, .y = 1.0, .z = 0.0 });
    const model = rym.mul(rxm);
    const mvp = model.mul(view_proj);
    return mvp;
}

export fn frame() void {
    const t: f32 = (@as(f32, @floatCast(sokol.app.frameDuration())) * 60.0);
    state.rx += 1.0 * t;
    state.ry += 2.0 * t;
    // the offscreen pass, rendering an rotating, untextured donut into a render target image
    {
        const vs_params = shader.VsParams{
            .mvp = compute_mvp(state.rx, state.ry, 1.0, 2.5).m,
        };
        sg.beginPass(state.offscreen.pass);
        sg.applyPipeline(state.offscreen.pip);
        sg.applyBindings(state.offscreen.bind);
        sg.applyUniforms(.VS, shader.SLOT_vs_params, sg.asRange(&vs_params));
        sg.draw(state.donut.base_element, state.donut.num_elements, 1);
        sg.endPass();
    }

    {
        // and the display-pass, rendering a rotating textured sphere which uses the
        // previously rendered offscreen render-target as texture
        const w = sokol.app.widthf();
        const h = sokol.app.heightf();
        const vs_params = shader.VsParams{
            .mvp = compute_mvp(-state.rx * 0.25, state.ry * 0.25, w / h, 2.0).m,
        };
        sg.beginPass(.{
            .action = state.display.pass_action,
            .swapchain = sokol.glue.swapchain(),
            .label = "swapchain-pass",
        });
        sg.applyPipeline(state.display.pip);
        sg.applyBindings(state.display.bind);
        sg.applyUniforms(.VS, shader.SLOT_vs_params, sg.asRange(&vs_params));
        sg.draw(state.sphere.base_element, state.sphere.num_elements, 1);
        dbgui.draw();
        sg.endPass();
    }

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
        .width = 800,
        .height = 600,
        .sample_count = DISPLAY_SAMPLE_COUNT,
        .window_title = "Offscreen Rendering (sokol-app)",
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = sokol.log.func },
    });
}
