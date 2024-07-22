const std = @import("std");
const rowmath = @import("rowmath.zig");
const Vec3 = rowmath.Vec3;
const Quat = rowmath.Quat;
const Mat4 = rowmath.Mat4;
const RigidTransform = rowmath.RigidTransform;
const InputState = @import("input_state.zig").InputState;

pub const RenderTarget = enum {
    Display,
    OffScreen,
};

pub const Camera = struct {
    // mouse
    input_state: InputState = .{},

    // projection
    yFov: f32 = std.math.degreesToRadians(60.0),
    near_clip: f32 = 0.01,
    far_clip: f32 = 50.0,
    projection: Mat4 = Mat4.identity(),

    // transform
    pitch: f32 = 0,
    yaw: f32 = 0,
    shift: Vec3 = .{
        .x = 0,
        .y = 2,
        .z = 10,
    },
    transform: RigidTransform = .{},

    pub fn update_projection_matrix(self: *@This()) void {
        self.projection = Mat4.persp(
            std.math.radiansToDegrees(self.yFov),
            self.input_state.aspect(),
            self.near_clip,
            self.far_clip,
        );
    }

    pub fn update_transform(self: *@This()) void {
        const yaw = Quat.axisAngle(.{ .x = 0, .y = 1, .z = 0 }, self.yaw);
        const pitch = Quat.axisAngle(.{ .x = 1, .y = 0, .z = 0 }, self.pitch);
        self.transform.rotation = yaw.mul(pitch); //.matrix();
        const m = Mat4.translate(self.shift).mul(self.transform.rotation.matrix());
        self.transform.translation.x = m.m[12];
        self.transform.translation.y = m.m[13];
        self.transform.translation.z = m.m[14];
    }

    pub fn update(self: *@This(), input_state: InputState) void {
        const dx = input_state.mouse_x - self.input_state.mouse_x;
        const dy = input_state.mouse_y - self.input_state.mouse_y;
        self.input_state = input_state;
        const t = std.math.tan(self.yFov / 2);
        if (input_state.mouse_right) {
            self.yaw -= std.math.degreesToRadians(dx * t);
            self.pitch -= std.math.degreesToRadians(dy * t);
        }
        if (input_state.mouse_middle) {
            self.shift.x -= dx / input_state.screen_height * self.shift.z * t;
            self.shift.y += dy / input_state.screen_height * self.shift.z * t;
        }
        if (input_state.mouse_wheel > 0) {
            self.shift.z *= 0.9;
        } else if (input_state.mouse_wheel < 0) {
            self.shift.z *= 1.1;
        }
        self.update_projection_matrix();
        self.update_transform();
    }
};
