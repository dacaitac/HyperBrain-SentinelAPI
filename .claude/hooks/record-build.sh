#!/usr/bin/env bash
# PostToolUse(Bash) build recorder for HyperBrain-SentinelAPI (ADR-017 gate #2).
# Writes .claude/.build-passed when a `swift build` command completed without error.
set -euo pipefail

INPUT="$(cat)"
CMD="$(printf '%s' "$INPUT" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null || true)"
OUT="$(printf '%s' "$INPUT" | python3 -c 'import sys,json;d=json.load(sys.stdin);r=d.get("tool_response","");print(r if isinstance(r,str) else json.dumps(r))' 2>/dev/null || true)"

# Only react to swift build commands.
echo "$CMD" | grep -Eq 'swift[[:space:]]+build' || exit 0
# Treat as green only if the output does not signal a compile error / failure.
echo "$OUT" | grep -Eqi 'error:|Compiling failed|build failed' && exit 0

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
mkdir -p "$REPO_ROOT/.claude"
touch "$REPO_ROOT/.claude/.build-passed"
exit 0
