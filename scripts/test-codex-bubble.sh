#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUTPUT_DIR="${TMPDIR:-/tmp}/MirrorCodexBubbleSmoke"
mkdir -p "$OUTPUT_DIR"
swiftc Sources/Mirror/Models.swift Sources/Mirror/NativeStyle.swift Sources/Mirror/LegacyBrandMigration.swift Sources/Mirror/AppLanguage.swift \
  Sources/Mirror/AgentConfiguration.swift Sources/Mirror/AgentTransport.swift Sources/Mirror/CodexAppServer.swift Sources/Mirror/CodexChatPanel.swift Sources/Mirror/CodexMemory.swift \
  Sources/Mirror/CodexReference.swift Tools/CodexBubbleSmoke/main.swift -framework AppKit -framework WebKit -o "$OUTPUT_DIR/bubble-smoke"
"$OUTPUT_DIR/bubble-smoke" "$@"
