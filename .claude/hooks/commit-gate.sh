#!/usr/bin/env bash
# PreToolUse(Bash) commit gate for HyperBrain-SentinelAPI (ADR-017 gate #2).
# Blocks `git commit` unless the last green `swift build` (recorded by
# record-build.sh) is newer than every tracked Swift source / manifest file.
set -euo pipefail

INPUT="$(cat)"
CMD="$(printf '%s' "$INPUT" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null || true)"

# Only guard git commits; let everything else through.
echo "$CMD" | grep -qw git && echo "$CMD" | grep -qw commit || exit 0

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$REPO_ROOT"
MARKER=".claude/.build-passed"

if [ ! -f "$MARKER" ]; then
  echo "COMMIT BLOCKED (ADR-017): no green build recorded. Run 'swift build' (no warnings) before committing." >&2
  exit 2
fi

CHANGED="$(find Sources Tests Package.swift Package.resolved -type f -newer "$MARKER" 2>/dev/null | head -1 || true)"
if [ -n "$CHANGED" ]; then
  echo "COMMIT BLOCKED (ADR-017): source changed since last green build (e.g. ${CHANGED}). Re-run 'swift build' before committing." >&2
  exit 2
fi

exit 0
