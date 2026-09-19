#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d /tmp/MirrorThreadPicker.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT
swift build -c debug
python3 - "$TEST_DIR/main.swift" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_text('@testable import Mirror\n' + Path('Tools/CodexThreadPickerSmoke/main.swift').read_text())
PY
OBJECTS=()
for OBJECT in .build/debug/Mirror.build/*.o; do
  [[ "$OBJECT" == */MirrorApp.swift.o ]] || OBJECTS+=("$OBJECT")
done
swiftc -I .build/debug/Modules "$TEST_DIR/main.swift" "${OBJECTS[@]}" -framework AppKit -framework WebKit \
  -framework Quartz -framework ImageIO -framework UniformTypeIdentifiers -o "$TEST_DIR/thread-picker-smoke"
"$TEST_DIR/thread-picker-smoke" "$@"
