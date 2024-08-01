const ig = @import("cimgui");

pub const DrawFunc = fn (
    name: []const u8,
    p_open: *bool,
) void;

pub const DockItem = struct {
    name: []const u8,
    is_open: bool = true,
    draw_func: *const DrawFunc,

    pub fn make(
        name: []const u8,
        draw_func: *const DrawFunc,
    ) @This() {
        return .{
            .name = name,
            .draw_func = draw_func,
        };
    }

    pub fn show(_self: @This(), is_open: bool) @This() {
        var self = _self;
        self.is_open = is_open;
        return self;
    }

    pub fn draw(self: *@This()) void {
        if (self.is_open) {
            self.draw_func(
                self.name,
                &self.is_open,
            );
        }
    }
};

const state = struct {
    var firstCall = true;
    var dockspace_id: ig.ImGuiID = undefined;
};

pub fn init() void {
    const io = ig.igGetIO();
    io.*.ConfigFlags |= ig.ImGuiConfigFlags_DockingEnable;
    state.firstCall = true;
}

const WINDOW_FLAG = (ig.ImGuiWindowFlags_MenuBar |
    ig.ImGuiWindowFlags_NoDocking |
    ig.ImGuiWindowFlags_NoBackground |
    ig.ImGuiWindowFlags_NoTitleBar |
    ig.ImGuiWindowFlags_NoCollapse |
    ig.ImGuiWindowFlags_NoResize |
    ig.ImGuiWindowFlags_NoMove |
    ig.ImGuiWindowFlags_NoBringToFrontOnFocus |
    ig.ImGuiWindowFlags_NoNavFocus);

const DOCKNODE_FLAG = (ig.ImGuiDockNodeFlags_NoCloseButton |
    ig.ImGuiDockNodeFlags_NoWindowMenuButton |
    ig.ImGuiDockNodeFlags_NoDocking |
    ig.ImGuiDockNodeFlags_NoDockingSplit |
    ig.ImGuiDockNodeFlags_NoTabBar);

pub fn frame(dockspace_name: []const u8, docks: []DockItem) void {
    const viewport = ig.igGetMainViewport();
    const pos = viewport.*.Pos;
    const size = viewport.*.Size;

    if (state.firstCall) {
        state.dockspace_id = ig.igGetID_Str(&dockspace_name[0]);
        state.firstCall = false;
        ig.igDockBuilderRemoveNode(state.dockspace_id); // Clear out existing layout
        _ = ig.igDockBuilderAddNode(state.dockspace_id, DOCKNODE_FLAG); // Add empty node
        ig.igDockBuilderSetNodeSize(state.dockspace_id, size); // Add empty node

        // build dock tree node

        //     ImGuiID dock_main_id = ImGui::GetID("main);
        //     ImGuiID rightUp = ImGui::GetID("rightUp");
        //     ImGuiID rightDown = ImGui::GetID("rightDown");
        //     ImGuiID leftUp = ImGui::GetID("leftUp");
        //     ImGuiID right;
        //     ImGuiID leftUp;
        //     ImGuiID leftDown;
        //
        //     ImGui::DockBuilderSplitNode(dock_main_id, ImGuiDir_Right, 0.4f, &right, &left);
        //
        //     ImGui::DockBuilderSplitNode(right, ImGuiDir_Down, 0.30f, &rightDown, &rightUp);
        //     ImGui::DockBuilderSplitNode(left, ImGuiDir_Down, 0.30f, &leftDown, &leftUp);
        //     ImGui::DockBuilderDockWindow("rightUp", rightUp);
        //     ImGui::DockBuilderDockWindow("leftUp", leftUp);
        //     ImGui::DockBuilderDockWindow("rightDown", rightDown);
        //
        //     ImGui::DockBuilderFinish(dock_main_id);
    }

    ig.igSetNextWindowPos(pos, 0, .{ .x = 0, .y = 0 });
    ig.igSetNextWindowSize(size, 0);
    ig.igSetNextWindowViewport(viewport.*.ID);
    ig.igPushStyleVar_Float(ig.ImGuiStyleVar_WindowBorderSize, 0.0);
    ig.igPushStyleVar_Float(ig.ImGuiStyleVar_WindowRounding, 0.0);
    ig.igPushStyleVar_Vec2(ig.ImGuiStyleVar_WindowPadding, .{ .x = 0, .y = 0 });

    // DockSpace
    _ = ig.igBegin(&dockspace_name[0], null, WINDOW_FLAG);
    ig.igPopStyleVar(3);
    _ = ig.igDockSpace(state.dockspace_id, .{ .x = 0, .y = 0 }, ig.ImGuiDockNodeFlags_PassthruCentralNode, null);
    ig.igEnd();

    // draw docks
    if (ig.igBeginMainMenuBar()) {
        if (ig.igBeginMenu("Docks", true)) {
            for (docks) |*dock| {
                // Dockの表示状態と chekmark を連動
                _ = ig.igMenuItem_BoolPtr(&dock.name[0], null, &dock.is_open, true);
            }
            ig.igEndMenu();
        }
        ig.igEndMainMenuBar();
    }

    for (docks) |*dock| {
        // dock の描画
        dock.draw();
    }
}
