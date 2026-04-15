#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="${1:-/Users/seb/Desktop/letgo_test-shots}"
OUT_DIR="${2:-/Users/seb/letgo/tmp/hls-test-shots}"

SEGMENT_SECONDS="${SEGMENT_SECONDS:-2}"
PACKAGER_PROFILE="${PACKAGER_PROFILE:-vod}" # vod | hybrid-live

# Backward-compatible default for old LOOP_MINUTES callers.
DEFAULT_LOOP_MINUTES="${LOOP_MINUTES:-10}"
VOD_LOOP_MINUTES="${VOD_LOOP_MINUTES:-$DEFAULT_LOOP_MINUTES}"
LIVE_LOOP_MINUTES="${LIVE_LOOP_MINUTES:-$VOD_LOOP_MINUTES}"

LIVE_LIST_SIZE="${LIVE_LIST_SIZE:-8}"
LIVE_DELETE_SEGMENTS="${LIVE_DELETE_SEGMENTS:-0}"
LIVE_DELETE_THRESHOLD="${LIVE_DELETE_THRESHOLD:-2}"
LIVE_PROGRAM_DATE_TIME="${LIVE_PROGRAM_DATE_TIME:-1}"
MAIN_STATIC_LOOP_MINUTES="${MAIN_STATIC_LOOP_MINUTES:-0}"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg is required but not found." >&2
  exit 1
fi

if ! command -v ffprobe >/dev/null 2>&1; then
  echo "ffprobe is required but not found." >&2
  exit 1
fi

if [[ ! -d "$SRC_DIR" ]]; then
  echo "Source directory not found: $SRC_DIR" >&2
  exit 1
fi

case "$PACKAGER_PROFILE" in
  vod|hybrid-live)
    ;;
  *)
    echo "Unsupported PACKAGER_PROFILE '$PACKAGER_PROFILE'. Use 'vod' or 'hybrid-live'." >&2
    exit 1
    ;;
esac

find_required() {
  local pattern="$1"
  local label="$2"
  local file
  file="$(find "$SRC_DIR" -maxdepth 1 -type f | grep -Ei "$pattern" | head -n 1 || true)"
  if [[ -z "$file" ]]; then
    echo "Missing required source '$label' (pattern '$pattern') in $SRC_DIR" >&2
    exit 1
  fi
  echo "$file"
}

find_optional() {
  local pattern="$1"
  find "$SRC_DIR" -maxdepth 1 -type f | grep -Ei "$pattern" | head -n 1 || true
}

duration_seconds() {
  local file="$1"
  ffprobe -v error -show_entries format=duration -of csv=p=0 "$file"
}

calc_stream_loop() {
  local loop_for_minutes="$1"
  local duration="$2"
  local plays
  local stream_loop
  local target_seconds

  stream_loop=0
  if [[ "$loop_for_minutes" -gt 0 ]]; then
    target_seconds=$((loop_for_minutes * 60))
    plays="$(awk -v t="$target_seconds" -v d="$duration" 'BEGIN { if (d <= 0) { print 1 } else { print int((t + d - 0.0001) / d) } }')"
    if [[ "$plays" -lt 1 ]]; then
      plays=1
    fi
    stream_loop=$((plays - 1))
  fi

  echo "$stream_loop"
}

build_vod_hls() {
  local input="$1"
  local scene_dir_name="$2"
  local playlist_name="$3"
  local loop_for_minutes="$4"
  local scene_dir="$OUT_DIR/$scene_dir_name"
  local playlist="$scene_dir/$playlist_name.m3u8"
  local segment_pattern="$scene_dir/${playlist_name}_%05d.ts"
  local duration
  local stream_loop
  local -a ffmpeg_cmd

  rm -rf "$scene_dir"
  mkdir -p "$scene_dir"
  duration="$(duration_seconds "$input")"
  stream_loop="$(calc_stream_loop "$loop_for_minutes" "$duration")"

  ffmpeg_cmd=(
    ffmpeg
    -y
    -hide_banner
    -loglevel
    warning
  )

  if [[ "$stream_loop" -gt 0 ]]; then
    ffmpeg_cmd+=(-stream_loop "$stream_loop")
  fi

  ffmpeg_cmd+=(
    -i "$input"
    -an
    -c:v libx264
    -preset veryfast
    -profile:v high
    -level:v 4.1
    -pix_fmt yuv420p
    -r 24
    -g 48
    -keyint_min 48
    -sc_threshold 0
    -hls_time "$SEGMENT_SECONDS"
    -hls_playlist_type vod
    -hls_segment_type mpegts
    -hls_flags independent_segments
    -hls_segment_filename "$segment_pattern"
    "$playlist"
  )

  echo "Building VOD $scene_dir_name/$playlist_name from $(basename "$input")"
  "${ffmpeg_cmd[@]}"
}

build_live_rolling_hls() {
  local input="$1"
  local scene_dir_name="$2"
  local playlist_name="$3"
  local loop_for_minutes="$4"
  local scene_dir="$OUT_DIR/$scene_dir_name"
  local playlist="$scene_dir/$playlist_name.m3u8"
  local segment_pattern="$scene_dir/${playlist_name}_%05d.ts"
  local duration
  local stream_loop
  local flags_arg
  local -a flags
  local -a ffmpeg_cmd

  rm -rf "$scene_dir"
  mkdir -p "$scene_dir"
  duration="$(duration_seconds "$input")"
  stream_loop="$(calc_stream_loop "$loop_for_minutes" "$duration")"

  flags=("independent_segments" "omit_endlist")
  if [[ "$LIVE_PROGRAM_DATE_TIME" == "1" ]]; then
    flags+=("program_date_time")
  fi
  if [[ "$LIVE_DELETE_SEGMENTS" == "1" ]]; then
    flags+=("delete_segments")
  fi
  flags_arg="$(IFS=+; echo "${flags[*]}")"

  ffmpeg_cmd=(
    ffmpeg
    -y
    -hide_banner
    -loglevel
    warning
  )

  if [[ "$stream_loop" -gt 0 ]]; then
    ffmpeg_cmd+=(-stream_loop "$stream_loop")
  fi

  ffmpeg_cmd+=(
    -i "$input"
    -an
    -c:v libx264
    -preset veryfast
    -profile:v high
    -level:v 4.1
    -pix_fmt yuv420p
    -r 24
    -g 48
    -keyint_min 48
    -sc_threshold 0
    -hls_time "$SEGMENT_SECONDS"
    -hls_list_size "$LIVE_LIST_SIZE"
  )

  if [[ "$LIVE_DELETE_SEGMENTS" == "1" ]]; then
    ffmpeg_cmd+=(-hls_delete_threshold "$LIVE_DELETE_THRESHOLD")
  fi

  ffmpeg_cmd+=(
    -hls_start_number_source epoch
    -hls_segment_type mpegts
    -hls_flags "$flags_arg"
    -hls_segment_filename "$segment_pattern"
    "$playlist"
  )

  echo "Building rolling-live $scene_dir_name/$playlist_name from $(basename "$input")"
  "${ffmpeg_cmd[@]}"
}

INTRO_INPUT="$(find_required 'intro' 'introduction')"
PRESHOW_INPUT="$(find_required 'preshow' 'preshow')"
INTERSTITIAL_INPUT="$(find_required 'interstitial' 'interstitial')"
ENDING_INPUT="$(find_required 'ending' 'ending')"
MAIN_STATIC_INPUT="$(find_optional 'main[-_ ]?static|static[-_ ]?main')"
MAIN_DYNAMIC_INPUT="$(find_optional 'main[-_ ]?dynamic|dynamic[-_ ]?main')"

mkdir -p "$OUT_DIR"

case "$PACKAGER_PROFILE" in
  vod)
    # Intro + ending are one-pass moments. Preshow + interstitial are looped VOD.
    build_vod_hls "$INTRO_INPUT" "introduction" "introduction" 0
    build_vod_hls "$PRESHOW_INPUT" "preshow" "preshow" "$VOD_LOOP_MINUTES"
    build_vod_hls "$INTERSTITIAL_INPUT" "interstitial" "interstitial" "$VOD_LOOP_MINUTES"
    build_vod_hls "$ENDING_INPUT" "ending" "ending" 0
    if [[ -n "$MAIN_STATIC_INPUT" ]]; then
      build_vod_hls "$MAIN_STATIC_INPUT" "main" "main" "$MAIN_STATIC_LOOP_MINUTES"
    fi
    ;;
  hybrid-live)
    # Static scenes stay VOD; interstitial + optional main-dynamic become live-style rolling playlists.
    build_vod_hls "$INTRO_INPUT" "introduction" "introduction" 0
    build_vod_hls "$PRESHOW_INPUT" "preshow" "preshow" "$VOD_LOOP_MINUTES"
    build_vod_hls "$ENDING_INPUT" "ending" "ending" 0
    if [[ -n "$MAIN_STATIC_INPUT" ]]; then
      build_vod_hls "$MAIN_STATIC_INPUT" "main" "main" "$MAIN_STATIC_LOOP_MINUTES"
    fi

    build_live_rolling_hls "$INTERSTITIAL_INPUT" "interstitial" "interstitial" "$LIVE_LOOP_MINUTES"
    if [[ -n "$MAIN_DYNAMIC_INPUT" ]]; then
      build_live_rolling_hls "$MAIN_DYNAMIC_INPUT" "main-dynamic" "main-dynamic" "$LIVE_LOOP_MINUTES"
    else
      echo "No main-dynamic source found; skipping optional rolling main-dynamic output."
    fi
    ;;
esac

echo
echo "HLS output ready: $OUT_DIR"
echo "Profile: $PACKAGER_PROFILE"
echo "Playlists:"
find "$OUT_DIR" -type f -name '*.m3u8' | sort | sed 's#^#  - #'
