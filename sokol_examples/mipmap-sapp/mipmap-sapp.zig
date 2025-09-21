//------------------------------------------------------------------------------
//  https://github.com/floooh/sokol-samples/blob/master/sapp/mipmap-sapp.c
//  Demonstrate all the mipmapping filters.
//------------------------------------------------------------------------------
const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const dbgui = @import("dbgui");
const mipmap_shader = @import("mipmap-sapp.glsl.zig");
const rowmath = @import("rowmath");
const Mat4 = rowmath.Mat4;

const state = struct {
    var pip = sg.Pipeline{};
    var vbuf = sg.Buffer{};
    var tex_view = sg.View{};
    var smp: [12]sg.Sampler = undefined;
    var r: f32 = 0;
    const pixels = struct {
        var mip0: [65536]u32 = undefined; // 256x256
        var mip1: [16384]u32 = undefined; // 128x128
        var mip2: [4096]u32 = undefined; // 64*64
        var mip3: [1024]u32 = undefined; // 32*32
        var mip4: [256]u32 = undefined; // 16*16
        var mip5: [64]u32 = undefined; // 8*8
        var mip6: [16]u32 = undefined; // 4*4
        var mip7: [4]u32 = undefined; // 2*2
        var mip8: [1]u32 = undefined; // 1*2
    };
};

const mip_colors = [9]u32{
    0xFF0000FF, // red
    0xFF00FF00, // green
    0xFFFF0000, // blue
    0xFFFF00FF, // magenta
    0xFFFFFF00, // cyan
    0xFF00FFFF, // yellow
    0xFFFF00A0, // violet
    0xFFFFA0FF, // orange
    0xFFA000FF, // purple
};

export fn init() void {
    sg.setup(.{
        .environment = sokol.glue.environment(),
        .logger = .{ .func = sokol.log.func },
    });
    dbgui.setup(sokol.app.sampleCount());

    // a plane vertex buffer
    const vertices = [_]f32{
        -1.0, -1.0, 0.0, 0.0, 0.0,
        1.0,  -1.0, 0.0, 1.0, 0.0,
        -1.0, 1.0,  0.0, 0.0, 1.0,
        1.0,  1.0,  0.0, 1.0, 1.0,
    };
    state.vbuf = sg.makeBuffer(.{
        .data = sg.asRange(&vertices),
    });

    // create image with mipmap content, different colors and checkboard pattern
    var img_data = sg.ImageData{};
    var even_odd = false;
    inline for (0..9) |mip_index| {
        var ptr: [*]u32 = switch (mip_index) {
            0 => @ptrCast(&state.pixels.mip0[0]),
            1 => @ptrCast(&state.pixels.mip1[0]),
            2 => @ptrCast(&state.pixels.mip2[0]),
            3 => @ptrCast(&state.pixels.mip3[0]),
            4 => @ptrCast(&state.pixels.mip4[0]),
            5 => @ptrCast(&state.pixels.mip5[0]),
            6 => @ptrCast(&state.pixels.mip6[0]),
            7 => @ptrCast(&state.pixels.mip7[0]),
            8 => @ptrCast(&state.pixels.mip8[0]),
            else => unreachable,
        };
        const dim = 1 << (8 - mip_index);
        img_data.mip_levels[mip_index].ptr = ptr;
        img_data.mip_levels[mip_index].size = dim * dim * 4;
        for (0..dim) |_| {
            for (0..dim) |_| {
                ptr[0] = if (even_odd) mip_colors[mip_index] else 0xFF000000;
                ptr = @ptrCast(&ptr[1]);
                even_odd = !even_odd;
            }
            even_odd = !even_odd;
        }
    }
    const img = sg.makeImage(.{
        .width = 256,
        .height = 256,
        .num_mipmaps = 9,
        .pixel_format = .RGBA8,
        .data = img_data,
    });
    state.tex_view = sg.makeView(.{
        .texture = .{
            .image = img,
        },
    });

    // the first 4 samplers are just different min-filters
    var smp_desc = sg.SamplerDesc{
        .mag_filter = .LINEAR,
    };
    const filters = [2]sg.Filter{
        .NEAREST,
        .LINEAR,
    };
    const mipmap_filters = [2]sg.Filter{
        .NEAREST,
        .LINEAR,
    };
    var smp_index: usize = 0;
    for (0..2) |i| {
        for (0..2) |j| {
            smp_desc.min_filter = filters[i];
            smp_desc.mipmap_filter = mipmap_filters[j];
            state.smp[smp_index] = sg.makeSampler(smp_desc);
            smp_index += 1;
        }
    }
    // the next 4 samplers use min_lod/max_lod
    smp_desc.min_lod = 2.0;
    smp_desc.max_lod = 4.0;
    for (0..2) |i| {
        for (0..2) |j| {
            smp_desc.min_filter = filters[i];
            smp_desc.mipmap_filter = mipmap_filters[j];
            state.smp[smp_index] = sg.makeSampler(smp_desc);
            smp_index += 1;
        }
    }
    // the last 4 samplers use different anistropy levels
    smp_desc.min_lod = 0.0;
    smp_desc.max_lod = 0.0; // for max_lod, zero-initialized means "FLT_MAX"
    smp_desc.min_filter = .LINEAR;
    smp_desc.mag_filter = .LINEAR;
    smp_desc.mipmap_filter = .LINEAR;
    inline for (0..4) |i| {
        smp_desc.max_anisotropy = 1 << i;
        state.smp[smp_index] = sg.makeSampler(smp_desc);
        smp_index += 1;
    }
    std.debug.assert(smp_index == 12);

    // pipeline state
    var pip_desc = sg.PipelineDesc{
        .shader = sg.makeShader(
            mipmap_shader.mipmapShaderDesc(sg.queryBackend()),
        ),
        .primitive_type = .TRIANGLE_STRIP,
    };
    pip_desc.layout.attrs[mipmap_shader.ATTR_mipmap_pos].format = .FLOAT3;
    pip_desc.layout.attrs[mipmap_shader.ATTR_mipmap_uv0].format = .FLOAT2;
    state.pip = sg.makePipeline(pip_desc);
}

export fn frame() void {
    defer sg.commit();

    const proj = Mat4.makePerspective(
        std.math.degreesToRadians(90.0),
        sokol.app.widthf() / sokol.app.heightf(),
        0.01,
        10.0,
    );
    const view = Mat4.makeLookAt(
        .{ .x = 0.0, .y = 0.0, .z = 5.0 },
        .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .{ .x = 0.0, .y = 1.0, .z = 0.0 },
    );
    const view_proj = view.mul(proj);

    state.r += @floatCast(0.1 * 60.0 * sokol.app.frameDuration());
    const rm = Mat4.makeRotation(state.r, .{ .x = 1.0, .y = 0.0, .z = 0.0 });

    var bind = sg.Bindings{};
    bind.vertex_buffers[0] = state.vbuf;
    bind.views[mipmap_shader.VIEW_tex] = state.tex_view;
    {
        sg.beginPass(.{ .swapchain = sokol.glue.swapchain() });
        defer sg.endPass();
        sg.applyPipeline(state.pip);
        for (0..12) |i| {
            const x = (@as(f32, @floatFromInt(i & 3)) - 1.5) * 2.0;
            const y = (@as(f32, @floatFromInt(i / 4)) - 1.0) * -2.0;
            const model = rm.mul(Mat4.makeTranslation(.{ .x = x, .y = y, .z = 0.0 }));
            const vs_params = mipmap_shader.VsParams{
                .mvp = model.mul(view_proj).m,
            };

            bind.samplers[mipmap_shader.SMP_smp] = state.smp[i];
            sg.applyBindings(bind);
            sg.applyUniforms(
                mipmap_shader.UB_vs_params,
                sg.asRange(&vs_params),
            );
            sg.draw(0, 4, 1);
        }
        dbgui.draw();
    }
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
        .window_title = "mipmap-sapp.c",
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = sokol.log.func },
    });
}
