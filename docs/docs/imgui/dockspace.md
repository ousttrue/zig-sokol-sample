# dockspace

- https://github.com/ocornut/imgui/wiki#docking
  - https://github.com/ocornut/imgui/wiki/Docking

## 初期化

```c++
  io.ConfigFlags |= ImGuiConfigFlags_DockingEnable;
```

## dockspace

## dockbuilder

- https://github.com/search?q=repo%3Aocornut%2Fimgui+DockBuilder+&type=issues
- [Docking layout without Docking actions · Issue #2999 · ocornut/imgui · GitHub](https://github.com/ocornut/imgui/issues/2999)

- [A commented example for Dear ImGui&#39;s DockBuilder API. · GitHub](https://gist.github.com/AidanSun05/953f1048ffe5699800d2c92b88c36d9f)

- [Simple example, of how to use the dock builder API. (Adapted from the dock space example in the demo window) You need to use the docking branch and set the ImGuiConfigFlags_DockingEnable config flag. Learn more about Dear ImGui here: https://github.com/ocornut/imgui · GitHub](https://gist.github.com/PossiblyAShrub/0aea9511b84c34e191eaa90dd7225969)


```cpp
ImGuiDockNodeFlags dockNodeFlags = ImGuiDockNodeFlags_NoCloseButton | ImGuiDockNodeFlags_NoWindowMenuButton | ImGuiDockNodeFlags_NoDocking | ImGuiDockNodeFlags_NoSplit | ImGuiDockNodeFlags_NoTabBar;


if( firstCall){
    ImGui::DockBuilderRemoveNode(dockSpaceId_m); // Clear out existing layout
    ImGui::DockBuilderAddNode(dockSpaceId_m,dockNodeFlags ); // Add empty node
    ImGui::DockBuilderSetNodeSize(dockSpaceId_m, 
      {getWidgetArea()->getWidth(),getWidgetArea()->getHeight()}); // Add empty node

    ImGuiID dock_main_id = ImGui::GetID("main);
    ImGuiID rightUp = ImGui::GetID("rightUp");
    ImGuiID rightDown = ImGui::GetID("rightDown");
    ImGuiID leftUp = ImGui::GetID("leftUp");
    ImGuiID right;
    ImGuiID leftUp;
    ImGuiID leftDown;

    ImGui::DockBuilderSplitNode(dock_main_id, ImGuiDir_Right, 0.4f, &right, &left);

    ImGui::DockBuilderSplitNode(right, ImGuiDir_Down, 0.30f, &rightDown, &rightUp);
    ImGui::DockBuilderSplitNode(left, ImGuiDir_Down, 0.30f, &leftDown, &leftUp);
    ImGui::DockBuilderDockWindow("rightUp", rightUp);
    ImGui::DockBuilderDockWindow("leftUp", leftUp);
    ImGui::DockBuilderDockWindow("rightDown", rightDown);

    ImGui::DockBuilderFinish(dock_main_id);
}


ImGui::DockSpace(dock_main_id, ImVec2(0.0f, 0.0f), dockNodeFlags); //called every frame
```

### save / load docking layout

- [Seeking help on implementing and saving docking layouts · Issue #4033 · ocornut/imgui · GitHub](https://github.com/ocornut/imgui/issues/4033)
