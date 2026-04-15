# harness-swift

macOS conductor app and core engine modules.

## Key Modules

- `ShowStateMachine`: deterministic fixed timeline transitions + control actions
- `TimelineTransport`: action application + command/vector dispatch
- `MIDIIngestor`: maps controller CC values to dynamic parameter vectors
- `TextSelectionEngine`: hybrid rule-gated text selection
- `TelemetryHub`: tracks per-device updates
- `ReplayRecorder`: rehearsal replay and freeze-frame windows

## CoreML Runtime Loading

- Compiled `.mlmodelc` bundles are discovered from:
  - `$CONDUCTOR_COREML_MODEL_PATH` (single explicit bundle path)
  - `$CONDUCTOR_COREML_MODEL_DIR` (directory search root)
  - `./Models` under the harness working directory
  - app bundle `Models` resources
- The harness UI exposes:
  - bundle selection (`Load Selected Bundle`)
  - auto-reload using the preferred model name
  - runtime health checks (bundle presence, deserialization, output feature, probe prediction)
- The text engine automatically falls back to heuristic scoring if health checks fail.

## Command Dispatch Mode

- Transport now emits direct conductor `command` envelopes for scene actions:
  - `start`, `hold`, `jump`, `abort`, `recover`
- Local cue IDs are still generated for rehearsal logging and deterministic local timing.

## HLS Cue Output

Harness cue payloads can include `showFixedMediaRef` for participant `/live` playback.
Configure stream URLs with environment variables:

- `CONDUCTOR_HLS_BASE_URL` (optional shortcut; derives defaults below)
- `CONDUCTOR_HLS_PRESHOW_URL`
- `CONDUCTOR_HLS_INTRODUCTION_URL`
- `CONDUCTOR_HLS_MAIN_URL`
- `CONDUCTOR_HLS_ENDING_URL`
- `CONDUCTOR_HLS_INTERSTITIAL_URL`
- `CONDUCTOR_HLS_LANE_BASE_URL` (lane IDs map to `<lane-base>/<lane-id>.m3u8`)

Example (R2 test-shots prefix):

```bash
export CONDUCTOR_HLS_PRESHOW_URL="https://media.letgofilm.com/test-shots-v1/preshow/preshow.m3u8"
export CONDUCTOR_HLS_INTRODUCTION_URL="https://media.letgofilm.com/test-shots-v1/introduction/introduction.m3u8"
export CONDUCTOR_HLS_INTERSTITIAL_URL="https://media.letgofilm.com/test-shots-v1/interstitial/interstitial.m3u8"
export CONDUCTOR_HLS_ENDING_URL="https://media.letgofilm.com/test-shots-v1/ending/ending.m3u8"
unset CONDUCTOR_HLS_MAIN_URL
unset CONDUCTOR_HLS_LANE_BASE_URL
```

If only `CONDUCTOR_HLS_BASE_URL` is set, defaults are:

- `<base>/preshow.m3u8`
- `<base>/introduction.m3u8`
- `<base>/main.m3u8`
- `<base>/ending.m3u8`
- `<base>/interstitial.m3u8`
- lane base `<base>/lanes/`

## Run

```bash
cd harness-swift
swift test
swift run ConductorHarnessApp
```
