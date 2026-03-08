#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  tts_to_wav.sh --text "こんにちは" [--voice Kore] [--output-base output] [--output-dir .] [--max-chars 300] [--keep-temp]
  tts_to_wav.sh --text-file input.txt [--voice Kore] [--output-base output] [--output-dir .] [--max-chars 300] [--keep-temp]
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL="gemini-2.5-flash-preview-tts"
VOICE_NAME="Kore"
OUTPUT_BASE="output"
OUTPUT_DIR="."
MAX_CHARS="300"
TEXT=""
TEXT_FILE=""
KEEP_TEMP="false"
MAX_RETRIES="${GEMINI_TTS_MAX_RETRIES:-3}"

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
    --output-base)
      OUTPUT_BASE="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --max-chars)
      MAX_CHARS="${2:-}"
      shift 2
      ;;
    --keep-temp)
      KEEP_TEMP="true"
      shift
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

if [[ -n "$TEXT" && -n "$TEXT_FILE" ]]; then
  echo "Use either --text or --text-file, not both." >&2
  exit 1
fi

if ! [[ "$MAX_CHARS" =~ ^[0-9]+$ ]] || [[ "$MAX_CHARS" -le 0 ]]; then
  echo "--max-chars must be a positive integer." >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

temp_dir="$(mktemp -d)"
cleanup() {
  if [[ "$KEEP_TEMP" != "true" && -d "$temp_dir" ]]; then
    rm -rf "$temp_dir"
  fi
}
trap cleanup EXIT

retry_sleep_seconds() {
  local response_json="$1"
  local retry_seconds

  if [[ -f "$response_json" ]]; then
    retry_seconds="$(grep -oE '"retryDelay":[[:space:]]*"[0-9]+s"' "$response_json" | grep -oE '[0-9]+' | head -n 1 || true)"
    if [[ -n "$retry_seconds" ]]; then
      printf '%s' "$retry_seconds"
      return
    fi
  fi

  printf '0'
}

input_text_file="$temp_dir/input.txt"
chunks_dir="$temp_dir/chunks"
wav_parts_dir="$temp_dir/wav_parts"
responses_dir="$temp_dir/responses"
concat_list="$temp_dir/concat-list.txt"
merged_wav="${OUTPUT_DIR%/}/${OUTPUT_BASE}.wav"

mkdir -p "$chunks_dir" "$wav_parts_dir" "$responses_dir"

if [[ -n "$TEXT_FILE" ]]; then
  if [[ ! -f "$TEXT_FILE" ]]; then
    echo "Text file not found: $TEXT_FILE" >&2
    exit 1
  fi
  cp "$TEXT_FILE" "$input_text_file"
else
  if [[ -z "$TEXT" ]]; then
    echo "Text is required. Use --text or --text-file." >&2
    exit 1
  fi
  printf '%s' "$TEXT" > "$input_text_file"
fi

chunk_count="$(node "$SCRIPT_DIR/split_text_chunks.js" --input-file "$input_text_file" --max-chars "$MAX_CHARS" --output-dir "$chunks_dir")"
if ! [[ "$chunk_count" =~ ^[0-9]+$ ]] || [[ "$chunk_count" -le 0 ]]; then
  echo "Failed to split input text into chunks." >&2
  exit 1
fi

: > "$concat_list"
for chunk_file in "$chunks_dir"/chunk_*.txt; do
  chunk_name="$(basename "$chunk_file" .txt)"
  response_json="$responses_dir/${chunk_name}.json"
  wav_part="$wav_parts_dir/${chunk_name}.wav"

  attempt=1
  until [[ "$attempt" -gt "$MAX_RETRIES" ]]; do
    if "$SCRIPT_DIR/generate_tts.sh" \
      --text-file "$chunk_file" \
      --voice "$VOICE_NAME" \
      --model "$MODEL" \
      --out "$response_json" && \
      node "$SCRIPT_DIR/decode_pcm_to_wav.js" --input "$response_json" --output "$wav_part"; then
      break
    fi

    if [[ "$attempt" -eq "$MAX_RETRIES" ]]; then
      echo "Failed to generate audio for ${chunk_name} after ${MAX_RETRIES} attempts." >&2
      exit 1
    fi

    sleep_seconds="$(retry_sleep_seconds "$response_json")"
    rm -f "$response_json" "$wav_part"
    if [[ "$sleep_seconds" -gt 0 ]]; then
      sleep "$sleep_seconds"
    else
      sleep $((attempt * 2))
    fi
    attempt=$((attempt + 1))
  done

  printf "file '%s'\n" "$wav_part" >> "$concat_list"
done

if [[ "$chunk_count" -eq 1 ]]; then
  cp "$wav_parts_dir/chunk_001.wav" "$merged_wav"
else
  if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "ffmpeg is required but not found in PATH." >&2
    exit 1
  fi

  ffmpeg -y -hide_banner -loglevel error \
    -f concat -safe 0 -i "$concat_list" \
    -c copy "$merged_wav"
fi

if [[ "$KEEP_TEMP" == "true" ]]; then
  artifacts_dir="${OUTPUT_DIR%/}/${OUTPUT_BASE}.artifacts"
  rm -rf "$artifacts_dir"
  mv "$temp_dir" "$artifacts_dir"
  echo "Temp artifacts saved: $artifacts_dir"
fi

echo "Chunks processed: $chunk_count"
echo "Done: $merged_wav"
