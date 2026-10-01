# Windows 1.3.1 验收记录

日期：2026-10-01。平台：Windows 11 Pro x64，系统 10.0.26300，Node.js 22.22.1，Electron 44.5.1。同步基线为 macOS `3d85eed`（1.3.0 build 13）。本目录截图来自 Windows Electron 实机。

## 通过

- `npm test`：14 项通过。文件保存与外部/删除冲突、文件扫描限制、草稿与快照、流式 Unicode、HTTP 错误与取消、自定义命令、原生输出解析、Smartwork/WorkBuddy、Codex JSON-RPC 原会话续聊、线程锁、工作区搜索/链接/监听、临时占用重试与永久失败保留原文件。
- `npm run build`：生产构建通过，Markdown、公式字体和 Mermaid 使用本地资源。
- `npm run test:ui`：10 项通过（20.4 秒）。编辑/阅读、清理 HTML、模式/主题/草稿重启恢复、真实文件冲突取消/覆盖、版本恢复、HTML/PDF 导出、引用对话、图表文字/缩放/外框调整、工作区搜索/相对链接/冲突横幅、排版、Smartwork IPC 调用、Codex 原会话选择、Windows 凭据加密。
- 保存/冲突用例额外连续重复 5 次通过。曾发现保存完成之前继续编辑的测试时序问题，增加界面保存状态等待；同时补强 Windows 原子替换的有限重试与数据保留测试。
- 最终 x64 NSIS 安装版与便携版在 Windows 上构建成功。打包的 8 个 Electron 主进程模块与源文件逐字节一致；`app.asar` 版本为 1.3.1；PE 产品版本 1.3.1.0。
- 最终便携 `.exe` 用隔离应用数据目录启动；原生窗口检查确认纸张布局、阅读模式与工具，CDP 核对 Mermaid 节点文字、离线公式和阅读工具正常。
- 本机 `codex-cli 0.144.0` 的 `model/list` 返回 4 个模型，验证 PATH 中 npm shim 查找与真实 app-server 握手；未发送真实模型问题。
- `npm audit`：0 个已知漏洞。`git diff --check` 通过。

## 发布产物

| 文件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| Mirror-1.3.1-windows-x64-portable.exe | 114650598 | 91e844ff2b0a480212912c861d00697d41654e79a4f9d81bf6212bc89c5fa07b |
| Mirror-1.3.1-windows-x64-setup.exe | 114942640 | 455ca7853c5b36a62438b65cb0506e646193eee9fe3a0a3e402f8c4dfe5d65d8 |

Authenticode 状态为 NotSigned；没有使用签名证书。Release 同时提供 `SHA256SUMS.txt`。

## 范围与未验收项

生成测试使用本地 HTTP 与 CLI fixture，原会话续聊在协议层验证，只读查询使用本机 Codex；没有让真实智能体修改文档或生成收费回复。WorkBuddy 与其他原生 CLI 的真实登录/模型兼容性、安装/卸载、文件关联、ARM64、不同 DPI 和 Windows 10 未单独实测。

Windows 文件浏览限 Markdown/纯文本，尚未包含 macOS Quick Look 的图片/PDF/二进制预览、源码行号边栏、Markdown 清理助手和完整多行脚注。桌面草稿预填改为复制引用，字体使用 Windows 本机字体。原 Codex 会话续聊需先退出 Codex 桌面，停止、完成或异常后刷新历史核对。

本次发布仅更新 Windows 1.3.1，macOS 安装包继续使用 v1.3.0。
