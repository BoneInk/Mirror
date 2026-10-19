#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${1:-$PROJECT_DIR/dist/Mirror.app}"
IDENTITY="${MIRROR_CODESIGN_IDENTITY:-}"

if [[ ! -d "$APP_DIR/Contents/MacOS" ]]; then
  echo "Mirror.app was not found at $APP_DIR" >&2
  exit 1
fi

if [[ -z "$IDENTITY" ]]; then
  AVAILABLE_IDENTITIES="$(/usr/bin/security find-identity -v -p codesigning)"
  IDENTITIES=()
  while IFS= read -r FINGERPRINT; do
    [[ -z "$FINGERPRINT" ]] || IDENTITIES+=("$FINGERPRINT")
  done < <(/usr/bin/awk '/"Apple Development:/ { print $2 }' <<< "$AVAILABLE_IDENTITIES")

  case "${#IDENTITIES[@]}" in
    0)
      IDENTITY="-"
      echo "No valid Apple Development identity found; using ad-hoc signing." >&2
      ;;
    1) IDENTITY="${IDENTITIES[0]}" ;;
    *)
      echo "Multiple Apple Development identities found. Set MIRROR_CODESIGN_IDENTITY to a certificate SHA-1 or full name." >&2
      exit 1
      ;;
  esac
fi

echo "Signing $APP_DIR with $IDENTITY" >&2
/usr/bin/codesign --force --sign "$IDENTITY" --timestamp=none "$APP_DIR"
/usr/bin/codesign --verify --deep --strict --all-architectures --verbose=2 "$APP_DIR"
/usr/bin/codesign --display --verbose=2 "$APP_DIR"
