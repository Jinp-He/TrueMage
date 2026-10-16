# 界面

- `ui_components_sheet.webp`：UI 组件图集原图。
- `pieces/`：由 `tools/slice_ui_sheet.gd` 从图集切出来的组件，以及据此生成的变色版本（紫、绿、金、灰的符文牌和云朵）、占位金币图标。

替换图集后，在项目根目录运行切图工具重新生成 `pieces/`（图集尺寸变了的话，要先更新工具里的坐标）：

    godot --headless --path . --script res://tools/slice_ui_sheet.gd

也可以直接替换 `pieces/` 里的单个文件，文件名保持不变。
