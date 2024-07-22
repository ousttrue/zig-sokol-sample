const sokol = @import("sokol");
const sg = sokol.gfx;
const vec3 = @import("math.zig").Vec3;
const mat4 = @import("math.zig").Mat4;
const quat = @import("math.zig").Quat;
const shd = @import("teapot.glsl.zig");
const geometry = @import("teapot_geometry.zig");

pub const InputState = struct {
    screen_width: f32 = 0,
    screen_height: f32 = 0,
    mouse_left: bool = false,
    mouse_right: bool = false,
    mouse_middle: bool = false,
    mouse_x: f32 = 0,
    mouse_y: f32 = 0,
    mouse_wheel: f32 = 0,
};

const Camera = struct {
    yfov: f32 = 0,
    near_clip: f32 = 0,
    far_clip: f32 = 0,
    position: vec3 = .{ .x = 0, .y = 0, .z = 0 },
    pitch: f32 = 0,
    yaw: f32 = 0,
    fn get_orientation(self: @This()) quat {
        return quat.axisAngle(.{ .x = 0, .y = 1, .z = 0 }, self.yaw).mul(quat.axisAngle(.{ .x = 1, .y = 0, .z = 0 }, self.pitch));
    }
    fn get_view_matrix(self: @This()) mat4 {
        return self.get_orientation().conj().matrix().mul(mat4.translate(self.position.negate()));
    }
    // linalg::aliases::float4x4 get_projection_matrix(const float aspectRatio) const { return linalg::perspective_matrix(yfov, aspectRatio, near_clip, far_clip); }
    // linalg::aliases::float4x4 get_viewproj_matrix(const float aspectRatio) const { return mul(get_projection_matrix(aspectRatio), get_view_matrix()); }
};

const RigidTransform = struct {
    // rigid_transform() {}
    // rigid_transform(const minalg::float4 & orientation, const minalg::float3 & position, const minalg::float3 & scale) : orientation(orientation), position(position), scale(scale) {}
    // rigid_transform(const minalg::float4 & orientation, const minalg::float3 & position, float scale) : orientation(orientation), position(position), scale(scale) {}
    // rigid_transform(const minalg::float4 & orientation, const minalg::float3 & position) : orientation(orientation), position(position) {}

    position: vec3 = vec3{ .x = 0, .y = 0, .z = 0 },
    orientation: quat = quat{ .x = 0, .y = 0, .z = 0, .w = 1 },
    scale: vec3 = vec3{ .x = 1, .y = 1, .z = 1 },

    // bool                uniform_scale() const { return scale.x == scale.y && scale.x == scale.z; }
    fn matrix(self: @This()) mat4 {
        return mat4.trs(self.position, self.orientation, self.scale);
    }
    // minalg::float3      transform_vector(const minalg::float3 & vec) const { return qrot(orientation, vec * scale); }
    // minalg::float3      transform_point(const minalg::float3 & p) const { return position + transform_vector(p); }
    // minalg::float3      detransform_point(const minalg::float3 & p) const { return detransform_vector(p - position); }
    // minalg::float3      detransform_vector(const minalg::float3 & vec) const { return qrot(qinv(orientation), vec) / scale; }
};

const state = struct {
    var pip: sg.Pipeline = .{};
    var bind: sg.Bindings = .{};
    var camera = Camera{};
    var xform_a = RigidTransform{};
    var xform_b = RigidTransform{};
    var input = InputState{};
};

pub fn setup() void {
    state.camera = .{
        .yfov = 1.0,
        .near_clip = 0.01,
        .far_clip = 32.0,
        .position = .{ .x = 0, .y = 1.5, .z = 4 },
    };

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

fn mat4_to_array(m: *const mat4) *const [16]f32 {
    return @ptrCast(m);
}

fn computeVsParams(model: mat4) shd.VsParams {
    const aspect = sokol.app.widthf() / sokol.app.heightf();
    const proj = mat4.persp(60.0, aspect, 0.01, 10.0);
    return shd.VsParams{
        .u_viewProj = mat4_to_array(&mat4.mul(proj, state.camera.get_view_matrix())).*,
        .u_modelMatrix = mat4_to_array(&model).*,
    };
}

pub fn draw(input_state: InputState) void {
    if (input_state.mouse_right) {
        const dx = input_state.mouse_x - state.input.mouse_x;
        const dy = input_state.mouse_y - state.input.mouse_y;
        state.camera.yaw -= dx * 0.01;
        state.camera.pitch -= dy * 0.01;
    }
    if (input_state.mouse_wheel > 0) {
        state.camera.position.z *= 0.9;
    } else if (input_state.mouse_wheel < 0) {
        state.camera.position.z *= 1.1;
    }
    state.input = input_state;

    sg.applyPipeline(state.pip);
    sg.applyBindings(state.bind);

    const fsParams = shd.FsParams{
        .u_diffuse = .{ 1, 1, 1 },
        .u_eye = .{
            state.camera.position.x,
            state.camera.position.y,
            state.camera.position.z,
        },
    };

    {
        const vsParams = computeVsParams(state.xform_a.matrix());
        sg.applyUniforms(.VS, shd.SLOT_vs_params, sg.asRange(&vsParams));
        sg.applyUniforms(.FS, shd.SLOT_fs_params, sg.asRange(&fsParams));
        sg.draw(0, geometry.teapot_triangles.len, 1);
    }

    {
        const vsParams = computeVsParams(state.xform_b.matrix());
        sg.applyUniforms(.VS, shd.SLOT_vs_params, sg.asRange(&vsParams));
        sg.applyUniforms(.FS, shd.SLOT_fs_params, sg.asRange(&fsParams));
        sg.draw(0, geometry.teapot_triangles.len, 1);
    }
}
