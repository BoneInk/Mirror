#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUTPUT_DIR="${TMPDIR:-/tmp}/MirrorMemoryVisual"
TEST_HOME="$OUTPUT_DIR/MirrorMemorySmokeHome-$$"
mkdir -p "$OUTPUT_DIR" "$TEST_HOME"
swift build -c debug
python3 - "$OUTPUT_DIR/main.swift" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_text('@testable import Mirror\n' + Path('Tools/CodexMemorySmoke/main.swift').read_text())
PY
OBJECTS=()
for OBJECT in .build/debug/Mirror.build/*.o; do
  [[ "$OBJECT" == */MirrorApp.swift.o ]] || OBJECTS+=("$OBJECT")
done
swiftc -I .build/debug/Modules "$OUTPUT_DIR/main.swift" "${OBJECTS[@]}" -framework AppKit -framework WebKit \
  -framework Quartz -framework ImageIO -framework UniformTypeIdentifiers -o "$OUTPUT_DIR/memory-smoke"
cp -R Resources/zh-Hans.lproj "$OUTPUT_DIR/"
CFFIXED_USER_HOME="$TEST_HOME" "$OUTPUT_DIR/memory-smoke" "$@"
