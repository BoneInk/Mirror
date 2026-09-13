# Mirror

简体中文 | [English](README_EN.md)

Mirror 是一款 macOS Markdown 编辑器。你可以边写边预览，也可以选中一段文字，直接向 AI 提问。

[下载 Mirror 1.1](https://github.com/BoneInk/Mirror/releases/tag/v1.1) · macOS 14+ · Intel / Apple Silicon

## 有什么不一样

- **选中文字就能问 AI。** 对话就在旁边打开，不用来回复制粘贴。问过的地方会留下标记，以后可以点开接着聊，也可以删除记录。
- **接着用你熟悉的 AI 工具。** 支持 Codex、Claude Code、Smartwork 等。对话里就能切换智能体、模型和支持的思考深度，下次自动沿用。
- **边写边看，随时阅读。** Markdown 与预览同步滚动，也能切到阅读模式，专心看文章。
- **文件就在你的电脑上。** 直接读写本地 Markdown，离线显示图表和公式，支持导出 HTML / PDF。发送提问时，才会把问题和引用内容交给所选智能体。

## 界面

![源码编辑与实时预览](docs/images/native-editor-light.png)

![沉浸式阅读](docs/images/native-reader-light.png)

## 开始使用

下载安装包，将 Mirror 拖入 Applications。选中文字后点击「提问」；`Return` 发送，`⌘ Return` 换行，`Esc` 关闭气泡。

在设置中配置智能体和气泡记忆。不同运行时需要各自的安装、登录或服务配置；WorkBuddy 需要授权 Token，千问办公目前通过自定义桥接接入。详见[智能体接入说明](docs/agents.md)。

安装包使用 ad-hoc 签名，尚未完成 Apple 公证。

首次打开若提示“Apple 无法验证 Mirror”，请先点“完成”，再到 **系统设置 → 隐私与安全性 → 仍要打开**，按提示确认。仅在确认安装包来自本项目 Release 且信任来源时操作。详见 [Apple 官方说明](https://support.apple.com/zh-cn/102445)。

## 从源码构建

需要 Swift 6 工具链：

```bash
swift run Mirror
# 生成通用应用与安装包
bash scripts/build-app.sh release
bash scripts/build-dmg.sh --skip-build
```

产物位于 `dist/`。回归检查见 `scripts/test-*.sh`。
