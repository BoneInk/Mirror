#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_MODE="${1:-release}"
APP_DIR="$PROJECT_DIR/dist/Mirror.app"
CONTENTS_DIR="$APP_DIR/Contents"

cd "$PROJECT_DIR"

if [[ "$BUILD_MODE" == "release" ]]; then
  ARCHITECTURES=(x86_64 arm64)
  ARCH_BINARIES=()
  for ARCHITECTURE in "${ARCHITECTURES[@]}"; do
    SCRATCH_DIR="$PROJECT_DIR/.build-$ARCHITECTURE"
    swift build -c release \
      --triple "$ARCHITECTURE-apple-macosx14.0" \
      --scratch-path "$SCRATCH_DIR"
    BIN_DIR="$(swift build -c release \
      --triple "$ARCHITECTURE-apple-macosx14.0" \
      --scratch-path "$SCRATCH_DIR" --show-bin-path)"
    ARCH_BINARIES+=("$BIN_DIR/Mirror")
  done
  mkdir -p "$PROJECT_DIR/.build-universal/release"
  xcrun lipo -create "${ARCH_BINARIES[@]}" -output "$PROJECT_DIR/.build-universal/release/Mirror"
  BUILT_EXECUTABLE="$PROJECT_DIR/.build-universal/release/Mirror"
else
  swift build -c "$BUILD_MODE"
  BUILT_EXECUTABLE="$(swift build -c "$BUILD_MODE" --show-bin-path)/Mirror"
fi

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$BUILT_EXECUTABLE" "$CONTENTS_DIR/MacOS/Mirror"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns" 2>/dev/null || true
for LOCALIZATION in "$PROJECT_DIR"/Resources/*.lproj; do
  [[ -d "$LOCALIZATION" ]] || continue
  cp -R "$LOCALIZATION" "$CONTENTS_DIR/Resources/"
done
cp -R "$PROJECT_DIR/Resources/Mermaid" "$CONTENTS_DIR/Resources/Mermaid"
cp -R "$PROJECT_DIR/Resources/KaTeX" "$CONTENTS_DIR/Resources/KaTeX"

codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
echo "$APP_DIR"
