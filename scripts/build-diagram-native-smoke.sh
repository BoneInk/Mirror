#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${TMPDIR:-/tmp}/MirrorDiagramNativeSmoke"
APP_DIR="$OUTPUT_DIR/MirrorDiagramNativeSmoke.app"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cd "$PROJECT_DIR"
SOURCES=()
for SOURCE in Sources/Mirror/*.swift; do
  [[ "$SOURCE" == "Sources/Mirror/MirrorApp.swift" ]] || SOURCES+=("$SOURCE")
done
cp -R Resources/Mermaid "$APP_DIR/Contents/Resources/Mermaid"
cp -R Resources/KaTeX "$APP_DIR/Contents/Resources/KaTeX"
swiftc "${SOURCES[@]}" Tools/DiagramNativeSmoke/main.swift \
  -framework AppKit -framework WebKit -framework Quartz -framework CoreText \
  -framework ImageIO -framework UniformTypeIdentifiers -o "$APP_DIR/Contents/MacOS/MirrorDiagramNativeSmoke"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MirrorDiagramNativeSmoke</string>
<key>CFBundleIdentifier</key><string>com.boneink.mirror.diagram-smoke</string>
<key>CFBundleName</key><string>MirrorDiagramNativeSmoke</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
echo "$APP_DIR"
