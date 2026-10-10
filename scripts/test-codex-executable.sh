#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d /tmp/MirrorCodexExecutable.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc Sources/Mirror/CodexAppServer.swift Tools/CodexExecutableSmoke/main.swift \
  -framework AppKit -o "$TEST_DIR/codex-executable-smoke"
# Reproduce an app launched by Finder, without the shell's bundled CLI PATH.
PATH=/usr/bin:/bin "$TEST_DIR/codex-executable-smoke" "$@"
