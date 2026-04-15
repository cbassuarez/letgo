#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="${1:-/Users/seb/letgo/tmp/hls-test-shots}"
BUCKET="${2:-${R2_BUCKET:-}}"
PREFIX="${3:-${R2_PREFIX:-}}"
WRANGLER_BIN="${WRANGLER_BIN:-npx wrangler}"
PLAYLIST_CACHE_CONTROL="${PLAYLIST_CACHE_CONTROL:-public, max-age=3, s-maxage=3, must-revalidate}"
SEGMENT_CACHE_CONTROL="${SEGMENT_CACHE_CONTROL:-public, max-age=31536000, immutable}"
DRY_RUN="${DRY_RUN:-0}"
RETRY_COUNT="${RETRY_COUNT:-4}"
RETRY_DELAY_SECONDS="${RETRY_DELAY_SECONDS:-2}"
FAILED_COUNT=0
FAILED_KEYS=()

if [[ -z "$BUCKET" ]]; then
  echo "Usage: $0 <src_dir> <bucket> [prefix]" >&2
  echo "Or set R2_BUCKET environment variable." >&2
  exit 1
fi

if [[ ! -d "$SRC_DIR" ]]; then
  echo "Source directory not found: $SRC_DIR" >&2
  exit 1
fi

read -r -a WRANGLER_CMD <<< "$WRANGLER_BIN"

upload_one() {
  local file="$1"
  local rel="$2"
  local key
  local content_type
  local cache_control

  if [[ -n "$PREFIX" ]]; then
    key="${PREFIX%/}/$rel"
  else
    key="$rel"
  fi

  case "$file" in
    *.m3u8)
      content_type="application/vnd.apple.mpegurl"
      cache_control="$PLAYLIST_CACHE_CONTROL"
      ;;
    *.ts)
      content_type="video/mp2t"
      cache_control="$SEGMENT_CACHE_CONTROL"
      ;;
    *.m4s)
      content_type="video/iso.segment"
      cache_control="$SEGMENT_CACHE_CONTROL"
      ;;
    *.mp4)
      content_type="video/mp4"
      cache_control="$SEGMENT_CACHE_CONTROL"
      ;;
    *)
      return 0
      ;;
  esac

  echo "Uploading: $key"
  if [[ "$DRY_RUN" = "1" ]]; then
    echo "  dry-run: ${WRANGLER_CMD[*]} r2 object put \"$BUCKET/$key\" --remote --file \"$file\" --content-type \"$content_type\" --cache-control \"$cache_control\""
  else
    local attempt=1
    while true; do
      if "${WRANGLER_CMD[@]}" r2 object put "$BUCKET/$key" \
        --remote \
        --file "$file" \
        --content-type "$content_type" \
        --cache-control "$cache_control"; then
        break
      fi

      if [[ "$attempt" -ge "$RETRY_COUNT" ]]; then
        echo "  failed after $RETRY_COUNT attempts: $key" >&2
        FAILED_COUNT=$((FAILED_COUNT + 1))
        FAILED_KEYS+=("$key")
        break
      fi

      attempt=$((attempt + 1))
      echo "  retry $attempt/$RETRY_COUNT in ${RETRY_DELAY_SECONDS}s: $key" >&2
      sleep "$RETRY_DELAY_SECONDS"
    done
  fi
}

while IFS= read -r -d '' file; do
  rel="${file#$SRC_DIR/}"
  upload_one "$file" "$rel"
done < <(find "$SRC_DIR" -type f \( -name '*.m3u8' -o -name '*.ts' -o -name '*.m4s' -o -name '*.mp4' \) -print0)

if [[ "$FAILED_COUNT" -gt 0 ]]; then
  echo
  echo "Upload completed with failures: $FAILED_COUNT object(s)." >&2
  for failed_key in "${FAILED_KEYS[@]}"; do
    echo "  - $failed_key" >&2
  done
  exit 1
fi

echo
echo "Upload complete to bucket: $BUCKET"
if [[ -n "${HLS_BASE_URL:-}" ]]; then
  base="${HLS_BASE_URL%/}"
  if [[ -n "$PREFIX" ]]; then
    base="$base/${PREFIX%/}"
  fi
  echo "Mode playlist URLs:"
  echo "  preshow      $base/preshow/preshow.m3u8"
  echo "  introduction $base/introduction/introduction.m3u8"
  echo "  interstitial $base/interstitial/interstitial.m3u8"
  echo "  ending       $base/ending/ending.m3u8"
  if [[ -f "$SRC_DIR/main/main.m3u8" ]]; then
    echo "  main         $base/main/main.m3u8"
  fi
  if [[ -f "$SRC_DIR/main-dynamic/main-dynamic.m3u8" ]]; then
    echo "  main-dynamic $base/main-dynamic/main-dynamic.m3u8"
  fi
fi
