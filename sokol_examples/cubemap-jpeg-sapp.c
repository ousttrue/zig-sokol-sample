//------------------------------------------------------------------------------
//  cubemap-jpeg-sapp.c
//
//  Load and render cubemap from individual jpeg files.
//------------------------------------------------------------------------------
#define HANDMADE_MATH_IMPLEMENTATION
#define HANDMADE_MATH_NO_SSE
#include "HandmadeMath.h"
#define SOKOL_DEBUGTEXT_IMPL
#include "sokol_gfx.h"
#include "sokol_app.h"
#include "sokol_fetch.h"
#include "sokol_debugtext.h"
#include "sokol_log.h"
#include "sokol_glue.h"
#include "stb/stb_image.h"
#include "dbgui/dbgui.h"
#include "util/camera.h"
#include "util/fileutil.h"
#include "cubemap-jpeg-sapp.glsl.h"

static struct {
    sg_pass_action pass_action;
    sg_pipeline pip;
    sg_bindings bind;
    camera_t camera;
    int load_count;
    bool load_failed;
    sg_range pixels;
} state;

// room for loading all cubemap faces in parallel
#define FACE_WIDTH (2048)
#define FACE_HEIGHT (2048)
#define FACE_NUM_BYTES (FACE_WIDTH * FACE_HEIGHT * 4)

static void fetch_cb(const sfetch_response_t*);

static sg_range cubeface_range(int face_index) {
    assert(state.pixels.ptr);
    assert((face_index >= 0) && (face_index < SG_CUBEFACE_NUM));
    size_t offset = (size_t)(face_index * FACE_NUM_BYTES);
    assert((offset + FACE_NUM_BYTES) <= state.pixels.size);
    return (sg_range){
        .ptr = ((uint8_t*)state.pixels.ptr) + offset,
        .size = FACE_NUM_BYTES
    };
}

static void init(void) {

    sg_setup(&(sg_desc){
        .environment = sglue_environment(),
        .logger.func = slog_func,
    });
    __dbgui_setup(sapp_sample_count());

    sdtx_setup(&(sdtx_desc_t){
        .fonts[0] = sdtx_font_oric(),
        .logger.func = slog_func,
    });

    // setup sokol-fetch to load 6 faces in parallel
    sfetch_setup(&(sfetch_desc_t){
        .max_requests = 6,
        .num_channels = 1,
        .num_lanes = SG_CUBEFACE_NUM,
        .logger.func = slog_func,
    });

    // setup camera helper
    cam_init(&state.camera, &(camera_desc_t){
        .latitude = 0.0f,
        .longitude = 0.0f,
        .distance = 0.1f,
        .min_dist = 0.1f,
        .max_dist = 0.1f,
    });

    // allocate memory for pixel data (both as io buffer for JPEG data, and for the decoded pixel data)
    state.pixels.size = SG_CUBEFACE_NUM * FACE_NUM_BYTES;
    state.pixels.ptr = malloc(state.pixels.size);
    assert(state.pixels.ptr);

    // pass action, clear to black
    state.pass_action = (sg_pass_action){
        .colors[0] = { .load_action = SG_LOADACTION_CLEAR, .clear_value = { 0, 0, 0, 1 } },
    };

    const float vertices[] = {
        -1.0f, -1.0f, -1.0f,
         1.0f, -1.0f, -1.0f,
         1.0f,  1.0f, -1.0f,
        -1.0f,  1.0f, -1.0f,

        -1.0f, -1.0f,  1.0f,
         1.0f, -1.0f,  1.0f,
         1.0f,  1.0f,  1.0f,
        -1.0f,  1.0f,  1.0f,

        -1.0f, -1.0f, -1.0f,
        -1.0f,  1.0f, -1.0f,
        -1.0f,  1.0f,  1.0f,
        -1.0f, -1.0f,  1.0f,

         1.0f, -1.0f, -1.0f,
         1.0f,  1.0f, -1.0f,
         1.0f,  1.0f,  1.0f,
         1.0f, -1.0f,  1.0f,

        -1.0f, -1.0f, -1.0f,
        -1.0f, -1.0f,  1.0f,
         1.0f, -1.0f,  1.0f,
         1.0f, -1.0f, -1.0f,

        -1.0f,  1.0f, -1.0f,
        -1.0f,  1.0f,  1.0f,
         1.0f,  1.0f,  1.0f,
         1.0f,  1.0f, -1.0f,
    };
    state.bind.vertex_buffers[0] = sg_make_buffer(&(sg_buffer_desc){
        .data = SG_RANGE(vertices),
        .label = "cubemap-vertices"
    });

    const uint16_t indices[] = {
        0, 1, 2,  0, 2, 3,
        6, 5, 4,  7, 6, 4,
        8, 9, 10,  8, 10, 11,
        14, 13, 12,  15, 14, 12,
        16, 17, 18,  16, 18, 19,
        22, 21, 20,  23, 22, 20
    };
    state.bind.index_buffer = sg_make_buffer(&(sg_buffer_desc){
        .type = SG_BUFFERTYPE_INDEXBUFFER,
        .data = SG_RANGE(indices),
        .label = "cubemap-indices"
    });

    // allocate a texture handle, but initialize the texture later after data is loaded
    state.bind.fs.images[SLOT_tex] = sg_alloc_image();

    // a sampler object
    state.bind.fs.samplers[SLOT_smp] = sg_make_sampler(&(sg_sampler_desc){
        .min_filter = SG_FILTER_LINEAR,
        .mag_filter = SG_FILTER_LINEAR,
        .label = "cubemap-sampler"
    });

    // a pipeline object
    state.pip = sg_make_pipeline(&(sg_pipeline_desc){
        .layout.attrs[ATTR_vs_pos].format = SG_VERTEXFORMAT_FLOAT3,
        .shader = sg_make_shader(cubemap_shader_desc(sg_query_backend())),
        .index_type = SG_INDEXTYPE_UINT16,
        .depth = {
            .compare = SG_COMPAREFUNC_LESS_EQUAL,
            .write_enabled = true
        },
        .label = "cubemap-pipeline",
    });

    // load 6 cubemap face image files (note: filenames are in same order as SG_CUBEFACE_*)
    char path_buf[1024];
    const char* filenames[SG_CUBEFACE_NUM] = {
        "nb2_posx.jpg", "nb2_negx.jpg",
        "nb2_posy.jpg", "nb2_negy.jpg",
        "nb2_posz.jpg", "nb2_negz.jpg"
    };
    for (int i = 0; i < SG_CUBEFACE_NUM; i++) {
        sfetch_send(&(sfetch_request_t){
            .path = fileutil_get_path(filenames[i], path_buf, sizeof(path_buf)),
            .callback = fetch_cb,
            .buffer = { .ptr = cubeface_range(i).ptr, .size = cubeface_range(i).size },
        });
    }
}

static void fetch_cb(const sfetch_response_t* response) {
    if (response->fetched) {
        // decode loaded jpeg data
        int width, height, channels_in_file;
        const int desired_channels = 4;
        stbi_uc* decoded_pixels = stbi_load_from_memory(
            response->data.ptr,
            (int)response->data.size,
            &width, &height,
            &channels_in_file, desired_channels);
        if (decoded_pixels) {
            assert(width == FACE_WIDTH);
            assert(height == FACE_HEIGHT);
            // overwrite JPEG data with decoded pixel data
            memcpy((void*)response->buffer.ptr, decoded_pixels, FACE_NUM_BYTES);
            stbi_image_free(decoded_pixels);
            // all 6 faces loaded?
            if (++state.load_count == SG_CUBEFACE_NUM) {
                sg_init_image(state.bind.fs.images[SLOT_tex], &(sg_image_desc){
                    .type = SG_IMAGETYPE_CUBE,
                    .width = width,
                    .height = height,
                    .pixel_format = SG_PIXELFORMAT_RGBA8,
                    .data.subimage = {
                        [SG_CUBEFACE_POS_X][0] = cubeface_range(SG_CUBEFACE_POS_X),
                        [SG_CUBEFACE_NEG_X][0] = cubeface_range(SG_CUBEFACE_NEG_X),
                        [SG_CUBEFACE_POS_Y][0] = cubeface_range(SG_CUBEFACE_POS_Y),
                        [SG_CUBEFACE_NEG_Y][0] = cubeface_range(SG_CUBEFACE_NEG_Y),
                        [SG_CUBEFACE_POS_Z][0] = cubeface_range(SG_CUBEFACE_POS_Z),
                        [SG_CUBEFACE_NEG_Z][0] = cubeface_range(SG_CUBEFACE_NEG_Z),
                    },
                    .label = "cubemap-image",
                });
                free((void*)state.pixels.ptr); state.pixels.ptr = 0;
            }
        }
    } else if (response->failed) {
        state.load_failed = true;
    }
}

static void frame(void) {
    sfetch_dowork();
    cam_update(&state.camera, sapp_width(), sapp_height());

    const vs_params_t vs_params = {
        .mvp = state.camera.view_proj,
    };

    sdtx_canvas(sapp_widthf() * 0.5f, sapp_heightf() * 0.5f);
    sdtx_origin(1, 1);
    if (state.load_failed) {
        sdtx_puts("LOAD FAILED!");
    } else if (state.load_count < 6) {
        sdtx_puts("LOADING ...");
    } else {
        sdtx_puts("LMB + move mouse to look around");
    }

    sg_begin_pass(&(sg_pass){ .action = state.pass_action, .swapchain = sglue_swapchain() });
    sg_apply_pipeline(state.pip);
    sg_apply_bindings(&state.bind),
    sg_apply_uniforms(SG_SHADERSTAGE_VS, SLOT_vs_params, &SG_RANGE(vs_params));
    sg_draw(0, 36, 1);
    sdtx_draw();
    __dbgui_draw();
    sg_end_pass();
    sg_commit();
}

static void cleanup(void) {
    __dbgui_shutdown();
    sfetch_shutdown();
    sdtx_shutdown();
    sg_shutdown();
}

static void input(const sapp_event* ev) {
    if (__dbgui_event_with_retval(ev)) {
        return;
    }
    cam_handle_event(&state.camera, ev);
}

sapp_desc sokol_main(int argc, char* argv[]) {
    (void)argc; (void)argv;
    return (sapp_desc){
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = input,
        .width = 800,
        .height = 600,
        .sample_count = 1,
        .window_title = "cubemap-jpeg-sapp.c",
        .icon.sokol_default = true,
        .logger.func = slog_func,
    };
}
