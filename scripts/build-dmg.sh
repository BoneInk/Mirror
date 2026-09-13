#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$PROJECT_DIR/dist/Mirror.app"
INFO_PLIST="$PROJECT_DIR/Resources/Info.plist"
SKIP_BUILD=false

if [[ "${1:-}" == "--skip-build" ]]; then
  SKIP_BUILD=true
fi

if [[ "$SKIP_BUILD" == false ]]; then
  "$PROJECT_DIR/scripts/build-app.sh" release
fi

if [[ ! -d "$APP_DIR" ]]; then
  echo "Mirror.app was not found at $APP_DIR" >&2
  echo "Run scripts/build-app.sh before using --skip-build." >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
DMG_PATH="$PROJECT_DIR/dist/Mirror-$VERSION.dmg"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mirror-dmg.XXXXXX")"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

cp -R "$APP_DIR" "$STAGING_DIR/Mirror.app"
ln -s /Applications "$STAGING_DIR/Applications"
cp "$PROJECT_DIR/Resources/First-Open.txt" "$STAGING_DIR/首次打开 - First Open.txt"

hdiutil create \
  -volname "Mirror $VERSION" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

hdiutil verify "$DMG_PATH"

echo "$DMG_PATH"
shasum -a 256 "$DMG_PATH"
