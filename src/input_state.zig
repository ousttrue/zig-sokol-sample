const ig = @import("cimgui");

pub const InputState = struct {
    screen_width: f32 = 0,
    screen_height: f32 = 0,
    mouse_left: bool = false,
    mouse_right: bool = false,
    mouse_middle: bool = false,
    mouse_x: f32 = 0,
    mouse_y: f32 = 0,
    mouse_wheel: f32 = 0,

    pub fn from_imgui() @This() {
        const io = ig.igGetIO().*;
        var input = InputState{
            .screen_width = io.DisplaySize.x,
            .screen_height = io.DisplaySize.y,
            .mouse_x = io.MousePos.x,
            .mouse_y = io.MousePos.y,
        };

        if (!io.WantCaptureMouse) {
            input.mouse_left = io.MouseDown[ig.ImGuiMouseButton_Left];
            input.mouse_right = io.MouseDown[ig.ImGuiMouseButton_Right];
            input.mouse_middle = io.MouseDown[ig.ImGuiMouseButton_Middle];
            input.mouse_wheel = io.MouseWheel;
        }

        return input;
    }
};
