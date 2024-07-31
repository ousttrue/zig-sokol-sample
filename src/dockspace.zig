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

pub fn init() void {
    const io = ig.igGetIO();
    io.*.ConfigFlags |= ig.ImGuiConfigFlags_DockingEnable;
}

pub fn frame(name: []const u8, docks: []DockItem) void {
    const flags = (ig.ImGuiWindowFlags_MenuBar |
        ig.ImGuiWindowFlags_NoDocking |
        ig.ImGuiWindowFlags_NoBackground |
        ig.ImGuiWindowFlags_NoTitleBar |
        ig.ImGuiWindowFlags_NoCollapse |
        ig.ImGuiWindowFlags_NoResize |
        ig.ImGuiWindowFlags_NoMove |
        ig.ImGuiWindowFlags_NoBringToFrontOnFocus |
        ig.ImGuiWindowFlags_NoNavFocus);

    const viewport = ig.igGetMainViewport();
    const pos = viewport.*.Pos;
    const size = viewport.*.Size;
    ig.igSetNextWindowPos(pos, 0, .{ .x = 0, .y = 0 });
    ig.igSetNextWindowSize(size, 0);
    ig.igSetNextWindowViewport(viewport.*.ID);
    ig.igPushStyleVar_Float(ig.ImGuiStyleVar_WindowBorderSize, 0.0);
    ig.igPushStyleVar_Float(ig.ImGuiStyleVar_WindowRounding, 0.0);
    ig.igPushStyleVar_Vec2(ig.ImGuiStyleVar_WindowPadding, .{ .x = 0, .y = 0 });

    // DockSpace
    _ = ig.igBegin(&name[0], null, flags);
    ig.igPopStyleVar(3);
    const dockspace_id = ig.igGetID_Str(&name[0]);
    _ = ig.igDockSpace(dockspace_id, .{ .x = 0, .y = 0 }, ig.ImGuiDockNodeFlags_PassthruCentralNode, null);
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
