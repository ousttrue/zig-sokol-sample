//------------------------------------------------------------------------------
//  cgltf-sapp.c
//
//  A simple(!) GLTF viewer, cgltf + basisu + sokol_app.h + sokol_gfx.h + sokol_fetch.h.
//  Doesn't support all GLTF features.
//
//  https://github.com/jkuhlmann/cgltf
//------------------------------------------------------------------------------
const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const dbgui = @import("dbgui");
const shader = @import("cgltf-sapp.glsl.zig");
const rowmath = @import("rowmath");
const Mat4 = rowmath.Mat4;
const Quat = rowmath.Quat;
const Vec3 = rowmath.Vec3;
// #include "basisu/sokol_basisu.h"
const c = @cImport({
    @cInclude("cgltf.h");
});

const filename = "DamagedHelmet.gltf";

const SCENE_INVALID_INDEX = std.math.maxInt(usize);
const SCENE_MAX_BUFFERS = 16;
const SCENE_MAX_IMAGES = 16;
const SCENE_MAX_MATERIALS = 16;
const SCENE_MAX_PIPELINES = 16;
const SCENE_MAX_PRIMITIVES = 16; // aka submesh
const SCENE_MAX_MESHES = 16;
const SCENE_MAX_NODES = 16;

// statically allocated buffers for file downloads
const SFETCH_NUM_CHANNELS = 1;
const SFETCH_NUM_LANES = 4;
const MAX_FILE_SIZE = 1024 * 1024;
var sfetch_buffers: [SFETCH_NUM_CHANNELS][SFETCH_NUM_LANES][MAX_FILE_SIZE]u8 = undefined;

// per-material texture indices into scene.images for metallic material
const metallic_images_t = struct {
    base_color: usize,
    metallic_roughness: usize,
    normal: usize,
    occlusion: usize,
    emissive: usize,
};

// per-material texture indices into scene.images for specular material
// typedef struct {
//     int diffuse;
//     int specular_glossiness;
//     int normal;
//     int occlusion;
//     int emissive;
// } specular_images_t;

// fragment-shader-params and textures for metallic material
const metallic_material_t = struct {
    fs_params: shader.MetallicParams,
    images: metallic_images_t,
};

// fragment-shader-params and textures for specular material
// /*
// typedef struct {
//     specular_params_t fs_params;
//     specular_images_t images;
// } specular_material_t;
// */

// ...and everything grouped into a material struct
const material_t = struct {
    is_metallic: bool,
    metallic: metallic_material_t,
    // specular_material_t specular;
};

// helper struct to map sokol-gfx buffer bindslots to scene.buffers indices
const vertex_buffer_mapping_t = struct {
    num: usize = 0,
    buffer: [sg.max_vertex_buffers]usize = undefined,
};

// a 'primitive' (aka submesh) contains everything needed to issue a draw call
const primitive_t = struct {
    pipeline: usize, // index into scene.pipelines array
    material: usize, // index into scene.materials array
    vertex_buffers: vertex_buffer_mapping_t, // indices into bufferview array by vbuf bind slot
    index_buffer: usize, // index into bufferview array for index buffer, or SCENE_INVALID_INDEX
    base_element: u32, // index of first index or vertex to draw
    num_elements: u32, // number of vertices or indices to draw
};

// a mesh is just a group of primitives (aka submeshes)
const mesh_t = struct {
    first_primitive: usize, // index into scene.primitives
    num_primitives: usize,
};

// a node associates a transform with an mesh,
// currently, the transform matrices are 'baked' upfront into world space
const node_t = struct {
    mesh: usize, // index into scene.meshes
    transform: Mat4,
};

const image_sampler_t = struct {
    img: sg.Image,
    smp: sg.Sampler,
};

// the complete scene
const scene_t = struct {
    num_buffers: usize,
    num_images: usize,
    num_pipelines: usize,
    num_materials: usize,
    num_primitives: usize, // aka 'submeshes'
    num_meshes: usize,
    num_nodes: usize,
    buffers: [SCENE_MAX_BUFFERS]sg.Buffer,
    image_samplers: [SCENE_MAX_IMAGES]image_sampler_t,
    pipelines: [SCENE_MAX_PIPELINES]sg.Pipeline,
    materials: [SCENE_MAX_MATERIALS]material_t,
    primitives: [SCENE_MAX_PRIMITIVES]primitive_t,
    meshes: [SCENE_MAX_MESHES]mesh_t,
    nodes: [SCENE_MAX_NODES]node_t,
};

// resource creation helper params, these are stored until the
// async-loaded resources (buffers and images) have been loaded
const buffer_creation_params_t = struct {
    type: sg.BufferType,
    offset: usize,
    size: usize,
    gltf_buffer_index: usize,
};

const image_sampler_creation_params_t = struct {
    min_filter: sg.Filter,
    mag_filter: sg.Filter,
    mipmap_filter: sg.Filter,
    wrap_s: sg.Wrap,
    wrap_t: sg.Wrap,
    gltf_image_index: usize,
};

// pipeline cache helper struct to avoid duplicate pipeline-state-objects
const pipeline_cache_params_t = struct {
    layout: sg.VertexLayoutState = .{},
    prim_type: sg.PrimitiveType = .DEFAULT,
    index_type: sg.IndexType = .NONE,
    alpha: bool,
};

// the top-level application state struct
const state = struct {
    var failed = false;
    const pass_actions = struct {
        var ok = sg.PassAction{};
        var failed = sg.PassAction{};
    };
    const shaders = struct {
        var metallic = sg.Shader{};
        var specular = sg.Shader{};
    };
    //     sg_sampler smp;
    var scene: scene_t = undefined;
    var orbit = rowmath.OrbitCamera{};
    // initialize camera helper
    //     cam_init(&state.camera, &(camera_desc_t){
    //         .latitude = -10.0f,
    //         .longitude = 45.0f,
    //         .distance = 3.0f
    //     });

    var input = rowmath.InputState{};
    var point_light: shader.LightParams = undefined; // code-generated from shader
    var root_transform = Mat4.identity;
    //     float rx, ry;
    const creation_params = struct {
        var buffers: [SCENE_MAX_BUFFERS]buffer_creation_params_t = undefined;
        var images: [SCENE_MAX_IMAGES]image_sampler_creation_params_t = undefined;
    };
    const pip_cache = struct {
        var items: [SCENE_MAX_PIPELINES]pipeline_cache_params_t = undefined;
    };
    const placeholders = struct {
        var white = sg.Image{};
        var normal = sg.Image{};
        var black = sg.Image{};
        var smp = sg.Sampler{};
    };
};

// sokol-app init callback, called once at startup
export fn init() void {
    // setup sokol-gfx
    sg.setup(.{
        .environment = sokol.glue.environment(),
        .logger = .{ .func = sokol.log.func },
    });
    // setup the optional debugging UI
    dbgui.setup(sokol.app.sampleCount());

    // initialize Basis Universal
    // sbasisu_setup();

    // setup sokol-debugtext
    var sdtx_desc = sokol.debugtext.Desc{
        .logger = .{ .func = sokol.log.func },
    };
    sdtx_desc.fonts[0] = sokol.debugtext.fontOric();
    sokol.debugtext.setup(sdtx_desc);

    // normal background color, and a "load failed" background color
    state.pass_actions.ok.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.0, .g = 0.569, .b = 0.918, .a = 1.0 },
    };
    state.pass_actions.failed.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 1.0 },
    };

    // create shaders
    state.shaders.metallic = sg.makeShader(shader.cgltfMetallicShaderDesc(sg.queryBackend()));
    //state.shaders.specular = sg_make_shader(cgltf_specular_shader_desc());

    // setup the point light
    state.point_light = .{
        .light_pos = .{ 10.0, 10.0, 10.0 },
        .light_range = 200.0,
        .light_color = .{ 1.0, 1.5, 2.0 },
        .light_intensity = 700.0,
    };

    // setup sokol-fetch with 2 channels and 6 lanes per channel,
    // we'll use one channel for mesh data and the other for textures
    sokol.fetch.setup(.{
        .max_requests = 64,
        .num_channels = SFETCH_NUM_CHANNELS,
        .num_lanes = SFETCH_NUM_LANES,
        .logger = .{ .func = sokol.log.func },
    });

    // start loading the base gltf file...
    _ = sokol.fetch.send(.{
        .path = &filename[0],
        .callback = gltf_fetch_callback,
    });

    // create placeholder textures and sampler
    var pixels: [64]u32 = undefined;
    {
        for (0..64) |i| {
            pixels[i] = 0xFFFFFFFF;
        }
        var img_desc = sg.ImageDesc{
            .width = 8,
            .height = 8,
            .pixel_format = .RGBA8,
        };
        img_desc.data.subimage[0][0] = sg.asRange(&pixels);
        state.placeholders.white = sg.makeImage(img_desc);
    }
    {
        for (0..64) |i| {
            pixels[i] = 0xFF000000;
        }
        var img_desc = sg.ImageDesc{
            .width = 8,
            .height = 8,
            .pixel_format = .RGBA8,
        };
        img_desc.data.subimage[0][0] = sg.asRange(&pixels);
        state.placeholders.black = sg.makeImage(img_desc);
    }
    {
        for (0..64) |i| {
            pixels[i] = 0xFF0000FF;
        }
        var img_desc = sg.ImageDesc{
            .width = 8,
            .height = 8,
            .pixel_format = .RGBA8,
        };
        img_desc.data.subimage[0][0] = sg.asRange(&pixels);
        state.placeholders.normal = sg.makeImage(img_desc);
    }
    state.placeholders.smp = sg.makeSampler(.{
        .min_filter = .NEAREST,
        .mag_filter = .NEAREST,
        .mipmap_filter = .NONE,
    });
}

// sokol-app frame callback
export fn frame() void {
    // pump the sokol-fetch message queue
    sokol.fetch.dowork();

    state.input.screen_width = sokol.app.widthf();
    state.input.screen_height = sokol.app.heightf();
    state.orbit.frame(state.input);
    state.input.mouse_wheel = 0;

    // print help text
    sokol.debugtext.canvas(sokol.app.widthf() * 0.5, sokol.app.heightf() * 0.5);
    sokol.debugtext.color1i(0xFFFFFFFF);
    sokol.debugtext.origin(1.0, 2.0);
    sokol.debugtext.puts("LMB + drag:  rotate\n");
    sokol.debugtext.puts("mouse wheel: zoom");

    //     update_scene();

    // render the scene
    if (state.failed) {
        // if something went wrong during loading, just render a red screen
        sg.beginPass(.{
            .action = state.pass_actions.failed,
            .swapchain = sokol.glue.swapchain(),
        });
        dbgui.draw();
        sg.endPass();
    } else {
        sg.beginPass(.{
            .action = state.pass_actions.ok,
            .swapchain = sokol.glue.swapchain(),
        });
        for (0..state.scene.num_nodes) |node_index| {
            const node = &state.scene.nodes[node_index];
            const vs_params = vs_params_for_node(node_index);
            const mesh = &state.scene.meshes[node.*.mesh];
            for (0..mesh.*.num_primitives) |i| {
                const prim = &state.scene.primitives[i + mesh.*.first_primitive];
                const mat = &state.scene.materials[prim.*.material];
                sg.applyPipeline(state.scene.pipelines[prim.*.pipeline]);
                var bind = sg.Bindings{};
                for (0..prim.*.vertex_buffers.num) |vb_slot| {
                    bind.vertex_buffers[vb_slot] = state.scene.buffers[prim.*.vertex_buffers.buffer[vb_slot]];
                }
                if (prim.*.index_buffer != SCENE_INVALID_INDEX) {
                    bind.index_buffer = state.scene.buffers[prim.*.index_buffer];
                }
                sg.applyUniforms(.VS, shader.SLOT_vs_params, sg.asRange(&vs_params));
                sg.applyUniforms(.FS, shader.SLOT_light_params, sg.asRange(&state.point_light));
                if (mat.*.is_metallic) {
                    var base_color_tex = state.scene.image_samplers[mat.metallic.images.base_color].img;
                    var metallic_roughness_tex = state.scene.image_samplers[mat.metallic.images.metallic_roughness].img;
                    var normal_tex = state.scene.image_samplers[mat.metallic.images.normal].img;
                    var occlusion_tex = state.scene.image_samplers[mat.metallic.images.occlusion].img;
                    var emissive_tex = state.scene.image_samplers[mat.metallic.images.emissive].img;
                    var base_color_smp = state.scene.image_samplers[mat.metallic.images.base_color].smp;
                    var metallic_roughness_smp = state.scene.image_samplers[mat.metallic.images.metallic_roughness].smp;
                    var normal_smp = state.scene.image_samplers[mat.metallic.images.normal].smp;
                    var occlusion_smp = state.scene.image_samplers[mat.metallic.images.occlusion].smp;
                    var emissive_smp = state.scene.image_samplers[mat.metallic.images.emissive].smp;

                    if (base_color_tex.id == 0) {
                        base_color_tex = state.placeholders.white;
                        base_color_smp = state.placeholders.smp;
                    }
                    if (metallic_roughness_tex.id == 0) {
                        metallic_roughness_tex = state.placeholders.white;
                        metallic_roughness_smp = state.placeholders.smp;
                    }
                    if (normal_tex.id == 0) {
                        normal_tex = state.placeholders.normal;
                        normal_smp = state.placeholders.smp;
                    }
                    if (occlusion_tex.id == 0) {
                        occlusion_tex = state.placeholders.white;
                        occlusion_smp = state.placeholders.smp;
                    }
                    if (emissive_tex.id == 0) {
                        emissive_tex = state.placeholders.black;
                        emissive_smp = state.placeholders.smp;
                    }
                    bind.fs.images[shader.SLOT_base_color_tex] = base_color_tex;
                    bind.fs.images[shader.SLOT_metallic_roughness_tex] = metallic_roughness_tex;
                    bind.fs.images[shader.SLOT_normal_tex] = normal_tex;
                    bind.fs.images[shader.SLOT_occlusion_tex] = occlusion_tex;
                    bind.fs.images[shader.SLOT_emissive_tex] = emissive_tex;
                    bind.fs.samplers[shader.SLOT_base_color_smp] = base_color_smp;
                    bind.fs.samplers[shader.SLOT_metallic_roughness_smp] = metallic_roughness_smp;
                    bind.fs.samplers[shader.SLOT_normal_smp] = normal_smp;
                    bind.fs.samplers[shader.SLOT_occlusion_smp] = occlusion_smp;
                    bind.fs.samplers[shader.SLOT_emissive_tex] = emissive_smp;
                    sg.applyUniforms(.FS, shader.SLOT_metallic_params, sg.asRange(&mat.metallic.fs_params));
                } else {
                    // // sg_apply_uniforms(SG_SHADERSTAGE_VS,
                    // //     SLOT_specular_params,
                    // //     &mat.specular.fs_params,
                    // //     sizeof(specular_params_t));
                }
                sg.applyBindings(bind);
                sg.draw(prim.*.base_element, prim.*.num_elements, 1);
            }
        }
        sokol.debugtext.draw();
        dbgui.draw();
        sg.endPass();
    }
    sg.commit();
}

// sokol-app cleanup callback, called once at shutdown
export fn cleanup() void {
    sokol.fetch.shutdown();
    dbgui.shutdown();
    // sbasisu_shutdown();
    sg.shutdown();
}

// input event handler for camera manipulation
export fn input(e: [*c]const sokol.app.Event) void {
    if (dbgui.eventWithRetval(e)) {
        return;
    }
    switch (e.*.type) {
        .MOUSE_DOWN => {
            switch (e.*.mouse_button) {
                .LEFT => {
                    state.input.mouse_left = true;
                },
                .RIGHT => {
                    state.input.mouse_right = true;
                },
                .MIDDLE => {
                    state.input.mouse_middle = true;
                },
                .INVALID => {},
            }
        },
        .MOUSE_UP => {
            switch (e.*.mouse_button) {
                .LEFT => {
                    state.input.mouse_left = false;
                },
                .RIGHT => {
                    state.input.mouse_right = false;
                },
                .MIDDLE => {
                    state.input.mouse_middle = false;
                },
                .INVALID => {},
            }
        },
        .MOUSE_MOVE => {
            state.input.mouse_x = e.*.mouse_x;
            state.input.mouse_y = e.*.mouse_y;
        },
        .MOUSE_SCROLL => {
            state.input.mouse_wheel = e.*.scroll_y;
        },
        else => {},
    }
}

// load-callback for the GLTF base file
export fn gltf_fetch_callback(response: [*c]const sokol.fetch.Response) void {
    if (response.*.dispatched) {
        // bind buffer to load file into
        sokol.fetch.bindBuffer(
            response.*.handle,
            sokol.fetch.asRange(&sfetch_buffers[response.*.channel][response.*.lane]),
        );
    } else if (response.*.fetched) {
        // file has been loaded, parse as GLTF
        gltf_parse(response.*.data);
    }
    if (response.*.finished) {
        if (response.*.failed) {
            state.failed = true;
        }
    }
}

// load-callback for GLTF buffer files
const gltf_buffer_fetch_userdata_t = struct {
    buffer_index: c.cgltf_size,
};

export fn gltf_buffer_fetch_callback(response: [*c]const sokol.fetch.Response) void {
    if (response.*.dispatched) {
        sokol.fetch.bindBuffer(
            response.*.handle,
            sokol.fetch.asRange(&sfetch_buffers[response.*.channel][response.*.lane]),
        );
    } else if (response.*.fetched) {
        const user_data: *const gltf_buffer_fetch_userdata_t = @ptrCast(@alignCast(response.*.user_data));
        const buffer_index = user_data.*.buffer_index;
        create_sg_buffers_for_gltf_buffer(
            buffer_index,
            .{ .ptr = response.*.data.ptr, .size = response.*.data.size },
        );
    }
    if (response.*.finished) {
        if (response.*.failed) {
            state.failed = true;
        }
    }
}

// load-callback for GLTF image files
const gltf_image_fetch_userdata_t = struct {
    image_index: c.cgltf_size,
};

export fn gltf_image_fetch_callback(response: [*c]const sokol.fetch.Response) void {
    if (response.*.dispatched) {
        sokol.fetch.bindBuffer(response.*.handle, sokol.fetch.asRange(&sfetch_buffers[response.*.channel][response.*.lane]));
    } else if (response.*.fetched) {
        const user_data: *const gltf_image_fetch_userdata_t = @ptrCast(@alignCast(response.*.user_data));
        const gltf_image_index = user_data.image_index;
        create_sg_image_samplers_for_gltf_image(
            gltf_image_index,
            .{ .ptr = response.*.data.ptr, .size = response.*.data.size },
        );
    }
    if (response.*.finished) {
        if (response.*.failed) {
            state.failed = true;
        }
    }
}

// load GLTF data from memory, build scene and issue resource fetch requests
fn gltf_parse(file_data: sokol.fetch.Range) void {
    var options = c.cgltf_options{};
    var data: [*c]c.cgltf_data = undefined;
    const result = c.cgltf_parse(&options, file_data.ptr, file_data.size, &data);
    if (result == c.cgltf_result_success) {
        gltf_parse_buffers(data);
        gltf_parse_images(data);
        gltf_parse_materials(data);
        gltf_parse_meshes(data);
        gltf_parse_nodes(data);
        c.cgltf_free(data);
    }
}

// compute indices from cgltf element pointers
fn get_gltf_buffer_index(gltf: *const c.cgltf_data, buf: *const c.cgltf_buffer) usize {
    const d = @intFromPtr(buf) - @intFromPtr(&gltf.buffers[0]);
    return @divTrunc(d, @sizeOf(c.cgltf_buffer));
}

fn get_gltf_bufferview_index(gltf: *const c.cgltf_data, buf_view: *const c.cgltf_buffer_view) usize {
    const d = @intFromPtr(buf_view) - @intFromPtr(&gltf.buffer_views[0]);
    return @divTrunc(d, @sizeOf(c.cgltf_buffer_view));
}

fn get_gltf_image_index(gltf: *const c.cgltf_data, img: *const c.cgltf_image) usize {
    const d = @intFromPtr(img) - @intFromPtr(&gltf.images[0]);
    return @divTrunc(d, @sizeOf(c.cgltf_image));
}

fn get_gltf_texture_index(gltf: *const c.cgltf_data, tex: *const c.cgltf_texture) usize {
    const d = @intFromPtr(tex) - @intFromPtr(&gltf.textures[0]);
    return @divTrunc(d, @sizeOf(c.cgltf_texture));
}

fn get_gltf_material_index(gltf: *const c.cgltf_data, mat: *const c.cgltf_material) usize {
    const d = @intFromPtr(mat) - @intFromPtr(&gltf.materials[0]);
    return @divTrunc(d, @sizeOf(c.cgltf_material));
}

fn get_gltf_mesh_index(gltf: *const c.cgltf_data, mesh: *const c.cgltf_mesh) usize {
    const d = @intFromPtr(mesh) - @intFromPtr(&gltf.meshes[0]);
    return @divTrunc(d, @sizeOf(c.cgltf_mesh));
}

// parse the GLTF buffer definitions and start loading buffer blobs
fn gltf_parse_buffers(gltf: *const c.cgltf_data) void {
    if (gltf.buffer_views_count > SCENE_MAX_BUFFERS) {
        state.failed = true;
        return;
    }

    // parse the buffer-view attributes
    state.scene.num_buffers = gltf.buffer_views_count;
    for (0..state.scene.num_buffers) |i| {
        const gltf_buf_view = &gltf.buffer_views[i];
        const p = &state.creation_params.buffers[i];
        p.gltf_buffer_index = get_gltf_buffer_index(gltf, gltf_buf_view.buffer);
        p.offset = gltf_buf_view.offset;
        p.size = gltf_buf_view.size;
        if (gltf_buf_view.type == c.cgltf_buffer_view_type_indices) {
            p.type = .INDEXBUFFER;
        } else {
            p.type = .VERTEXBUFFER;
        }
        // allocate a sokol-gfx buffer handle
        state.scene.buffers[i] = sg.allocBuffer();
    }

    // start loading all buffers
    for (0..gltf.buffers_count) |i| {
        const gltf_buf = &gltf.buffers[i];
        var user_data = gltf_buffer_fetch_userdata_t{ .buffer_index = i };
        // var path_buf: [512]u8 = undefined;
        _ = sokol.fetch.send(.{
            .path = gltf_buf.uri,
            .callback = gltf_buffer_fetch_callback,
            .user_data = sokol.fetch.asRange(&user_data),
        });
    }
}

// parse all the image-related stuff in the GLTF data

// https://github.com/KhronosGroup/glTF/tree/master/specification/2.0#samplerminfilter
fn gltf_to_sg_min_filter(gltf_filter: c_int) sg.Filter {
    return switch (gltf_filter) {
        9728 => .NEAREST,
        9729 => .LINEAR,
        else => .LINEAR,
    };
}

fn gltf_to_sg_mag_filter(gltf_filter: c_int) sg.Filter {
    return switch (gltf_filter) {
        9728 => .NEAREST,
        9729 => .LINEAR,
        else => .LINEAR,
    };
}

fn gltf_to_sg_mipmap_filter(gltf_filter: c_int) sg.Filter {
    return switch (gltf_filter) {
        9728 => .NONE,
        9729 => .NONE,
        9984 => .NEAREST,
        9985 => .NEAREST,
        9986 => .LINEAR,
        9987 => .LINEAR,
        else => .LINEAR,
    };
}

// https://github.com/KhronosGroup/glTF/tree/master/specification/2.0#samplerwraps
fn gltf_to_sg_wrap(gltf_wrap: c_int) sg.Wrap {
    return switch (gltf_wrap) {
        33071 => .CLAMP_TO_EDGE,
        33648 => .MIRRORED_REPEAT,
        10497 => .REPEAT,
        else => .REPEAT,
    };
}

fn gltf_parse_images(gltf: *const c.cgltf_data) void {
    if (gltf.textures_count > SCENE_MAX_IMAGES) {
        state.failed = true;
        return;
    }

    // parse the texture and sampler attributes
    state.scene.num_images = gltf.textures_count;
    for (0..state.scene.num_images) |i| {
        const gltf_tex = &gltf.textures[i];
        const p = &state.creation_params.images[i];
        p.gltf_image_index = get_gltf_image_index(gltf, gltf_tex.image);
        p.min_filter = gltf_to_sg_min_filter(gltf_tex.sampler.*.min_filter);
        p.mag_filter = gltf_to_sg_mag_filter(gltf_tex.sampler.*.mag_filter);
        p.mipmap_filter = gltf_to_sg_mipmap_filter(gltf_tex.sampler.*.min_filter);
        p.wrap_s = gltf_to_sg_wrap(gltf_tex.sampler.*.wrap_s);
        p.wrap_t = gltf_to_sg_wrap(gltf_tex.sampler.*.wrap_t);
        state.scene.image_samplers[i].img.id = sg.invalid_id;
        state.scene.image_samplers[i].smp.id = sg.invalid_id;
    }

    // start loading all images
    for (0..gltf.images_count) |i| {
        const gltf_img = &gltf.images[i];
        const user_data = gltf_image_fetch_userdata_t{ .image_index = i };
        // char path_buf[512];
        _ = sokol.fetch.send(.{
            .path = gltf_img.uri,
            .callback = gltf_image_fetch_callback,
            .user_data = sokol.fetch.asRange(&user_data),
        });
    }
}

// parse GLTF materials into our own material definition
fn gltf_parse_materials(gltf: *const c.cgltf_data) void {
    if (gltf.materials_count > SCENE_MAX_MATERIALS) {
        state.failed = true;
        return;
    }
    state.scene.num_materials = gltf.materials_count;
    for (0..state.scene.num_materials) |i| {
        const gltf_mat = &gltf.materials[i];
        const scene_mat = &state.scene.materials[i];
        scene_mat.is_metallic = gltf_mat.has_pbr_metallic_roughness != 0;
        if (scene_mat.is_metallic) {
            const src = &gltf_mat.pbr_metallic_roughness;
            const dst = &scene_mat.metallic;
            for (0..4) |d| {
                dst.fs_params.base_color_factor[d] = src.base_color_factor[d];
            }
            for (0..3) |d| {
                dst.fs_params.emissive_factor[d] = gltf_mat.emissive_factor[d];
            }
            dst.fs_params.metallic_factor = src.metallic_factor;
            dst.fs_params.roughness_factor = src.roughness_factor;
            dst.images = .{
                .base_color = get_gltf_texture_index(gltf, src.base_color_texture.texture),
                .metallic_roughness = get_gltf_texture_index(gltf, src.metallic_roughness_texture.texture),
                .normal = get_gltf_texture_index(gltf, gltf_mat.normal_texture.texture),
                .occlusion = get_gltf_texture_index(gltf, gltf_mat.occlusion_texture.texture),
                .emissive = get_gltf_texture_index(gltf, gltf_mat.emissive_texture.texture),
            };
        } else {
            //             /*
            //             const cgltf_pbr_specular_glossiness* src = &gltf_mat.pbr_specular_glossiness;
            //             specular_material_t* dst = &scene_mat.specular;
            //             for (int d = 0; d < 4; d++) {
            //                 dst.fs_params.diffuse_factor.Elements[d] = src.diffuse_factor[d];
            //             }
            //             for (int d = 0; d < 3; d++) {
            //                 dst.fs_params.specular_factor.Elements[d] = src.specular_factor[d];
            //             }
            //             for (int d = 0; d < 3; d++) {
            //                 dst.fs_params.emissive_factor.Elements[d] = gltf_mat.emissive_factor[d];
            //             }
            //             dst.fs_params.glossiness_factor = src.glossiness_factor;
            //             dst.images = (specular_images_t) {
            //                 .diffuse = gltf_texture_index(gltf, src.diffuse_texture.texture),
            //                 .specular_glossiness = gltf_texture_index(gltf, src.specular_glossiness_texture.texture),
            //                 .normal = gltf_texture_index(gltf, gltf_mat.normal_texture.texture),
            //                 .occlusion = gltf_texture_index(gltf, gltf_mat.occlusion_texture.texture),
            //                 .emissive = gltf_texture_index(gltf, gltf_mat.emissive_texture.texture)
            //             };
            //             */
        }
    }
}

// parse GLTF meshes into our own mesh and submesh definition
fn gltf_parse_meshes(gltf: *const c.cgltf_data) void {
    if (gltf.meshes_count > SCENE_MAX_MESHES) {
        state.failed = true;
        return;
    }
    //     state.scene.num_meshes = (int) gltf.meshes_count;
    for (0..gltf.meshes_count) |mesh_index| {
        const gltf_mesh = &gltf.meshes[mesh_index];
        if ((gltf_mesh.primitives_count + state.scene.num_primitives) > SCENE_MAX_PRIMITIVES) {
            state.failed = true;
            return;
        }
        const mesh = &state.scene.meshes[mesh_index];
        mesh.first_primitive = state.scene.num_primitives;
        mesh.num_primitives = gltf_mesh.primitives_count;
        for (0..gltf_mesh.primitives_count) |prim_index| {
            const gltf_prim: *const c.cgltf_primitive = @ptrCast(&gltf_mesh.primitives[prim_index]);
            const prim = &state.scene.primitives[state.scene.num_primitives];
            state.scene.num_primitives += 1;

            // a mapping from sokol-gfx vertex buffer bind slots into the scene.buffers array
            prim.vertex_buffers = create_vertex_buffer_mapping_for_gltf_primitive(gltf, gltf_prim);
            // create or reuse a matching pipeline state object
            prim.pipeline = create_sg_pipeline_for_gltf_primitive(gltf, gltf_prim, &prim.vertex_buffers);
            // the material parameters
            prim.material = get_gltf_material_index(gltf, gltf_prim.material);
            // index buffer, base element, num elements
            if (gltf_prim.indices != null) {
                prim.index_buffer = get_gltf_bufferview_index(gltf, gltf_prim.indices.*.buffer_view);
                std.debug.assert(state.creation_params.buffers[prim.index_buffer].type == .INDEXBUFFER);
                std.debug.assert(gltf_prim.indices.*.stride != 0);
                prim.base_element = 0;
                prim.num_elements = @intCast(gltf_prim.indices.*.count);
            } else {
                // hmm... looking up the number of elements to render from
                // a random vertex component accessor looks a bit shady
                prim.index_buffer = SCENE_INVALID_INDEX;
                prim.base_element = 0;
                prim.num_elements = @intCast(gltf_prim.attributes.*.data.*.count);
            }
        }
    }
}

// parse GLTF nodes into our own node definition
fn gltf_parse_nodes(gltf: *const c.cgltf_data) void {
    if (gltf.nodes_count > SCENE_MAX_NODES) {
        state.failed = true;
        return;
    }
    for (0..gltf.nodes_count) |node_index| {
        const gltf_node = &gltf.nodes[node_index];
        // ignore nodes without mesh, those are not relevant since we
        // bake the transform hierarchy into per-node world space transforms
        if (gltf_node.mesh) |gltf_mesh| {
            const node = &state.scene.nodes[state.scene.num_nodes];
            state.scene.num_nodes += 1;
            node.mesh = get_gltf_mesh_index(gltf, gltf_mesh);
            node.transform = build_transform_for_gltf_node(gltf, @ptrCast(gltf_node));
        }
    }
}

// create the sokol-gfx buffer objects associated with a GLTF buffer view
fn create_sg_buffers_for_gltf_buffer(gltf_buffer_index: usize, data: sg.Range) void {
    for (0..state.scene.num_buffers) |i| {
        const p = &state.creation_params.buffers[i];
        if (p.gltf_buffer_index == gltf_buffer_index) {
            std.debug.assert(p.offset + p.size <= data.size);
            sg.initBuffer(state.scene.buffers[i], .{ .type = p.type, .data = .{
                .ptr = @ptrFromInt(@intFromPtr(data.ptr) + p.offset),
                .size = p.size,
            } });
        }
    }
}

// create the sokol-gfx image objects associated with a GLTF image
fn create_sg_image_samplers_for_gltf_image(gltf_image_index: usize, data: sg.Range) void {
    for (0..state.scene.num_images) |i| {
        const p = &state.creation_params.images[i];
        if (p.gltf_image_index == gltf_image_index) {
            _ = data;
            // state.scene.image_samplers[i].img = sbasisu_make_image(data);
            state.scene.image_samplers[i].smp = sg.makeSampler(.{
                .min_filter = p.min_filter,
                .mag_filter = p.mag_filter,
                .mipmap_filter = p.mipmap_filter,
            });
        }
    }
}

fn gltf_to_vertex_format(acc: *const c.cgltf_accessor) sg.VertexFormat {
    return switch (acc.component_type) {
        c.cgltf_component_type_r_8 => if (acc.type == c.cgltf_type_vec4)
            if (acc.normalized != 0) .BYTE4N else .BYTE4
        else
            unreachable,
        c.cgltf_component_type_r_8u => if (acc.type == c.cgltf_type_vec4)
            if (acc.normalized != 0) .UBYTE4N else .UBYTE4
        else
            unreachable,
        c.cgltf_component_type_r_16 => switch (acc.type) {
            c.cgltf_type_vec2 => if (acc.normalized != 0) .SHORT2N else .SHORT2,
            c.cgltf_type_vec4 => if (acc.normalized != 0) .SHORT4N else .SHORT4,
            else => unreachable,
        },
        c.cgltf_component_type_r_32f => switch (acc.type) {
            c.cgltf_type_scalar => .FLOAT,
            c.cgltf_type_vec2 => .FLOAT2,
            c.cgltf_type_vec3 => .FLOAT3,
            c.cgltf_type_vec4 => .FLOAT4,
            else => unreachable,
        },
        else => unreachable,
    };
}

fn gltf_attr_type_to_vs_input_slot(attr_type: c.cgltf_attribute_type) usize {
    return switch (attr_type) {
        c.cgltf_attribute_type_position => shader.ATTR_vs_position,
        c.cgltf_attribute_type_normal => shader.ATTR_vs_normal,
        c.cgltf_attribute_type_texcoord => shader.ATTR_vs_texcoord,
        else => SCENE_INVALID_INDEX,
    };
}

fn gltf_to_prim_type(prim_type: c.cgltf_primitive_type) sg.PrimitiveType {
    return switch (prim_type) {
        c.cgltf_primitive_type_points => .POINTS,
        c.cgltf_primitive_type_lines => .LINES,
        c.cgltf_primitive_type_line_strip => .LINE_STRIP,
        c.cgltf_primitive_type_triangles => .TRIANGLES,
        c.cgltf_primitive_type_triangle_strip => .TRIANGLE_STRIP,
        else => .DEFAULT,
    };
}

fn gltf_to_index_type(prim: *const c.cgltf_primitive) sg.IndexType {
    return if (prim.indices != null)
        if (prim.indices.*.component_type == c.cgltf_component_type_r_16u)
            .UINT16
        else
            .UINT32
    else
        return .NONE;
}

// creates a vertex buffer bind slot mapping for a specific GLTF primitive
fn create_vertex_buffer_mapping_for_gltf_primitive(gltf: *const c.cgltf_data, prim: *const c.cgltf_primitive) vertex_buffer_mapping_t {
    var map = vertex_buffer_mapping_t{};
    for (0..sg.max_vertex_buffers) |i| {
        map.buffer[i] = SCENE_INVALID_INDEX;
    }
    for (0..prim.attributes_count) |attr_index| {
        const attr = &prim.attributes[attr_index];
        const acc = attr.data;
        const buffer_view_index = get_gltf_bufferview_index(gltf, acc.*.buffer_view);
        var i: usize = 0;
        while (i < map.num) : (i += 1) {
            if (map.buffer[i] == buffer_view_index) {
                break;
            }
        }
        if ((i == map.num) and (map.num < sg.max_vertex_buffers)) {
            map.buffer[map.num] = buffer_view_index;
            map.num += 1;
        }
        std.debug.assert(map.num <= sg.max_vertex_buffers);
    }
    return map;
}

fn create_sg_layout_for_gltf_primitive(
    gltf: *const c.cgltf_data,
    prim: *const c.cgltf_primitive,
    vbuf_map: *const vertex_buffer_mapping_t,
) sg.VertexLayoutState {
    std.debug.assert(prim.attributes_count <= sg.max_vertex_attributes);
    var layout = sg.VertexLayoutState{};
    for (0..prim.attributes_count) |attr_index| {
        const attr = &prim.attributes[attr_index];
        const attr_slot = gltf_attr_type_to_vs_input_slot(attr.type);
        if (attr_slot != SCENE_INVALID_INDEX) {
            layout.attrs[attr_slot].format = gltf_to_vertex_format(attr.data);
        }
        const buffer_view_index = get_gltf_bufferview_index(gltf, attr.data.*.buffer_view);
        for (0..vbuf_map.num) |vb_slot| {
            if (vbuf_map.buffer[vb_slot] == buffer_view_index) {
                layout.attrs[attr_slot].buffer_index = @intCast(vb_slot);
            }
        }
    }
    return layout;
}

// helper to compare to pipeline-cache items
fn pipelines_equal(
    p0: *const pipeline_cache_params_t,
    p1: *const pipeline_cache_params_t,
) bool {
    if (p0.prim_type != p1.prim_type) {
        return false;
    }
    if (p0.alpha != p1.alpha) {
        return false;
    }
    if (p0.index_type != p1.index_type) {
        return false;
    }
    for (0..sg.max_vertex_attributes) |i| {
        const a0 = &p0.layout.attrs[i];
        const a1 = &p1.layout.attrs[i];
        if ((a0.buffer_index != a1.buffer_index) or
            (a0.offset != a1.offset) or
            (a0.format != a1.format))
        {
            return false;
        }
    }
    return true;
}

// Create a unique sokol-gfx pipeline object for GLTF primitive (aka submesh),
// maintains a cache of shared, unique pipeline objects. Returns an index
// into state.scene.pipelines
fn create_sg_pipeline_for_gltf_primitive(
    gltf: *const c.cgltf_data,
    prim: *const c.cgltf_primitive,
    vbuf_map: *const vertex_buffer_mapping_t,
) usize {
    const pip_params = pipeline_cache_params_t{
        .layout = create_sg_layout_for_gltf_primitive(gltf, prim, vbuf_map),
        .prim_type = gltf_to_prim_type(prim.type),
        .index_type = gltf_to_index_type(prim),
        .alpha = prim.material.*.alpha_mode != c.cgltf_alpha_mode_opaque,
    };
    var i: usize = 0;
    while (i < state.scene.num_pipelines) : (i += 1) {
        if (pipelines_equal(&state.pip_cache.items[i], &pip_params)) {
            // an indentical pipeline already exists, reuse this
            std.debug.assert(state.scene.pipelines[i].id != sg.invalid_id);
            return i;
        }
    }
    if ((i == state.scene.num_pipelines) and (state.scene.num_pipelines < SCENE_MAX_PIPELINES)) {
        state.pip_cache.items[i] = pip_params;
        const is_metallic = prim.material.*.has_pbr_metallic_roughness != 0;
        state.scene.pipelines[i] = sg.makePipeline(.{
            .layout = pip_params.layout,
            .shader = if (is_metallic) state.shaders.metallic else state.shaders.specular,
            .primitive_type = pip_params.prim_type,
            .index_type = pip_params.index_type,
            .cull_mode = .BACK,
            .face_winding = .CCW,
            .depth = .{
                .write_enabled = !pip_params.alpha,
                .compare = .LESS_EQUAL,
            },
            .colors = .{
                .{
                    .write_mask = if (pip_params.alpha) .RGB else .DEFAULT,
                    .blend = .{
                        .enabled = pip_params.alpha,
                        .src_factor_rgb = if (pip_params.alpha) .SRC_ALPHA else .DEFAULT,
                        .dst_factor_rgb = if (pip_params.alpha) .ONE_MINUS_SRC_ALPHA else .DEFAULT,
                    },
                },
                .{},
                .{},
                .{},
            },
        });
        state.scene.num_pipelines += 1;
    }
    std.debug.assert(state.scene.num_pipelines <= SCENE_MAX_PIPELINES);
    return i;
}

fn build_transform_for_gltf_node(
    gltf: *const c.cgltf_data,
    node: *const c.cgltf_node,
) Mat4 {
    var parent_tform = Mat4.identity;
    if (node.parent) |node_parent| {
        parent_tform = build_transform_for_gltf_node(gltf, node_parent);
    }
    if (node.has_matrix != 0) {
        // needs testing, not sure if the element order is correct
        const tform = node.matrix;
        return .{
            .m = .{
                tform[0],  tform[1],  tform[2],  tform[3],
                tform[4],  tform[5],  tform[6],  tform[7],
                tform[8],  tform[9],  tform[10], tform[11],
                tform[12], tform[13], tform[14], tform[15],
            },
        };
    } else {
        var translate = Mat4.identity;
        var rotate = Mat4.identity;
        var scale = Mat4.identity;
        if (node.has_translation != 0) {
            translate = Mat4.translate(.{
                .x = node.translation[0],
                .y = node.translation[1],
                .z = node.translation[2],
            });
        }
        if (node.has_rotation != 0) {
            rotate = Mat4.fromTrs(.{ .r = Quat{
                .x = node.rotation[0],
                .y = node.rotation[1],
                .z = node.rotation[2],
                .w = node.rotation[3],
            } });
        }
        if (node.has_scale != 0) {
            scale = Mat4.makeScale(.{
                .x = node.scale[0],
                .y = node.scale[1],
                .z = node.scale[2],
            });
        }
        // NOTE: not sure if the multiplication order is correct
        return parent_tform.mul(scale.mul(rotate).mul(translate));
    }
}

// static void update_scene(void) {
//     /*
//     state.rx += 0.25f;
//     state.ry += 2.0f;
//     */
//     state.root_transform = HMM_Rotate(state.rx, HMM_Vec3(0, 1, 0));
// }

fn vs_params_for_node(node_index: usize) shader.VsParams {
    const model_transform = state.root_transform.mul(state.scene.nodes[node_index].transform);
    const eye = state.orbit.camera.transform.translation;
    return .{
        .model = model_transform.m,
        .view_proj = state.orbit.camera.viewProjectionMatrix().m,
        .eye_pos = .{ eye.x, eye.y, eye.z },
    };
}

pub fn main() void {
    sokol.app.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .event_cb = input,
        .cleanup_cb = cleanup,
        .width = 800,
        .height = 600,
        .sample_count = 4,
        .window_title = "GLTF Viewer",
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = sokol.log.func },
    });
}
