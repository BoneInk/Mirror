# Mirror

简体中文 | [English](README_EN.md)

Mirror 是一款支持 macOS 和 Windows 的 Markdown 编辑器。你可以边写边预览，也可以选中一段文字，直接向 AI 提问。

| 平台 | 当前版本 | 下载 | 系统要求 |
| --- | --- | --- | --- |
| macOS | 1.3.0 | [DMG 与更新说明](https://github.com/BoneInk/Mirror/releases/tag/v1.3.0) | macOS 14+ · Intel / Apple Silicon |
| Windows | 1.3.2 | [安装版](https://github.com/BoneInk/Mirror/releases/download/v1.3.2/Mirror-1.3.2-windows-x64-setup.exe) · [便携版](https://github.com/BoneInk/Mirror/releases/download/v1.3.2/Mirror-1.3.2-windows-x64-portable.exe) · [更新说明](https://github.com/BoneInk/Mirror/releases/tag/v1.3.2) | Windows 10 / 11 · x64 |

## 有什么不一样

- **选中文字就能问 AI。** 对话就在旁边打开，不用来回复制粘贴。问过的地方会留下标记，以后可以点开接着聊，也可以删除记录。
- **接着用你熟悉的 AI 工具。** 支持 Codex、Claude Code、Smartwork 等。对话里就能切换智能体、模型和支持的思考深度，下次自动沿用。
- **边写边看，随时阅读。** Markdown 与预览同步滚动，也能切到阅读模式，专心看文章。
- **文件就在你的电脑上。** 直接读写本地 Markdown，离线显示图表和公式，支持导出 HTML / PDF。发送提问时，才会把问题和引用内容交给所选智能体。

## 界面

![macOS 源码编辑与实时预览](docs/images/native-editor-light.png)

![macOS 沉浸式阅读](docs/images/native-reader-light.png)

![Windows 1.3.2 分栏编辑与预览](Windows/docs/windows-light.png)

## 开始使用

- **macOS：** 下载 DMG，将 Mirror 拖入 Applications。
- **Windows：** 运行安装版 `.exe`，或直接打开便携版。文件校验见 [SHA256SUMS.txt](https://github.com/BoneInk/Mirror/releases/download/v1.3.2/SHA256SUMS.txt)。

打开 Markdown，选中文字后点击「提问」。提示会出现在选区末端附近，对话在引用旁打开。`Enter/Return` 发送，macOS 用 `⌘ Return` 换行，Windows 用 `Ctrl Enter` 换行，`Esc` 收起对话。

macOS 的预览或阅读模式中，Mermaid 流程图支持直接拖动外框的右边、下边或右下角调整宽高；靠近边缘时光标会提示拖拽方向，不显示额外手柄或边条，图表自动适配外框，也可按住图表拖拽移动；使用右上角的加减按钮、`⌘/Ctrl + 滚轮` 或触控板捏合缩放。双击图表或点击复位按钮可重新适配；图表获得焦点后也可用方向键移动、加减键缩放、`0` 复位，拖拽时按 `Esc` 取消。操作只影响预览，不会修改 Markdown 或导出的图表。图片不再提供拖拽缩放，旧版保存的尺寸注释也不再生效。

要引用到已有 Codex 会话，macOS 中选中文字后右键选择「引用到 Codex 会话…」；Windows 中先点击「提问」，再展开对话顶部的智能体菜单，选择「引用到 Codex 会话…」。预览历史并选定目标，退出 Codex 桌面后即可在 Mirror 继续原会话。macOS 还支持「在 Codex 打开」填入桌面草稿（会替换原草稿）。详见[会话引用说明](docs/codex-thread-reference.md)和 [Windows 使用说明](Windows/README.md)。

在设置中配置智能体和气泡记忆。不同运行时需要各自的安装、登录或服务配置；WorkBuddy 需要授权 Token，千问办公目前通过自定义桥接接入。详见[智能体接入说明](docs/agents.md)。

macOS 安装包使用 ad-hoc 签名，尚未完成 Apple 公证；Windows 安装包未签名。

首次打开若提示“Apple 无法验证 Mirror”，请先点“完成”，再到 **系统设置 → 隐私与安全性 → 仍要打开**，按提示确认。仅在确认安装包来自本项目 Release 且信任来源时操作。详见 [Apple 官方说明](https://support.apple.com/zh-cn/102445)。

## 从源码构建

macOS 需要 Swift 6 工具链：

```bash
swift run Mirror
# 生成通用应用与安装包
bash scripts/build-app.sh release
bash scripts/build-dmg.sh --skip-build
```

macOS 产物位于 `dist/`，回归检查见 `scripts/test-*.sh`。Windows 需要 Node.js 22.12+，构建与检查命令见 [Windows 文档](Windows/README.md#构建与检查)。

## Windows 版本

[下载 Windows 1.3.2](https://github.com/BoneInk/Mirror/releases/tag/v1.3.2) · Windows 10 / 11 · x64 安装版 / 便携版。

[Windows 桌面项目](Windows/README.md) 对齐 macOS 的工具栏、导航、纸张留白、设置分区、搜索、版本历史和引用对话，支持拖动调整侧栏与分栏宽度。圈选后只显示「提问」，支持反向选择、键盘选择、滚动和窗口边缘避让。

确认缺失的本地智能体会自动从对话选择中隐藏，设置保留配置入口，安装后重新检测即可恢复。暂时离线的 HTTP 服务、已有配置和历史对话继续保留。

Windows 1.3.2 已通过 16 项单元测试和 16 项 Electron 界面回归，并核对发布文件的 SHA-256。平台差异与验证范围见 [Windows 文档](Windows/README.md)和[验收记录](Windows/docs/validation.md)。
