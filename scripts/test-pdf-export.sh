#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${TMPDIR:-/tmp}/MirrorPDFExportSmoke"
mkdir -p "$OUTPUT_DIR"
cd "$PROJECT_DIR"
swiftc Sources/Mirror/MarkdownFileExporter.swift Tools/PDFExportSmoke/main.swift \
  -framework AppKit -framework WebKit -framework PDFKit -o "$OUTPUT_DIR/pdf-export-smoke"
"$OUTPUT_DIR/pdf-export-smoke"
