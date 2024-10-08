const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
// #if defined(SOKOL_IMPL) && !defined(SOKOL_SHAPE_IMPL)
// #define SOKOL_SHAPE_IMPL
// #endif
// #ifndef SOKOL_SHAPE_INCLUDED
// /*
//     sokol_shape.h -- create simple primitive shapes for sokol_gfx.h
//
//     Project URL: https://github.com/floooh/sokol
//
//     Do this:
//         #define SOKOL_IMPL or
//         #define SOKOL_SHAPE_IMPL
//     before you include this file in *one* C or C++ file to create the
//     implementation.
//
//     Include the following headers before including sokol_shape.h:
//
//         sokol_gfx.h
//
//     ...optionally provide the following macros to override defaults:
//
//     SOKOL_ASSERT(c)     - your own assert macro (default: assert(c))
//     SOKOL_SHAPE_API_DECL- public function declaration prefix (default: extern)
//     SOKOL_API_DECL      - same as SOKOL_SHAPE_API_DECL
//     SOKOL_API_IMPL      - public function implementation prefix (default: -)
//
//     If sokol_shape.h is compiled as a DLL, define the following before
//     including the declaration or implementation:
//
//     SOKOL_DLL
//
//     On Windows, SOKOL_DLL will define SOKOL_SHAPE_API_DECL as __declspec(dllexport)
//     or __declspec(dllimport) as needed.
//
//     FEATURE OVERVIEW
//     ================
//     sokol_shape.h creates vertices and indices for simple shapes and
//     builds structs which can be plugged into sokol-gfx resource
//     creation functions:
//
//     The following shape types are supported:
//
//         - plane
//         - cube
//         - sphere (with poles, not geodesic)
//         - cylinder
//         - torus (donut)
//
//     Generated vertices look like this:
//
//         typedef struct sshape_vertex_t {
//             float x, y, z;
//             uint32_t normal;        // packed normal as BYTE4N
//             uint16_t u, v;          // packed uv coords as USHORT2N
//             uint32_t color;         // packed color as UBYTE4N (r,g,b,a);
//         } sshape_vertex_t;
//
//     Indices are generally 16-bits wide (SG_INDEXTYPE_UINT16) and the indices
//     are written as triangle-lists (SG_PRIMITIVETYPE_TRIANGLES).
//
//     EXAMPLES:
//     =========
//
//     Create multiple shapes into the same vertex- and index-buffer and
//     render with separate draw calls:
//
//     https://github.com/floooh/sokol-samples/blob/master/sapp/shapes-sapp.c
//
//     Same as the above, but pre-transform shapes and merge them into a single
//     shape that's rendered with a single draw call.
//
//     https://github.com/floooh/sokol-samples/blob/master/sapp/shapes-transform-sapp.c
//
//     STEP-BY-STEP:
//     =============
//
//     Setup an sshape_buffer_t struct with pointers to memory buffers where
//     generated vertices and indices will be written to:
//
//     ```c
//     sshape_vertex_t vertices[512];
//     uint16_t indices[4096];
//
//     sshape_buffer_t buf = {
//         .vertices = {
//             .buffer = SSHAPE_RANGE(vertices),
//         },
//         .indices = {
//             .buffer = SSHAPE_RANGE(indices),
//         }
//     };
//     ```
//
//     To find out how big those memory buffers must be (in case you want
//     to allocate dynamically) call the following functions:
//
//     ```c
//     sshape_sizes_t sshape_plane_sizes(uint32_t tiles);
//     sshape_sizes_t sshape_box_sizes(uint32_t tiles);
//     sshape_sizes_t sshape_sphere_sizes(uint32_t slices, uint32_t stacks);
//     sshape_sizes_t sshape_cylinder_sizes(uint32_t slices, uint32_t stacks);
//     sshape_sizes_t sshape_torus_sizes(uint32_t sides, uint32_t rings);
//     ```
//
//     The returned sshape_sizes_t struct contains vertex- and index-counts
//     as well as the equivalent buffer sizes in bytes. For instance:
//
//     ```c
//     sshape_sizes_t sizes = sshape_sphere_sizes(36, 12);
//     uint32_t num_vertices = sizes.vertices.num;
//     uint32_t num_indices = sizes.indices.num;
//     uint32_t vertex_buffer_size = sizes.vertices.size;
//     uint32_t index_buffer_size = sizes.indices.size;
//     ```
//
//     With the sshape_buffer_t struct that was setup earlier, call any
//     of the shape-builder functions:
//
//     ```c
//     sshape_buffer_t sshape_build_plane(const sshape_buffer_t* buf, const sshape_plane_t* params);
//     sshape_buffer_t sshape_build_box(const sshape_buffer_t* buf, const sshape_box_t* params);
//     sshape_buffer_t sshape_build_sphere(const sshape_buffer_t* buf, const sshape_sphere_t* params);
//     sshape_buffer_t sshape_build_cylinder(const sshape_buffer_t* buf, const sshape_cylinder_t* params);
//     sshape_buffer_t sshape_build_torus(const sshape_buffer_t* buf, const sshape_torus_t* params);
//     ```
//
//     Note how the sshape_buffer_t struct is both an input value and the
//     return value. This can be used to append multiple shapes into the
//     same vertex- and index-buffers (more on this later).
//
//     The second argument is a struct which holds creation parameters.
//
//     For instance to build a sphere with radius 2, 36 "cake slices" and 12 stacks:
//
//     ```c
//     sshape_buffer_t buf = ...;
//     buf = sshape_build_sphere(&buf, &(sshape_sphere_t){
//         .radius = 2.0f,
//         .slices = 36,
//         .stacks = 12,
//     });
//     ```
//
//     If the provided buffers are big enough to hold all generated vertices and
//     indices, the "valid" field in the result will be true:
//
//     ```c
//     assert(buf.valid);
//     ```
//
//     The shape creation parameters have "useful defaults", refer to the
//     actual C struct declarations below to look up those defaults.
//
//     You can also provide additional creation parameters, like a common vertex
//     color, a debug-helper to randomize colors, tell the shape builder function
//     to merge the new shape with the previous shape into the same draw-element-range,
//     or a 4x4 transform matrix to move, rotate and scale the generated vertices:
//
//     ```c
//     sshape_buffer_t buf = ...;
//     buf = sshape_build_sphere(&buf, &(sshape_sphere_t){
//         .radius = 2.0f,
//         .slices = 36,
//         .stacks = 12,
//         // merge with previous shape into a single element-range
//         .merge = true,
//         // set vertex color to red+opaque
//         .color = sshape_color_4f(1.0f, 0.0f, 0.0f, 1.0f),
//         // set position to y = 2.0
//         .transform = {
//             .m = {
//                 { 1.0f, 0.0f, 0.0f, 0.0f },
//                 { 0.0f, 1.0f, 0.0f, 0.0f },
//                 { 0.0f, 0.0f, 1.0f, 0.0f },
//                 { 0.0f, 2.0f, 0.0f, 1.0f },
//             }
//         }
//     });
//     assert(buf.valid);
//     ```
//
//     The following helper functions can be used to build a packed
//     color value or to convert from external matrix types:
//
//     ```c
//     uint32_t sshape_color_4f(float r, float g, float b, float a);
//     uint32_t sshape_color_3f(float r, float g, float b);
//     uint32_t sshape_color_4b(uint8_t r, uint8_t g, uint8_t b, uint8_t a);
//     uint32_t sshape_color_3b(uint8_t r, uint8_t g, uint8_t b);
//     sshape_mat4_t sshape_mat4(const float m[16]);
//     sshape_mat4_t sshape_mat4_transpose(const float m[16]);
//     ```
//
//     After the shape builder function has been called, the following functions
//     are used to extract the build result for plugging into sokol_gfx.h:
//
//     ```c
//     sshape_element_range_t sshape_element_range(const sshape_buffer_t* buf);
//     sg_buffer_desc sshape_vertex_buffer_desc(const sshape_buffer_t* buf);
//     sg_buffer_desc sshape_index_buffer_desc(const sshape_buffer_t* buf);
//     sg_vertex_buffer_layout_state sshape_vertex_buffer_layout_state(void);
//     sg_vertex_attr_state sshape_position_vertex_attr_state(void);
//     sg_vertex_attr_state sshape_normal_vertex_attr_state(void);
//     sg_vertex_attr_state sshape_texcoord_vertex_attr_state(void);
//     sg_vertex_attr_state sshape_color_vertex_attr_state(void);
//     ```
//
//     The sshape_element_range_t struct contains the base-index and number of
//     indices which can be plugged into the sg_draw() call:
//
//     ```c
//     sshape_element_range_t elms = sshape_element_range(&buf);
//     ...
//     sg_draw(elms.base_element, elms.num_elements, 1);
//     ```
//
//     To create sokol-gfx vertex- and index-buffers from the generated
//     shape data:
//
//     ```c
//     // create sokol-gfx vertex buffer
//     sg_buffer_desc vbuf_desc = sshape_vertex_buffer_desc(&buf);
//     sg_buffer vbuf = sg_make_buffer(&vbuf_desc);
//
//     // create sokol-gfx index buffer
//     sg_buffer_desc ibuf_desc = sshape_index_buffer_desc(&buf);
//     sg_buffer ibuf = sg_make_buffer(&ibuf_desc);
//     ```
//
//     The remaining functions are used to populate the vertex-layout item
//     in sg_pipeline_desc, note that these functions don't depend on the
//     created geometry, they always return the same result:
//
//     ```c
//     sg_pipeline pip = sg_make_pipeline(&(sg_pipeline_desc){
//         .layout = {
//             .buffers[0] = sshape_vertex_buffer_layout_state(),
//             .attrs = {
//                 [0] = sshape_position_vertex_attr_state(),
//                 [1] = ssape_normal_vertex_attr_state(),
//                 [2] = sshape_texcoord_vertex_attr_state(),
//                 [3] = sshape_color_vertex_attr_state()
//             }
//         },
//         ...
//     });
//     ```
//
//     Note that you don't have to use all generated vertex attributes in the
//     pipeline's vertex layout, the sg_vertex_buffer_layout_state struct returned
//     by sshape_vertex_buffer_layout_state() contains the correct vertex stride
//     to skip vertex components.
//
//     WRITING MULTIPLE SHAPES INTO THE SAME BUFFER
//     ============================================
//     You can merge multiple shapes into the same vertex- and
//     index-buffers and either render them as a single shape, or
//     in separate draw calls.
//
//     To build a single shape made of two cubes which can be rendered
//     in a single draw-call:
//
//     ```
//     sshape_vertex_t vertices[128];
//     uint16_t indices[16];
//
//     sshape_buffer_t buf = {
//         .vertices.buffer = SSHAPE_RANGE(vertices),
//         .indices.buffer  = SSHAPE_RANGE(indices)
//     };
//
//     // first cube at pos x=-2.0 (with default size of 1x1x1)
//     buf = sshape_build_cube(&buf, &(sshape_box_t){
//         .transform = {
//             .m = {
//                 { 1.0f, 0.0f, 0.0f, 0.0f },
//                 { 0.0f, 1.0f, 0.0f, 0.0f },
//                 { 0.0f, 0.0f, 1.0f, 0.0f },
//                 {-2.0f, 0.0f, 0.0f, 1.0f },
//             }
//         }
//     });
//     // ...and append another cube at pos pos=+1.0
//     // NOTE the .merge = true, this tells the shape builder
//     // function to not advance the current shape start offset
//     buf = sshape_build_cube(&buf, &(sshape_box_t){
//         .merge = true,
//         .transform = {
//             .m = {
//                 { 1.0f, 0.0f, 0.0f, 0.0f },
//                 { 0.0f, 1.0f, 0.0f, 0.0f },
//                 { 0.0f, 0.0f, 1.0f, 0.0f },
//                 {-2.0f, 0.0f, 0.0f, 1.0f },
//             }
//         }
//     });
//     assert(buf.valid);
//
//     // skipping buffer- and pipeline-creation...
//
//     sshape_element_range_t elms = sshape_element_range(&buf);
//     sg_draw(elms.base_element, elms.num_elements, 1);
//     ```
//
//     To render the two cubes in separate draw-calls, the element-ranges used
//     in the sg_draw() calls must be captured right after calling the
//     builder-functions:
//
//     ```c
//     sshape_vertex_t vertices[128];
//     uint16_t indices[16];
//     sshape_buffer_t buf = {
//         .vertices.buffer = SSHAPE_RANGE(vertices),
//         .indices.buffer = SSHAPE_RANGE(indices)
//     };
//
//     // build a red cube...
//     buf = sshape_build_cube(&buf, &(sshape_box_t){
//         .color = sshape_color_3b(255, 0, 0)
//     });
//     sshape_element_range_t red_cube = sshape_element_range(&buf);
//
//     // append a green cube to the same vertex-/index-buffer:
//     buf = sshape_build_cube(&bud, &sshape_box_t){
//         .color = sshape_color_3b(0, 255, 0);
//     });
//     sshape_element_range_t green_cube = sshape_element_range(&buf);
//
//     // skipping buffer- and pipeline-creation...
//
//     sg_draw(red_cube.base_element, red_cube.num_elements, 1);
//     sg_draw(green_cube.base_element, green_cube.num_elements, 1);
//     ```
//
//     ...that's about all :)
//
//     LICENSE
//     =======
//     zlib/libpng license
//
//     Copyright (c) 2020 Andre Weissflog
//
//     This software is provided 'as-is', without any express or implied warranty.
//     In no event will the authors be held liable for any damages arising from the
//     use of this software.
//
//     Permission is granted to anyone to use this software for any purpose,
//     including commercial applications, and to alter it and redistribute it
//     freely, subject to the following restrictions:
//
//         1. The origin of this software must not be misrepresented; you must not
//         claim that you wrote the original software. If you use this software in a
//         product, an acknowledgment in the product documentation would be
//         appreciated but is not required.
//
//         2. Altered source versions must be plainly marked as such, and must not
//         be misrepresented as being the original software.
//
//         3. This notice may not be removed or altered from any source
//         distribution.
// */
// /*

//     sshape_range is a pointer-size-pair struct used to pass memory
//     blobs into sokol-shape. When initialized from a value type
//     (array or struct), use the SSHAPE_RANGE() macro to build
//     an sshape_range struct.
// */
pub const Range = struct {
    ptr: *const anyopaque,
    size: usize,
};

pub fn range(x: anytype) Range {
    return .{
        .ptr = &x,
        .size = @sizeOf(@TypeOf(x)),
    };
}

// a 4x4 matrix wrapper struct
pub const Mat4 = struct {
    m: [16]f32,

    pub const IDENTITY: @This() = .{
        .m = .{
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
        },
    };

    pub fn init(m: [16]f32) @This() {
        return .{
            .m = m,
        };
    }

    fn isnull(self: @This()) bool {
        for (self.m) |n| {
            if (0.0 != n) {
                return false;
            }
        }
        return true;
    }

    fn mul(m: @This(), v: Vec4) Vec4 {
        return .{
            .x = m.m[0] * v.x + m.m[4] * v.y + m.m[8] * v.z + m.m[12] * v.w,
            .y = m.m[1] * v.x + m.m[5] * v.y + m.m[9] * v.z + m.m[13] * v.w,
            .z = m.m[2] * v.x + m.m[6] * v.y + m.m[10] * v.z + m.m[14] * v.w,
            .w = m.m[3] * v.x + m.m[7] * v.y + m.m[11] * v.z + m.m[15] * v.w,
        };
    }
};

// vertex layout of the generated geometry
pub const Vertex = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
    normal: u32 = 0, // packed normal as BYTE4N
    u: u16 = 0,
    v: u16 = 0, // packed uv coords as USHORT2N
    color: u32 = 0, // packed color as UBYTE4N (r,g,b,a);
};

// a range of draw-elements (sg_draw(int base_element, int num_element, ...))
pub const ElementRange = struct {
    base_element: i32,
    num_elements: i32,
};

// number of elements and byte size of build actions
pub const SizesItem = struct {
    num: u32, // number of elements
    size: u32, // the same as size in bytes
};

pub const Sizes = struct {
    vertices: SizesItem,
    indices: SizesItem,
};

// in/out struct to keep track of mesh-build state
pub const BufferItem = struct {
    buffer: sokol.shape.Range = .{}, // pointer/size pair of output buffer
    data_size: usize = 0, // size in bytes of valid data in buffer
    shape_offset: usize = 0, // data offset of the most recent shape
    //
    fn advance_offset(self: *@This()) void {
        self.shape_offset = self.data_size;
    }
};

pub const Buffer = struct {
    valid: bool = false,
    vertices: BufferItem = .{},
    indices: BufferItem = .{},

    fn base_index(buf: @This()) u16 {
        return @intCast(@divTrunc(buf.vertices.data_size, @sizeOf(Vertex)));
    }

    fn add_vertex(
        buf: *@This(),
        pos: Vec4,
        norm: Vec4,
        uv: Vec2,
        color: u32,
    ) void {
        const offset = buf.vertices.data_size;
        // SOKOL_ASSERT((offset + sizeof(sshape_vertex_t)) <= buf->vertices.buffer.size);
        buf.vertices.data_size += @sizeOf(Vertex);
        const address = @intFromPtr(buf.vertices.buffer.ptr.?) + offset;
        const v_ptr: *Vertex = @ptrFromInt(address);
        v_ptr.x = pos.x;
        v_ptr.y = pos.y;
        v_ptr.z = pos.z;
        v_ptr.normal = _sshape_pack_f4_byte4n(norm.x, norm.y, norm.z, norm.w);
        v_ptr.u = _sshape_pack_f_ushortn(uv.x);
        v_ptr.v = _sshape_pack_f_ushortn(uv.y);
        v_ptr.color = color;
    }

    fn add_triangle(buf: *@This(), _i0: u16, _i1: u16, _i2: u16) void {
        const offset = buf.indices.data_size;
        // SOKOL_ASSERT((offset + 3*sizeof(uint16_t)) <= buf->indices.buffer.size);
        buf.indices.data_size += 3 * @sizeOf(u16);
        const address = @intFromPtr(buf.indices.buffer.ptr.?) + offset;
        const i_ptr: [*]u16 = @ptrFromInt(address);
        i_ptr[0] = _i0;
        i_ptr[1] = _i1;
        i_ptr[2] = _i2;
    }
};

// creation parameters for the different shape types
pub const Plane = struct {
    width: f32 = 0,
    depth: f32 = 0, // default: 1.0
    tiles: u16 = 0, // default: 1
    color: u32 = 0, // default: white
    random_colors: bool = false, // default: false
    merge: bool = false, // if true merge with previous shape (default: false)
    transform: Mat4 = Mat4.IDENTITY, // default: identity matrix
};

pub const Box = struct {
    width: f32 = 0,
    height: f32 = 0,
    depth: f32 = 0, // default: 1.0
    tiles: u16 = 0, // default: 1
    color: u32 = 0, // default: white
    random_colors: bool = false, // default: false
    merge: bool = false, // if true merge with previous shape (default: false)
    transform: Mat4 = Mat4.IDENTITY, // default: identity matrix

    fn defaults(params: Box) Box {
        var res = params;
        res.width = _sshape_def_flt(res.width, 1.0);
        res.height = _sshape_def_flt(res.height, 1.0);
        res.depth = _sshape_def_flt(res.depth, 1.0);
        res.tiles = _sshape_def(res.tiles, 1);
        res.color = _sshape_def(res.color, _sshape_white);
        res.transform = if (res.transform.isnull())
            Mat4.IDENTITY
        else
            res.transform;
        return res;
    }

    fn num_vertices(self: @This()) u32 {
        return (self.tiles + 1) * (self.tiles + 1) * 6;
    }

    fn num_indices(self: @This()) u32 {
        return self.tiles * self.tiles * 2 * 6 * 3;
    }
};

pub const Sphere = struct {
    radius: f32 = 0, // default: 0.5
    slices: u16 = 0, // default: 5
    stacks: u16 = 0, // default: 4
    color: u32 = 0, // default: white
    random_colors: bool = false, // default: false
    merge: bool = false, // if true merge with previous shape (default: false)
    transform: Mat4 = Mat4.IDENTITY, // default: identity matrix

    fn defaults(params: @This()) @This() {
        var res = params;
        res.radius = _sshape_def_flt(res.radius, 0.5);
        res.slices = _sshape_def(res.slices, 5);
        res.stacks = _sshape_def(res.stacks, 4);
        res.color = _sshape_def(res.color, _sshape_white);
        res.transform = if (res.transform.isnull())
            Mat4.IDENTITY
        else
            res.transform;
        return res;
    }

    fn num_vertices(self: @This()) u32 {
        return (self.slices + 1) * (self.stacks + 1);
    }

    fn num_indices(self: @This()) u32 {
        return ((2 * self.slices * self.stacks) - (2 * self.slices)) * 3;
    }
};

pub const Cylinder = struct {
    radius: f32 = 0, // default: 0.5
    height: f32 = 0, // default: 1.0
    slices: u16 = 0, // default: 5
    stacks: u16 = 0, // default: 1
    color: u32 = 0, // default: white
    random_colors: bool = false, // default: false
    merge: bool = false, // if true merge with previous shape (default: false)
    transform: Mat4 = Mat4.IDENTITY, // default: identity matrix

    fn defaults(params: @This()) @This() {
        var res = params;
        res.radius = _sshape_def_flt(res.radius, 0.5);
        res.height = _sshape_def_flt(res.height, 1.0);
        res.slices = _sshape_def(res.slices, 5);
        res.stacks = _sshape_def(res.stacks, 1);
        res.color = _sshape_def(res.color, _sshape_white);
        res.transform = if (res.transform.isnull())
            Mat4.IDENTITY
        else
            res.transform;
        return res;
    }

    fn num_vertices(self: @This()) u32 {
        return (self.slices + 1) * (self.stacks + 5);
    }

    fn num_indices(self: @This()) u32 {
        return ((2 * self.slices * self.stacks) + (2 * self.slices)) * 3;
    }

    fn cap_pole(
        params: @This(),
        buf: *Buffer,
        pos_y: f32,
        norm_y: f32,
        du: f32,
        v: f32,
        rand_seed: *u32,
    ) void {
        const tnorm = params.transform.mul(Vec4{
            .x = 0.0,
            .y = norm_y,
            .z = 0.0,
            .w = 0.0,
        }).normalized();
        const tpos = params.transform.mul(Vec4{
            .x = 0.0,
            .y = pos_y,
            .z = 0.0,
            .w = 1.0,
        });
        for (0..params.slices + 1) |slice| {
            const uv = Vec2{
                .x = @as(f32, @floatFromInt(slice)) * du,
                .y = 1.0 - v,
            };
            const color = if (params.random_colors)
                _sshape_rand_color(rand_seed)
            else
                params.color;
            buf.add_vertex(tpos, tnorm, uv, color);
        }
    }

    fn cap_ring(
        params: @This(),
        buf: *Buffer,
        pos_y: f32,
        norm_y: f32,
        du: f32,
        v: f32,
        rand_seed: *u32,
    ) void {
        const two_pi = 2.0 * 3.14159265358979323846;
        const tnorm = params.transform.mul(Vec4{
            .x = 0.0,
            .y = norm_y,
            .z = 0.0,
            .w = 0.0,
        }).normalized();
        for (0..params.slices + 1) |slice| {
            const slice_angle = (two_pi * @as(f32, @floatFromInt(slice))) / @as(f32, @floatFromInt(params.slices));
            const sin_slice = std.math.sin(slice_angle);
            const cos_slice = std.math.cos(slice_angle);
            const pos = Vec4{
                .x = sin_slice * params.radius,
                .y = pos_y,
                .z = cos_slice * params.radius,
                .w = 1.0,
            };
            const tpos = params.transform.mul(pos);
            const uv = Vec2{
                .x = @as(f32, @floatFromInt(slice)) * du,
                .y = 1.0 - v,
            };
            const color = if (params.random_colors)
                _sshape_rand_color(rand_seed)
            else
                params.color;
            buf.add_vertex(tpos, tnorm, uv, color);
        }
    }
};

pub const Torus = struct {
    radius: f32 = 0, // default: 0.5f
    ring_radius: f32 = 0, // default: 0.2f
    sides: u16 = 0, // default: 5
    rings: u16 = 0, // default: 5
    color: u32 = 0, // default: white
    random_colors: bool = false, // default: false
    merge: bool = false, // if true merge with previous shape (default: false)
    transform: Mat4 = Mat4.IDENTITY, // default: identity matrix

    fn defaults(params: @This()) @This() {
        var res = params;
        res.radius = _sshape_def_flt(res.radius, 0.5);
        res.ring_radius = _sshape_def_flt(res.ring_radius, 0.2);
        res.sides = _sshape_def_flt(res.sides, 5);
        res.rings = _sshape_def_flt(res.rings, 5);
        res.color = _sshape_def(res.color, _sshape_white);
        res.transform = if (res.transform.isnull())
            Mat4.IDENTITY
        else
            res.transform;
        return res;
    }

    fn num_vertices(self: @This()) u32 {
        return (self.sides + 1) * (self.rings + 1);
    }

    fn num_indices(self: @This()) u32 {
        return self.sides * self.rings * 2 * 3;
    }
};

// /* shape builder functions */
// SOKOL_SHAPE_API_DECL sshape_buffer_t sshape_build_plane(const sshape_buffer_t* buf, const sshape_plane_t* params);
// SOKOL_SHAPE_API_DECL sshape_buffer_t sshape_build_box(const sshape_buffer_t* buf, const sshape_box_t* params);
// SOKOL_SHAPE_API_DECL sshape_buffer_t sshape_build_sphere(const sshape_buffer_t* buf, const sshape_sphere_t* params);
// SOKOL_SHAPE_API_DECL sshape_buffer_t sshape_build_cylinder(const sshape_buffer_t* buf, const sshape_cylinder_t* params);
// SOKOL_SHAPE_API_DECL sshape_buffer_t sshape_build_torus(const sshape_buffer_t* buf, const sshape_torus_t* params);
//
// /* query required vertex- and index-buffer sizes in bytes */
// SOKOL_SHAPE_API_DECL sshape_sizes_t sshape_plane_sizes(uint32_t tiles);
// SOKOL_SHAPE_API_DECL sshape_sizes_t sshape_box_sizes(uint32_t tiles);
// SOKOL_SHAPE_API_DECL sshape_sizes_t sshape_sphere_sizes(uint32_t slices, uint32_t stacks);
// SOKOL_SHAPE_API_DECL sshape_sizes_t sshape_cylinder_sizes(uint32_t slices, uint32_t stacks);
// SOKOL_SHAPE_API_DECL sshape_sizes_t sshape_torus_sizes(uint32_t sides, uint32_t rings);
//
// /* extract sokol-gfx desc structs and primitive ranges from build state */
// SOKOL_SHAPE_API_DECL sshape_element_range_t sshape_element_range(const sshape_buffer_t* buf);
// SOKOL_SHAPE_API_DECL sg_buffer_desc sshape_vertex_buffer_desc(const sshape_buffer_t* buf);
// SOKOL_SHAPE_API_DECL sg_buffer_desc sshape_index_buffer_desc(const sshape_buffer_t* buf);
// SOKOL_SHAPE_API_DECL sg_vertex_buffer_layout_state sshape_vertex_buffer_layout_state(void);
// SOKOL_SHAPE_API_DECL sg_vertex_attr_state sshape_position_vertex_attr_state(void);
// SOKOL_SHAPE_API_DECL sg_vertex_attr_state sshape_normal_vertex_attr_state(void);
// SOKOL_SHAPE_API_DECL sg_vertex_attr_state sshape_texcoord_vertex_attr_state(void);
// SOKOL_SHAPE_API_DECL sg_vertex_attr_state sshape_color_vertex_attr_state(void);
//
// /* helper functions to build packed color value from floats or bytes */
// SOKOL_SHAPE_API_DECL uint32_t sshape_color_4f(float r, float g, float b, float a);
// SOKOL_SHAPE_API_DECL uint32_t sshape_color_3f(float r, float g, float b);
// SOKOL_SHAPE_API_DECL uint32_t sshape_color_4b(uint8_t r, uint8_t g, uint8_t b, uint8_t a);
// SOKOL_SHAPE_API_DECL uint32_t sshape_color_3b(uint8_t r, uint8_t g, uint8_t b);
//
// /* adapter function for filling matrix struct from generic float[16] array */
// SOKOL_SHAPE_API_DECL sshape_mat4_t sshape_mat4(const float m[16]);
// SOKOL_SHAPE_API_DECL sshape_mat4_t sshape_mat4_transpose(const float m[16]);
//
// #ifdef __cplusplus
// } // extern "C"
//
// // FIXME: C++ helper functions
//
// #endif
// #endif // SOKOL_SHAPE_INCLUDED
//
// /*-- IMPLEMENTATION ----------------------------------------------------------*/
// #ifdef SOKOL_SHAPE_IMPL
// #define SOKOL_SHAPE_IMPL_INCLUDED (1)
//
// #include <string.h> // memcpy
// #include <math.h>   // sinf, cosf
//
// #ifdef __clang__
// #pragma clang diagnostic push
// #pragma clang diagnostic ignored "-Wmissing-field-initializers"
// #endif
//
// #ifndef SOKOL_API_IMPL
//     #define SOKOL_API_IMPL
// #endif
// #ifndef SOKOL_ASSERT
//     #include <assert.h>
//     #define SOKOL_ASSERT(c) assert(c)
// #endif
//
fn _sshape_def(val: anytype, def: @TypeOf(val)) @TypeOf(val) {
    return if (val == 0) def else val;
}
fn _sshape_def_flt(val: anytype, def: @TypeOf(val)) @TypeOf(val) {
    return if (val == 0.0) def else val;
}
const _sshape_white = (0xFFFFFFFF);

const Vec4 = struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,

    fn normalized(v: @This()) @This() {
        const l = std.math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z + v.w * v.w);
        if (l != 0.0) {
            return .{
                .x = v.x / l,
                .y = v.y / l,
                .z = v.z / l,
                .w = v.w / l,
            };
        } else {
            return .{ .x = 0.0, .y = 1.0, .z = 0.0, .w = 0.0 };
        }
    }
};

const Vec2 = struct {
    x: f32,
    y: f32,
};

// static inline float _sshape_clamp(float v) {
//     if (v < 0.0f) return 0.0f;
//     else if (v > 1.0f) return 1.0f;
//     else return v;
// }

fn _sshape_pack_ub4_ubyte4n(x: u8, y: u8, z: u8, w: u8) u32 {
    return (@as(u32, w) << 24) | (@as(u32, z) << 16) | (@as(u32, y) << 8) | x;
}

fn _sshape_pack_f4_ubyte4n(x: f32, y: f32, z: f32, w: f32) u32 {
    const x8 = @as(u8, x * 255.0);
    const y8 = @as(u8, y * 255.0);
    const z8 = @as(u8, z * 255.0);
    const w8 = @as(u8, w * 255.0);
    return _sshape_pack_ub4_ubyte4n(x8, y8, z8, w8);
}

fn _sshape_pack_f4_byte4n(x: f32, y: f32, z: f32, w: f32) u32 {
    const x8: i8 = @intFromFloat(x * 127.0);
    const y8: i8 = @intFromFloat(y * 127.0);
    const z8: i8 = @intFromFloat(z * 127.0);
    const w8: i8 = @intFromFloat(w * 127.0);
    return _sshape_pack_ub4_ubyte4n(
        @intCast(x8),
        @intCast(y8),
        @intCast(z8),
        @intCast(w8),
    );
}

fn _sshape_pack_f_ushortn(x: f32) u16 {
    return @intFromFloat(x * 65535.0);
}

// static uint32_t _sshape_plane_num_vertices(uint32_t tiles) {
//     return (tiles + 1) * (tiles + 1);
// }
//
// static uint32_t _sshape_plane_num_indices(uint32_t tiles) {
//     return tiles * tiles * 2 * 3;
// }

fn _sshape_validate_buffer_item(item: *const BufferItem, build_size: u32) bool {
    if (null == item.buffer.ptr) {
        return false;
    }
    if (0 == item.buffer.size) {
        return false;
    }
    if ((item.data_size + build_size) > item.buffer.size) {
        return false;
    }
    if (item.shape_offset > item.data_size) {
        return false;
    }
    return true;
}

fn _sshape_validate_buffer(buf: *const Buffer, num_vertices: u32, num_indices: u32) bool {
    if (!_sshape_validate_buffer_item(&buf.vertices, num_vertices * @sizeOf(Vertex))) {
        return false;
    }
    if (!_sshape_validate_buffer_item(&buf.indices, num_indices * @sizeOf(u16))) {
        return false;
    }
    return true;
}

// static sshape_plane_t _sshape_plane_defaults(const sshape_plane_t* params) {
//     sshape_plane_t res = *params;
//     res.width = _sshape_def_flt(res.width, 1.0f);
//     res.depth = _sshape_def_flt(res.depth, 1.0f);
//     res.tiles = _sshape_def(res.tiles, 1);
//     res.color = _sshape_def(res.color, _sshape_white);
//     res.transform = _sshape_mat4_isnull(&res.transform) ? _sshape_mat4_identity() : res.transform;
//     return res;
// }

fn _sshape_rand_color(xorshift_state: *u32) u32 {
    // xorshift32
    var x = xorshift_state.*;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    xorshift_state.* = x;

    // rand => bright color with alpha 1.0
    x |= 0xFF000000;
    return x;
}

// /*=== PUBLIC API FUNCTIONS ===================================================*/
// SOKOL_API_IMPL uint32_t sshape_color_4f(float r, float g, float b, float a) {
//     return _sshape_pack_f4_ubyte4n(_sshape_clamp(r), _sshape_clamp(g), _sshape_clamp(b), _sshape_clamp(a));
// }
//
// SOKOL_API_IMPL uint32_t sshape_color_3f(float r, float g, float b) {
//     return _sshape_pack_f4_ubyte4n(_sshape_clamp(r), _sshape_clamp(g), _sshape_clamp(b), 1.0f);
// }
//
// SOKOL_API_IMPL uint32_t sshape_color_4b(uint8_t r, uint8_t g, uint8_t b, uint8_t a) {
//     return _sshape_pack_ub4_ubyte4n(r, g, b, a);
// }
//
// SOKOL_API_IMPL uint32_t sshape_color_3b(uint8_t r, uint8_t g, uint8_t b) {
//     return _sshape_pack_ub4_ubyte4n(r, g, b, 255);
// }

// SOKOL_API_IMPL sshape_mat4_t sshape_mat4_transpose(const float m[16]) {
//     sshape_mat4_t res;
//     for (int c = 0; c < 4; c++) {
//         for (int r = 0; r < 4; r++) {
//             res.m[r][c] = m[c*4 + r];
//         }
//     }
//     return res;
// }
//
// SOKOL_API_IMPL sshape_sizes_t sshape_plane_sizes(uint32_t tiles) {
//     SOKOL_ASSERT(tiles >= 1);
//     sshape_sizes_t res = { {0} };
//     res.vertices.num = _sshape_plane_num_vertices(tiles);
//     res.indices.num = _sshape_plane_num_indices(tiles);
//     res.vertices.size = res.vertices.num * sizeof(sshape_vertex_t);
//     res.indices.size = res.indices.num * sizeof(uint16_t);
//     return res;
// }
//
// SOKOL_API_IMPL sshape_sizes_t sshape_box_sizes(uint32_t tiles) {
//     SOKOL_ASSERT(tiles >= 1);
//     sshape_sizes_t res = { {0} };
//     res.vertices.num = _sshape_box_num_vertices(tiles);
//     res.indices.num = _sshape_box_num_indices(tiles);
//     res.vertices.size = res.vertices.num * sizeof(sshape_vertex_t);
//     res.indices.size = res.indices.num * sizeof(uint16_t);
//     return res;
// }
//
// SOKOL_API_IMPL sshape_sizes_t sshape_sphere_sizes(uint32_t slices, uint32_t stacks) {
//     SOKOL_ASSERT((slices >= 3) && (stacks >= 2));
//     sshape_sizes_t res = { {0} };
//     res.vertices.num = _sshape_sphere_num_vertices(slices, stacks);
//     res.indices.num = _sshape_sphere_num_indices(slices, stacks);
//     res.vertices.size = res.vertices.num * sizeof(sshape_vertex_t);
//     res.indices.size = res.indices.num * sizeof(uint16_t);
//     return res;
// }
//
// SOKOL_API_IMPL sshape_sizes_t sshape_cylinder_sizes(uint32_t slices, uint32_t stacks) {
//     SOKOL_ASSERT((slices >= 3) && (stacks >= 1));
//     sshape_sizes_t res = { {0} };
//     res.vertices.num = _sshape_cylinder_num_vertices(slices, stacks);
//     res.indices.num = _sshape_cylinder_num_indices(slices, stacks);
//     res.vertices.size = res.vertices.num * sizeof(sshape_vertex_t);
//     res.indices.size = res.indices.num * sizeof(uint16_t);
//     return res;
// }
//
// SOKOL_API_IMPL sshape_sizes_t sshape_torus_sizes(uint32_t sides, uint32_t rings) {
//     SOKOL_ASSERT((sides >= 3) && (rings >= 3));
//     sshape_sizes_t res = { {0} };
//     res.vertices.num = _sshape_torus_num_vertices(sides, rings);
//     res.indices.num = _sshape_torus_num_indices(sides, rings);
//     res.vertices.size = res.vertices.num * sizeof(sshape_vertex_t);
//     res.indices.size = res.indices.num * sizeof(uint16_t);
//     return res;
// }
//
// /*
//     Geometry layout for plane (4 tiles):
//     +--+--+--+--+
//     |\ |\ |\ |\ |
//     | \| \| \| \|
//     +--+--+--+--+    25 vertices (tiles + 1) * (tiles + 1)
//     |\ |\ |\ |\ |    32 triangles (tiles + 1) * (tiles + 1) * 2
//     | \| \| \| \|
//     +--+--+--+--+
//     |\ |\ |\ |\ |
//     | \| \| \| \|
//     +--+--+--+--+
//     |\ |\ |\ |\ |
//     | \| \| \| \|
//     +--+--+--+--+
// */
// SOKOL_API_IMPL sshape_buffer_t sshape_build_plane(const sshape_buffer_t* in_buf, const sshape_plane_t* in_params) {
//     SOKOL_ASSERT(in_buf && in_params);
//     const sshape_plane_t params = _sshape_plane_defaults(in_params);
//     const uint32_t num_vertices = _sshape_plane_num_vertices(params.tiles);
//     const uint32_t num_indices = _sshape_plane_num_indices(params.tiles);
//     sshape_buffer_t buf = *in_buf;
//     if (!_sshape_validate_buffer(&buf, num_vertices, num_indices)) {
//         buf.valid = false;
//         return buf;
//     }
//     buf.valid = true;
//     const uint16_t start_index = _sshape_base_index(&buf);
//     if (!params.merge) {
//         _sshape_advance_offset(&buf.vertices);
//         _sshape_advance_offset(&buf.indices);
//     }
//
//     // write vertices
//     uint32_t rand_seed = 0x12345678;
//     const float x0 = -params.width * 0.5f;
//     const float z0 =  params.depth * 0.5f;
//     const float dx =  params.width / params.tiles;
//     const float dz = -params.depth / params.tiles;
//     const float duv = 1.0f / params.tiles;
//     _sshape_vec4_t tnorm = _sshape_vec4_norm(_sshape_mat4_mul(&params.transform, _sshape_vec4(0.0f, 1.0f, 0.0f, 0.0f)));
//     for (uint32_t ix = 0; ix <= params.tiles; ix++) {
//         for (uint32_t iz = 0; iz <= params.tiles; iz++) {
//             const _sshape_vec4_t pos = _sshape_vec4(x0 + dx*ix, 0.0f, z0 + dz*iz, 1.0f);
//             const _sshape_vec4_t tpos = _sshape_mat4_mul(&params.transform, pos);
//             const _sshape_vec2_t uv = _sshape_vec2(duv*ix, duv*iz);
//             const uint32_t color = params.random_colors ? _sshape_rand_color(&rand_seed) : params.color;
//             _sshape_add_vertex(&buf, tpos, tnorm, uv, color);
//         }
//     }
//
//     // write indices
//     for (uint16_t j = 0; j < params.tiles; j++) {
//         for (uint16_t i = 0; i < params.tiles; i++) {
//             const uint16_t i0 = start_index + (j * (params.tiles + 1)) + i;
//             const uint16_t i1 = i0 + 1;
//             const uint16_t i2 = i0 + params.tiles + 1;
//             const uint16_t i3 = i2 + 1;
//             _sshape_add_triangle(&buf, i0, i1, i3);
//             _sshape_add_triangle(&buf, i0, i3, i2);
//         }
//     }
//     return buf;
// }

pub fn buildBox(
    in_buf: Buffer,
    in_params: Box,
) Buffer {
    const params = in_params.defaults();
    const num_vertices = params.num_vertices();
    const num_indices = params.num_indices();
    var buf = in_buf;
    if (!_sshape_validate_buffer(&buf, num_vertices, num_indices)) {
        buf.valid = false;
        return buf;
    }
    buf.valid = true;
    const start_index = buf.base_index();
    if (!params.merge) {
        buf.vertices.advance_offset();
        buf.indices.advance_offset();
    }

    // build vertices
    var rand_seed: u32 = 0x12345678;
    const x0 = -params.width * 0.5;
    const x1 = params.width * 0.5;
    const y0 = -params.height * 0.5;
    const y1 = params.height * 0.5;
    const z0 = -params.depth * 0.5;
    const z1 = params.depth * 0.5;
    const dx = params.width / @as(f32, @floatFromInt(params.tiles));
    const dy = params.height / @as(f32, @floatFromInt(params.tiles));
    const dz = params.depth / @as(f32, @floatFromInt(params.tiles));
    const duv = 1.0 / @as(f32, @floatFromInt(params.tiles));

    // bottom/top vertices
    for (0..2) |top_bottom| {
        var pos = Vec4{
            .x = 0.0,
            .y = if (0 == top_bottom) y0 else y1,
            .z = 0.0,
            .w = 1.0,
        };
        const norm = Vec4{
            .x = 0.0,
            .y = if (0 == top_bottom) -1.0 else 1.0,
            .z = 0.0,
            .w = 0.0,
        };
        const tnorm = params.transform.mul(norm);
        for (0..params.tiles + 1) |ix| {
            pos.x = if (0 == top_bottom)
                (x0 + dx * @as(f32, @floatFromInt(ix)))
            else
                (x1 - dx * @as(f32, @floatFromInt(ix)));
            for (0..params.tiles + 1) |iz| {
                pos.z = z0 + dz * @as(f32, @floatFromInt(iz));
                const tpos = params.transform.mul(pos);
                const uv = Vec2{
                    .x = @as(f32, @floatFromInt(ix)) * duv,
                    .y = @as(f32, @floatFromInt(iz)) * duv,
                };
                const color = if (params.random_colors)
                    _sshape_rand_color(&rand_seed)
                else
                    params.color;
                buf.add_vertex(tpos, tnorm, uv, color);
            }
        }
    }

    // left/right vertices
    for (0..2) |left_right| {
        var pos = Vec4{
            .x = if (0 == left_right)
                x0
            else
                x1,
            .y = 0.0,
            .z = 0.0,
            .w = 1.0,
        };
        const norm = Vec4{
            .x = if (0 == left_right)
                -1.0
            else
                1.0,
            .y = 0.0,
            .z = 0.0,
            .w = 0.0,
        };
        const tnorm = params.transform.mul(norm);
        for (0..params.tiles + 1) |iy| {
            pos.y = if (0 == left_right)
                (y1 - dy * @as(f32, @floatFromInt(iy)))
            else
                (y0 + dy * @as(f32, @floatFromInt(iy)));
            for (0..params.tiles + 1) |iz| {
                pos.z = z0 + dz * @as(f32, @floatFromInt(iz));
                const tpos = params.transform.mul(pos);
                const uv = Vec2{
                    .x = @as(f32, @floatFromInt(iy)) * duv,
                    .y = @as(f32, @floatFromInt(iz)) * duv,
                };
                const color = if (params.random_colors)
                    _sshape_rand_color(&rand_seed)
                else
                    params.color;
                buf.add_vertex(tpos, tnorm, uv, color);
            }
        }
    }

    // front/back vertices
    for (0..2) |front_back| {
        var pos = Vec4{ .x = 0.0, .y = 0.0, .z = if (0 == front_back)
            z0
        else
            z1, .w = 1.0 };
        const norm = Vec4{ .x = 0.0, .y = 0.0, .z = if (0 == front_back)
            -1.0
        else
            1.0, .w = 0.0 };
        const tnorm = params.transform.mul(norm);
        for (0..params.tiles + 1) |ix| {
            pos.x = if (0 == front_back)
                (x1 - dx * @as(f32, @floatFromInt(ix)))
            else
                (x0 + dx * @as(f32, @floatFromInt(ix)));
            for (0..params.tiles + 1) |iy| {
                pos.y = y0 + dy * @as(f32, @floatFromInt(iy));
                const tpos = params.transform.mul(pos);
                const uv = Vec2{
                    .x = @as(f32, @floatFromInt(ix)) * duv,
                    .y = @as(f32, @floatFromInt(iy)) * duv,
                };
                const color = if (params.random_colors)
                    _sshape_rand_color(&rand_seed)
                else
                    params.color;
                buf.add_vertex(tpos, tnorm, uv, color);
            }
        }
    }

    // build indices
    const verts_per_face = (params.tiles + 1) * (params.tiles + 1);
    for (0..6) |face| {
        const face_start_index = start_index + face * verts_per_face;
        for (0..params.tiles + 1) |j| {
            for (0..params.tiles + 1) |i| {
                const _i0 = face_start_index + (j * (params.tiles + 1)) + i;
                const _i1 = _i0 + 1;
                const _i2 = _i0 + params.tiles + 1;
                const _i3 = _i2 + 1;
                buf.add_triangle(@intCast(_i0), @intCast(_i1), @intCast(_i3));
                buf.add_triangle(@intCast(_i0), @intCast(_i3), @intCast(_i2));
            }
        }
    }
    return buf;
}

//
//     Geometry layout for spheres is as follows (for 5 slices, 4 stacks):
//
//     +  +  +  +  +  +        north pole
//     |\ |\ |\ |\ |\
//     | \| \| \| \| \
//     +--+--+--+--+--+        30 vertices (slices + 1) * (stacks + 1)
//     |\ |\ |\ |\ |\ |        30 triangles (2 * slices * stacks) - (2 * slices)
//     | \| \| \| \| \|        2 orphaned vertices
//     +--+--+--+--+--+
//     |\ |\ |\ |\ |\ |
//     | \| \| \| \| \|
//     +--+--+--+--+--+
//      \ |\ |\ |\ |\ |
//       \| \| \| \| \|
//     +  +  +  +  +  +        south pole
//
pub fn buildSphere(in_buf: Buffer, in_params: Sphere) Buffer {
    const params = in_params.defaults();
    const num_vertices = params.num_vertices();
    const num_indices = params.num_indices();
    var buf = in_buf;
    if (!_sshape_validate_buffer(&buf, num_vertices, num_indices)) {
        buf.valid = false;
        return buf;
    }
    buf.valid = true;
    const start_index = buf.base_index();
    if (!params.merge) {
        buf.vertices.advance_offset();
        buf.indices.advance_offset();
    }

    var rand_seed: u32 = 0x12345678;
    const pi: f32 = 3.14159265358979323846;
    const two_pi = 2.0 * pi;
    const du = 1.0 / @as(f32, @floatFromInt(params.slices));
    const dv = 1.0 / @as(f32, @floatFromInt(params.stacks));

    // generate vertices
    for (0..params.stacks + 1) |stack| {
        const stack_angle = (pi * @as(f32, @floatFromInt(stack))) / @as(f32, @floatFromInt(params.stacks));
        const sin_stack = std.math.sin(stack_angle);
        const cos_stack = std.math.cos(stack_angle);
        for (0..params.slices + 1) |slice| {
            const slice_angle = (two_pi * @as(f32, @floatFromInt(slice))) / @as(f32, @floatFromInt(params.slices));
            const sin_slice = std.math.sin(slice_angle);
            const cos_slice = std.math.cos(slice_angle);
            const norm = Vec4{
                .x = -sin_slice * sin_stack,
                .y = cos_stack,
                .z = cos_slice * sin_stack,
                .w = 0.0,
            };
            const pos = Vec4{
                .x = norm.x * params.radius,
                .y = norm.y * params.radius,
                .z = norm.z * params.radius,
                .w = 1.0,
            };
            const tnorm = params.transform.mul(norm).normalized();
            const tpos = params.transform.mul(pos);
            const uv = Vec2{
                .x = 1.0 - @as(f32, @floatFromInt(slice)) * du,
                .y = 1.0 - @as(f32, @floatFromInt(stack)) * dv,
            };
            const color = if (params.random_colors)
                _sshape_rand_color(&rand_seed)
            else
                params.color;
            buf.add_vertex(tpos, tnorm, uv, color);
        }
    }

    // generate indices
    {
        // north-pole triangles
        const row_a = start_index;
        const row_b = row_a + params.slices + 1;
        for (0..params.slices) |slice| {
            buf.add_triangle(
                @intCast(row_a + slice),
                @intCast(row_b + slice),
                @intCast(row_b + slice + 1),
            );
        }
    }
    // stack triangles
    for (1..params.stacks - 1) |stack| {
        const row_a = start_index + stack * (params.slices + 1);
        const row_b = row_a + params.slices + 1;
        for (0..params.slices) |slice| {
            buf.add_triangle(
                @intCast(row_a + slice),
                @intCast(row_b + slice + 1),
                @intCast(row_a + slice + 1),
            );
            buf.add_triangle(
                @intCast(row_a + slice),
                @intCast(row_b + slice),
                @intCast(row_b + slice + 1),
            );
        }
    }
    {
        // south-pole triangles
        const row_a = start_index + (params.stacks - 1) * (params.slices + 1);
        const row_b = row_a + params.slices + 1;
        for (0..params.slices) |slice| {
            buf.add_triangle(
                @intCast(row_a + slice),
                @intCast(row_b + slice + 1),
                @intCast(row_a + slice + 1),
            );
        }
    }
    return buf;
}

//
//     Geometry for cylinders is as follows (2 stacks, 5 slices):
//
//     +  +  +  +  +  +
//     |\ |\ |\ |\ |\
//     | \| \| \| \| \
//     +--+--+--+--+--+
//     +--+--+--+--+--+    42 vertices (2 wasted) (slices + 1) * (stacks + 5)
//     |\ |\ |\ |\ |\ |    30 triangles (2 * slices * stacks) + (2 * slices)
//     | \| \| \| \| \|
//     +--+--+--+--+--+
//     |\ |\ |\ |\ |\ |
//     | \| \| \| \| \|
//     +--+--+--+--+--+
//     +--+--+--+--+--+
//      \ |\ |\ |\ |\ |
//       \| \| \| \| \|
//     +  +  +  +  +  +
//
pub fn buildCylinder(in_buf: Buffer, in_params: Cylinder) Buffer {
    const params = in_params.defaults();
    const num_vertices = params.num_vertices();
    const num_indices = params.num_indices();
    var buf = in_buf;
    if (!_sshape_validate_buffer(&buf, num_vertices, num_indices)) {
        buf.valid = false;
        return buf;
    }
    buf.valid = true;
    const start_index = buf.base_index();
    if (!params.merge) {
        buf.vertices.advance_offset();
        buf.indices.advance_offset();
    }

    var rand_seed: u32 = 0x12345678;
    const two_pi = 2.0 * 3.14159265358979323846;
    const du = 1.0 / @as(f32, @floatFromInt(params.slices));
    const dv = 1.0 / @as(f32, @floatFromInt(params.stacks + 2));
    const y0 = params.height * 0.5;
    const y1 = -params.height * 0.5;
    const dy = params.height / @as(f32, @floatFromInt(params.stacks));

    // generate vertices
    params.cap_pole(&buf, y0, 1.0, du, 0.0, &rand_seed);
    params.cap_ring(&buf, y0, 1.0, du, dv, &rand_seed);
    for (0..params.stacks + 1) |stack| {
        const y = y0 - dy * @as(f32, @floatFromInt(stack));
        const v = dv * @as(f32, @floatFromInt(stack)) + dv;
        for (0..params.slices + 1) |slice| {
            const slice_angle = (two_pi * @as(f32, @floatFromInt(slice))) / @as(f32, @floatFromInt(params.slices));
            const sin_slice = std.math.sin(slice_angle);
            const cos_slice = std.math.cos(slice_angle);
            const pos = Vec4{
                .x = sin_slice * params.radius,
                .y = y,
                .z = cos_slice * params.radius,
                .w = 1.0,
            };
            const tpos = params.transform.mul(pos);
            const norm = Vec4{
                .x = sin_slice,
                .y = 0.0,
                .z = cos_slice,
                .w = 0.0,
            };
            const tnorm = params.transform.mul(norm).normalized();
            const uv = Vec2{
                .x = @as(f32, @floatFromInt(slice)) * du,
                .y = 1.0 - v,
            };
            const color = if (params.random_colors)
                _sshape_rand_color(&rand_seed)
            else
                params.color;
            buf.add_vertex(tpos, tnorm, uv, color);
        }
    }
    params.cap_ring(&buf, y1, -1.0, du, 1.0 - dv, &rand_seed);
    params.cap_pole(&buf, y1, -1.0, du, 1.0, &rand_seed);

    // generate indices
    {
        // top-cap indices
        const row_a = start_index;
        const row_b = row_a + params.slices + 1;
        for (0..params.slices) |slice| {
            buf.add_triangle(
                @intCast(row_a + slice),
                @intCast(row_b + slice + 1),
                @intCast(row_b + slice),
            );
        }
    }
    // shaft triangles
    for (0..params.stacks) |stack| {
        const row_a = start_index + (stack + 2) * (params.slices + 1);
        const row_b = row_a + params.slices + 1;
        for (0..params.slices) |slice| {
            buf.add_triangle(
                @intCast(row_a + slice),
                @intCast(row_a + slice + 1),
                @intCast(row_b + slice + 1),
            );
            buf.add_triangle(
                @intCast(row_a + slice),
                @intCast(row_b + slice + 1),
                @intCast(row_b + slice),
            );
        }
    }
    {
        // bottom-cap indices
        const row_a = start_index + (params.stacks + 3) * (params.slices + 1);
        const row_b = row_a + params.slices + 1;
        for (0..params.slices) |slice| {
            buf.add_triangle(
                @intCast(row_a + slice),
                @intCast(row_a + slice + 1),
                @intCast(row_b + slice + 1),
            );
        }
    }
    return buf;
}

//
//     Geometry layout for torus (sides = 4, rings = 5):
//
//     +--+--+--+--+--+
//     |\ |\ |\ |\ |\ |
//     | \| \| \| \| \|
//     +--+--+--+--+--+    30 vertices (sides + 1) * (rings + 1)
//     |\ |\ |\ |\ |\ |    40 triangles (2 * sides * rings)
//     | \| \| \| \| \|
//     +--+--+--+--+--+
//     |\ |\ |\ |\ |\ |
//     | \| \| \| \| \|
//     +--+--+--+--+--+
//     |\ |\ |\ |\ |\ |
//     | \| \| \| \| \|
//     +--+--+--+--+--+
//
pub fn buildTorus(in_buf: Buffer, in_params: Torus) Buffer {
    const params = in_params.defaults();
    const num_vertices = params.num_vertices();
    const num_indices = params.num_indices();
    var buf = in_buf;
    if (!_sshape_validate_buffer(&buf, num_vertices, num_indices)) {
        buf.valid = false;
        return buf;
    }
    buf.valid = true;
    const start_index = buf.base_index();
    if (!params.merge) {
        buf.vertices.advance_offset();
        buf.indices.advance_offset();
    }

    var rand_seed: u32 = 0x12345678;
    const two_pi = 2.0 * 3.14159265358979323846;
    const dv = 1.0 / @as(f32, @floatFromInt(params.sides));
    const du = 1.0 / @as(f32, @floatFromInt(params.rings));

    // generate vertices
    for (0..params.sides + 1) |side| {
        const phi = (@as(f32, @floatFromInt(side)) * two_pi) / @as(f32, @floatFromInt(params.sides));
        const sin_phi = std.math.sin(phi);
        const cos_phi = std.math.cos(phi);
        for (0..params.rings + 1) |ring| {
            const theta = (@as(f32, @floatFromInt(ring)) * two_pi) / @as(f32, @floatFromInt(params.rings));
            const sin_theta = std.math.sin(theta);
            const cos_theta = std.math.cos(theta);

            // torus surface position
            const spx = sin_theta * (params.radius - (params.ring_radius * cos_phi));
            const spy = sin_phi * params.ring_radius;
            const spz = cos_theta * (params.radius - (params.ring_radius * cos_phi));

            // torus position with ring-radius zero (for normal computation)
            const ipx = sin_theta * params.radius;
            const ipy = 0.0;
            const ipz = cos_theta * params.radius;

            const pos = Vec4{ .x = spx, .y = spy, .z = spz, .w = 1.0 };
            const norm = Vec4{ .x = spx - ipx, .y = spy - ipy, .z = spz - ipz, .w = 0.0 };
            const tpos = params.transform.mul(pos);
            const tnorm = params.transform.mul(norm).normalized();
            const uv = Vec2{
                .x = @as(f32, @floatFromInt(ring)) * du,
                .y = 1.0 - @as(f32, @floatFromInt(side)) * dv,
            };
            const color = if (params.random_colors)
                _sshape_rand_color(&rand_seed)
            else
                params.color;
            buf.add_vertex(tpos, tnorm, uv, color);
        }
    }

    // generate indices
    for (0..params.sides) |side| {
        const row_a = start_index + side * (params.rings + 1);
        const row_b = row_a + params.rings + 1;
        for (0..params.rings) |ring| {
            buf.add_triangle(
                @as(u16, @intCast(row_a + ring)),
                @as(u16, @intCast(row_a + ring + 1)),
                @as(u16, @intCast(row_b + ring + 1)),
            );
            buf.add_triangle(
                @as(u16, @intCast(row_a + ring)),
                @as(u16, @intCast(row_b + ring + 1)),
                @as(u16, @intCast(row_b + ring)),
            );
        }
    }
    return buf;
}

pub fn vertexBufferDesc(buf: Buffer) sg.BufferDesc {
    std.debug.assert(buf.valid);
    var desc = sg.BufferDesc{};
    if (buf.valid) {
        desc.type = .VERTEXBUFFER;
        desc.usage = .IMMUTABLE;
        desc.data.ptr = buf.vertices.buffer.ptr;
        desc.data.size = buf.vertices.data_size;
    }
    return desc;
}

pub fn indexBufferDesc(buf: Buffer) sg.BufferDesc {
    std.debug.assert(buf.valid);
    var desc = sg.BufferDesc{};
    if (buf.valid) {
        desc.type = .INDEXBUFFER;
        desc.usage = .IMMUTABLE;
        desc.data.ptr = buf.indices.buffer.ptr;
        desc.data.size = buf.indices.data_size;
    }
    return desc;
}

// SOKOL_SHAPE_API_DECL sshape_element_range_t sshape_element_range(const sshape_buffer_t* buf) {
//     SOKOL_ASSERT(buf && buf->valid);
//     SOKOL_ASSERT(buf->indices.shape_offset < buf->indices.data_size);
//     SOKOL_ASSERT(0 == (buf->indices.shape_offset & (sizeof(uint16_t) - 1)));
//     SOKOL_ASSERT(0 == (buf->indices.data_size & (sizeof(uint16_t) - 1)));
//     sshape_element_range_t range = { 0 };
//     range.base_element = (int) (buf->indices.shape_offset / sizeof(uint16_t));
//     if (buf->valid) {
//         range.num_elements = (int) ((buf->indices.data_size - buf->indices.shape_offset) / sizeof(uint16_t));
//     }
//     else {
//         range.num_elements = 0;
//     }
//     return range;
// }

pub fn vertexBufferLayoutState() sg.VertexBufferLayoutState {
    return .{
        .stride = @sizeOf(Vertex),
    };
}

pub fn positionVertexAttrState() sg.VertexAttrState {
    return .{
        .offset = @offsetOf(Vertex, "x"),
        .format = .FLOAT3,
    };
}

pub fn normalVertexAttrState() sg.VertexAttrState {
    return .{
        .offset = @offsetOf(Vertex, "normal"),
        .format = .BYTE4N,
    };
}

pub fn texcoordVertexAttrState() sg.VertexAttrState {
    return .{
        .offset = @offsetOf(Vertex, "u"),
        .format = .USHORT2N,
    };
}

pub fn colorVertexAttrState() sg.VertexAttrState {
    return .{
        .offset = @offsetOf(Vertex, "color"),
        .format = .UBYTE4N,
    };
}
