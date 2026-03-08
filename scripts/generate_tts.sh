#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  generate_tts.sh --text "こんにちは" [--voice Kore] [--model gemini-2.5-flash-preview-tts] [--out response.json]
  generate_tts.sh --text-file input.txt [--voice Kore] [--model gemini-2.5-flash-preview-tts] [--out response.json]

Environment:
  GEMINI_API_KEY   Fallback Gemini API key (used last)
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL="gemini-2.5-flash-preview-tts"
VOICE_NAME="Kore"
OUT_JSON="response.json"
TEXT=""
TEXT_FILE=""

read_api_key_from_env_file() {
  local env_file="$1"
  local line value

  [[ -f "$env_file" ]] || return 1

  line="$(grep -E '^[[:space:]]*GEMINI_API_KEY[[:space:]]*=' "$env_file" | tail -n 1 || true)"
  [[ -n "$line" ]] || return 1

  value="${line#*=}"
  value="$(printf '%s' "$value" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"

  if [[ "$value" == \"*\" && "$value" == *\" && "${#value}" -ge 2 ]]; then
    value="${value:1:${#value}-2}"
  elif [[ "$value" == \'*\' && "$value" == *\' && "${#value}" -ge 2 ]]; then
    value="${value:1:${#value}-2}"
  fi

  [[ -n "$value" ]] || return 1
  printf '%s' "$value"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --text)
      TEXT="${2:-}"
      shift 2
      ;;
    --text-file)
      TEXT_FILE="${2:-}"
      shift 2
      ;;
    --voice)
      VOICE_NAME="${2:-}"
      shift 2
      ;;
    --model)
      MODEL="${2:-}"
      shift 2
      ;;
    --out)
      OUT_JSON="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

API_KEY=""
if API_KEY="$(read_api_key_from_env_file ".env")"; then
  :
elif API_KEY="$(read_api_key_from_env_file "$SCRIPT_DIR/../.env")"; then
  :
elif [[ -n "${GEMINI_API_KEY:-}" ]]; then
  API_KEY="${GEMINI_API_KEY}"
fi

if [[ -z "$API_KEY" ]]; then
  echo "GEMINI_API_KEY is not set." >&2
  exit 1
fi

if [[ -n "$TEXT" && -n "$TEXT_FILE" ]]; then
  echo "Use either --text or --text-file, not both." >&2
  exit 1
fi

if [[ -n "$TEXT_FILE" ]]; then
  if [[ ! -f "$TEXT_FILE" ]]; then
    echo "Text file not found: $TEXT_FILE" >&2
    exit 1
  fi
  TEXT="$(cat "$TEXT_FILE")"
fi

if [[ -z "$TEXT" ]]; then
  echo "Text is required. Use --text or --text-file." >&2
  exit 1
fi

payload_file="$(mktemp)"
trap 'rm -f "$payload_file"' EXIT

TEXT="$TEXT" VOICE_NAME="$VOICE_NAME" node -e '
const fs = require("fs");
const transcript = process.env.TEXT;
const payload = {
  contents: [{
    parts: [{
      text: `Read aloud the following Japanese text in standard Japanese. Speak only the quoted transcript without adding anything else: 「${transcript}」`
    }]
  }],
  generationConfig: {
    responseModalities: ["AUDIO"],
    speechConfig: {
      voiceConfig: {
        prebuiltVoiceConfig: {
          voiceName: process.env.VOICE_NAME,
        },
      },
    },
  },
};
fs.writeFileSync(process.argv[1], JSON.stringify(payload));
' "$payload_file"

url="https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent"
http_code="$(curl -sS -o "$OUT_JSON" -w "%{http_code}" "$url" \
  -H "x-goog-api-key: ${API_KEY}" \
  -H 'Content-Type: application/json' \
  -d @"$payload_file")"

if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
  echo "Gemini API request failed (HTTP $http_code)." >&2
  if [[ -s "$OUT_JSON" ]]; then
    cat "$OUT_JSON" >&2
  fi
  exit 1
fi

echo "Saved API response: $OUT_JSON"
