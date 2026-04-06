#!/usr/bin/env bash
set -euo pipefail

# Read user prompt from stdin (JSON)
# If python3 is unavailable, PROMPT becomes empty and the script returns {} (pass-through).
# This is intentional: a missed classification trigger is cheaper than a false one.
INPUT=$(cat)
PROMPT=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('prompt',''))" 2>/dev/null || echo "")

# Empty prompt = pass-through
if [ -z "$PROMPT" ]; then
  echo '{}'
  exit 0
fi

PROMPT_LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')
PROMPT_LEN=${#PROMPT}

# --- Rule 1: Explicit harness-run invocation ---
if echo "$PROMPT_LOWER" | grep -qE '((^|[[:space:]])(/simple-harness:run|/run)([[:space:]]|$)|\.simple/spec\.md)'; then
  cat <<'INJECT'
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "<system-reminder>\nThis request requires the full development pipeline (Planner + Generator + Evaluator). You MUST invoke the Skill tool with skill: \"simple-harness:run\" with args: \"full\" before taking any action. Pass the user's full request after the mode arg.\n</system-reminder>"
  }
}
INJECT
  exit 0
fi

# --- Rule 2: Question detection (short questions without action verbs) ---
if echo "$PROMPT" | grep -qE '\?$' && [ "$PROMPT_LEN" -lt 300 ]; then
  if ! echo "$PROMPT_LOWER" | grep -qE '(implement|build|create|add|fix|refactor|migrate|develop)'; then
    echo '{}'
    exit 0
  fi
fi

# --- Rule 3: Simple edit patterns ---
# Single file with line number
if echo "$PROMPT_LOWER" | grep -qE '(line [0-9]+|:[0-9]+)' && [ "$PROMPT_LEN" -lt 200 ]; then
  echo '{}'
  exit 0
fi

# Git operations
if echo "$PROMPT_LOWER" | grep -qE '^(commit|push|pull|merge|rebase|cherry-pick|stash|branch|checkout|tag|log|diff|status|/commit)'; then
  echo '{}'
  exit 0
fi

# Very short single-verb requests
if [ "$PROMPT_LEN" -lt 100 ] && echo "$PROMPT_LOWER" | grep -qE '^(rename|delete|remove|move|copy|format|lint)'; then
  echo '{}'
  exit 0
fi

# --- Rule 4: Complexity classification (MEDIUM vs HIGH) ---
MEDIUM=0
HIGH=0

# HIGH signals: architecture-level work, multi-system scope
# Multi-step language
if echo "$PROMPT_LOWER" | grep -qE '(and then|after that|first.*then|step [0-9]|1\.|2\.)'; then
  HIGH=1
fi

# Architecture verbs
if echo "$PROMPT_LOWER" | grep -qE '(refactor|redesign|migrate|architect|restructure)'; then
  HIGH=1
fi

# Scope words
if echo "$PROMPT_LOWER" | grep -qE '(across all|every file|throughout|entire|all files)'; then
  HIGH=1
fi

# Long prompts with action verbs
if [ "$PROMPT_LEN" -gt 500 ] && echo "$PROMPT_LOWER" | grep -qE '(implement|build|create|add|fix|refactor)'; then
  HIGH=1
fi

# MEDIUM signals: single feature or focused change
# Feature verbs with scope (but not multi-step)
if echo "$PROMPT_LOWER" | grep -qE '(implement .+ feature|add support for|build a|create a .+ system|develop a)'; then
  if [ "$HIGH" -eq 0 ]; then
    MEDIUM=1
  fi
fi

# Quality requirements
if echo "$PROMPT_LOWER" | grep -qE '(with tests|ensure|verify that|make sure|test coverage)'; then
  if [ "$HIGH" -eq 0 ]; then
    MEDIUM=1
  fi
fi

# --- Decision ---
if [ "$HIGH" -eq 1 ]; then
  # Full pipeline: Planner -> Generator -> Evaluator
  cat <<'INJECT'
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "<system-reminder>\nThis request requires the full development pipeline (Planner + Generator + Evaluator). You MUST invoke the Skill tool with skill: \"simple-harness:run\" with args: \"full\" before taking any action. Pass the user's full request after the mode arg.\n</system-reminder>"
  }
}
INJECT
elif [ "$MEDIUM" -eq 1 ]; then
  # Fast pipeline: Generator -> Evaluator (skip Planner)
  cat <<'INJECT'
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "<system-reminder>\nThis request needs the fast development pipeline (Generator + Evaluator, no Planner). You MUST invoke the Skill tool with skill: \"simple-harness:run\" with args: \"fast\" before taking any action. Pass the user's full request after the mode arg.\n</system-reminder>"
  }
}
INJECT
else
  # Default: pass-through
  echo '{}'
fi
