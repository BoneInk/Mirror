# Windows 首版验证记录

验证日期：2026-09-30。环境：Linux，Node.js 24.19.0、Electron 38.8.6；Electron 窗口通过 Xvfb 显示。`docs/windows-*.png` 是此次 Electron 窗口截图，不是 Windows 实机截图。

## 通过

- `npm test`：9 项通过。中文与 BOM 文件、外部修改及删除冲突、确认覆盖、文件扫描范围与符号链接、序列化草稿持久化、历史去重与数量限制、SSE 分段 Unicode 与上下文、JSON 与 HTTP 错误、拒绝重定向、取消生成、自定义命令及 Codex JSON 协议。
- `npm run build`：Vite 生产构建通过，渲染库、公式字体与图表模块进入本地资源。
- `DISPLAY=:99 npm run test:ui`：3 项通过。Markdown/KaTeX/Mermaid、HTML 清理、主题/模式/草稿重启恢复、真实文件保存与冲突取消/覆盖、快照恢复、HTML 内嵌图表/字体、PDF 输出、选区发送假 CLI、多轮记录持久化与重开。
- `node --check`：主进程、preload、智能体模块语法检查通过；`git diff --check` 通过。
- Windows x64 便携 `.exe` 交叉构建通过。核对 `app.asar` 内主进程、智能体和 preload 文件与源码一致；本地公式资源存在；没有将开发依赖的 `node_modules` 重复打入应用。

便携版构建命令（关闭签名，使用 ZIP 压缩）：

```bash
npx electron-builder --win portable --x64 \
  -c.win.signExecutable=false -c.portable.useZip=true
```

## 未完成的目标平台验收

NSIS 安装版在本 Linux 环境构建失败：最初缺少系统 Wine，随后下载的 electron-builder Wine 11 工具包无法加载 `ntdll.dll`，所以无法生成卸载器。失败的安装程序中间文件已删除。`npm run dist:win` 与 Windows GitHub Actions 配置已提供，需在 Windows 上执行后验收安装/卸载和文件关联。

便携版尚未在 Windows 实机启动；Windows DPAPI、系统缩放、ARM64、真实 Codex/Claude 登录及模型服务未在本环境验证。所有智能体测试使用假进程或本机 HTTP fixture，不调用真实模型。产物未签名，不是正式发布版本。
