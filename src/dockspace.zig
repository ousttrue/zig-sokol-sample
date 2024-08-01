const std = @import("std");
const ig = @import("cimgui");

pub const DockFunc = fn (
    name: []const u8,
    p_open: *bool,
) void;

pub const DockItem = struct {
    name: []const u8,
    is_open: bool = true,
    draw_func: *const DockFunc,

    pub fn make(
        name: []const u8,
        draw_func: *const DockFunc,
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

pub const DockNodeSplitType = enum {
    None,
    Horizontal,
    Vertical,
};

pub const DockNodeSplit = union(DockNodeSplitType) {
    None: void,
    Horizontal: struct { left: *DockNode, right: *DockNode },
    Vertical: struct { up: *DockNode, down: *DockNode },
};

fn show_empty(_: []const u8, _: *bool) void {
    // if (ig.igBegin(&name[0], null, ig.ImGuiWindowFlags_None)) {
    // }
    // ig.igEnd();
}

pub const DockNode = struct {
    item: DockItem,
    children: DockNodeSplit = .{ .None = void{} },

    pub fn make_empty(
        allocator: std.mem.Allocator,
        name: []const u8,
    ) !*@This() {
        const p = try allocator.create(DockNode);
        p.* = .{ .item = DockItem.make(
            name,
            &show_empty,
        ) };
        return p;
    }

    pub fn make(
        allocator: std.mem.Allocator,
        name: []const u8,
        dockfunc: *const DockFunc,
    ) !*@This() {
        const p = try allocator.create(DockNode);
        p.* = .{ .item = DockItem.make(
            name,
            dockfunc,
        ) };
        return p;
    }

    pub fn split(
        self: *@This(),
        split_type: DockNodeSplitType,
        child0: *@This(),
        child1: *@This(),
    ) void {
        self.children = switch (split_type) {
            .None => .{ .None = void{} },
            .Horizontal => .{ .Horizontal = .{ .left = child0, .right = child1 } },
            .Vertical => .{ .Vertical = .{ .up = child0, .down = child1 } },
        };
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

fn node_tree_build(node: *DockNode, node_id: ig.ImGuiID) void {
    switch (node.children) {
        .Horizontal => |children| {
            var right: ig.ImGuiID = undefined;
            var left: ig.ImGuiID = undefined;
            _ = ig.igDockBuilderSplitNode(
                node_id,
                ig.ImGuiDir_Left,
                0.5,
                &left,
                &right,
            );
            node_tree_build(children.left, left);
            node_tree_build(children.right, right);
        },
        .Vertical => |children| {
            var down: ig.ImGuiID = undefined;
            var up: ig.ImGuiID = undefined;
            _ = ig.igDockBuilderSplitNode(
                node_id,
                ig.ImGuiDir_Up,
                0.5,
                &up,
                &down,
            );
            node_tree_build(children.up, up);
            node_tree_build(children.down, down);
        },
        .None => {},
    }
    ig.igDockBuilderDockWindow(&node.item.name[0], node_id);
}

fn node_tree_menu(node: *DockNode) void {
    // Dockの表示状態と chekmark を連動
    _ = ig.igMenuItem_BoolPtr(&node.item.name[0], null, &node.item.is_open, true);
}

fn node_tree_show(node: *DockNode) void {
    // dock の描画
    node.item.draw();

    switch (node.children) {
        .Horizontal => |children| {
            node_tree_show(children.left);
            node_tree_show(children.right);
        },
        .Vertical => |children| {
            node_tree_show(children.up);
            node_tree_show(children.down);
        },
        .None => {},
    }
}

pub fn frame(dockspace_name: []const u8, root: *DockNode) void {
    const viewport = ig.igGetMainViewport();
    const pos = viewport.*.Pos;
    const size = viewport.*.Size;

    if (state.firstCall) {
        state.dockspace_id = ig.igGetID_Str(&dockspace_name[0]);
        state.firstCall = false;
        ig.igDockBuilderRemoveNode(state.dockspace_id); // Clear out existing layout
        _ = ig.igDockBuilderAddNode(state.dockspace_id, DOCKNODE_FLAG); // Add empty node
        ig.igDockBuilderSetNodeSize(state.dockspace_id, size); // Add empty node

        // central node
        const root_id = ig.igGetID_Str(&root.item.name[0]);
        _ = ig.igDockBuilderAddNode(root_id, ig.ImGuiDockNodeFlags_DockSpace);
        node_tree_build(root, root_id);

        ig.igDockBuilderFinish(root_id);
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

    // menu
    if (ig.igBeginMainMenuBar()) {
        if (ig.igBeginMenu("Docks", true)) {
            node_tree_menu(root);
            ig.igEndMenu();
        }
        ig.igEndMainMenuBar();
    }

    // widgets
    node_tree_show(root);
}
