#!/usr/bin/env bash
set -euo pipefail

# $1 is the project root, passed by hooks.json via $CLAUDE_PROJECT_ROOT
PROJECT_ROOT="${1:-$PWD}"
SIMPLE_DIR="$PROJECT_ROOT/.simple"
NOTEPAD="$SIMPLE_DIR/notepad.md"

# No .simple/ directory = nothing to save
if [ ! -d "$SIMPLE_DIR" ]; then
  echo '{}'
  exit 0
fi

# Build notepad content from existing harness files
CONTENT="# Harness Notepad (saved before compaction)\n\n"
CONTENT+="## Timestamp\n$(date -u +%Y-%m-%dT%H:%M:%SZ)\n\n"

# Include current spec if pipeline is active
if [ -f "$SIMPLE_DIR/spec.md" ]; then
  SPEC_CONTENT=$(cat "$SIMPLE_DIR/spec.md")
  CONTENT+="## Active Spec\n$SPEC_CONTENT\n\n"
fi

# Include latest evaluation if exists
if [ -f "$SIMPLE_DIR/evaluation.md" ]; then
  EVAL_CONTENT=$(cat "$SIMPLE_DIR/evaluation.md")
  CONTENT+="## Latest Evaluation\n$EVAL_CONTENT\n\n"
fi

# Include gotchas for context continuity
if [ -f "$SIMPLE_DIR/gotchas.md" ]; then
  GOTCHA_CONTENT=$(cat "$SIMPLE_DIR/gotchas.md")
  CONTENT+="## Known Gotchas\n$GOTCHA_CONTENT\n\n"
fi

# Write notepad
printf '%b' "$CONTENT" > "$NOTEPAD"

# Output JSON with additional context for post-compaction
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreCompact",
    "additionalContext": "<system-reminder>\nHarness state saved before compaction. After compaction, check .simple/notepad.md to restore pipeline context.\n</system-reminder>"
  }
}
EOF
