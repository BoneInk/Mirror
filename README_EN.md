# Mirror

[简体中文](README.md) | English

A native macOS Markdown editor for writing, reading, and AI conversations anchored to your document.

[Download Mirror 1.1](https://github.com/BoneInk/Mirror/releases/tag/v1.1) · macOS 14+ · Intel / Apple Silicon

## What Mirror focuses on

- **Conversations beside the text.** Select a passage to ask a question. Reopen its document marker to revisit or continue the discussion. Delete records individually or in batches.
- **Your choice of agent.** Connect Codex, Claude Code, Smartwork, and other local runtimes or services. Switch agents, models, and supported thinking levels in the bubble. Mirror remembers your choices and supports custom connections.
- **Writing and reading together.** Source and preview scroll in sync. Switch to reader mode while keeping your file tree, outline, and local document history close at hand.
- **Local documents.** Edit Markdown files directly, render Mermaid diagrams and math offline, and export HTML or PDF. Questions and quotations are sent to your chosen agent only when you submit them.

## Screenshots

![Source editing and live preview](docs/images/native-editor-light.png)

![Immersive reading](docs/images/native-reader-light.png)

## Get started

Download the DMG and drag Mirror into Applications. Select text and click Ask. `Return` sends, `⌘ Return` inserts a newline, and `Esc` closes the bubble.

Configure agents and conversation memory in Settings. Each runtime requires its own installation, login, or service configuration. WorkBuddy requires an authorized token; QwenWork currently requires a custom bridge. See the [agent setup guide (Chinese)](docs/agents.md).

The app is ad-hoc signed and has not been notarized by Apple.

## Build from source

Requires the Swift 6 toolchain:

```bash
swift run Mirror
# Build the universal app and DMG
bash scripts/build-app.sh release
bash scripts/build-dmg.sh --skip-build
```

Outputs are in `dist/`. Regression checks are in `scripts/test-*.sh`.
