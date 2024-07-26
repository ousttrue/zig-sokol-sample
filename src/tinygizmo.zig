const std = @import("std");
const rowmath = @import("rowmath.zig");
const Vec2 = rowmath.Vec2;
const Vec3 = rowmath.Vec3;
const Vec4 = rowmath.Vec4;
const Quat = rowmath.Quat;
const Mat4 = rowmath.Mat4;
const Transform = rowmath.Transform;
const Ray = @import("camera.zig").Ray;
const TAU = 6.28318530718;

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

pub const CameraParameters = struct {
    yfov: f32 = 0,
    near_clip: f32 = 0,
    far_clip: f32 = 0,
    position: Vec3 = .{ .x = 0, .y = 0, .z = 0 },
    orientation: Quat = Quat.indentity,
};

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
};

const Renderable = struct {
    mesh: MeshComponent,
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

const Drag = struct {
    mode: InteractionMode = .None,
    // Offset from position of grabbed object to coordinates of clicked point
    click_offset: Vec3 = .{ .x = 0, .y = 0, .z = 0 },
};

const Interaction = struct {
    // Flag to indicate if the gizmo is being hovered
    hover: InteractionMode = .None,
    // Original position of an object being manipulated with a gizmo
    original_position: Vec3 = .{ .x = 0, .y = 0, .z = 0 },
    // Original orientation of an object being manipulated with a gizmo
    original_orientation: Quat = .{ .x = 0, .y = 0, .z = 0, .w = 1 },
    // Original scale of an object being manipulated with a gizmo
    original_scale: Vec3 = .{ .x = 0, .y = 0, .z = 0 },
    // Currently active component
    active: ?Drag = null,
};

const GeometryVertex = struct {
    position: Vec3 = .{ .x = 0, .y = 0, .z = 0 },
    normal: Vec3 = .{ .x = 0, .y = 0, .z = 0 },
    color: Vec4 = .{ .x = 0, .y = 0, .z = 0, .w = 0 },
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

const Mat32 = struct {
    row0: Vec3,
    row1: Vec3,
    fn mul(a: @This(), b: Vec2) Vec3 {
        return a.row0.scale(b.x).add(a.row1.scale(b.y));
    }
};

fn make_const_mesh(_vertices: anytype, _triangles: anytype) type {
    return struct {
        const vertices = _vertices;
        const triangles = _triangles;
    };
}

fn make_lathed_geometry(
    comptime axis: Vec3,
    comptime arm1: Vec3,
    comptime arm2: Vec3,
    comptime slices: i32,
    comptime points: []const Vec2,
    comptime eps: f32,
) type {
    var vertices = [1]GeometryVertex{.{}} ** ((slices + 1) * points.len);
    var triangles = [1][3]u16{.{ 0, 0, 0 }} ** (slices * (points.len - 1) * 6);
    var v_index: usize = 0;
    var t_index: usize = 0;

    @setEvalBranchQuota(2000);
    for (0..slices + 1) |i| {
        const angle = (@as(f32, @floatFromInt(i % slices)) * TAU / slices) + (TAU / 8.0);
        const c = std.math.cos(angle);
        const s = std.math.sin(angle);
        const mat = Mat32{ .row0 = axis, .row1 = arm1.scale(c).add(arm2.scale(s)) };
        for (points) |p| {
            vertices[v_index].position = mat.mul(p).add(.{ .x = eps, .y = eps, .z = eps });
            v_index += 1;
        }

        if (i > 0) {
            for (1..points.len) |j| {
                const index0: u16 = @intCast((i - 1) * (points.len) + (j - 1));
                const index1: u16 = @intCast((i - 0) * (points.len) + (j - 1));
                const index2: u16 = @intCast((i - 0) * (points.len) + (j - 0));
                const index3: u16 = @intCast((i - 1) * (points.len) + (j - 0));
                triangles[t_index] = .{ index0, index1, index2 };
                t_index += 1;
                triangles[t_index] = .{ index0, index2, index3 };
                t_index += 1;
            }
        }
    }

    compute_normals(&vertices, &triangles);

    return make_const_mesh(vertices, triangles);
}

fn compute_normals(vertices: []GeometryVertex, triangles: []const [3]u16) void {
    const NORMAL_EPSILON = 0.0001;
    @setEvalBranchQuota(100000);

    var uniqueVertIndices = [1]u16{0} ** vertices.len;
    for (0..vertices.len) |i| {
        if (uniqueVertIndices[i] == 0) {
            uniqueVertIndices[i] = i + 1;
            const v0 = vertices[i].position;
            for (i..vertices.len) |j| {
                const v1 = vertices[j].position;
                if (v1.sub(v0).len2() < NORMAL_EPSILON) {
                    uniqueVertIndices[j] = uniqueVertIndices[i];
                }
            }
        }
    }

    // uint32_t idx0, idx1, idx2;
    for (triangles) |t| {
        const idx0 = uniqueVertIndices[t[0]] - 1;
        const idx1 = uniqueVertIndices[t[1]] - 1;
        const idx2 = uniqueVertIndices[t[2]] - 1;
        var v0 = vertices[idx0];
        var v1 = vertices[idx1];
        var v2 = vertices[idx2];
        const n = v1.position.sub(v0.position).cross(v2.position.sub(v0.position));
        v0.normal =v0.normal.add( n);
        v1.normal =v1.normal.add( n);
        v2.normal =v2.normal.add( n);
    }

    for (0..vertices.len) |i| {
        vertices[i].normal = vertices[uniqueVertIndices[i] - 1].normal;
    }
    for (vertices) |*v| {
        v.normal = v.normal.norm();
    }
}

fn make_box_geometry(a: Vec3, b: Vec3) type {
    // geometry_mesh mesh;
    const vertices = [_]GeometryVertex{
        .{ .position = .{ .x = a.x, .y = a.y, .z = a.z }, .normal = .{ .x = -1, .y = 0, .z = 0 } },
        .{ .position = .{ .x = a.x, .y = a.y, .z = b.z }, .normal = .{ .x = -1, .y = 0, .z = 0 } },
        .{ .position = .{ .x = a.x, .y = b.y, .z = b.z }, .normal = .{ .x = -1, .y = 0, .z = 0 } },
        .{ .position = .{ .x = a.x, .y = b.y, .z = a.z }, .normal = .{ .x = -1, .y = 0, .z = 0 } },
        .{ .position = .{ .x = b.x, .y = a.y, .z = a.z }, .normal = .{ .x = 1, .y = 0, .z = 0 } },
        .{ .position = .{ .x = b.x, .y = b.y, .z = a.z }, .normal = .{ .x = 1, .y = 0, .z = 0 } },
        .{ .position = .{ .x = b.x, .y = b.y, .z = b.z }, .normal = .{ .x = 1, .y = 0, .z = 0 } },
        .{ .position = .{ .x = b.x, .y = a.y, .z = b.z }, .normal = .{ .x = 1, .y = 0, .z = 0 } },
        .{ .position = .{ .x = a.x, .y = a.y, .z = a.z }, .normal = .{ .x = 0, .y = -1, .z = 0 } },
        .{ .position = .{ .x = b.x, .y = a.y, .z = a.z }, .normal = .{ .x = 0, .y = -1, .z = 0 } },
        .{ .position = .{ .x = b.x, .y = a.y, .z = b.z }, .normal = .{ .x = 0, .y = -1, .z = 0 } },
        .{ .position = .{ .x = a.x, .y = a.y, .z = b.z }, .normal = .{ .x = 0, .y = -1, .z = 0 } },
        .{ .position = .{ .x = a.x, .y = b.y, .z = a.z }, .normal = .{ .x = 0, .y = 1, .z = 0 } },
        .{ .position = .{ .x = a.x, .y = b.y, .z = b.z }, .normal = .{ .x = 0, .y = 1, .z = 0 } },
        .{ .position = .{ .x = b.x, .y = b.y, .z = b.z }, .normal = .{ .x = 0, .y = 1, .z = 0 } },
        .{ .position = .{ .x = b.x, .y = b.y, .z = a.z }, .normal = .{ .x = 0, .y = 1, .z = 0 } },
        .{ .position = .{ .x = a.x, .y = a.y, .z = a.z }, .normal = .{ .x = 0, .y = 0, .z = -1 } },
        .{ .position = .{ .x = a.x, .y = b.y, .z = a.z }, .normal = .{ .x = 0, .y = 0, .z = -1 } },
        .{ .position = .{ .x = b.x, .y = b.y, .z = a.z }, .normal = .{ .x = 0, .y = 0, .z = -1 } },
        .{ .position = .{ .x = b.x, .y = a.y, .z = a.z }, .normal = .{ .x = 0, .y = 0, .z = -1 } },
        .{ .position = .{ .x = a.x, .y = a.y, .z = b.z }, .normal = .{ .x = 0, .y = 0, .z = 1 } },
        .{ .position = .{ .x = b.x, .y = a.y, .z = b.z }, .normal = .{ .x = 0, .y = 0, .z = 1 } },
        .{ .position = .{ .x = b.x, .y = b.y, .z = b.z }, .normal = .{ .x = 0, .y = 0, .z = 1 } },
        .{ .position = .{ .x = a.x, .y = b.y, .z = b.z }, .normal = .{ .x = 0, .y = 0, .z = 1 } },
    };
    const triangles = [_][3]u16{
        .{ 0, 1, 2 },    .{ 0, 2, 3 },    .{ 4, 5, 6 },    .{ 4, 6, 7 },    .{ 8, 9, 10 },
        .{ 8, 10, 11 },  .{ 12, 13, 14 }, .{ 12, 14, 15 }, .{ 16, 17, 18 }, .{ 16, 18, 19 },
        .{ 20, 21, 22 }, .{ 20, 22, 23 },
    };

    return make_const_mesh(vertices, triangles);
}

const GeometryMesh = struct {
    vertices: []const GeometryVertex,
    triangles: []const [3]u16,

    fn intersect(self: @This(), ray: Ray) ?f32 {
        var best_t = std.math.inf(f32);
        for (self.triangles) |a| {
            const triangle = Triangle{
                .v0 = self.vertices[a[0]].position,
                .v1 = self.vertices[a[1]].position,
                .v2 = self.vertices[a[2]].position,
            };
            if (triangle.intersect(ray)) |t| {
                if (t < best_t) {
                    best_t = t;
                }
            }
        }
        return if (best_t == std.math.inf(f32)) null else best_t;
    }
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

const MeshComponent = struct {
    mesh: GeometryMesh,
    base_color: Vec4,

    fn init(mesh: type, base_color: Vec4) @This() {
        return .{
            .mesh = .{
                .vertices = &mesh.vertices,
                .triangles = &mesh.triangles,
            },
            .base_color = base_color,
        };
    }

    const translate_x = MeshComponent.init(
        make_lathed_geometry(RIGHT, UP, FORWARD, 16, &ARROW_POINTS, 0),
        BASE_RED,
    );
    const translate_y = MeshComponent.init(
        make_lathed_geometry(UP, FORWARD, RIGHT, 16, &ARROW_POINTS, 0),
        BASE_GREEN,
    );
    const translate_z = MeshComponent.init(
        make_lathed_geometry(FORWARD, RIGHT, UP, 16, &ARROW_POINTS, 0),
        BASE_BLUE,
    );
    const translate_yz = MeshComponent.init(
        make_box_geometry(
            .{ .x = -0.01, .y = 0.25, .z = 0.25 },
            .{ .x = 0.01, .y = 0.75, .z = 0.75 },
        ),
        BASE_CYAN,
    );
    const translate_zx = MeshComponent.init(
        make_box_geometry(
            .{ .x = 0.25, .y = -0.01, .z = 0.25 },
            .{ .x = 0.75, .y = 0.01, .z = 0.75 },
        ),
        BASE_MAGENTA,
    );
    const translate_xy = MeshComponent.init(
        make_box_geometry(
            .{ .x = 0.25, .y = 0.25, .z = -0.01 },
            .{ .x = 0.75, .y = 0.75, .z = 0.01 },
        ),
        BASE_YELLOW,
    );
    const translate_xyz = MeshComponent.init(
        make_box_geometry(
            .{ .x = -0.05, .y = -0.05, .z = -0.05 },
            .{ .x = 0.05, .y = 0.05, .z = 0.05 },
        ),
        BASE_GRAY,
    );

    const rotate_x = MeshComponent.init(
        make_lathed_geometry(RIGHT, UP, FORWARD, 32, &RING_POINTS, 0.003),
        BASE_RED,
    );
    const rotate_y = MeshComponent.init(
        make_lathed_geometry(UP, FORWARD, RIGHT, 32, &RING_POINTS, -0.003),
        BASE_GREEN,
    );
    const rotate_z = MeshComponent.init(
        make_lathed_geometry(FORWARD, RIGHT, UP, 32, &RING_POINTS, 0),
        BASE_BLUE,
    );

    const scale_x = MeshComponent.init(
        make_lathed_geometry(RIGHT, UP, FORWARD, 16, &MACE_POINTS, 0),
        BASE_RED,
    );
    const scale_y = MeshComponent.init(
        make_lathed_geometry(UP, FORWARD, RIGHT, 16, &MACE_POINTS, 0),
        BASE_GREEN,
    );
    const scale_z = MeshComponent.init(
        make_lathed_geometry(FORWARD, RIGHT, UP, 16, &MACE_POINTS, 0),
        BASE_BLUE,
    );

    fn get(i: InteractionMode) ?MeshComponent {
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
};

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
    fn scale_screenspace(self: @This(), position: rowmath.Vec3, pixel_scale: f32) f32 {
        const dist = position.sub(self.active_state.ray.origin).len();
        return std.math.tan(self.active_state.cam_yFov) * dist * (pixel_scale / self.active_state.viewport_size.y);
    }

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
        const draw_scale = if (self.active_state.screenspace_scale > 0.0) self.scale_screenspace(p.rigid_transform.translation, self.active_state.screenspace_scale) else 1.0;
        const id = hash_fnv1a(name);
        var g = self.get_or_add(id);

        {
            var updated_state: InteractionMode = .None;
            var local_ray = detransform(p, self.active_state.ray);
            local_ray.descale(draw_scale);

            var best_t = std.math.inf(f32);

            if (MeshComponent.translate_x.mesh.intersect(local_ray)) |t| {
                if (t < best_t) {
                    updated_state = .Translate_x;
                    best_t = t;
                }
            }
            if (MeshComponent.translate_y.mesh.intersect(local_ray)) |t| {
                if (t < best_t) {
                    updated_state = .Translate_y;
                    best_t = t;
                }
            }
            if (MeshComponent.translate_z.mesh.intersect(local_ray)) |t| {
                if (t < best_t) {
                    updated_state = .Translate_z;
                    best_t = t;
                }
            }
            if (MeshComponent.translate_yz.mesh.intersect(local_ray)) |t| {
                if (t < best_t) {
                    updated_state = .Translate_yz;
                    best_t = t;
                }
            }
            if (MeshComponent.translate_zx.mesh.intersect(local_ray)) |t| {
                if (t < best_t) {
                    updated_state = .Translate_zx;
                    best_t = t;
                }
            }
            if (MeshComponent.translate_xy.mesh.intersect(local_ray)) |t| {
                if (t < best_t) {
                    updated_state = .Translate_xy;
                    best_t = t;
                }
            }
            if (MeshComponent.translate_xyz.mesh.intersect(local_ray)) |t| {
                if (t < best_t) {
                    updated_state = .Translate_xyz;
                    best_t = t;
                }
            }

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

            if (g.active) |active| {
                if (self.active_state.mouse_left) {
                    var position = p.rigid_transform.translation.add(active.click_offset);
                    if (switch (active.mode) {
                        .Translate_x => self.axis_translation_dragger(g, axes[0], position),
                        .Translate_y => self.axis_translation_dragger(g, axes[1], position),
                        .Translate_z => self.axis_translation_dragger(g, axes[2], position),
                        .Translate_yz => self.plane_translation_dragger(g, axes[0], position),
                        .Translate_zx => self.plane_translation_dragger(g, axes[1], position),
                        .Translate_xy => self.plane_translation_dragger(g, axes[2], position),
                        .Translate_xyz => self.plane_translation_dragger(
                            g,
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
                if (MeshComponent.get(i)) |c| {
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
    }

    fn plane_translation_dragger(self: @This(), interaction: *Interaction, plane_normal: Vec3, point: Vec3) ?Vec3 {
        // Mouse clicked
        if (self.has_clicked) {
            interaction.original_position = point;
        }

        // Define the plane to contain the original position of the object
        const plane_point = interaction.original_position;

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

    fn axis_translation_dragger(self: @This(), interaction: *Interaction, axis: Vec3, point: Vec3) ?Vec3 {
        // First apply a plane translation dragger with a plane that contains the desired axis and is oriented to face the camera
        const plane_tangent = axis.cross(point.sub(self.active_state.ray.origin));
        const plane_normal = axis.cross(plane_tangent);
        const new_point = self.plane_translation_dragger(interaction, plane_normal, point) orelse {
            return null;
        };
        // Constrain object motion to be along the desired axis
        const delta = new_point.sub(interaction.original_position);
        return interaction.original_position.add(axis.scale(delta.dot(axis)));
    }

    pub fn rotation(self: *@This(), name: []const u8, _p: *Transform) !void {
        std.debug.assert(_p.rigid_transform.rotation.length2() > 1e-6);

        const p = Transform.trs(
            _p.rigid_transform.translation,
            if (self.local_toggle) _p.rigid_transform.rotation else Quat.identity,
            Vec3.one,
        );
        // Orientation is local by default
        const draw_scale = if (self.active_state.screenspace_scale > 0.0) self.scale_screenspace(p.rigid_transform.translation, self.active_state.screenspace_scale) else 1.0;
        const id = hash_fnv1a(name);
        const g = self.get_or_add(id);

        var updated_state: InteractionMode = .None;

        var local_ray = detransform(p, self.active_state.ray);
        local_ray.descale(draw_scale);
        var best_t = std.math.inf(f32);

        if (MeshComponent.rotate_x.mesh.intersect(local_ray)) |t| {
            if (t < best_t) {
                updated_state = .Rotate_x;
                best_t = t;
            }
        }
        if (MeshComponent.rotate_y.mesh.intersect(local_ray)) |t| {
            if (t < best_t) {
                updated_state = .Rotate_y;
                best_t = t;
            }
        }
        if (MeshComponent.rotate_z.mesh.intersect(local_ray)) |t| {
            if (t < best_t) {
                updated_state = .Rotate_z;
                best_t = t;
            }
        }

        if (self.has_clicked) {
            g.active = null;
            if (updated_state != .None) {
                //             transform(draw_scale, ray);
                //             g.gizmos[id].original_position = center;
                //             g.gizmos[id].original_orientation = orientation;
                //             g.gizmos[id].click_offset = p.transform_point(ray.origin + ray.direction * t);
                //             g.gizmos[id].active = true;
            }
        }

        // float3 activeAxis;
        // if (g.gizmos[id].active)
        // {
        //     const float4 starting_orientation = g.local_toggle ? g.gizmos[id].original_orientation : float4(0, 0, 0, 1);
        //     switch (g.gizmos[id].interaction_mode)
        //     {
        //     case interact::rotate_x: axis_rotation_dragger(id, g, { 1, 0, 0 }, center, starting_orientation, p.orientation); activeAxis = { 1, 0, 0 }; break;
        //     case interact::rotate_y: axis_rotation_dragger(id, g, { 0, 1, 0 }, center, starting_orientation, p.orientation); activeAxis = { 0, 1, 0 }; break;
        //     case interact::rotate_z: axis_rotation_dragger(id, g, { 0, 0, 1 }, center, starting_orientation, p.orientation); activeAxis = { 0, 0, 1 }; break;
        //     }
        // }

        if (self.has_released) {
            g.active = null;
        }

        const scaleMatrix = Mat4.scale(.{
            .x = draw_scale,
            .y = draw_scale,
            .z = draw_scale,
        });
        const modelMatrix = p.matrix().mul(scaleMatrix);

        // std::vector<interact> draw_interactions;
        // if (!g.local_toggle && g.gizmos[id].interaction_mode != interact::none) draw_interactions = { g.gizmos[id].interaction_mode };
        // else draw_interactions = { interact::rotate_x, interact::rotate_y, interact::rotate_z };

        for ([_]InteractionMode{ .Rotate_x, .Rotate_y, .Rotate_z }) |i| {
            if (MeshComponent.get(i)) |c| {
                try self.drawlist.append(.{
                    .mesh = c,
                    .matrix = modelMatrix,
                    .hover = i == updated_state,
                    .active = false,
                });
            }
        }

        // // For non-local transformations, we only present one rotation ring
        // // and draw an arrow from the center of the gizmo to indicate the degree of rotation
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
    }

    pub fn scale(self: *@This(), name: []const u8, _p: *rowmath.Transform) !void {
        const p = Transform.trs(
            _p.rigid_transform.translation,
            _p.rigid_transform.rotation,
            Vec3.one,
        );
        const draw_scale = if (self.active_state.screenspace_scale > 0.0) self.scale_screenspace(p.rigid_transform.translation, self.active_state.screenspace_scale) else 1.0;
        const id = hash_fnv1a(name);
        const g = self.get_or_add(id);
        _ = g;

        // if (g.has_clicked) g.gizmos[id].interaction_mode = interact::none;
        //
        // {
        var updated_state: InteractionMode = .None;
        var local_ray = detransform(p, self.active_state.ray);
        local_ray.descale(draw_scale);

        var best_t = std.math.inf(f32);
        if (MeshComponent.scale_x.mesh.intersect(local_ray)) |t| {
            if (t < best_t) {
                updated_state = .Scale_x;
                best_t = t;
            }
        }
        if (MeshComponent.scale_y.mesh.intersect(local_ray)) |t| {
            if (t < best_t) {
                updated_state = .Scale_y;
                best_t = t;
            }
        }
        if (MeshComponent.scale_z.mesh.intersect(local_ray)) |t| {
            if (t < best_t) {
                updated_state = .Scale_z;
                best_t = t;
            }
        }

        //     if (g.has_clicked)
        //     {
        //         g.gizmos[id].interaction_mode = updated_state;
        //         if (g.gizmos[id].interaction_mode != interact::none)
        //         {
        //             transform(draw_scale, ray);
        //             g.gizmos[id].original_scale = scale;
        //             g.gizmos[id].click_offset = p.transform_point(ray.origin + ray.direction*t);
        //             g.gizmos[id].active = true;
        //         }
        //         else g.gizmos[id].active = false;
        //     }
        // }
        //
        // if (g.has_released)
        // {
        //     g.gizmos[id].interaction_mode = interact::none;
        //     g.gizmos[id].active = false;
        // }
        //
        // if (g.gizmos[id].active)
        // {
        //     switch (g.gizmos[id].interaction_mode)
        //     {
        //     case interact::scale_x: axis_scale_dragger(id, g, { 1,0,0 }, center, scale, g.active_state.hotkey_ctrl); break;
        //     case interact::scale_y: axis_scale_dragger(id, g, { 0,1,0 }, center, scale, g.active_state.hotkey_ctrl); break;
        //     case interact::scale_z: axis_scale_dragger(id, g, { 0,0,1 }, center, scale, g.active_state.hotkey_ctrl); break;
        //     }
        // }

        const scaleMatrix = Mat4.scale_uniform(draw_scale);
        const modelMatrix = p.matrix().mul(scaleMatrix);
        for ([_]InteractionMode{ .Scale_x, .Scale_y, .Scale_z }) |i| {
            if (MeshComponent.get(i)) |c| {
                try self.drawlist.append(.{
                    .mesh = c,
                    .matrix = modelMatrix,
                    .hover = i == updated_state,
                    .active = false,
                });
            }
        }
    }
};
