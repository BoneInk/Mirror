#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${MIRROR_RENDERER_OUTPUT_DIR:-${TMPDIR:-/tmp}/MirrorRendererSmoke}"
OUTPUT="$OUTPUT_DIR/renderer-smoke"

cd "$PROJECT_DIR"
mkdir -p "$OUTPUT_DIR"
swiftc \
  Sources/Mirror/Models.swift \
  Sources/Mirror/MermaidRuntime.swift \
  Sources/Mirror/MathRuntime.swift \
  Sources/Mirror/MarkdownRenderer.swift \
  Sources/Mirror/MarkdownExportResources.swift \
  Tools/RendererSmoke/main.swift \
  -framework AppKit \
  -framework UniformTypeIdentifiers \
  -framework WebKit \
  -o "$OUTPUT"

"$OUTPUT" "$@"
