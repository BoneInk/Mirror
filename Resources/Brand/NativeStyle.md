# Mirror 原生 macOS 界面

采用 Apple Liquid Glass 的内容与导航分层原则。`Sources/Mirror/NativeStyle.swift` 集中维护材质和系统按钮。

- 导航与浮动控件：macOS 26 使用 SwiftUI glassEffect 和 glass / glassProminent 按钮；macOS 14–25 回退 regularMaterial 和原生 bordered 按钮。
- 正文、主题卡、消息与引用：不透明背景与轻分隔线，无折角、装饰阴影。
- 降低透明度或增强对比度：导航回退系统实色背景；内容边界增强。
- Mirror Light / Dark 保留 builtin.paper / builtin.ink ID，不迁移用户偏好。其他主题继续保留。
- 保留折页 M 品牌图标，界面装饰不再延伸折纸风格。

参考：https://developer.apple.com/design/human-interface-guidelines/materials

验证：scripts/test-renderer.sh、scripts/test-codex-reference.sh、scripts/test-native-visual.sh。后者在隔离 HOME 中捕获主界面、阅读、深色、紧凑窗口、设置、命令、表格及 Codex 对话框。

玻璃作为独立背景层合成，避免其自动前景处理改变自定义主题的文字颜色。视觉脚本可用 `MIRROR_SYSTEM_CAPTURE_HELPER` 指向系统截图助手，捕获实际窗口合成；默认使用离屏布局截图。
