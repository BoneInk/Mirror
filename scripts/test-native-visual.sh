#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${TMPDIR:-/tmp}/MirrorNativeVisual"
TEST_HOME="$OUTPUT_DIR/MirrorNativeVisualHome-$$"
mkdir -p "$OUTPUT_DIR" "$TEST_HOME"
cd "$PROJECT_DIR"
SOURCES=()
for SOURCE in Sources/Mirror/*.swift; do
  [[ "$SOURCE" == "Sources/Mirror/MirrorApp.swift" ]] || SOURCES+=("$SOURCE")
done
swiftc "${SOURCES[@]}" Tools/NativeVisualSmoke/main.swift \
  -framework AppKit -framework WebKit -framework Quartz -framework CoreText \
  -framework ImageIO -framework UniformTypeIdentifiers -o "$OUTPUT_DIR/native-visual"
CFFIXED_USER_HOME="$TEST_HOME" "$OUTPUT_DIR/native-visual"
