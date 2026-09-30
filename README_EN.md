# Mirror

[简体中文](README.md) | English

Mirror is a Markdown editor for macOS. Preview as you write, or select a passage and ask AI about it.

[Download Mirror 1.2.0](https://github.com/BoneInk/Mirror/releases/tag/v1.2.0) · macOS 14+ · Intel / Apple Silicon

## What makes it different

- **Select text and ask AI.** A conversation opens beside the passage, with no copying back and forth. A marker lets you return to the conversation later, continue it, or delete it.
- **Use the AI tools you know.** Connect Codex, Claude Code, Smartwork, and more. Switch agents, models, and supported thinking levels right in the conversation. Mirror remembers your choices.
- **Preview as you write.** Markdown and preview scroll together. Switch to reader mode when you want to focus on the article.
- **Keep your files on your Mac.** Edit local Markdown files, view diagrams and math offline, and export HTML or PDF. Questions and quoted text go to your chosen agent only when you send them.

## Screenshots

![Source editing and live preview](docs/images/native-editor-light.png)

![Immersive reading](docs/images/native-reader-light.png)

## Get started

Download the DMG and drag Mirror into Applications. Select text and click Ask. `Return` sends, `⌘ Return` inserts a newline, and `Esc` closes the bubble.

Configure agents and conversation memory in Settings. Each runtime requires its own installation, login, or service configuration. WorkBuddy requires an authorized token; QwenWork currently requires a custom bridge. See the [agent setup guide (Chinese)](docs/agents.md).

The app is ad-hoc signed and has not been notarized by Apple.

If macOS says Apple cannot verify Mirror, dismiss the alert, then go to **System Settings → Privacy & Security → Open Anyway** and confirm. Only proceed if you trust the download from this project’s Release page. See [Apple’s instructions](https://support.apple.com/en-us/102445).

In preview or reading mode, drag the right border, bottom border, or bottom-right corner to resize the Mermaid frame; the diagram automatically fits the frame, or drag the diagram itself to pan. Zoom with the header buttons, `⌘/Ctrl + wheel`, or a trackpad pinch. Double-click or use the reset button to fit the diagram again. When focused, use arrow keys to pan, plus/minus to zoom, `0` to reset, or `Esc` to cancel a drag. These interactions only affect the preview; Markdown and exported diagrams keep their original layout. Image resize handles have been removed, and size comments saved by older versions are ignored.

## Build from source

Requires the Swift 6 toolchain:

```bash
swift run Mirror
# Build the universal app and DMG
bash scripts/build-app.sh release
bash scripts/build-dmg.sh --skip-build
```

Outputs are in `dist/`. Regression checks are in `scripts/test-*.sh`.

## Windows edition (initial port)

An independent [Windows desktop project](Windows/README.md) preserves Mirror’s visual style and core Markdown, reading, offline rendering, and selection-based AI workflows. Built with Electron and React, with NSIS and portable build targets. See the Windows README for setup, supported agent protocols, and current parity limits.
