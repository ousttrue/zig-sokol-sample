const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const rowmath = @import("rowmath.zig");
const Mat4 = rowmath.Mat4;
const Vec3 = rowmath.Vec3;
const Quat = rowmath.Quat;
const Transform = rowmath.Transform;
const shd = @import("teapot.glsl.zig");
const geometry = @import("teapot_geometry.zig");
const InputState = @import("input_state.zig").InputState;
const Camera = @import("camera.zig").Camera;
const RenderTarget = @import("camera.zig").RenderTarget;

pub const state = struct {
    var bind: sg.Bindings = .{};
    pub var xform_a = Transform{};
    pub var xform_b = Transform{};
    pub var xform_c = Transform{};
    var pip: sg.Pipeline = .{};
    var offscreen_pip: sg.Pipeline = .{};
};

pub fn setup() void {
    state.xform_a.rigid_transform.translation.x = -2;
    state.xform_b.rigid_transform.translation.x = 2;
    state.xform_c.rigid_transform.translation.z = -2;

    // cube vertex buffer
    state.bind.vertex_buffers[0] = sg.makeBuffer(.{
        .data = sg.asRange(&geometry.teapot_vertices),
    });

    // cube index buffer
    state.bind.index_buffer = sg.makeBuffer(.{
        .type = .INDEXBUFFER,
        .data = sg.asRange(&geometry.teapot_triangles),
    });

    // shader and pipeline object
    var pip_desc: sg.PipelineDesc = .{
        .shader = sg.makeShader(shd.teapotShaderDesc(sg.queryBackend())),
        .index_type = .UINT32,
        .depth = .{
            .compare = .LESS_EQUAL,
            .write_enabled = true,
        },
        .cull_mode = .FRONT,
    };
    pip_desc.layout.attrs[shd.ATTR_vs_inPosition].format = .FLOAT3;
    pip_desc.layout.attrs[shd.ATTR_vs_inNormal].format = .FLOAT3;
    state.pip = sg.makePipeline(pip_desc);

    // offscreen_pip
    pip_desc.colors[0].pixel_format = .RGBA8;
    pip_desc.sample_count = 1;
    pip_desc.depth = .{
        .pixel_format = .DEPTH,
        .compare = .LESS_EQUAL,
        .write_enabled = true,
    };
    state.offscreen_pip = sg.makePipeline(pip_desc);
}

fn mat4_to_array(m: *const Mat4) *const [16]f32 {
    return @ptrCast(m);
}

pub fn draw(camera: Camera, renderTarget: RenderTarget) void {
    const viewProj = camera.transform.worldToLocal().mul(camera.projection);

    // teapot
    switch (renderTarget) {
        .Display => sg.applyPipeline(state.pip),
        .OffScreen => sg.applyPipeline(state.offscreen_pip),
    }
    sg.applyBindings(state.bind);

    const fsParams = shd.FsParams{
        .u_diffuse = .{ 1, 1, 1 },
        .u_eye = .{
            camera.transform.translation.x,
            camera.transform.translation.y,
            camera.transform.translation.z,
        },
    };

    draw_teapot(state.xform_a, &viewProj, &fsParams);
    draw_teapot(state.xform_b, &viewProj, &fsParams);
    draw_teapot(state.xform_c, &viewProj, &fsParams);
}

fn draw_teapot(t: Transform, viewProj: *const Mat4, fsParams: *const shd.FsParams) void {
    const vsParams = shd.VsParams{
        .u_viewProj = mat4_to_array(viewProj).*,
        .u_modelMatrix = mat4_to_array(&t.matrix()).*,
    };
    sg.applyUniforms(.VS, shd.SLOT_vs_params, sg.asRange(&vsParams));
    sg.applyUniforms(.FS, shd.SLOT_fs_params, sg.asRange(fsParams));
    sg.draw(0, geometry.teapot_triangles.len, 1);
}
