#!/usr/bin/env bash
set -euo pipefail

CACHE_DIR="$HOME/.claude/hooks/gemini-tts-audio"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ASSET_DIR="$REPO_DIR/assets"
VOICE_NAME="${GEMINI_TTS_VOICE:-Kore}"
MAX_CHARS="${GEMINI_TTS_MAX_CHARS:-300}"

mkdir -p "$CACHE_DIR" "$ASSET_DIR"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: $1 が見つかりません。" >&2
    exit 1
  fi
}

for cmd in node ffmpeg curl; do
  require_cmd "$cmd"
done

generate_wav() {
  local output_dir="$1"
  local key="$2"
  local text="$3"
  local output_file="${output_dir}/${key}.wav"

  if [[ -s "$output_file" ]]; then
    echo "skip: ${key}.wav"
    return
  fi

  "$SCRIPT_DIR/tts_to_wav.sh" \
    --text "$text" \
    --voice "$VOICE_NAME" \
    --max-chars "$MAX_CHARS" \
    --output-dir "$output_dir" \
    --output-base "$key"

  echo "generated: ${key}.wav  「$text」"
}

TOOL_AUDIO_MAP=(
  "PreToolUse_Bash:コマンドを実行します"
  "PreToolUse_Write:ファイルを書き込みます"
  "PreToolUse_Edit:ファイルを編集します"
  "PreToolUse_Read:ファイルを読み込みます"
  "PreToolUse_Glob:ファイルを探します"
  "PreToolUse_Grep:ファイルを検索します"
  "PreToolUse_Unknown:ツールを使用します"
  "PostToolUse_Bash:コマンドが完了しました"
  "PostToolUse_Write:書き込みが完了しました"
  "PostToolUse_Edit:編集が完了しました"
  "PostToolUse_Unknown:処理が完了しました"
  "PreToolUse_Bash_GitPush:プッシュします"
  "PreToolUse_Bash_GhPrCreate:プルリクエストを作成します"
  "PostToolUse_Bash_GitPush:プッシュが完了しました"
  "PostToolUse_Bash_GhPrCreate:プルリクエストを作成しました"
)

echo "=== Gemini TTS 音声キャッシュ生成 ==="
echo "キャッシュ先: $CACHE_DIR"
echo "音声: $VOICE_NAME"
echo ""

for entry in "${TOOL_AUDIO_MAP[@]}"; do
  key="${entry%%:*}"
  text="${entry#*:}"
  generate_wav "$CACHE_DIR" "$key" "$text"
done

generate_wav "$ASSET_DIR" "initial_warning" \
  "見知らぬ人が作成した hooks を内容を確認せずにインストールして使うのは危険です"

{
  for entry in "${TOOL_AUDIO_MAP[@]}"; do
    printf '%s\n' "${entry%%:*}"
  done
} > "$CACHE_DIR/.cache-manifest"
echo "updated: .cache-manifest"

echo ""
echo "=== 完了 ==="
ls -lh "$CACHE_DIR"/*.wav 2>/dev/null || echo "(WAVファイルなし)"
