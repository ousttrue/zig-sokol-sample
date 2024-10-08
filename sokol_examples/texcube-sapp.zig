//------------------------------------------------------------------------------
//  texcube-sapp.c
//  Texture creation, rendering with texture, packed vertex components.
//------------------------------------------------------------------------------
const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const rowmath = @import("rowmath");
const dbgui = @import("dbgui");
const shader = @import("texcube-sapp.glsl.zig");

const state = struct {
    var rx: f32 = 0;
    var ry: f32 = 0;
    var pass_action = sg.PassAction{};
    var pip = sg.Pipeline{};
    var bind = sg.Bindings{};
};

const Vertex = struct {
    x: f32,
    y: f32,
    z: f32,
    color: u32,
    u: u16,
    v: u16,
};

export fn init() void {
    sg.setup(.{
        .environment = sokol.glue.environment(),
        .logger = .{ .func = sokol.log.func },
    });
    dbgui.setup(sokol.app.sampleCount());

    // Cube vertex buffer with packed vertex formats for color and texture coords.
    // Note that a vertex format which must be portable across all
    // backends must only use the normalized integer formats
    // (BYTE4N, UBYTE4N, SHORT2N, SHORT4N), which can be converted
    // to floating point formats in the vertex shader inputs.
    //
    // The reason is that D3D11 cannot convert from non-normalized
    // formats to floating point inputs (only to integer inputs),
    // and WebGL2 / GLES2 don't support integer vertex shader inputs.
    const vertices = [_]Vertex{
        .{ .x = -1.0, .y = -1.0, .z = -1.0, .color = 0xFF0000FF, .u = 0, .v = 0 },
        .{ .x = 1.0, .y = -1.0, .z = -1.0, .color = 0xFF0000FF, .u = 32767, .v = 0 },
        .{ .x = 1.0, .y = 1.0, .z = -1.0, .color = 0xFF0000FF, .u = 32767, .v = 32767 },
        .{ .x = -1.0, .y = 1.0, .z = -1.0, .color = 0xFF0000FF, .u = 0, .v = 32767 },
        .{ .x = -1.0, .y = -1.0, .z = 1.0, .color = 0xFF00FF00, .u = 0, .v = 0 },
        .{ .x = 1.0, .y = -1.0, .z = 1.0, .color = 0xFF00FF00, .u = 32767, .v = 0 },
        .{ .x = 1.0, .y = 1.0, .z = 1.0, .color = 0xFF00FF00, .u = 32767, .v = 32767 },
        .{ .x = -1.0, .y = 1.0, .z = 1.0, .color = 0xFF00FF00, .u = 0, .v = 32767 },
        .{ .x = -1.0, .y = -1.0, .z = -1.0, .color = 0xFFFF0000, .u = 0, .v = 0 },
        .{ .x = -1.0, .y = 1.0, .z = -1.0, .color = 0xFFFF0000, .u = 32767, .v = 0 },
        .{ .x = -1.0, .y = 1.0, .z = 1.0, .color = 0xFFFF0000, .u = 32767, .v = 32767 },
        .{ .x = -1.0, .y = -1.0, .z = 1.0, .color = 0xFFFF0000, .u = 0, .v = 32767 },
        .{ .x = 1.0, .y = -1.0, .z = -1.0, .color = 0xFFFF007F, .u = 0, .v = 0 },
        .{ .x = 1.0, .y = 1.0, .z = -1.0, .color = 0xFFFF007F, .u = 32767, .v = 0 },
        .{ .x = 1.0, .y = 1.0, .z = 1.0, .color = 0xFFFF007F, .u = 32767, .v = 32767 },
        .{ .x = 1.0, .y = -1.0, .z = 1.0, .color = 0xFFFF007F, .u = 0, .v = 32767 },
        .{ .x = -1.0, .y = -1.0, .z = -1.0, .color = 0xFFFF7F00, .u = 0, .v = 0 },
        .{ .x = -1.0, .y = -1.0, .z = 1.0, .color = 0xFFFF7F00, .u = 32767, .v = 0 },
        .{ .x = 1.0, .y = -1.0, .z = 1.0, .color = 0xFFFF7F00, .u = 32767, .v = 32767 },
        .{ .x = 1.0, .y = -1.0, .z = -1.0, .color = 0xFFFF7F00, .u = 0, .v = 32767 },
        .{ .x = -1.0, .y = 1.0, .z = -1.0, .color = 0xFF007FFF, .u = 0, .v = 0 },
        .{ .x = -1.0, .y = 1.0, .z = 1.0, .color = 0xFF007FFF, .u = 32767, .v = 0 },
        .{ .x = 1.0, .y = 1.0, .z = 1.0, .color = 0xFF007FFF, .u = 32767, .v = 32767 },
        .{ .x = 1.0, .y = 1.0, .z = -1.0, .color = 0xFF007FFF, .u = 0, .v = 32767 },
    };
    state.bind.vertex_buffers[0] = sg.makeBuffer(.{
        .data = sg.asRange(&vertices),
        .label = "texcube-vertices",
    });

    // create an index buffer for the cube
    const indices = [_]u16{
        0,  1,  2,  0,  2,  3,
        6,  5,  4,  7,  6,  4,
        8,  9,  10, 8,  10, 11,
        14, 13, 12, 15, 14, 12,
        16, 17, 18, 16, 18, 19,
        22, 21, 20, 23, 22, 20,
    };
    state.bind.index_buffer = sg.makeBuffer(.{
        .type = .INDEXBUFFER,
        .data = sg.asRange(&indices),
        .label = "texcube-indices",
    });

    // create a checkerboard texture
    const pixels = [4 * 4]u32{
        0xFFFFFFFF, 0xFF000000, 0xFFFFFFFF, 0xFF000000,
        0xFF000000, 0xFFFFFFFF, 0xFF000000, 0xFFFFFFFF,
        0xFFFFFFFF, 0xFF000000, 0xFFFFFFFF, 0xFF000000,
        0xFF000000, 0xFFFFFFFF, 0xFF000000, 0xFFFFFFFF,
    };
    // NOTE: SLOT_tex is provided by shader code generation
    var img_desc = sg.ImageDesc{
        .width = 4,
        .height = 4,
        .label = "texcube-texture",
    };
    img_desc.data.subimage[0][0] = sg.asRange(&pixels);
    state.bind.fs.images[shader.SLOT_tex] = sg.makeImage(img_desc);

    // create a sampler object with default attributes
    state.bind.fs.samplers[shader.SLOT_smp] = sg.makeSampler(.{
        .label = "texcube-sampler",
    });

    // a shader
    const shd = sg.makeShader(shader.texcubeShaderDesc(sg.queryBackend()));

    // a pipeline state object
    var pip_desc = sg.PipelineDesc{
        .shader = shd,
        .index_type = .UINT16,
        .cull_mode = .BACK,
        .depth = .{ .compare = .LESS_EQUAL, .write_enabled = true },
        .label = "texcube-pipeline",
    };
    pip_desc.layout.attrs[shader.ATTR_vs_pos].format = .FLOAT3;
    pip_desc.layout.attrs[shader.ATTR_vs_color0].format = .UBYTE4N;
    pip_desc.layout.attrs[shader.ATTR_vs_texcoord0].format = .SHORT2N;
    state.pip = sg.makePipeline(pip_desc);

    // default pass action
    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.25, .g = 0.5, .b = 0.75, .a = 1.0 },
    };
}

export fn frame() void {
    // compute model-view-projection matrix for vertex shader
    const t: f32 = @as(f32, @floatCast(sokol.app.frameDuration())) * 60.0;
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
    state.rx += 1.0 * t;
    state.ry += 2.0 * t;
    const rxm = rowmath.Mat4.rotate(state.rx, .{ .x = 1.0, .y = 0.0, .z = 0.0 });
    const rym = rowmath.Mat4.rotate(state.ry, .{ .x = 0.0, .y = 1.0, .z = 0.0 });
    const model = rxm.mul(rym);
    var vs_params = shader.VsParams{
        .mvp = model.mul(view_proj).m,
    };

    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sokol.glue.swapchain(),
    });
    sg.applyPipeline(state.pip);
    sg.applyBindings(state.bind);
    sg.applyUniforms(.VS, shader.SLOT_vs_params, sg.asRange(&vs_params));
    sg.draw(0, 36, 1);
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
        .event_cb = dbgui.event,
        .width = 800,
        .height = 600,
        .sample_count = 4,
        .window_title = "Textured Cube (sokol-app)",
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = sokol.log.func },
        // NOTE: this is just a test for using the 'set-main-loop' method
        // in the sokol-app Emscripten backend
        .html5_use_emsc_set_main_loop = true,
    });
}
