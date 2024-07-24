const std = @import("std");
const rowmath = @import("rowmath.zig");
const Vec2 = rowmath.Vec2;
const Vec3 = rowmath.Vec3;
const Quat = rowmath.Quat;
const Mat4 = rowmath.Mat4;
const RigidTransform = rowmath.RigidTransform;
const InputState = @import("input_state.zig").InputState;

pub const RenderTarget = enum {
    Display,
    OffScreen,
};

pub const Ray = struct {
    origin: Vec3,
    direction: Vec3,

    pub fn point(self: @This(), t: f32) Vec3 {
        return self.origin.add(self.direction.scale(t));
    }

    pub fn scale(self: *@This(), f: f32) void {
        self.origin = self.origin.scale(f);
        self.direction = self.direction.scale(f);
    }

    pub fn descale(self: *@This(), f: f32) void {
        self.origin = .{
            .x = self.origin.x / f,
            .y = self.origin.y / f,
            .z = self.origin.z / f,
        };
        self.direction = .{
            .x = self.direction.x / f,
            .y = self.direction.y / f,
            .z = self.direction.z / f,
        };
    }
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

    pub fn ray(self: @This(), mouse_cursor: Vec2) Ray {
        const mx = mouse_cursor.x / self.input_state.screen_width * 2 - 1;
        const my = mouse_cursor.y / self.input_state.screen_height * 2 - 1;

        const h = std.math.tan(self.yFov / 2);
        const dir = Vec3{
            .x = mx * h / self.input_state.screen_height * self.input_state.screen_width,
            .y = -my * h,
            .z = -1,
        };

        const dir_cursor = self.transform.rotation.qrot(dir.norm());
        // std.debug.print("{d:.3}, {d:.3}, {d:.3}\n", .{dir_cursor.x, dir_cursor.y, dir_cursor.z});
        return .{
            .origin = self.transform.translation,
            .direction = dir_cursor,
        };
    }
};

test "camera" {
    const cam = Camera{};
    try std.testing.expectEqual(Vec3{ .x = 1, .y = 0, .z = 0 }, cam.transform.rotation.dirX());
    try std.testing.expectEqual(Vec3{ .x = 0, .y = 1, .z = 0 }, cam.transform.rotation.dirY());
    try std.testing.expectEqual(Vec3{ .x = 0, .y = 0, .z = 1 }, cam.transform.rotation.dirZ());

    const q = Quat{ .x = 0, .y = 0, .z = 0, .w = 1 };
    const v = q.qrot(.{ .x = 1, .y = 2, .z = 3 });
    try std.testing.expectEqual(Vec3{ .x = 1, .y = 2, .z = 3 }, v);
}
