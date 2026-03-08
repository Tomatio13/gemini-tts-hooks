#!/usr/bin/env bash
set -euo pipefail

CACHE_DIR="$HOME/.claude/hooks/gemini-tts-audio"
LOCK_FILE="$CACHE_DIR/.playing.lock"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts"
VOICE_NAME="${GEMINI_TTS_VOICE:-Kore}"
MAX_CHARS="${GEMINI_TTS_MAX_CHARS:-300}"
AUDIO_DEVICE="${GEMINI_TTS_AUDIO_DEVICE:-}"

if ! command -v jq >/dev/null 2>&1; then
  echo "gemini-tts-speak: jq not found." >&2
  exit 0
fi
if ! command -v node >/dev/null 2>&1; then
  echo "gemini-tts-speak: node not found." >&2
  exit 0
fi
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "gemini-tts-speak: ffmpeg not found." >&2
  exit 0
fi

INPUT=$(cat)
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // ""')
TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""')
BASH_CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

resolve() {
  local event="$1" tool="$2" cmd="$3"
  if [ "$event" = "PreToolUse" ] && [ "$tool" = "Bash" ]; then
    if echo "$cmd" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+push([[:space:]]|$)'; then
      printf '%s\t%s' "プッシュします" "PreToolUse_Bash_GitPush"
      return
    fi
    if echo "$cmd" | grep -qE '(^|[;&|[:space:]])(gh[[:space:]]+pr[[:space:]]+create)([[:space:]]|$)'; then
      printf '%s\t%s' "プルリクエストを作成します" "PreToolUse_Bash_GhPrCreate"
      return
    fi
  fi
  if [ "$event" = "PostToolUse" ] && [ "$tool" = "Bash" ]; then
    PREV_CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
    if echo "$PREV_CMD" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+push([[:space:]]|$)'; then
      printf '%s\t%s' "プッシュが完了しました" "PostToolUse_Bash_GitPush"
      return
    fi
    if echo "$PREV_CMD" | grep -qE '(^|[;&|[:space:]])(gh[[:space:]]+pr[[:space:]]+create)([[:space:]]|$)'; then
      printf '%s\t%s' "プルリクエストを作成しました" "PostToolUse_Bash_GhPrCreate"
      return
    fi
  fi
  # デフォルトマッピング
  case "${event}_${tool}" in
    PreToolUse_Bash)   printf '%s\t%s' "コマンドを実行します"     "PreToolUse_Bash" ;;
    PreToolUse_Write)  printf '%s\t%s' "ファイルを書き込みます"   "PreToolUse_Write" ;;
    PreToolUse_Edit)   printf '%s\t%s' "ファイルを編集します"     "PreToolUse_Edit" ;;
    PreToolUse_Read)   printf '%s\t%s' "ファイルを読み込みます"   "PreToolUse_Read" ;;
    PreToolUse_Glob)   printf '%s\t%s' "ファイルを探します"       "PreToolUse_Glob" ;;
    PreToolUse_Grep)   printf '%s\t%s' "ファイルを検索します"     "PreToolUse_Grep" ;;
    PreToolUse_*)      printf '%s\t%s' "ツールを使用します"       "PreToolUse_Unknown" ;;
    PostToolUse_Bash)  printf '%s\t%s' "コマンドが完了しました"   "PostToolUse_Bash" ;;
    PostToolUse_Write) printf '%s\t%s' "書き込みが完了しました"   "PostToolUse_Write" ;;
    PostToolUse_Edit)  printf '%s\t%s' "編集が完了しました"       "PostToolUse_Edit" ;;
    PostToolUse_*)     printf '%s\t%s' "処理が完了しました"       "PostToolUse_Unknown" ;;
    *)                 printf '%s\t%s' "" "" ;;
  esac
}

RESOLVED=$(resolve "$EVENT" "$TOOL" "$BASH_CMD")
TEXT=$(echo "$RESOLVED" | cut -f1)
CACHE_KEY=$(echo "$RESOLVED" | cut -f2)

[ -z "$TEXT" ] && exit 0

mkdir -p "$CACHE_DIR"

SAFE_KEY=$(echo "$CACHE_KEY" | tr -cd '[:alnum:]_')
CACHE_FILE="$CACHE_DIR/${SAFE_KEY}.wav"

_lock_is_active() {
  [ -f "$LOCK_FILE" ] || return 1
  local pid
  pid=$(cat "$LOCK_FILE" 2>/dev/null) || return 1
  [ -n "$pid" ] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  local comm
  comm=$(ps -p "$pid" -o comm= 2>/dev/null) || return 1
  echo "$comm" | grep -qiE '^(afplay|aplay|paplay|powershell|powershell\.exe)$'
}

if _lock_is_active; then
  exit 0
fi
rm -f "$LOCK_FILE"

OS=$(uname -s)
play_audio_bg() {
  local file="$1"
  [ -f "$file" ] || return
  if ! (set -o noclobber; : > "$LOCK_FILE") 2>/dev/null; then
    if _lock_is_active; then
      return
    fi
    rm -f "$LOCK_FILE"
    (set -o noclobber; : > "$LOCK_FILE") 2>/dev/null || return
  fi
  case "$OS" in
    Darwin*)
      afplay "$file" &
      echo $! > "$LOCK_FILE" ;;
    MINGW*|MSYS*|CYGWIN*)
      local winpath
      if command -v cygpath >/dev/null 2>&1; then
        winpath=$(cygpath -w "$file")
      else
        winpath=$(printf '%s' "$file" | sed 's|^/\([a-zA-Z]\)/|\1:/|;s|/|\\|g')
      fi
      local escaped="${winpath//\'/\'\'}"
      powershell.exe -NoProfile -Command \
        "Add-Type -AssemblyName presentationCore; \$player = New-Object System.Windows.Media.MediaPlayer; \$player.Open([Uri]'$escaped'); while (-not \$player.NaturalDuration.HasTimeSpan) { Start-Sleep -Milliseconds 100 }; \$player.Play(); Start-Sleep -Milliseconds ([int](\$player.NaturalDuration.TimeSpan.TotalMilliseconds + 250)); \$player.Close()" 2>/dev/null &
      echo $! > "$LOCK_FILE" ;;
    *)
      if command -v paplay >/dev/null 2>&1; then
        if [[ -n "$AUDIO_DEVICE" ]]; then
          paplay --device="$AUDIO_DEVICE" "$file" >/dev/null 2>&1 &
        else
          paplay "$file" >/dev/null 2>&1 &
        fi
        echo $! > "$LOCK_FILE"
      elif command -v aplay >/dev/null 2>&1; then
        aplay -q "$file" >/dev/null 2>&1 &
        echo $! > "$LOCK_FILE"
      else
        echo "gemini-tts-speak: no wav player found (paplay/aplay)" >&2
        rm -f "$LOCK_FILE"
      fi ;;
  esac
}

if [ -f "$CACHE_FILE" ]; then
  if [ ! -s "$CACHE_FILE" ]; then
    rm -f "$CACHE_FILE"
  else
    play_audio_bg "$CACHE_FILE"
    exit 0
  fi
fi

START_LOCK="$CACHE_DIR/.gemini.generating.${SAFE_KEY}.lock"
if ! (set -o noclobber; : > "$START_LOCK") 2>/dev/null; then
  exit 0
fi

cleanup() {
  rm -f "$START_LOCK"
}
trap cleanup EXIT

TMP_DIR="$(mktemp -d "${CACHE_DIR}/.tmp_${SAFE_KEY}_XXXXXX")"
TMP_FILE="$TMP_DIR/${SAFE_KEY}.wav"

if "$SCRIPT_DIR/tts_to_wav.sh" \
  --text "$TEXT" \
  --voice "$VOICE_NAME" \
  --max-chars "$MAX_CHARS" \
  --output-dir "$TMP_DIR" \
  --output-base "$SAFE_KEY" >/dev/null 2>&1; then
  if [ -s "$TMP_FILE" ]; then
    mv "$TMP_FILE" "$CACHE_FILE"
    play_audio_bg "$CACHE_FILE"
  fi
fi

rm -rf "$TMP_DIR"

exit 0
