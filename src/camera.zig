const rowmath = @import("rowmath.zig");
const Vec3 = rowmath.Vec3;
const Quat = rowmath.Quat;
const Mat4 = rowmath.Mat4;
const InputState = @import("input_state.zig").InputState;

pub const Camera = struct {
    yfov: f32 = 0,
    near_clip: f32 = 0.01,
    far_clip: f32 = 50.0,
    position: Vec3 = .{ .x = 0, .y = 0, .z = 0 },
    pitch: f32 = 0,
    yaw: f32 = 0,
    input_state: InputState = .{},
    view: Mat4 = Mat4.identity(),
    projection: Mat4 = Mat4.identity(),

    pub fn update_projection_matrix(self: *@This()) void {
        self.projection = Mat4.persp(
            60.0,
            self.input_state.aspect(),
            self.near_clip,
            self.far_clip,
        );
    }

    pub fn update_view_matrix(self: *@This()) void {
        const yaw = Quat.axisAngle(.{ .x = 0, .y = 1, .z = 0 }, self.yaw);
        const pitch = Quat.axisAngle(.{ .x = 1, .y = 0, .z = 0 }, self.pitch);
        const rot = pitch.mul(yaw).matrix();
        self.view = rot.mul(Mat4.translate(self.position.negate()));
    }

    pub fn update(self: *@This(), input_state: InputState) void {
        if (input_state.mouse_right) {
            const dx = input_state.mouse_x - self.input_state.mouse_x;
            const dy = input_state.mouse_y - self.input_state.mouse_y;
            self.yaw += dx * 0.01;
            self.pitch += dy * 0.01;
        }
        if (input_state.mouse_wheel > 0) {
            self.position.z *= 0.9;
        } else if (input_state.mouse_wheel < 0) {
            self.position.z *= 1.1;
        }
        self.input_state = input_state;

        self.update_view_matrix();
        self.update_projection_matrix();
    }
};
