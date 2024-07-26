const std = @import("std");
const rowmath = @import("rowmath");
const Vec2 = rowmath.Vec2;
const Vec3 = rowmath.Vec3;
const Vec4 = rowmath.Vec4;
const Quat = rowmath.Quat;
const Mat4 = rowmath.Mat4;
const Ray = rowmath.Ray;
const Transform = rowmath.Transform;
const geometry = @import("geometry.zig");

const translate_x = geometry.MeshComponent.init(
    geometry.make_lathed_geometry(RIGHT, UP, FORWARD, 16, &ARROW_POINTS, 0),
    BASE_RED,
);
const translate_y = geometry.MeshComponent.init(
    geometry.make_lathed_geometry(UP, FORWARD, RIGHT, 16, &ARROW_POINTS, 0),
    BASE_GREEN,
);
const translate_z = geometry.MeshComponent.init(
    geometry.make_lathed_geometry(FORWARD, RIGHT, UP, 16, &ARROW_POINTS, 0),
    BASE_BLUE,
);
const translate_yz = geometry.MeshComponent.init(
    geometry.make_box_geometry(
        .{ .x = -0.01, .y = 0.25, .z = 0.25 },
        .{ .x = 0.01, .y = 0.75, .z = 0.75 },
    ),
    BASE_CYAN,
);
const translate_zx = geometry.MeshComponent.init(
    geometry.make_box_geometry(
        .{ .x = 0.25, .y = -0.01, .z = 0.25 },
        .{ .x = 0.75, .y = 0.01, .z = 0.75 },
    ),
    BASE_MAGENTA,
);
const translate_xy = geometry.MeshComponent.init(
    geometry.make_box_geometry(
        .{ .x = 0.25, .y = 0.25, .z = -0.01 },
        .{ .x = 0.75, .y = 0.75, .z = 0.01 },
    ),
    BASE_YELLOW,
);
const translate_xyz = geometry.MeshComponent.init(
    geometry.make_box_geometry(
        .{ .x = -0.05, .y = -0.05, .z = -0.05 },
        .{ .x = 0.05, .y = 0.05, .z = 0.05 },
    ),
    BASE_GRAY,
);

const rotate_x = geometry.MeshComponent.init(
    geometry.make_lathed_geometry(RIGHT, UP, FORWARD, 32, &RING_POINTS, 0.003),
    BASE_RED,
);
const rotate_y = geometry.MeshComponent.init(
    geometry.make_lathed_geometry(UP, FORWARD, RIGHT, 32, &RING_POINTS, -0.003),
    BASE_GREEN,
);
const rotate_z = geometry.MeshComponent.init(
    geometry.make_lathed_geometry(FORWARD, RIGHT, UP, 32, &RING_POINTS, 0),
    BASE_BLUE,
);

const scale_x = geometry.MeshComponent.init(
    geometry.make_lathed_geometry(RIGHT, UP, FORWARD, 16, &MACE_POINTS, 0),
    BASE_RED,
);
const scale_y = geometry.MeshComponent.init(
    geometry.make_lathed_geometry(UP, FORWARD, RIGHT, 16, &MACE_POINTS, 0),
    BASE_GREEN,
);
const scale_z = geometry.MeshComponent.init(
    geometry.make_lathed_geometry(FORWARD, RIGHT, UP, 16, &MACE_POINTS, 0),
    BASE_BLUE,
);

fn get(i: InteractionMode) ?geometry.MeshComponent {
    return switch (i) {
        .None => null,
        .Translate_x => translate_x,
        .Translate_y => translate_y,
        .Translate_z => translate_z,
        .Translate_yz => translate_yz,
        .Translate_zx => translate_zx,
        .Translate_xy => translate_xy,
        .Translate_xyz => translate_xyz,
        .Rotate_x => rotate_x,
        .Rotate_y => rotate_y,
        .Rotate_z => rotate_z,
        .Scale_x => scale_x,
        .Scale_y => scale_y,
        .Scale_z => scale_z,
        .Scale_xyz => null,
    };
}

fn snap(value: Vec3, f: f32) ?Vec3 {
    if (f > 0.0) {
        return .{
            .x = std.math.floor(value.x / f) * f,
            .y = std.math.floor(value.y / f) * f,
            .z = std.math.floor(value.z / f) * f,
        };
    }
    return null;
}

pub const ApplicationState = struct {
    // 3d viewport used to render the view
    viewport_size: Vec2,
    // Used for constructing inverse view projection for raycasting onto gizmo geometry
    cam_dir: Vec3 = .{ .x = 0, .y = 0, .z = 0 },
    cam_yFov: f32 = 0,
    // world-space ray (from camera position to mouse cursor)
    ray: Ray = .{
        .origin = .{ .x = 0, .y = 0, .z = 0 },
        .direction = .{ .x = 0, .y = 0, .z = 0 },
    },
    // mouse
    mouse_left: bool = false,
    // If > 0.f, the gizmos are drawn scale-invariant with a screenspace value defined here
    screenspace_scale: f32 = 0,
    // World-scale units used for snapping translation
    snap_translation: f32 = 0,
    // World-scale units used for snapping scale
    snap_scale: f32 = 0,
    // Radians used for snapping rotation quaternions (i.e. PI/8 or PI/16)
    snap_rotation: f32 = 0,

    fn scale_screenspace(self: @This(), position: rowmath.Vec3, pixel_scale: f32) f32 {
        const dist = position.sub(self.ray.origin).len();
        return std.math.tan(self.cam_yFov) * dist * (pixel_scale / self.viewport_size.y);
    }

    fn draw_scale(self: @This(), p: Transform) f32 {
        if (self.screenspace_scale > 0.0) {
            return self.scale_screenspace(
                p.rigid_transform.translation,
                self.screenspace_scale,
            );
        } else {
            return 1.0;
        }
    }

    fn local_ray(self: @This(), p: Transform) struct { Ray, f32 } {
        return .{
            detransform(p, self.ray),
            self.draw_scale(p),
        };
    }
};

const Renderable = struct {
    mesh: geometry.MeshComponent,
    matrix: Mat4,
    hover: bool,
    active: bool,

    pub fn color(self: @This()) Vec4 {
        if (self.hover) {
            return .{
                .x = std.math.lerp(self.mesh.base_color.x, 1, 0.5),
                .y = std.math.lerp(self.mesh.base_color.y, 1, 0.5),
                .z = std.math.lerp(self.mesh.base_color.z, 1, 0.5),
                .w = std.math.lerp(self.mesh.base_color.w, 1, 0.5),
            };
        } else {
            return self.mesh.base_color;
        }
    }
};

// 32 bit Fowler–Noll–Vo Hash
const fnv1aBase32: u32 = 0x811C9DC5;
const fnv1aPrime32: u32 = 0x01000193;
fn hash_fnv1a(str: []const u8) u32 {
    var result = fnv1aBase32;
    for (str) |ch| {
        result ^= @as(u32, ch);
        result *%= fnv1aPrime32;
    }
    return result;
}

fn detransform(p: Transform, r: Ray) Ray {
    return .{
        .origin = p.detransform_point(r.origin),
        .direction = p.detransform_vector(r.direction),
    };
}

const InteractionMode = enum {
    None,
    Translate_x,
    Translate_y,
    Translate_z,
    Translate_yz,
    Translate_zx,
    Translate_xy,
    Translate_xyz,
    Rotate_x,
    Rotate_y,
    Rotate_z,
    Scale_x,
    Scale_y,
    Scale_z,
    Scale_xyz,
};

fn flush_to_zero(f: Vec3) Vec3 {
    return .{
        .x = if (@abs(f.x) < 0.02) 0 else f.x,
        .y = if (@abs(f.y) < 0.02) 0 else f.y,
        .z = if (@abs(f.z) < 0.02) 0 else f.z,
    };
}

const Drag = struct {
    mode: InteractionMode = .None,
    // Offset from position of grabbed object to coordinates of clicked point
    click_offset: Vec3 = .{ .x = 0, .y = 0, .z = 0 },
    // Original position of an object being manipulated with a gizmo
    original_position: Vec3 = .{ .x = 0, .y = 0, .z = 0 },
    // Original orientation of an object being manipulated with a gizmo
    original_orientation: Quat = .{ .x = 0, .y = 0, .z = 0, .w = 1 },
    // Original scale of an object being manipulated with a gizmo
    original_scale: Vec3 = .{ .x = 0, .y = 0, .z = 0 },

    fn axis_rotation_dragger(
        self: @This(),
        mouse_left: bool,
        snap_rotation: f32,
        r: Ray,
        axis: Vec3,
        start_orientation: Quat,
    ) ?Quat {
        if (!mouse_left) {
            return null;
        }
        const original_pose = Transform.trs(self.original_position, start_orientation, Vec3.one);
        const the_axis = original_pose.transform_vector(axis);
        const the_plane = Vec4{
            .x = the_axis.x,
            .y = the_axis.y,
            .z = the_axis.z,
            .w = -the_axis.dot(self.click_offset),
        };

        if (intersect_ray_plane(r, the_plane)) |t| {
            const center_of_rotation = self.original_position.add(the_axis.scale(the_axis.dot(self.click_offset.sub(self.original_position))));
            const arm1 = self.click_offset.sub(center_of_rotation).norm();
            const arm2 = r.point(t).sub(center_of_rotation).norm();

            const d = arm1.dot(arm2);
            if (d > 0.999) {
                return null;
            }

            const angle = std.math.acos(d);
            if (angle < 0.001) {
                return null;
            }

            if (snap_rotation > 0) {
                const snapped = make_rotation_quat_between_vectors_snapped(arm1, arm2, snap_rotation);
                return snapped.mul(start_orientation);
            } else {
                const a = arm1.cross(arm2).norm();
                return Quat.axisAngle(a, angle).mul(start_orientation);
            }
        }

        return null;
    }

    fn axis_scale_dragger(
        self: @This(),
        mouse_left: bool,
        snap_scale: f32,
        ray: Ray,
        axis: Vec3,
        // Define the plane to contain the original position of the object
        plane_point: Vec3,
        uniform: bool,
    ) ?Vec3 {
        if (!mouse_left) {
            return null;
        }

        const plane_tangent = axis.cross(plane_point.sub(ray.origin));
        const plane_normal = axis.cross(plane_tangent);

        // If an intersection exists between the ray and the plane, place the object at that point
        const denom = ray.direction.dot(plane_normal);
        if (@abs(denom) == 0) return null;

        const t = plane_point.sub(ray.origin).dot(plane_normal) / denom;
        if (t < 0) return null;

        const distance = ray.point(t);

        var offset_on_axis = (distance.sub(self.click_offset)).mul_each(axis);
        offset_on_axis = flush_to_zero(offset_on_axis);
        var new_scale = self.original_scale.add(offset_on_axis);

        new_scale = if (uniform) Vec3.scalar(std.math.clamp(distance.dot(new_scale), 0.01, 1000.0)) else Vec3{
            .x = std.math.clamp(new_scale.x, 0.01, 1000.0),
            .y = std.math.clamp(new_scale.y, 0.01, 1000.0),
            .z = std.math.clamp(new_scale.z, 0.01, 1000.0),
        };
        if (snap_scale > 0) return snap(new_scale, snap_scale);
        return new_scale;
    }
};

const Interaction = struct {
    // Flag to indicate if the gizmo is being hovered
    hover: InteractionMode = .None,
    // Currently active component
    active: ?Drag = null,
};

const ARROW_POINTS = [_]Vec2{
    .{ .x = 0.25, .y = 0 },
    .{ .x = 0.25, .y = 0.05 },
    .{ .x = 1, .y = 0.05 },
    .{ .x = 1, .y = 0.10 },
    .{ .x = 1.2, .y = 0 },
};
const MACE_POINTS = [_]Vec2{
    .{ .x = 0.25, .y = 0 },
    .{ .x = 0.25, .y = 0.05 },
    .{ .x = 1, .y = 0.05 },
    .{ .x = 1, .y = 0.1 },
    .{ .x = 1.25, .y = 0.1 },
    .{ .x = 1.25, .y = 0 },
};
const RING_POINTS = [_]Vec2{
    .{ .x = 0.025, .y = 1 },
    .{ .x = -0.025, .y = 1 },
    .{ .x = -0.025, .y = 1 },
    .{ .x = -0.025, .y = 1.1 },
    .{ .x = -0.025, .y = 1.1 },
    .{ .x = 0.025, .y = 1.1 },
    .{ .x = 0.025, .y = 1.1 },
    .{ .x = 0.025, .y = 1 },
};

const BASE_RED: Vec4 = .{ .x = 1, .y = 0, .z = 0, .w = 1.0 };
const BASE_GREEN: Vec4 = .{ .x = 0, .y = 1, .z = 0, .w = 1.0 };
const BASE_BLUE: Vec4 = .{ .x = 0, .y = 0, .z = 1, .w = 1.0 };
const BASE_CYAN: Vec4 = .{ .x = 0, .y = 0.5, .z = 0.5, .w = 1.0 };
const BASE_MAGENTA: Vec4 = .{ .x = 0.5, .y = 0, .z = 0.5, .w = 1.0 };
const BASE_YELLOW: Vec4 = .{ .x = 0.3, .y = 0.3, .z = 0, .w = 1.0 };
const BASE_GRAY: Vec4 = .{ .x = 0.7, .y = 0.7, .z = 0.7, .w = 1.0 };

const RIGHT: Vec3 = .{ .x = 1, .y = 0, .z = 0 };
const UP: Vec3 = .{ .x = 0, .y = 1, .z = 0 };
const FORWARD: Vec3 = .{ .x = 0, .y = 0, .z = 1 };

fn intersect_ray_plane(ray: Ray, plane: Vec4) ?f32 {
    const denom = (Vec3{ .x = plane.x, .y = plane.y, .z = plane.z }).dot(ray.direction);
    if (@abs(denom) == 0) return null;
    return -plane.dot(Vec4.fromVec3(ray.origin, 1)) / denom;
}

fn make_rotation_quat_between_vectors_snapped(
    from: Vec3,
    to: Vec3,
    angle: f32,
) Quat {
    const a = from.norm();
    const b = to.norm();
    const snappedAcos = std.math.floor(std.math.acos(a.dot(b)) / angle) * angle;
    return make_rotation_quat_axis_angle(a.cross(b).norm(), snappedAcos);
}

fn make_rotation_quat_axis_angle(axis: Vec3, angle: f32) Quat {
    const s = std.math.sin(angle / 2);
    const c = std.math.cos(angle / 2);
    return .{
        .x = axis.x * s,
        .y = axis.y * s,
        .z = axis.z * s,
        .w = c,
    };
}

pub const Context = struct {
    gizmos: std.AutoHashMap(u32, Interaction),
    active_state: ApplicationState = .{ .viewport_size = .{ .x = 0, .y = 0 } },
    last_state: ApplicationState = .{ .viewport_size = .{ .x = 0, .y = 0 } },
    // State to describe if the gizmo should use transform-local math
    local_toggle: bool = true,
    // State to describe if the user has pressed the left mouse button during the last frame
    has_clicked: bool = false,
    // State to describe if the user has released the left mouse button during the last frame
    has_released: bool = false,
    drawlist: std.ArrayList(Renderable),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .gizmos = std.AutoHashMap(u32, Interaction).init(allocator),
            .drawlist = std.ArrayList(Renderable).init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.gizmos.deinit();
        self.drawlist.deinit();
    }

    pub fn update(self: *@This(), state: ApplicationState) void {
        self.last_state = self.active_state;
        self.active_state = state;
        // self.local_toggle = if (!self.last_state.hotkey_local and self.active_state.hotkey_local and self.active_state.hotkey_ctrl) !self.local_toggle else self.local_toggle;
        self.has_clicked = !self.last_state.mouse_left and self.active_state.mouse_left;
        self.has_released = self.last_state.mouse_left and !self.active_state.mouse_left;
        self.drawlist.clearRetainingCapacity();
    }

    // This will calculate a scale constant based on the number of screenspace pixels passed as pixel_scale.
    fn get_or_add(self: *@This(), id: u32) *Interaction {
        if (self.gizmos.getPtr(id)) |gizmo| {
            return gizmo;
        } else {
            self.gizmos.put(id, .{}) catch {
                @panic("get_or_add");
            };
            return self.gizmos.getPtr(id).?;
        }
    }

    pub fn translation(
        self: *@This(),
        name: []const u8,
        _p: *Transform,
    ) !void {
        var p = Transform.trs(
            _p.rigid_transform.translation,
            if (self.local_toggle) _p.rigid_transform.rotation else Quat.identity,
            Vec3.one,
        );
        var local_ray, const draw_scale = self.active_state.local_ray(p);
        local_ray.descale(draw_scale);

        var updated_state: InteractionMode = .None;

        var best_t = std.math.inf(f32);
        if (translate_x.mesh.intersect(local_ray)) |t| {
            if (t < best_t) {
                updated_state = .Translate_x;
                best_t = t;
            }
        }
        if (translate_y.mesh.intersect(local_ray)) |t| {
            if (t < best_t) {
                updated_state = .Translate_y;
                best_t = t;
            }
        }
        if (translate_z.mesh.intersect(local_ray)) |t| {
            if (t < best_t) {
                updated_state = .Translate_z;
                best_t = t;
            }
        }
        if (translate_yz.mesh.intersect(local_ray)) |t| {
            if (t < best_t) {
                updated_state = .Translate_yz;
                best_t = t;
            }
        }
        if (translate_zx.mesh.intersect(local_ray)) |t| {
            if (t < best_t) {
                updated_state = .Translate_zx;
                best_t = t;
            }
        }
        if (translate_xy.mesh.intersect(local_ray)) |t| {
            if (t < best_t) {
                updated_state = .Translate_xy;
                best_t = t;
            }
        }
        if (translate_xyz.mesh.intersect(local_ray)) |t| {
            if (t < best_t) {
                updated_state = .Translate_xyz;
                best_t = t;
            }
        }

        const id = hash_fnv1a(name);
        var g = self.get_or_add(id);
        if (self.has_clicked) {
            g.active = null;
            if (updated_state != .None) {
                local_ray.scale(draw_scale);
                const point = local_ray.point(best_t);
                const active = Drag{
                    .mode = updated_state,
                    .click_offset = if (self.local_toggle) p.transform_vector(point) else point,
                };
                g.active = active;
            }
        }

        const axes = if (self.local_toggle) [3]Vec3{
            p.rigid_transform.rotation.dirX(),
            p.rigid_transform.rotation.dirY(),
            p.rigid_transform.rotation.dirZ(),
        } else [3]Vec3{
            .{ .x = 1, .y = 0, .z = 0 },
            .{ .x = 0, .y = 1, .z = 0 },
            .{ .x = 0, .y = 0, .z = 1 },
        };

        if (g.active) |*active| {
            if (self.active_state.mouse_left) {
                var position = p.rigid_transform.translation.add(active.click_offset);
                if (switch (active.mode) {
                    .Translate_x => self.axis_translation_dragger(active, axes[0], position),
                    .Translate_y => self.axis_translation_dragger(active, axes[1], position),
                    .Translate_z => self.axis_translation_dragger(active, axes[2], position),
                    .Translate_yz => self.plane_translation_dragger(active, axes[0], position),
                    .Translate_zx => self.plane_translation_dragger(active, axes[1], position),
                    .Translate_xy => self.plane_translation_dragger(active, axes[2], position),
                    .Translate_xyz => self.plane_translation_dragger(
                        active,
                        self.active_state.cam_dir, //.orientation.dirZ().negate(),
                        position,
                    ),
                    else => @panic("switch"),
                }) |new_position| {
                    position = new_position;
                }
                p.rigid_transform.translation = position.sub(active.click_offset);
            }
        }

        if (self.has_released) {
            g.active = null;
        }

        const draw_interactions = [_]InteractionMode{
            .Translate_x,
            .Translate_y,
            .Translate_z,
            .Translate_yz,
            .Translate_zx,
            .Translate_xy,
            .Translate_xyz,
        };

        const scaleMatrix = Mat4.scale(.{
            .x = draw_scale,
            .y = draw_scale,
            .z = draw_scale,
        });
        const modelMatrix = p.matrix().mul(scaleMatrix);

        for (draw_interactions) |i| {
            if (get(i)) |c| {
                try self.drawlist.append(.{
                    .mesh = c,
                    .matrix = modelMatrix,
                    .hover = i == updated_state,
                    .active = false,
                });
            }
        }

        _p.* = p;
    }

    fn plane_translation_dragger(self: @This(), active: *Drag, plane_normal: Vec3, point: Vec3) ?Vec3 {
        // Mouse clicked
        if (self.has_clicked) {
            active.original_position = point;
        }

        // Define the plane to contain the original position of the object
        const plane_point = active.original_position;

        // If an intersection exists between the ray and the plane, place the object at that point
        const denom = self.active_state.ray.direction.dot(plane_normal);
        if (@abs(denom) == 0) {
            return null;
        }

        const t = plane_point.sub(self.active_state.ray.origin).dot(plane_normal) / denom;
        if (t < 0) {
            return null;
        }

        var result = self.active_state.ray.point(t);
        if (snap(result, self.active_state.snap_translation)) |new_position| {
            result = new_position;
        }
        return result;
    }

    fn axis_translation_dragger(self: @This(), active: *Drag, axis: Vec3, point: Vec3) ?Vec3 {
        // First apply a plane translation dragger with a plane that contains the desired axis and is oriented to face the camera
        const plane_tangent = axis.cross(point.sub(self.active_state.ray.origin));
        const plane_normal = axis.cross(plane_tangent);
        const new_point = self.plane_translation_dragger(active, plane_normal, point) orelse {
            return null;
        };
        // Constrain object motion to be along the desired axis
        const delta = new_point.sub(active.original_position);
        return active.original_position.add(axis.scale(delta.dot(axis)));
    }

    pub fn rotation(self: *@This(), name: []const u8, _p: *Transform) !void {
        std.debug.assert(_p.rigid_transform.rotation.length2() > 1e-6);

        var p = Transform.trs(
            _p.rigid_transform.translation,
            if (self.local_toggle) _p.rigid_transform.rotation else Quat.identity,
            Vec3.one,
        );
        // Orientation is local by default
        const draw_scale = self.active_state.draw_scale(p);
        const id = hash_fnv1a(name);
        const g = self.get_or_add(id);

        var updated_state: InteractionMode = .None;

        var local_ray = detransform(p, self.active_state.ray);
        local_ray.descale(draw_scale);
        var best_t = std.math.inf(f32);

        if (rotate_x.mesh.intersect(local_ray)) |t| {
            if (t < best_t) {
                updated_state = .Rotate_x;
                best_t = t;
            }
        }
        if (rotate_y.mesh.intersect(local_ray)) |t| {
            if (t < best_t) {
                updated_state = .Rotate_y;
                best_t = t;
            }
        }
        if (rotate_z.mesh.intersect(local_ray)) |t| {
            if (t < best_t) {
                updated_state = .Rotate_z;
                best_t = t;
            }
        }

        if (self.has_clicked) {
            g.active = null;
            if (updated_state != .None) {
                local_ray.scale(draw_scale);
                g.active = .{
                    .mode = updated_state,
                    .original_position = _p.rigid_transform.translation,
                    .original_orientation = _p.rigid_transform.rotation,
                    .click_offset = local_ray.point(best_t),
                };
            }
        }

        var activeAxis: Vec3 = undefined;
        if (g.active) |*active| {
            const starting_orientation = if (self.local_toggle) active.original_orientation else Quat.identity;
            switch (active.mode) {
                .Rotate_x => {
                    if (active.axis_rotation_dragger(
                        self.active_state.mouse_left,
                        self.active_state.snap_rotation,
                        self.active_state.ray,
                        RIGHT,
                        starting_orientation,
                    )) |rot| {
                        p.rigid_transform.rotation = rot;
                    }
                    activeAxis = RIGHT;
                },
                .Rotate_y => {
                    if (active.axis_rotation_dragger(
                        self.active_state.mouse_left,
                        self.active_state.snap_rotation,
                        self.active_state.ray,
                        UP,
                        starting_orientation,
                    )) |rot| {
                        p.rigid_transform.rotation = rot;
                    }
                    activeAxis = UP;
                },
                .Rotate_z => {
                    if (active.axis_rotation_dragger(
                        self.active_state.mouse_left,
                        self.active_state.snap_rotation,
                        self.active_state.ray,
                        FORWARD,
                        starting_orientation,
                    )) |rot| {
                        p.rigid_transform.rotation = rot;
                    }
                    activeAxis = FORWARD;
                },
                else => unreachable,
            }
        }

        if (self.has_released) {
            g.active = null;
        }

        const scaleMatrix = Mat4.scale(.{
            .x = draw_scale,
            .y = draw_scale,
            .z = draw_scale,
        });
        const modelMatrix = p.matrix().mul(scaleMatrix);

        if (!self.local_toggle and g.active != null) {
            // draw_interactions = { g.interaction_mode };
        } else {
            for ([_]InteractionMode{ .Rotate_x, .Rotate_y, .Rotate_z }) |i| {
                if (get(i)) |c| {
                    try self.drawlist.append(.{
                        .mesh = c,
                        .matrix = modelMatrix,
                        .hover = i == updated_state,
                        .active = false,
                    });
                }
            }
        }

        // For non-local transformations, we only present one rotation ring
        // and draw an arrow from the center of the gizmo to indicate the degree of rotation
        // if (g.local_toggle == false && g.gizmos[id].interaction_mode != interact::none)
        // {
        //     interaction_state & interaction = g.gizmos[id];
        //
        //     // Create orthonormal basis for drawing the arrow
        //     float3 a = qrot(p.orientation, interaction.click_offset - interaction.original_position);
        //     float3 zDir = normalize(activeAxis), xDir = normalize(cross(a, zDir)), yDir = cross(zDir, xDir);
        //
        //     // Ad-hoc geometry
        //     std::initializer_list<float2> arrow_points = { { 0.0f, 0.f },{ 0.0f, 0.05f },{ 0.8f, 0.05f },{ 0.9f, 0.10f },{ 1.0f, 0 } };
        //     auto geo = make_lathed_geometry(yDir, xDir, zDir, 32, arrow_points);
        //
        //     gizmo_renderable r;
        //     r.mesh = geo;
        //     r.color = float4(1);
        //     for (auto & v : r.mesh.vertices)
        //     {
        //         v.position = transform_coord(modelMatrix, v.position);
        //         v.normal = transform_vector(modelMatrix, v.normal);
        //     }
        //     g.drawlist.push_back(r);
        //
        //     orientation = qmul(p.orientation, interaction.original_orientation);
        // }
        // else if (g.local_toggle == true && g.gizmos[id].interaction_mode != interact::none) orientation = p.orientation;
        //

        _p.* = p;
    }

    pub fn scale(self: *@This(), name: []const u8, _p: *rowmath.Transform, uniform: bool) !void {
        var p = Transform.trs(
            _p.rigid_transform.translation,
            _p.rigid_transform.rotation,
            Vec3.one,
        );
        const draw_scale = self.active_state.draw_scale(p);
        const id = hash_fnv1a(name);
        const g = self.get_or_add(id);

        var updated_state: InteractionMode = .None;
        var local_ray = detransform(p, self.active_state.ray);
        local_ray.descale(draw_scale);

        var best_t = std.math.inf(f32);
        if (scale_x.mesh.intersect(local_ray)) |t| {
            if (t < best_t) {
                updated_state = .Scale_x;
                best_t = t;
            }
        }
        if (scale_y.mesh.intersect(local_ray)) |t| {
            if (t < best_t) {
                updated_state = .Scale_y;
                best_t = t;
            }
        }
        if (scale_z.mesh.intersect(local_ray)) |t| {
            if (t < best_t) {
                updated_state = .Scale_z;
                best_t = t;
            }
        }

        if (self.has_clicked) {
            g.active = null;
            if (updated_state != .None) {
                local_ray.scale(draw_scale);
                g.active = .{
                    .mode = updated_state,
                    .original_scale = _p.scale,
                    .click_offset = p.transform_point(local_ray.point(best_t)),
                };
            }
        }

        if (self.has_released) {
            g.active = null;
        }

        if (g.active) |active| {
            switch (active.mode) {
                .Scale_x => {
                    if (active.axis_scale_dragger(
                        self.active_state.mouse_left,
                        self.active_state.snap_scale,
                        self.active_state.ray,
                        RIGHT,
                        _p.rigid_transform.translation,
                        uniform,
                    )) |new_scale| {
                        _p.scale = new_scale;
                    }
                },
                .Scale_y => {
                    if (active.axis_scale_dragger(
                        self.active_state.mouse_left,
                        self.active_state.snap_scale,
                        self.active_state.ray,
                        UP,
                        _p.rigid_transform.translation,
                        uniform,
                    )) |new_scale| {
                        _p.scale = new_scale;
                    }
                },
                .Scale_z => {
                    if (active.axis_scale_dragger(
                        self.active_state.mouse_left,
                        self.active_state.snap_scale,
                        self.active_state.ray,
                        FORWARD,
                        _p.rigid_transform.translation,
                        uniform,
                    )) |new_scale| {
                        _p.scale = new_scale;
                    }
                },
                else => unreachable,
            }
        }

        const scaleMatrix = Mat4.scale_uniform(draw_scale);
        const modelMatrix = p.matrix().mul(scaleMatrix);
        for ([_]InteractionMode{ .Scale_x, .Scale_y, .Scale_z }) |i| {
            if (get(i)) |c| {
                try self.drawlist.append(.{
                    .mesh = c,
                    .matrix = modelMatrix,
                    .hover = i == updated_state,
                    .active = false,
                });
            }
        }

        // _p.* = p;
    }
};
