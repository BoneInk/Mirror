#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${TMPDIR:-/tmp}/MirrorCodexReferenceSmoke"
mkdir -p "$OUTPUT_DIR"
cd "$PROJECT_DIR"
swiftc Sources/Mirror/Models.swift Sources/Mirror/NativeStyle.swift Sources/Mirror/LegacyBrandMigration.swift Sources/Mirror/AppLanguage.swift \
  Sources/Mirror/AgentConfiguration.swift Sources/Mirror/AgentTransport.swift Sources/Mirror/CodexAppServer.swift Sources/Mirror/CodexChatPanel.swift \
  Sources/Mirror/CodexMemory.swift Sources/Mirror/CodexThreadPicker.swift Sources/Mirror/CodexReference.swift Tools/CodexReferenceSmoke/main.swift \
  -framework AppKit -framework WebKit -o "$OUTPUT_DIR/codex-reference-smoke"
"$OUTPUT_DIR/codex-reference-smoke" "$@"
