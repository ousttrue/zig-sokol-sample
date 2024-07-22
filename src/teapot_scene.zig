const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const rowmath = @import("rowmath.zig");
const Mat4 = rowmath.Mat4;
const Vec3 = rowmath.Vec3;
const Quat = rowmath.Quat;
const shd = @import("teapot.glsl.zig");
const geometry = @import("teapot_geometry.zig");
const InputState = @import("input_state.zig").InputState;
const Camera = @import("camera.zig").Camera;
const linegeom = @import("linegeom.zig");

const RigidTransform = struct {
    // rigid_transform() {}
    // rigid_transform(const minalg::float4 & orientation, const minalg::float3 & position, const minalg::float3 & scale) : orientation(orientation), position(position), scale(scale) {}
    // rigid_transform(const minalg::float4 & orientation, const minalg::float3 & position, float scale) : orientation(orientation), position(position), scale(scale) {}
    // rigid_transform(const minalg::float4 & orientation, const minalg::float3 & position) : orientation(orientation), position(position) {}

    position: Vec3 = .{ .x = 0, .y = 0, .z = 0 },
    orientation: Quat = .{ .x = 0, .y = 0, .z = 0, .w = 1 },
    scale: Vec3 = .{ .x = 1, .y = 1, .z = 1 },

    // bool                uniform_scale() const { return scale.x == scale.y && scale.x == scale.z; }
    fn matrix(self: @This()) Mat4 {
        return Mat4.trs(self.position, self.orientation, self.scale);
    }
    // minalg::float3      transform_vector(const minalg::float3 & vec) const { return qrot(orientation, vec * scale); }
    // minalg::float3      transform_point(const minalg::float3 & p) const { return position + transform_vector(p); }
    // minalg::float3      detransform_point(const minalg::float3 & p) const { return detransform_vector(p - position); }
    // minalg::float3      detransform_vector(const minalg::float3 & vec) const { return qrot(qinv(orientation), vec) / scale; }
};

const state = struct {
    var pip: sg.Pipeline = .{};
    var bind: sg.Bindings = .{};
    var xform_a = RigidTransform{};
    var xform_b = RigidTransform{};
};

pub fn setup() void {
    state.xform_a.position.x = -2;
    state.xform_b.position.x = 2;

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
}

fn mat4_to_array(m: *const Mat4) *const [16]f32 {
    return @ptrCast(m);
}

pub fn draw(camera: Camera) void {
    const viewProj = camera.view.mul(camera.projection);

    // grid
    linegeom.begin(camera);
    linegeom.grid();
    linegeom.end();

    // teapot
    sg.applyPipeline(state.pip);
    sg.applyBindings(state.bind);

    const fsParams = shd.FsParams{
        .u_diffuse = .{ 1, 1, 1 },
        .u_eye = .{
            camera.position.x,
            camera.position.y,
            camera.position.z,
        },
    };

    {
        const vsParams = shd.VsParams{
            .u_viewProj = mat4_to_array(&viewProj).*,
            .u_modelMatrix = mat4_to_array(&state.xform_a.matrix()).*,
        };
        sg.applyUniforms(.VS, shd.SLOT_vs_params, sg.asRange(&vsParams));
        sg.applyUniforms(.FS, shd.SLOT_fs_params, sg.asRange(&fsParams));
        sg.draw(0, geometry.teapot_triangles.len, 1);
    }

    {
        const vsParams = shd.VsParams{
            .u_viewProj = mat4_to_array(&viewProj).*,
            .u_modelMatrix = mat4_to_array(&state.xform_b.matrix()).*,
        };
        sg.applyUniforms(.VS, shd.SLOT_vs_params, sg.asRange(&vsParams));
        sg.applyUniforms(.FS, shd.SLOT_fs_params, sg.asRange(&fsParams));
        sg.draw(0, geometry.teapot_triangles.len, 1);
    }
}
