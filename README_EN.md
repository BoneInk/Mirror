# Mirror

[简体中文](README.md) | English

Mirror is a native macOS Markdown editor designed for a calm, clear writing experience. It brings file management, source editing, live preview, and immersive reading into one lightweight workspace, using native glass navigation, clear content surfaces, and a blue accent.

[Download Mirror 1.1](https://github.com/BoneInk/Mirror/releases/latest) · Requires macOS 14 or newer

## Screenshots

### Writing and live preview

The file tree and document outline are easy to switch between, while Markdown source and formatted preview stay synchronized through semantic anchors.

![Mirror file tree, Markdown source, and live preview](docs/images/native-editor-light.png)

### Reader mode

Reader mode removes source-level noise and provides a full-height paper canvas, heading navigation, reading progress, and lightweight typography controls.

![Mirror immersive reader mode](docs/images/native-reader-dark.png)

### Mermaid diagrams

Mermaid diagrams render locally and offline, so source and results can be viewed side by side while editing.

![Mirror editing and previewing a Mermaid sequence diagram](docs/images/mermaid-preview.png)

## Core features

- Native Markdown editing with syntax highlighting, live preview, and bidirectional scroll sync
- Workspace file tree, recent files, tabs, folder search, and document outline
- Immersive reader mode with adjustable width, typography, line height, and themes
- Built-in rendering for tables, highlighted code, images, HTML, Mermaid, and KaTeX
- Simplified Chinese by default, optional English, plus light, dark, and custom themes
- Autosave, crash recovery, external-change detection, and local document history
- Portable HTML and PDF export with the native macOS print workflow

Mirror supports commonly used CommonMark and GitHub-style Markdown, including task lists, footnotes, tables, reference links, fenced code, and safe HTML. Text and source files open as editable documents, while images, PDFs, and common binary formats can be previewed inside the app.

## Native macOS appearance

Navigation and floating controls use system Liquid Glass on macOS 26, with standard material fallbacks on earlier versions. Content stays opaque for readability. Mirror Light and Mirror Dark use neutral palettes, while existing theme IDs and custom palettes remain supported. Navigation becomes opaque with Reduce Transparency or Increase Contrast enabled.

Run `./scripts/test-native-visual.sh` for isolated visual checks.

## Build

Requires macOS 14 or newer and the Swift 6 toolchain.

```bash
swift build
swift run Mirror
```

Build the Universal 2 app and an installable DMG:

```bash
./scripts/build-app.sh release
./scripts/build-dmg.sh --skip-build
```

Outputs are written to `dist/Mirror.app` and `dist/Mirror-1.1.dmg`. Local builds use an ad-hoc signature; public distribution still requires Apple Developer ID signing and Apple notarization.

## Codex chat panel

Select text and use the source editor context menu or the preview selection button to open a Codex chat with a document reference. Right-click without a selection to start a separate blank chat. Panels support follow-up questions, streamed answers, and cancellation. “Open in Codex” opens the conversation or a prefilled draft through the installed desktop app's deep link, without clipboard or Accessibility access.

The panel uses the local Codex App Server and your existing login. Install and sign in to Codex first. Run `./scripts/test-codex-reference.sh` for offline coverage, or add `--live --visual` for an optional live connectivity test and panel screenshot.


### v1.1 interaction updates

The selection action follows the end of the drag, including backward and multiline selections, and stays inside the viewport. Return sends a question; Command-Return inserts a newline. Return during IME composition remains available for candidate confirmation.

Delete a local conversation from the bubble title menu, or use Settings → Bubble Memory to search, select, and delete multiple records. Deleting a record removes its document marker and stops its pending background generation from restoring it. Agent-side sessions are retained.


### Agent connections

Settings includes Codex, Claude Code, CodeBuddy, Cursor, Kimi, Qoder, OpenCode, Pi, Hermes, Smartwork, OpenClaw, WorkBuddy, DeepSeek Harness, QwenWork, and custom profiles. CLI adapters reuse local login; Hermes/OpenClaw use their Agent HTTP servers. Smartwork uses the D-Chat local Agent protocol with an anonymous health check. WorkBuddy uses its local-assistant Open API and requires an authorized access token and an online desktop client. Its shared channel should not receive concurrent questions from other apps; stopping Mirror only stops waiting for the reply.

QwenWork (千问办公) is a configurable bridge preset, not a verified native conversation adapter or an alias for a Qwen model API. See the [connection table and setup details](README.md#多智能体引用提问). New protocols have offline fixture coverage; no real inference requests were sent during validation.

System file-access permission prompts and file panels preserve the bubble and its draft. Esc and intentional outside clicks still dismiss it.
