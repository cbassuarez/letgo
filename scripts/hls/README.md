# HLS Packaging + R2 Upload

These scripts package scene clips into HLS and upload to R2 with correct content-type/cache headers.

## 1) Build HLS from local test shots

Default profile (`vod`) keeps all scenes as VOD playlists (`#EXT-X-ENDLIST` present):

```bash
bash /Users/seb/letgo/scripts/hls/build_test_shots_hls.sh \
  /Users/seb/Desktop/letgo_test-shots \
  /Users/seb/letgo/tmp/hls-test-shots
```

Hybrid profile keeps static scenes VOD, but emits rolling live-style playlists (no `#EXT-X-ENDLIST`) for:

- `interstitial/interstitial.m3u8`
- optional `main-dynamic/main-dynamic.m3u8` (if a matching source file exists)

```bash
PACKAGER_PROFILE=hybrid-live \
bash /Users/seb/letgo/scripts/hls/build_test_shots_hls.sh \
  /Users/seb/Desktop/letgo_test-shots \
  /Users/seb/letgo/tmp/hls-test-shots
```

Build variables:

- `SEGMENT_SECONDS` (default `2`)
- `VOD_LOOP_MINUTES` (default `10`) for looped VOD scenes like preshow
- `PACKAGER_PROFILE` (`vod` or `hybrid-live`)
- `LIVE_LOOP_MINUTES` (default = `VOD_LOOP_MINUTES`)
- `LIVE_LIST_SIZE` (default `8`) for rolling playlists
- `LIVE_PROGRAM_DATE_TIME` (`1` default)
- `LIVE_DELETE_SEGMENTS` (`0` default; set `1` for true sliding-window cleanup)
- `LIVE_DELETE_THRESHOLD` (default `2`)

Notes:

- Rolling playlists without `ENDLIST` are meant for live-style behavior.
- If you enable `LIVE_DELETE_SEGMENTS=1`, old segment files are removed while packaging.

## 2) Upload HLS to R2 with metadata

```bash
export R2_BUCKET="letgo-hls"
export HLS_BASE_URL="https://media.yourdomain.com"

bash /Users/seb/letgo/scripts/hls/upload_hls_to_r2.sh \
  /Users/seb/letgo/tmp/hls-test-shots \
  "$R2_BUCKET" \
  "test-shots-v1"
```

Dry run:

```bash
DRY_RUN=1 bash /Users/seb/letgo/scripts/hls/upload_hls_to_r2.sh \
  /Users/seb/letgo/tmp/hls-test-shots \
  "$R2_BUCKET" \
  "test-shots-v1"
```

Metadata behavior:

- `*.m3u8` -> `Content-Type: application/vnd.apple.mpegurl`
- `*.ts` -> `Content-Type: video/mp2t`
- `*.m4s` -> `Content-Type: video/iso.segment`
- `*.mp4` -> `Content-Type: video/mp4`

Cache behavior:

- playlists -> short cache (`max-age=3`)
- segments -> long cache (`max-age=31536000, immutable`)

## 3) Harness env mapping

```bash
export CONDUCTOR_HLS_PRESHOW_URL="https://media.yourdomain.com/test-shots-v1/preshow/preshow.m3u8"
export CONDUCTOR_HLS_INTRODUCTION_URL="https://media.yourdomain.com/test-shots-v1/introduction/introduction.m3u8"
export CONDUCTOR_HLS_INTERSTITIAL_URL="https://media.yourdomain.com/test-shots-v1/interstitial/interstitial.m3u8"
export CONDUCTOR_HLS_ENDING_URL="https://media.yourdomain.com/test-shots-v1/ending/ending.m3u8"
unset CONDUCTOR_HLS_MAIN_URL
unset CONDUCTOR_HLS_LANE_BASE_URL
```

If you later publish `main/main.m3u8`:

```bash
export CONDUCTOR_HLS_MAIN_URL="https://media.yourdomain.com/test-shots-v1/main/main.m3u8"
```

If you later publish lane playlists:

```bash
export CONDUCTOR_HLS_LANE_BASE_URL="https://media.yourdomain.com/test-shots-v1/lanes"
```
