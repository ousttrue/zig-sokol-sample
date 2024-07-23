const std = @import("std");
const rowmath = @import("rowmath.zig");
const Vec2 = rowmath.Vec2;
const Vec3 = rowmath.Vec3;
const Vec4 = rowmath.Vec4;
const Quat = rowmath.Quat;
const Mat4 = rowmath.Mat4;

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

pub const Ray = struct {
    origin: Vec3,
    direction: Vec3,

    fn point(self: @This(), t: f32) Vec3 {
        return self.origin.add(self.direction.scale(t));
    }

    fn transform(self: *@This(), scale: f32) void {
        self.origin = self.origin.scale(scale);
        self.direction = self.direction.scale(scale);
    }

    fn detransform(self: *@This(), scale: f32) void {
        self.origin = .{
            .x = self.origin.x / scale,
            .y = self.origin.y / scale,
            .z = self.origin.z / scale,
        };
        self.direction = .{
            .x = self.direction.x / scale,
            .y = self.direction.y / scale,
            .z = self.direction.z / scale,
        };
    }
};

pub const CameraParameters = struct {
    yfov: f32 = 0,
    near_clip: f32 = 0,
    far_clip: f32 = 0,
    position: Vec3 = .{ .x = 0, .y = 0, .z = 0 },
    orientation: Quat = Quat.indentity,
};

pub const ApplicationState = struct {
    mouse_left: bool = false,
    hotkey_translate: bool = false,
    hotkey_rotate: bool = false,
    hotkey_scale: bool = false,
    hotkey_local: bool = false,
    hotkey_ctrl: bool = false,
    // If > 0.f, the gizmos are drawn scale-invariant with a screenspace value defined here
    screenspace_scale: f32 = 0,
    // World-scale units used for snapping translation
    snap_translation: f32 = 0,
    // World-scale units used for snapping scale
    snap_scale: f32 = 0,
    // Radians used for snapping rotation quaternions (i.e. PI/8 or PI/16)
    snap_rotation: f32 = 0,
    // 3d viewport used to render the view
    viewport_size: Vec2 = .{ .x = 0, .y = 0 },
    // world-space ray origin (i.e. the camera position)
    ray_origin: Vec3 = .{ .x = 0, .y = 0, .z = 0 },
    // world-space ray direction
    ray_direction: Vec3 = .{ .x = 0, .y = 0, .z = 0 },
    // Used for constructing inverse view projection for raycasting onto gizmo geometry
    cam: CameraParameters = .{},
};

pub const TransformMode = enum { Translate, Rotate, Scale };

const Renderable = struct {
    mesh: GeometryMesh,
    color: Vec4,
};

// 32 bit Fowler–Noll–Vo Hash
const fnv1aBase32: u32 = 0x811C9DC5;
const fnv1aPrime32: u32 = 0x01000193;
fn hash_fnv1a(str: []const u8) u32 {
    var result = fnv1aBase32;
    for (str) |ch| {
        result ^= @as(u32, ch);
        result *= fnv1aPrime32;
    }
    return result;
}

fn detransform(p: rowmath.Transform, r: Ray) Ray {
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

const Interaction = struct {
    // Flag to indicate if the gizmo is being actively manipulated
    active: bool = false,
    // Flag to indicate if the gizmo is being hovered
    hover: bool = false,
    // Original position of an object being manipulated with a gizmo
    original_position: Vec3 = .{},
    // Original orientation of an object being manipulated with a gizmo
    original_orientation: Quat = .{},
    // Original scale of an object being manipulated with a gizmo
    original_scale: Vec3 = .{},
    // Offset from position of grabbed object to coordinates of clicked point
    click_offset: Vec3 = .{},
    // Currently active component
    mode: InteractionMode,
};

const GeometryVertex = struct {
    position: Vec3,
    normal: Vec3,
    color: Vec4,
};

const Triangle = struct {
    v0: Vec3,
    v1: Vec3,
    v2: Vec3,

    fn intersect(self: @This(), ray: Ray) ?f32 {
        const e1 = self.v1.sub(self.v0);
        const e2 = self.v2.sub(self.v0);
        const h = ray.direction.cross(e2);
        const a = e1.dot(h);
        if (@abs(a) == 0) {
            return null;
        }

        const f = 1 / a;
        const s = ray.origin.sub(self.v0);
        const u = f * s.dot(h);
        if (u < 0 or u > 1) {
            return null;
        }

        const q = s.cross(e1);
        const v = f * ray.direction.dot(q);
        if (v < 0 or u + v > 1) {
            return null;
        }

        const t = f * e2.dot(q);
        if (t < 0) {
            return null;
        }

        return t;
    }
};

const GeometryMesh = struct {
    vertices: std.ArrayList(GeometryVertex),
    triangles: std.ArrayList([3]u16),
    fn intersect(self: @This(), ray: Ray) f32 {
        var best_t = std.math.inf(f32);
        for (self.triangles.items) |a| {
            const triangle = Triangle{
                .v0 = self.vertices.items[a[0]].position,
                .v1 = self.vertices.items[a[1]].position,
                .v2 = self.vertices.items[a[2]].position,
            };
            if (triangle.intersect(ray)) |t| {
                if (t < best_t) {
                    best_t = t;
                }
            }
        }
        return best_t;
    }
};

const MeshComponent = struct {
    mesh: GeometryMesh,
    base_color: Vec4,
    highlight_color: Vec4,
};

pub const Context = struct {
    mesh_components: std.AutoHashMap(InteractionMode, MeshComponent),
    transform_mode: TransformMode = .Translate,
    // std::map<uint32_t, interaction_state> gizmos;
    gizmos: std.AutoHashMap(u32, Interaction),
    active_state: ApplicationState = .{},
    last_state: ApplicationState = .{},
    // State to describe if the gizmo should use transform-local math
    local_toggle: bool = true,
    // State to describe if the user has pressed the left mouse button during the last frame
    has_clicked: bool = false,
    // State to describe if the user has released the left mouse button during the last frame
    has_released: bool = false,
    mode: TransformMode = .Translate,
    drawlist: std.ArrayList(Renderable),

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .mesh_components = std.AutoHashMap(InteractionMode, MeshComponent).init(allocator),
            .gizmos = std.AutoHashMap(u32, Interaction).init(allocator),
            .drawlist = std.ArrayList(Renderable).init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.mesh_components.deinit();
        self.gizmos.deinit();
        self.drawlist.deinit();
    }

    pub fn update(self: *@This(), state: ApplicationState) void {
        self.active_state = state;
        self.local_toggle = if (!self.last_state.hotkey_local and self.active_state.hotkey_local and self.active_state.hotkey_ctrl) !self.local_toggle else self.local_toggle;
        self.has_clicked = !self.last_state.mouse_left and self.active_state.mouse_left;
        self.has_released = self.last_state.mouse_left and !self.active_state.mouse_left;
        self.drawlist.clearRetainingCapacity();
    }

    pub fn transform(self: *@This(), name: []const u8, t: *rowmath.Transform) !void {
        if (self.active_state.hotkey_ctrl) {
            if (!self.last_state.hotkey_translate and self.active_state.hotkey_translate) {
                self.mode = .Translate;
            } else if (!self.last_state.hotkey_rotate and self.active_state.hotkey_rotate) {
                self.mode = .Rotate;
            } else if (!self.last_state.hotkey_scale and self.active_state.hotkey_scale) {
                self.mode = .Scale;
            }
        }

        switch (self.mode) {
            .Translate => try self.translation_gizmo(name, t),
            .Rotate => self.rotation_gizmo(name, t),
            .Scale => self.scale_gizmo(name, t),
        }
    }

    // This will calculate a scale constant based on the number of screenspace pixels passed as pixel_scale.
    fn scale_screenspace(self: @This(), position: rowmath.Vec3, pixel_scale: f32) f32 {
        const dist = position.sub(self.active_state.cam.position).len();
        return std.math.tan(self.active_state.cam.yfov) * dist * (pixel_scale / self.active_state.viewport_size.y);
    }

    // The only purpose of this is readability: to reduce the total column width of the intersect(...) statements in every gizmo
    fn intersect(self: @This(), ray: Ray, i: InteractionMode, best_t: f32) ?f32 {
        if (self.mesh_components.getPtr(i)) |c| {
            const t = c.mesh.intersect(ray);
            if (t < best_t) {
                return t;
            }
        }
        return null;
    }

    fn translation_gizmo(
        self: *@This(),
        name: []const u8,
        _p: *rowmath.Transform,
    ) !void {
        const p = rowmath.Transform.trs(
            _p.rigid_transform.translation,
            if (self.local_toggle) _p.rigid_transform.rotation else Quat.indentity,
            Vec3.one,
        );
        const draw_scale = if (self.active_state.screenspace_scale > 0.0) self.scale_screenspace(p.rigid_transform.translation, self.active_state.screenspace_scale) else 1.0;
        const id = hash_fnv1a(name);

        // interaction_mode will only change on clicked
        if (self.has_clicked) {
            if (self.gizmos.getPtr(id)) |i| {
                i.mode = .None;
            }
        }

        {
            var updated_state: InteractionMode = .None;
            var ray = detransform(p, .{
                .origin = self.active_state.ray_origin,
                .direction = self.active_state.ray_direction,
            });
            ray.detransform(draw_scale);

            var best_t = std.math.inf(f32);
            if (self.intersect(ray, .Translate_x, best_t)) |t| {
                updated_state = .Translate_x;
                best_t = t;
            }
            if (self.intersect(ray, .Translate_y, best_t)) |t| {
                updated_state = .Translate_y;
                best_t = t;
            }
            if (self.intersect(ray, .Translate_z, best_t)) |t| {
                updated_state = .Translate_z;
                best_t = t;
            }
            if (self.intersect(ray, .Translate_yz, best_t)) |t| {
                updated_state = .Translate_yz;
                best_t = t;
            }
            if (self.intersect(ray, .Translate_zx, best_t)) |t| {
                updated_state = .Translate_zx;
                best_t = t;
            }
            if (self.intersect(ray, .Translate_xy, best_t)) |t| {
                updated_state = .Translate_xy;
                best_t = t;
            }
            if (self.intersect(ray, .Translate_xyz, best_t)) |t| {
                updated_state = .Translate_xyz;
                best_t = t;
            }

            if (self.has_clicked) {
                if (self.gizmos.getPtr(id)) |g| {
                    g.mode = updated_state;

                    if (g.mode != .None) {
                        ray.transform(draw_scale);
                        if (self.local_toggle) {
                            g.click_offset = p.transform_vector(ray.point(best_t));
                        } else {
                            g.click_offset = ray.point(best_t);
                        }
                        g.active = true;
                    } else {
                        g.active = false;
                    }
                }
            }

            if (self.gizmos.getPtr(id)) |g| {
                g.hover = !(best_t == std.math.inf(f32));
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

            var position = _p.rigid_transform.translation;
            if (self.gizmos.getPtr(id)) |g| {
                if (g.active) {
                    position = position.add(g.click_offset);
                    if (switch (g.mode) {
                        .Translate_x => self.axis_translation_dragger(g, axes[0], position),
                        .Translate_y => self.axis_translation_dragger(g, axes[1], position),
                        .Translate_z => self.axis_translation_dragger(g, axes[2], position),
                        .Translate_yz => self.plane_translation_dragger(g, axes[0], position),
                        .Translate_zx => self.plane_translation_dragger(g, axes[1], position),
                        .Translate_xy => self.plane_translation_dragger(g, axes[2], position),
                        .Translate_xyz => self.plane_translation_dragger(
                            g,
                            self.active_state.cam.orientation.dirZ().negate(),
                            position,
                        ),
                        else => unreachable,
                    }) |new_position| {
                        position = new_position;
                    }
                    position = position.sub(g.click_offset);
                }

                if (self.has_released) {
                    g.mode = .None;
                    g.active = false;
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
                    if (self.mesh_components.getPtr(i)) |c| {
                        const r = Renderable{
                            .mesh = c.mesh,
                            // .color = if (c == g.mode) c.base_color else c.highlight_color,
                            .color = c.base_color,
                        };
                        for (r.mesh.vertices.items) |*v| {
                            // transform local coordinates into worldspace
                            v.position = modelMatrix.transform_coord(v.position);
                            v.normal = modelMatrix.transform_vector(v.normal);
                        }
                        try self.drawlist.append(r);
                    }
                }
            }
        }
    }

    fn plane_translation_dragger(self: @This(), interaction: *Interaction, plane_normal: Vec3, point: Vec3) ?Vec3 {
        // Mouse clicked
        if (self.has_clicked) {
            interaction.original_position = point;
        }

        std.debug.assert(self.active_state.mouse_left);
        // Define the plane to contain the original position of the object
        const plane_point = interaction.original_position;
        const ray = Ray{
            .origin = self.active_state.ray_origin,
            .direction = self.active_state.ray_direction,
        };

        // If an intersection exists between the ray and the plane, place the object at that point
        const denom = ray.direction.dot(plane_normal);
        if (@abs(denom) == 0) {
            return null;
        }

        const t = plane_point.sub(ray.origin).dot(plane_normal) / denom;
        if (t < 0) {
            return null;
        }

        var result = ray.point(t);
        if (snap(result, self.active_state.snap_translation)) |new_position| {
            result = new_position;
        }
        return result;
    }

    fn axis_translation_dragger(self: @This(), interaction: *Interaction, axis: Vec3, point: Vec3) ?Vec3 {
        // First apply a plane translation dragger with a plane that contains the desired axis and is oriented to face the camera
        const plane_tangent = axis.cross(point.sub(self.active_state.cam.position));
        const plane_normal = axis.cross(plane_tangent);
        const new_point = self.plane_translation_dragger(interaction, plane_normal, point) orelse {
            return null;
        };
        // Constrain object motion to be along the desired axis
        const delta = new_point.sub(interaction.original_position);
        return interaction.original_position.add(axis.scale(delta.dot(axis)));
    }

    fn rotation_gizmo(_: @This(), name: []const u8, t: *rowmath.Transform) void {
        _ = t; // autofix
        _ = name; // autofix
    }

    fn scale_gizmo(_: @This(), name: []const u8, t: *rowmath.Transform) void {
        _ = t; // autofix
        _ = name; // autofix
    }
};
