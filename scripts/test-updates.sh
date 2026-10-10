#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUTPUT_DIR="${TMPDIR:-/tmp}/MirrorUpdateSmoke"
mkdir -p "$OUTPUT_DIR"
swift build --build-system native -c debug
BIN_DIR="$(swift build --build-system native -c debug --show-bin-path)"
python3 - "$OUTPUT_DIR/main.swift" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_text('@testable import Mirror\n' + Path('Tools/SoftwareUpdateSmoke/main.swift').read_text())
PY
OBJECTS=()
for OBJECT in "$BIN_DIR"/Mirror.build/*.o; do
  [[ "$OBJECT" == */MirrorApp.swift.o ]] || OBJECTS+=("$OBJECT")
done
swiftc -I "$BIN_DIR/Modules" "$OUTPUT_DIR/main.swift" "${OBJECTS[@]}" \
  -framework AppKit -framework WebKit -framework Quartz -framework ImageIO \
  -framework UniformTypeIdentifiers -o "$OUTPUT_DIR/update-smoke"
MIRROR_UPDATE_HELPER_OUTPUT="$OUTPUT_DIR/install.sh" "$OUTPUT_DIR/update-smoke"
python3 scripts/test-update-install.py "$OUTPUT_DIR/install.sh" "$BIN_DIR/Mirror"
