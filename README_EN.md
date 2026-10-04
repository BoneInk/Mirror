# Mirror

[简体中文](README.md) | English

Mirror is a Markdown editor for macOS and Windows. Preview as you write, or select a passage and ask AI about it.

| Platform | Current version | Download | Requirements |
| --- | --- | --- | --- |
| macOS | 1.3.0 | [DMG and release notes](https://github.com/BoneInk/Mirror/releases/tag/v1.3.0) | macOS 14+ · Intel / Apple Silicon |
| Windows | 1.3.2 | [Installer](https://github.com/BoneInk/Mirror/releases/download/v1.3.2/Mirror-1.3.2-windows-x64-setup.exe) · [Portable](https://github.com/BoneInk/Mirror/releases/download/v1.3.2/Mirror-1.3.2-windows-x64-portable.exe) · [Release notes](https://github.com/BoneInk/Mirror/releases/tag/v1.3.2) | Windows 10 / 11 · x64 |

## What makes it different

- **Select text and ask AI.** A conversation opens beside the passage, with no copying back and forth. A marker lets you return to the conversation later, continue it, or delete it.
- **Use the AI tools you know.** Connect Codex, Claude Code, Smartwork, and more. Switch agents, models, and supported thinking levels right in the conversation. Mirror remembers your choices.
- **Preview as you write.** Markdown and preview scroll together. Switch to reader mode when you want to focus on the article.
- **Keep your files on your computer.** Edit local Markdown files, view diagrams and math offline, and export HTML or PDF. Questions and quoted text go to your chosen agent only when you send them.

## Screenshots

![macOS source editing and live preview](docs/images/native-editor-light.png)

![macOS immersive reading](docs/images/native-reader-light.png)

![Windows 1.3.2 split editing and preview](Windows/docs/windows-light.png)

## Get started

- **macOS:** Download the DMG and drag Mirror into Applications.
- **Windows:** Run the installer `.exe`, or open the portable edition directly. Checksums are in [SHA256SUMS.txt](https://github.com/BoneInk/Mirror/releases/download/v1.3.2/SHA256SUMS.txt).

Open a Markdown file, select text, and click Ask. The prompt appears near the selection's focus end, and the conversation opens beside the quoted passage. `Enter/Return` sends, `⌘ Return` on macOS or `Ctrl Enter` on Windows inserts a newline, and `Esc` closes the bubble.

To quote text into an existing Codex thread, select text and use the context menu on macOS. On Windows, click Ask, open the agent menu at the top of the conversation, and choose the existing Codex thread option. Preview its history, select a thread, and close Codex desktop before continuing in Mirror. See the [thread reference guide (Chinese)](docs/codex-thread-reference.md) and [Windows guide (Chinese)](Windows/README.md).

Configure agents and conversation memory in Settings. Each runtime requires its own installation, login, or service configuration. WorkBuddy requires an authorized token; QwenWork currently requires a custom bridge. See the [agent setup guide (Chinese)](docs/agents.md).

The macOS app is ad-hoc signed and has not been notarized by Apple. Windows packages are unsigned.

If macOS says Apple cannot verify Mirror, dismiss the alert, then go to **System Settings → Privacy & Security → Open Anyway** and confirm. Only proceed if you trust the download from this project’s Release page. See [Apple’s instructions](https://support.apple.com/en-us/102445).

On macOS, in preview or reading mode, drag the right border, bottom border, or bottom-right corner to resize the Mermaid frame. The cursor changes near the edge, with no extra grips or edge strips. The diagram automatically fits the frame; drag the diagram itself to pan. Zoom with the header buttons, `⌘/Ctrl + wheel`, or a trackpad pinch. Double-click or use the reset button to fit the diagram again. When focused, use arrow keys to pan, plus/minus to zoom, `0` to reset, or `Esc` to cancel a drag. These interactions only affect the preview; Markdown and exported diagrams keep their original layout. Image resize handles have been removed, and size comments saved by older versions are ignored.

## Build from source

macOS requires the Swift 6 toolchain:

```bash
swift run Mirror
# Build the universal app and DMG
bash scripts/build-app.sh release
bash scripts/build-dmg.sh --skip-build
```

macOS outputs are in `dist/`, with regression checks in `scripts/test-*.sh`. Windows requires Node.js 22.12+; see the [Windows guide](Windows/README.md) for build and validation commands.

## Windows edition

[Download Windows 1.3.2](https://github.com/BoneInk/Mirror/releases/tag/v1.3.2) · Windows 10 / 11 · x64 installer and portable editions.

The [Windows desktop project](Windows/README.md) aligns the toolbar, navigation, page spacing, settings, search, version history, and reference conversations with macOS. Sidebar and split widths can be resized. Text selection shows only Ask, with support for backward selection, keyboard selection, scrolling, and placement near window edges.

Local agents confirmed to be missing are hidden from conversation choices. Their settings remain available, and detection restores them after installation. Temporarily offline HTTP services, existing configurations, and conversation history are retained.

Windows 1.3.2 passed 16 unit tests and 16 Electron UI tests, and published files were checked against their SHA-256 hashes. See the [Windows guide](Windows/README.md) and [validation record (Chinese)](Windows/docs/validation.md) for platform differences and verification scope.
