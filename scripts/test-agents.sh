#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d /tmp/MirrorAgents.XXXXXX)
HTTP_PID=""
trap '[[ -z "$HTTP_PID" ]] || kill "$HTTP_PID" 2>/dev/null || true; rm -rf "$TEST_DIR"' EXIT
for KIND in claude codebuddy cursor kimi qoder opencode pi custom slow; do
  cp Tools/AgentSmoke/fake-agent.py "$TEST_DIR/$KIND"
  chmod +x "$TEST_DIR/$KIND"
done
python3 Tools/AgentSmoke/http-fixture.py "$TEST_DIR/port" &
HTTP_PID=$!
for ATTEMPT in {1..50}; do [[ -s "$TEST_DIR/port" ]] && break; sleep 0.1; done
swift build -c debug
python3 - "$TEST_DIR/main.swift" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_text('@testable import Mirror\n' + Path('Tools/AgentSmoke/main.swift').read_text())
PY
OBJECTS=()
for OBJECT in .build/debug/Mirror.build/*.o; do
  [[ "$OBJECT" == */MirrorApp.swift.o ]] || OBJECTS+=("$OBJECT")
done
swiftc -I .build/debug/Modules "$TEST_DIR/main.swift" "${OBJECTS[@]}" -framework AppKit -framework WebKit \
  -framework Quartz -framework ImageIO -framework UniformTypeIdentifiers -o "$TEST_DIR/agent-smoke"
"$TEST_DIR/agent-smoke" "$TEST_DIR" "$(cat "$TEST_DIR/port")"
