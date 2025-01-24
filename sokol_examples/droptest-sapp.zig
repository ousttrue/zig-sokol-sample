//------------------------------------------------------------------------------
//  droptest-sapp.c
//  Test drag'n'drop file loading.
//------------------------------------------------------------------------------
const builtin = @import("builtin");
const sokol = @import("sokol");
const sg = sokol.gfx;
const simgui = sokol.imgui;
const ig = @import("cimgui");

const MAX_FILE_SIZE = 1024 * 1024;

const LoadState = enum {
    UNKNOWN,
    SUCCESS,
    FAILED,
    FILE_TOO_BIG,
};

const state = struct {
    var load_state: LoadState = .UNKNOWN;
    var size: i32 = 0;
    var buffer: [MAX_FILE_SIZE]u8 = undefined;
};

export fn init() void {
    sg.setup(.{
        .environment = sokol.glue.environment(),
        .logger = .{ .func = sokol.log.func },
    });
    simgui.setup(.{
        .logger = .{ .func = sokol.log.func },
    });

    // on native platforms, use sokol_fetch.h to load the dropped-file content,
    // on web, sokol_app.h has a builtin helper function for this
    if (!builtin.target.isWasm()) {
        sokol.fetch.setup(.{
            .num_channels = 1,
            .num_lanes = 1,
            .logger = .{ .func = sokol.log.func },
        });
    }
}

// render the loaded file content as hex view
fn render_file_content() void {
    const bytes_per_line = 16; // keep this 2^N
    const num_lines = @divTrunc((state.size + (bytes_per_line - 1)), bytes_per_line);

    _ = ig.igBeginChild(
        "##scrolling",
        .{ .x = 0, .y = 0 },
        0,
        ig.ImGuiWindowFlags_NoMove | ig.ImGuiWindowFlags_NoNav,
    );
    var clipper = ig.ImGuiListClipper{};
    ig.ImGuiListClipper_Begin(&clipper, num_lines, ig.igGetTextLineHeight());
    _ = ig.ImGuiListClipper_Step(&clipper);
    for (@intCast(clipper.DisplayStart)..@intCast(clipper.DisplayEnd)) |line_i| {
        const start_offset = line_i * bytes_per_line;
        var end_offset = start_offset + bytes_per_line;
        if (end_offset >= state.size) {
            end_offset = @intCast(state.size);
        }
        ig.igText("%04X: ", start_offset);
        for (start_offset..end_offset) |i| {
            ig.igSameLine();
            ig.igText("%02X ", state.buffer[i]);
        }
        ig.igSameLineEx((6 * 7.0) + (bytes_per_line * 3 * 7.0) + (2 * 7.0), 0.0);
        for (start_offset..end_offset) |i| {
            if (i != start_offset) {
                ig.igSameLine();
            }
            var c = state.buffer[i];
            if ((c < 32) or (c > 127)) {
                c = '.';
            }
            ig.igText("%c", c);
        }
    }
    ig.igText("EOF\n");
    ig.ImGuiListClipper_End(&clipper);
    ig.igEndChild();
}

export fn frame() void {
    if (!builtin.target.isWasm()) {
        sokol.fetch.dowork();
    }

    const width = sokol.app.width();
    const height = sokol.app.height();
    simgui.newFrame(.{
        .width = width,
        .height = height,
        .delta_time = sokol.app.frameDuration(),
        .dpi_scale = sokol.app.dpiScale(),
    });

    ig.igSetNextWindowPos(.{ .x = 10, .y = 10 }, ig.ImGuiCond_Once);
    ig.igSetNextWindowSize(.{ .x = 600, .y = 500 }, ig.ImGuiCond_Once);
    _ = ig.igBegin("Drop a file!", 0, 0);
    if (state.load_state != .UNKNOWN) {
        ig.igText("%s:", &sokol.app.getDroppedFilePath(0)[0]);
    }
    switch (state.load_state) {
        .FAILED => {
            ig.igText("LOAD FAILED!");
        },
        .FILE_TOO_BIG => {
            ig.igText("FILE TOO BIG!");
        },
        .SUCCESS => {
            ig.igSeparator();
            render_file_content();
        },
        .UNKNOWN => {},
    }
    ig.igEnd();

    sg.beginPass(.{ .swapchain = sokol.glue.swapchain() });
    simgui.render();
    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    if (!builtin.target.isWasm()) {
        sokol.fetch.shutdown();
    }
    simgui.shutdown();
    sg.shutdown();
}

export fn input(ev: [*c]const sokol.app.Event) void {
    _ = simgui.handleEvent(ev.*);
    if (ev.*.type == .FILES_DROPPED) {
        if (builtin.target.isWasm()) {
            const is_wasm = struct {
                // the async-loading callback for sapp_html5_fetch_dropped_file
                export fn emsc_load_callback(
                    response: [*c]const sokol.app.Html5FetchResponse,
                ) void {
                    if (response.*.succeeded) {
                        state.load_state = .SUCCESS;
                        state.size = @intCast(response.*.data.size);
                    } else if (response.*.error_code == .FETCH_ERROR_BUFFER_TOO_SMALL) {
                        state.load_state = .FILE_TOO_BIG;
                    } else {
                        state.load_state = .FAILED;
                    }
                }
            };

            // on emscripten need to use the sokol-app helper function to load the file data
            sokol.app.html5FetchDroppedFile(.{
                .dropped_file_index = 0,
                .callback = is_wasm.emsc_load_callback,
                .buffer = .{
                    .ptr = &state.buffer,
                    .size = @sizeOf(@TypeOf(state.buffer)),
                },
            });
        } else {
            const not_wasm = struct {
                // the async-loading callback for native platforms
                export fn native_load_callback(response: [*c]const sokol.fetch.Response) void {
                    if (response.*.fetched) {
                        state.load_state = .SUCCESS;
                        state.size = @intCast(response.*.data.size);
                    } else if (response.*.error_code == .BUFFER_TOO_SMALL) {
                        state.load_state = .FILE_TOO_BIG;
                    } else {
                        state.load_state = .FAILED;
                    }
                }
            };

            // native platform: use sokol-fetch to load file content
            _ = sokol.fetch.send(.{
                .path = sokol.app.getDroppedFilePath(0),
                .callback = not_wasm.native_load_callback,
                .buffer = sokol.fetch.asRange(&state.buffer),
            });
        }
    }
}

pub fn main() void {
    sokol.app.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = input,
        .width = 800,
        .height = 600,
        .window_title = "droptest-sapp",
        .enable_dragndrop = true,
        .max_dropped_files = 1,
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = sokol.log.func },
    });
}
