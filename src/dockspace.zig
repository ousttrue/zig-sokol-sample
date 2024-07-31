const ig = @import("cimgui");

pub fn frame(name: []const u8) void {
    if (ig.igBeginMainMenuBar()) {
        //       if (ImGui.BeginMenu("Window"))
        //       {
        //           foreach (var dock in Docks)
        //           {
        // // Dockの表示状態と chekmark を連動
        //               ImGui.MenuItem(dock.MenuLabel, dock.MenuShortCut, ref dock.IsOpen);
        //           }
        //           ImGui.EndMenu();
        //       }
        ig.igEndMainMenuBar();
    }

    //    foreach (var dock in Docks)
    //    {
    // // dock の描画
    //        dock.Draw();
    //    }

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
}
