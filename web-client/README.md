# web-client

Participant-facing mobile web client.

## Features

- `/:hashedId` identity route
- Permission bootstrap for audio, motion, geolocation
- Manual zone refinement for indoor spatial reliability
- Realtime cue + vector ingestion
- Drift estimation and sync pong replies
- Local fallback snapshot for temporary disconnects
- Experimental `html-in-canvas` visual layer

## Media Assets

Place fixed-scene files in `public/media`:

- `preshow.mp4`
- `introduction.mp4`
- `show-fixed.mp4`
- `ending.mp4`

## HLS Live Streams

`/live` prefers a cue payload stream ref when present:

- `showFixedMediaRef` (supports `.m3u8` HLS playlists)
- `showFixedMediaMime` optional (set to `application/vnd.apple.mpegurl` for explicit HLS typing)

When no stream ref is provided, it falls back to local files in `public/media`.
