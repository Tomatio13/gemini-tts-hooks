#!/usr/bin/env bash
set -euo pipefail

CACHE_DIR="$HOME/.claude/hooks/gemini-tts-audio"
SESSION_DIR="$CACHE_DIR/.sessions"

SESSION_ID=$(echo "${CLAUDE_SESSION_ID:-}" | tr -cd '[:alnum:]_-')
if [ -n "$SESSION_ID" ]; then
  rm -f "$SESSION_DIR/$SESSION_ID"
fi

exit 0
