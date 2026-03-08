#!/usr/bin/env bash
set -euo pipefail

CACHE_DIR="$HOME/.claude/hooks/gemini-tts-audio"
SESSION_DIR="$CACHE_DIR/.sessions"
AUDIO_DEVICE="${GEMINI_TTS_AUDIO_DEVICE:-}"

if [ -z "${CLAUDE_PROJECT_DIR:-}" ]; then
  echo "gemini-tts-session-start: CLAUDE_PROJECT_DIR unset, skipping" >&2
  exit 0
fi

INITIAL_WAV="${CLAUDE_PROJECT_DIR}/assets/initial_warning.wav"
mkdir -p "$CACHE_DIR" "$SESSION_DIR"

SESSION_ID=$(echo "${CLAUDE_SESSION_ID:-$$}" | tr -cd '[:alnum:]_-')
[ -n "$SESSION_ID" ] && touch "$SESSION_DIR/$SESSION_ID"

play_audio() {
  local file="$1"
  local os
  os=$(uname -s)
  [ -f "$file" ] || return

  case "$os" in
    Darwin*)
      afplay "$file"
      ;;
    MINGW*|MSYS*|CYGWIN*)
      local winpath
      if command -v cygpath >/dev/null 2>&1; then
        winpath=$(cygpath -w "$file")
      else
        winpath=$(printf '%s' "$file" | sed 's|^/\([a-zA-Z]\)/|\1:/|;s|/|\\|g')
      fi
      local escaped="${winpath//\'/\'\'}"
      powershell.exe -NoProfile -Command \
        "Add-Type -AssemblyName presentationCore; \$player = New-Object System.Windows.Media.MediaPlayer; \$player.Open([Uri]'$escaped'); while (-not \$player.NaturalDuration.HasTimeSpan) { Start-Sleep -Milliseconds 100 }; \$player.Play(); Start-Sleep -Milliseconds ([int](\$player.NaturalDuration.TimeSpan.TotalMilliseconds + 250)); \$player.Close()" 2>/dev/null
      ;;
    *)
      if command -v paplay >/dev/null 2>&1; then
        if [[ -n "$AUDIO_DEVICE" ]]; then
          paplay --device="$AUDIO_DEVICE" "$file" >/dev/null 2>&1
        else
          paplay "$file" >/dev/null 2>&1
        fi
      elif command -v aplay >/dev/null 2>&1; then
        aplay -q "$file" >/dev/null 2>&1
      fi
      ;;
  esac
}

CACHE_MANIFEST="$CACHE_DIR/.cache-manifest"
ALL_CACHED=false
if [ -f "$CACHE_MANIFEST" ]; then
  ALL_CACHED=true
  while IFS= read -r key || [ -n "$key" ]; do
    [ -n "$key" ] || continue
    [[ "$key" =~ ^[A-Za-z0-9_]+$ ]] || continue
    if [ ! -s "$CACHE_DIR/${key}.wav" ]; then
      ALL_CACHED=false
      break
    fi
  done < "$CACHE_MANIFEST"
fi

if [ "$ALL_CACHED" = "false" ] && [ -f "$INITIAL_WAV" ]; then
  play_audio "$INITIAL_WAV"
fi

exit 0
