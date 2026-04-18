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
- Training pipeline (`harness-swift/train/train_conductor_model.py`) now exports:
  - `ConductorTextDirector.mlmodelc` for harness runtime
  - `ConductorTextDirector.backend.json` for backend audience text scoring

## Text Runtime Control (App UI, No Headless Required)

- Open `Inspector` (`⌘I`) and go to `Text Runtime`.
- From this tab you can:
  - import strict script bank (`txt` or `json`)
  - import loose script bank (`txt` or `json`)
  - import backend text model (`.json`)
  - switch semantic mode (`OFF` or `OPENAI`)
  - push/reload backend runtime and inspect status/warnings
- Runtime status shows backend source counts, model health, semantic cache/last-error telemetry, and update timestamp.

This makes showtime script/model wiring visible and controllable from the harness app instead of relying on shell exports alone.

## Corpus + Semantic Training

`harness-swift/train/train_conductor_model.py` supports corpus-aware training and optional OpenAI semantic augmentation:

```bash
cd harness-swift/train
source .venv/bin/activate
python train_conductor_model.py \
  --samples 12000 \
  --corpus-samples 16000 \
  --strict-bank /Users/seb/letgo/show-assets/text/strict.txt \
  --loose-bank /Users/seb/letgo/show-assets/text/loose.txt \
  --epochs 250 \
  --output-dir /Users/seb/letgo/harness-swift/Models
```

Optional semantic teacher augmentation:

```bash
python train_conductor_model.py \
  --samples 12000 \
  --corpus-samples 18000 \
  --strict-bank /Users/seb/letgo/show-assets/text/strict.txt \
  --loose-bank /Users/seb/letgo/show-assets/text/loose.txt \
  --semantic-teacher openai \
  --semantic-augment-lines 250 \
  --semantic-model gpt-4.1-mini \
  --semantic-api-key "$OPENAI_API_KEY" \
  --epochs 250 \
  --output-dir /Users/seb/letgo/harness-swift/Models
```

Then point runtime env vars:

```bash
export CONDUCTOR_COREML_MODEL_PATH="/Users/seb/letgo/harness-swift/Models/ConductorTextDirector.mlmodelc"
export CONDUCTOR_TEXT_DIRECTOR_MODEL_PATH="/Users/seb/letgo/harness-swift/Models/ConductorTextDirector.backend.json"
```

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
- `CONDUCTOR_HLS_MAIN_STATIC_URL` (optional; falls back to `CONDUCTOR_HLS_MAIN_URL`)
- `CONDUCTOR_HLS_MAIN_DYNAMIC_URL` (optional; falls back to `CONDUCTOR_HLS_MAIN_URL`)
- `CONDUCTOR_HLS_MAIN_URL` (legacy alias used as fallback for both static + dynamic)
- `CONDUCTOR_HLS_ENDING_URL`
- `CONDUCTOR_HLS_INTERSTITIAL_URL`
- `CONDUCTOR_HLS_LANE_BASE_URL` (lane IDs map to `<lane-base>/<lane-id>.m3u8`)
- `CONDUCTOR_LOCAL_MEDIA_PREVIEW=true` (optional dev mode; use local imported files for preview instead of CDN HLS)

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

- `<base>/preshow/preshow.m3u8`
- `<base>/introduction/introduction.m3u8`
- `<base>/main/main.m3u8` (both static + dynamic fallback)
- `<base>/ending/ending.m3u8`
- `<base>/interstitial/interstitial.m3u8`
- lane base `<base>/lanes/`

## Voice Publisher Return Capture (Ableton Host Return -> SFU Tracks)

`VoiceRTPPublisher` now supports real return-channel capture as the primary source for `voice_publisher_announce` tracks.

Environment controls:

- `CONDUCTOR_VOICE_RETURN_CAPTURE_ENABLED=true|false` (default `true`)
- `CONDUCTOR_VOICE_RETURN_CAPTURE_BUS_COUNT` (default `8`, max `32`; each bus = stereo pair)
- `CONDUCTOR_VOICE_RETURN_CAPTURE_SAMPLE_RATE` (default `48000`)
- `CONDUCTOR_VOICE_RETURN_CAPTURE_BUFFER_SECONDS` (default `6`)
- `CONDUCTOR_VOICE_RETURN_CAPTURE_FALLBACK=silence|synth` (default `silence`)
- `CONDUCTOR_VOICE_RETURN_CAPTURE_NOTE_BUS_MAP` (optional note override map, e.g. `60:0,62:1,64:2`)

Behavior:

- On `voice_publisher_announce(active=true)`, each track binds to a return bus (`note` override first, then round-robin).
- On deactivate/note-off/reset/engine-stop, track publish is torn down and bus assignment is released.
- If capture is enabled but no audio frames are available, fallback mode applies (`silence` or synthesized tone).

## Run

```bash
cd harness-swift
swift test
swift run ConductorHarnessApp
```
