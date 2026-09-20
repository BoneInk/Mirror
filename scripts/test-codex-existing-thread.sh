#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d /tmp/MirrorExistingThread.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT
swift build -c debug
python3 - "$TEST_DIR/main.swift" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_text('@testable import Mirror\n' + Path('Tools/CodexExistingThreadSmoke/main.swift').read_text())
PY
OBJECTS=()
for OBJECT in .build/debug/Mirror.build/*.o; do
  [[ "$OBJECT" == */MirrorApp.swift.o ]] || OBJECTS+=("$OBJECT")
done
swiftc -I .build/debug/Modules "$TEST_DIR/main.swift" "${OBJECTS[@]}" -framework AppKit -framework WebKit \
  -framework Quartz -framework ImageIO -framework UniformTypeIdentifiers -o "$TEST_DIR/existing-thread-smoke"
"$TEST_DIR/existing-thread-smoke" "$@"
