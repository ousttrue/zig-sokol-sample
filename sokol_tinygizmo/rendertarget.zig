const builtin = @import("builtin");
const sokol = @import("sokol");
const sg = sokol.gfx;
const simgui = sokol.imgui;
const ig = @import("cimgui");
const rowmath = @import("rowmath");
const Vec2 = rowmath.Vec2;
const Camera = rowmath.Camera;
const InputState = rowmath.InputState;

extern fn Custom_ButtonBehaviorMiddleRight() void;

fn is_contain(pos: ig.ImVec2, size: ig.ImVec2, p: ig.ImVec2) bool {
    return (p.x >= pos.x and p.x <= (pos.x + size.x)) and (p.y >= pos.y and p.y <= (pos.y + size.y));
}

fn input_from_rendertarget(pos: ig.ImVec2, size: ig.ImVec2) InputState {
    const io = ig.igGetIO().*;
    var input = InputState{
        .screen_width = size.x,
        .screen_height = size.y,
        .mouse_x = io.MousePos.x - pos.x,
        .mouse_y = io.MousePos.y - pos.y,
    };

    if (ig.igIsItemActive()) {
        input.mouse_left = io.MouseDown[ig.ImGuiMouseButton_Left];
        input.mouse_right = io.MouseDown[ig.ImGuiMouseButton_Right];
        input.mouse_middle = io.MouseDown[ig.ImGuiMouseButton_Middle];
    } else if (ig.igIsItemHovered(0)) {
        input.mouse_wheel = io.MouseWheel;
    }

    return input;
}

pub const RenderTarget = struct {
    width: i32,
    height: i32,
    attachments_desc: sg.AttachmentsDesc,
    attachments: sg.Attachments,
    pass: sg.Pass,
    image: simgui.Image,

    pub fn init(width: i32, height: i32) @This() {
        const color_img = sg.makeImage(.{
            .render_target = true,
            .width = width,
            .height = height,
            .pixel_format = .RGBA8,
            // required
            .sample_count = 1,
            .label = "color-image",
        });
        const depth_img = sg.makeImage(.{
            .render_target = true,
            .width = width,
            .height = height,
            .pixel_format = .DEPTH,
            // required
            .sample_count = 1,
            .label = "depth-image",
        });
        var attachments_desc = sg.AttachmentsDesc{
            .depth_stencil = .{ .image = depth_img },
            .label = "offscreen-attachments",
        };
        attachments_desc.colors[0] = .{ .image = color_img };
        const attachments = sg.makeAttachments(attachments_desc);

        return .{
            .width = width,
            .height = height,
            .attachments_desc = attachments_desc,
            .attachments = attachments,
            .pass = sg.Pass{
                .attachments = attachments,
                .action = .{
                    .colors = .{
                        .{
                            .load_action = .CLEAR,
                            .clear_value = .{ .r = 0.25, .g = 0.25, .b = 0.25, .a = 1.0 },
                        },
                        .{},
                        .{},
                        .{},
                    },
                },
                .label = "offscreen-pass",
            },
            .image = simgui.makeImage(.{
                .image = color_img,
            }),
        };
    }

    pub fn deinit(self: @This()) void {
        simgui.destroyImage(self.image);
        sg.destroyAttachments(self.attachments);
        sg.destroyImage(self.attachments_desc.colors[0].image);
        sg.destroyImage(self.attachments_desc.depth_stencil.image);
    }
};

pub const RenderTargetImageButtonContext = struct {
    hover: bool,
    cursor: Vec2,
};

pub const RenderView = struct {
    camera: Camera = Camera{},
    pip: sg.Pipeline = .{},
    pass_action: sg.PassAction = .{
        .colors = .{
            .{
                // initial clear color
                .load_action = .CLEAR,
                .clear_value = .{ .r = 0.0, .g = 0.5, .b = 1.0, .a = 1.0 },
            },
            .{},
            .{},
            .{},
        },
    },
    sgl_ctx: sokol.gl.Context = .{},
    rendertarget: ?RenderTarget = null,

    fn get_or_create(self: *@This(), width: i32, height: i32) RenderTarget {
        if (self.rendertarget) |rendertarget| {
            if (rendertarget.width == width and rendertarget.height == height) {
                return rendertarget;
            }
            rendertarget.deinit();
        }

        const rendertarget = RenderTarget.init(width, height);
        self.rendertarget = rendertarget;
        return rendertarget;
    }

    pub fn update(self: *@This(), input: InputState) Vec2 {
        return self.camera.update(input);
    }

    pub fn begin(self: *@This(), _rendertarget: ?RenderTarget) void {
        if (_rendertarget) |rendertarget| {
            sg.beginPass(rendertarget.pass);
            sokol.gl.setContext(self.sgl_ctx);
        } else {
            sg.beginPass(.{
                .action = self.pass_action,
                .swapchain = sokol.glue.swapchain(),
            });
            sokol.gl.setContext(sokol.gl.defaultContext());
        }

        sokol.gl.defaults();
        sokol.gl.matrixModeProjection();
        sokol.gl.multMatrix(&self.camera.projection.m[0]);
        sokol.gl.matrixModeModelview();
        sokol.gl.multMatrix(&self.camera.transform.worldToLocal().m[0]);
    }

    pub fn end(self: *@This(), _rendertarget: ?RenderTarget) void {
        if (_rendertarget) |_| {
            sokol.gl.contextDraw(self.sgl_ctx);
        } else {
            sokol.gl.contextDraw(sokol.gl.defaultContext());
            simgui.render();
        }
        sg.endPass();
    }

    pub fn beginImageButton(self: *@This()) ?RenderTargetImageButtonContext {
        const io = ig.igGetIO();
        var pos = ig.ImVec2{};
        ig.igGetCursorScreenPos(&pos);
        var size = ig.ImVec2{};
        ig.igGetContentRegionAvail(&size);
        const hover = is_contain(pos, size, io.*.MousePos);

        if (size.x <= 0 or size.y <= 0) {
            return null;
        }

        const rendertarget = self.get_or_create(
            @intFromFloat(size.x),
            @intFromFloat(size.y),
        );

        ig.igPushStyleVar_Vec2(ig.ImGuiStyleVar_FramePadding, .{ .x = 0, .y = 0 });
        defer ig.igPopStyleVar(1);
        _ = ig.igImageButton(
            "fbo",
            simgui.imtextureid(rendertarget.image),
            size,
            .{ .x = 0, .y = if (builtin.os.tag == .emscripten) 1 else 0 },
            .{ .x = 1, .y = if (builtin.os.tag == .emscripten) 0 else 1 },
            .{ .x = 1, .y = 1, .z = 1, .w = 1 },
            .{ .x = 1, .y = 1, .z = 1, .w = 1 },
        );

        Custom_ButtonBehaviorMiddleRight();
        const offscreen_cursor = self.update(input_from_rendertarget(pos, size));

        // render offscreen
        self.begin(rendertarget);

        return .{
            .hover = hover,
            .cursor = offscreen_cursor,
        };
    }

    pub fn endImageButton(self: *@This()) void {
        if (self.rendertarget) |rendertarget| {
            self.end(rendertarget);
        }
    }
};
