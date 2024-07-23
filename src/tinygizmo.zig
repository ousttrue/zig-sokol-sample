const std = @import("std");
const rowmath = @import("rowmath.zig");
const Vec2 = rowmath.Vec2;
const Vec3 = rowmath.Vec3;
const Quat = rowmath.Quat;

pub const Ray = struct {
    origin: Vec3,
    direction: Vec3,

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

const Renderable = struct {};

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

pub const Context = struct {
    // std::map<interact, gizmo_mesh_component> mesh_components;
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
    drawlist: std.ArrayList(Renderable), // std::vector<gizmo_renderable> ;

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .gizmos = std.AutoHashMap(u32, Interaction).init(allocator),
            .drawlist = std.ArrayList(Renderable).init(allocator),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.drawlist.deinit();
    }

    pub fn update(self: *@This(), state: ApplicationState) void {
        self.active_state = state;
        self.local_toggle = if (!self.last_state.hotkey_local and self.active_state.hotkey_local and self.active_state.hotkey_ctrl) !self.local_toggle else self.local_toggle;
        self.has_clicked = !self.last_state.mouse_left and self.active_state.mouse_left;
        self.has_released = self.last_state.mouse_left and !self.active_state.mouse_left;
        self.drawlist.clearRetainingCapacity();
    }

    pub fn transform(self: *@This(), name: []const u8, t: *rowmath.Transform) void {
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
            .Translate => self.translation_gizmo(name, t),
            .Rotate => self.rotation_gizmo(name, t),
            .Scale => self.scale_gizmo(name, t),
        }
    }

    // This will calculate a scale constant based on the number of screenspace pixels passed as pixel_scale.
    fn scale_screenspace(self: @This(), position: rowmath.Vec3, pixel_scale: f32) f32 {
        const dist = position.sub(self.active_state.cam.position).len();
        return std.math.tan(self.active_state.cam.yfov) * dist * (pixel_scale / self.active_state.viewport_size.y);
    }

    fn translation_gizmo(self: @This(), name: []const u8, t: *rowmath.Transform) void {
        const p = rowmath.Transform.trs(t.rigid_transform.translation, if (self.local_toggle) t.rigid_transform.rotation else Quat.indentity, Vec3.one);
        const draw_scale = if (self.active_state.screenspace_scale > 0.0) self.scale_screenspace(p.rigid_transform.translation, self.active_state.screenspace_scale) else 1.0;
        const id = hash_fnv1a(name);

        // interaction_mode will only change on clicked
        if (self.has_clicked) {
            if (self.gizmos.getPtr(id)) |i| {
                i.mode = .None;
            }
            // }//, .interaction_mode = .None;
        }

        {
            const updated_state: InteractionMode = .None;
            _ = updated_state; // autofix
            var ray = detransform(p, .{
                .origin = self.active_state.ray_origin,
                .direction = self.active_state.ray_direction,
            });
            ray.detransform(draw_scale);

            //        float best_t = std::numeric_limits<float>::infinity(), t;
            //        if (intersect(g, ray, interact::translate_x, t, best_t)) { updated_state = interact::translate_x;     best_t = t; }
            //        if (intersect(g, ray, interact::translate_y, t, best_t)) { updated_state = interact::translate_y;     best_t = t; }
            //        if (intersect(g, ray, interact::translate_z, t, best_t)) { updated_state = interact::translate_z;     best_t = t; }
            //        if (intersect(g, ray, interact::translate_yz, t, best_t)) { updated_state = interact::translate_yz;   best_t = t; }
            //        if (intersect(g, ray, interact::translate_zx, t, best_t)) { updated_state = interact::translate_zx;   best_t = t; }
            //        if (intersect(g, ray, interact::translate_xy, t, best_t)) { updated_state = interact::translate_xy;   best_t = t; }
            //        if (intersect(g, ray, interact::translate_xyz, t, best_t)) { updated_state = interact::translate_xyz; best_t = t; }
            //
            //        if (g.has_clicked)
            //        {
            //            g.gizmos[id].interaction_mode = updated_state;
            //
            //            if (g.gizmos[id].interaction_mode != interact::none)
            //            {
            //                transform(draw_scale, ray);
            //                g.gizmos[id].click_offset = g.local_toggle ? p.transform_vector(ray.origin + ray.direction*t) : ray.origin + ray.direction*t;
            //                g.gizmos[id].active = true;
            //            }
            //            else g.gizmos[id].active = false;
            //        }
            //
            //        g.gizmos[id].hover = (best_t == std::numeric_limits<float>::infinity()) ? false : true;
            //    }
            //
            //    std::vector<float3> axes;
            //    if (g.local_toggle) axes = { qxdir(p.orientation), qydir(p.orientation), qzdir(p.orientation) };
            //    else axes = { { 1, 0, 0 },{ 0, 1, 0 },{ 0, 0, 1 } };
            //
            //    if (g.gizmos[id].active)
            //    {
            //        position += g.gizmos[id].click_offset;
            //        switch (g.gizmos[id].interaction_mode)
            //        {
            //        case interact::translate_x: axis_translation_dragger(id, g, axes[0], position); break;
            //        case interact::translate_y: axis_translation_dragger(id, g, axes[1], position); break;
            //        case interact::translate_z: axis_translation_dragger(id, g, axes[2], position); break;
            //        case interact::translate_yz: plane_translation_dragger(id, g, axes[0], position); break;
            //        case interact::translate_zx: plane_translation_dragger(id, g, axes[1], position); break;
            //        case interact::translate_xy: plane_translation_dragger(id, g, axes[2], position); break;
            //        case interact::translate_xyz: plane_translation_dragger(id, g, -minalg::qzdir(g.active_state.cam.orientation), position); break;
            //        }
            //        position -= g.gizmos[id].click_offset;
            //    }
            //
            //    if (g.has_released)
            //    {
            //        g.gizmos[id].interaction_mode = interact::none;
            //        g.gizmos[id].active = false;
            //    }
            //
            //    std::vector<interact> draw_interactions
            //    {
            //        interact::translate_x, interact::translate_y, interact::translate_z,
            //        interact::translate_yz, interact::translate_zx, interact::translate_xy,
            //        interact::translate_xyz
            //    };
            //
            //    float4x4 modelMatrix = p.matrix();
            //    float4x4 scaleMatrix = scaling_matrix(float3(draw_scale));
            //    modelMatrix = mul(modelMatrix, scaleMatrix);
            //
            //    for (auto c : draw_interactions)
            //    {
            //        gizmo_renderable r;
            //        r.mesh = g.mesh_components[c].mesh;
            //        r.color = (c == g.gizmos[id].interaction_mode) ? g.mesh_components[c].base_color : g.mesh_components[c].highlight_color;
            //        for (auto & v : r.mesh.vertices)
            //        {
            //            v.position = transform_coord(modelMatrix, v.position); // transform local coordinates into worldspace
            //            v.normal = transform_vector(modelMatrix, v.normal);
            //        }
            //        g.drawlist.push_back(r);
        }
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
