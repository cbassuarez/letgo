# Let Go: Text + Keyboard Audio Showtime Runbook

Last updated: 2026-04-18

This document is the operational guide for the two performance surfaces:

1. Text Runtime (strict/loose banks + trained director + optional semantic generation)
2. Keyboard Audio Out + Phone Choir Voice Streaming (MiniLab 3 -> Ableton -> Harness native RTP publisher -> backend SFU -> phones)

Use this as your rehearsal and show-day checklist.

---

## 1) System Architecture (Quick Mental Model)

### Text surface
- Harness runs local CoreML scoring for performer-side text direction.
- Backend runs audience text composition with:
  - strict/loose script banks
  - backend director model JSON
  - optional semantic generation (`off` or `openai`)
- Harness app can now push/reload text runtime state directly from UI (Inspector -> Text Runtime), so you are not stuck in headless-only setup.

### Keyboard + phone audio surface
- MiniLab 3 MIDI IN -> Harness (`MIDI INPUT`) for controls and note events.
- Harness MIDI OUT -> Ableton (`MIDI OUTPUT (ABLETON HOST LINK)`) for notes/CC/program/transport clock/start/stop.
- Ableton audio returns -> Harness input device (multi-channel preferred).
- Harness native publisher captures return channels by stereo bus pairs, encodes Opus RTP, and sends to ingest endpoints announced by backend (`voice_publisher_announce`).
- Backend mediasoup service assigns streams to phones (with fallback behavior handled in existing pipeline).

---

## 2) Prerequisites

## Hardware
- Mac running harness + backend (local or server for backend)
- Arturia MiniLab 3
- Audio interface or virtual loopback that supports multichannel return into macOS input
- Optional: external network AP/router dedicated for venue phones

## Software
- Xcode + Command Line Tools
- Node/npm (repo-standard version)
- Python venv for model trainer
- Ableton Live

## Network / runtime expectations
- Venue cohort should be local and low-latency.
- For 60 phones, prefer `webrtc` voice transport with SFU enabled.

---

## 3) One-Time File Layout

```bash
mkdir -p /Users/seb/letgo/show-assets/text
mkdir -p /Users/seb/letgo/harness-swift/Models
mkdir -p /Users/seb/letgo/harness-swift/docs
```

Suggested canonical files:
- `/Users/seb/letgo/show-assets/text/strict.txt`
- `/Users/seb/letgo/show-assets/text/loose.txt`
- `/Users/seb/letgo/harness-swift/Models/ConductorTextDirector.mlmodelc`
- `/Users/seb/letgo/harness-swift/Models/ConductorTextDirector.backend.json`

---

## 4) Text Surface: Train + Initialize + Perform

## 4.1 Script bank format

### `strict.txt`
Allowed line formats:
- `text only`
- `weight|text`
- `id|weight|text`

### `loose.txt`
Allowed line formats:
- `text only`
- `weight|text`
- `id|weight|text`

Notes:
- One candidate per line.
- `#` and `//` prefix lines are ignored.
- Keep strict bank constrained and cue-safe.
- Keep loose bank expressive, but still in your approved voice constraints.

## 4.2 Train models

### Deterministic/corpus-trained baseline
```bash
cd /Users/seb/letgo/harness-swift/train
source .venv/bin/activate
python train_conductor_model.py \
  --samples 20000 \
  --corpus-samples 16000 \
  --strict-bank /Users/seb/letgo/show-assets/text/strict.txt \
  --loose-bank /Users/seb/letgo/show-assets/text/loose.txt \
  --epochs 250 \
  --output-dir /Users/seb/letgo/harness-swift/Models
```

### Optional semantic augmentation during training
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

Trainer outputs expected:
- `ConductorTextDirector.mlmodelc`
- `ConductorTextDirector.backend.json`

## 4.3 Backend env for text runtime

Set these in backend shell (or `.env`):

```bash
export CONDUCTOR_TEXT_STRICT_BANK_PATH="/Users/seb/letgo/show-assets/text/strict.txt"
export CONDUCTOR_TEXT_LOOSE_BANK_PATH="/Users/seb/letgo/show-assets/text/loose.txt"
export CONDUCTOR_TEXT_BANK_REFRESH_MS=3000

export CONDUCTOR_TEXT_DIRECTOR_MODEL_PATH="/Users/seb/letgo/harness-swift/Models/ConductorTextDirector.backend.json"
export CONDUCTOR_TEXT_DIRECTOR_MODEL_REFRESH_MS=3000

# semantic runtime (optional)
export CONDUCTOR_TEXT_SEMANTIC_MODE=off
# or:
# export CONDUCTOR_TEXT_SEMANTIC_MODE=openai
# export CONDUCTOR_TEXT_SEMANTIC_OPENAI_API_KEY="..."
# export CONDUCTOR_TEXT_SEMANTIC_OPENAI_MODEL="gpt-4.1-mini"
# export CONDUCTOR_TEXT_SEMANTIC_REFRESH_MS=12000
# export CONDUCTOR_TEXT_SEMANTIC_TTL_MS=70000
# export CONDUCTOR_TEXT_SEMANTIC_TIMEOUT_MS=4500
```

## 4.4 Harness env for local model runtime

```bash
export CONDUCTOR_COREML_MODEL_PATH="/Users/seb/letgo/harness-swift/Models/ConductorTextDirector.mlmodelc"
```

## 4.5 Run stack

```bash
# shell 1
cd /Users/seb/letgo
npm run dev --workspace backend-realtime

# shell 2
cd /Users/seb/letgo/harness-swift
swift run ConductorHarnessApp

# shell 3 (if needed)
cd /Users/seb/letgo
npm run dev --workspace web-client
```

## 4.6 In-app text runtime control (non-headless path)

In Harness app:
1. Open Inspector (`Cmd+I`)
2. Go to `Text Runtime`
3. Use:
   - `Import Strict Script Bank`
   - `Import Loose Script Bank`
   - `Import Backend Model JSON`
4. Set semantic mode (`OFF`/`OPENAI`)
5. Set `OpenAI Model` and `OpenAI API Key` (key is saved in macOS Keychain from the app)
6. Click `Apply Semantic Config`
7. Use `Push` / `Reload` actions as needed
8. Confirm runtime status fields update:
   - strict/loose counts
   - source labels
   - model health
   - semantic status + warnings
   - backend key status (`configured`/`missing`)

## 4.7 Text performance checklist

Before audience enters:
- strict+loose banks loaded
- backend model loaded
- semantic mode explicitly chosen (don’t leave ambiguous)
- status has no warnings for missing files/model

During show:
- use strict/loose blend controls (HOTAS/MIDI) for density/tone shifts
- if text quality drifts, reload runtime from Inspector
- if semantic mode causes latency/noise, switch to `OFF` immediately

---

## 5) Keyboard + Phone Choir/Pad Voice Surface: Initialize + Perform

## 5.1 Backend env for voice streaming (SFU)

For local/venue test with WebRTC voice transport:

```bash
export CONDUCTOR_VOICE_STREAM_TRANSPORT=webrtc
export CONDUCTOR_SFU_ENABLED=true
export CONDUCTOR_SFU_ROOM_ID="letgo-room"
export CONDUCTOR_SFU_LISTEN_IP="0.0.0.0"

# Set announced IP to routable host for audience phones.
export CONDUCTOR_SFU_ANNOUNCED_IP="<LAN_OR_PUBLIC_IP>"

# Optional explicit RTC UDP range
export CONDUCTOR_SFU_RTC_MIN_PORT=40000
export CONDUCTOR_SFU_RTC_MAX_PORT=49999

# Audience scale / stream limits
export CONDUCTOR_SFU_MAX_SUBSCRIBERS=60
export CONDUCTOR_VOICE_STREAM_MAX_CONCURRENT=16

# session/token
export CONDUCTOR_MANAGED_SFU_SESSION_PREFIX="letgo"
export CONDUCTOR_MANAGED_SFU_TOKEN_SECRET="change-me-for-show"

# optional ICE servers JSON if needed off-LAN:
# export CONDUCTOR_SFU_ICE_SERVERS_JSON='[{"urls":["stun:stun.l.google.com:19302"]}]'
```

Notes:
- `MAX_CONCURRENT=16` means max concurrent per-voice streams; overflow should follow your fallback strategy.
- Keep SFU + backend on low-latency network path to audience devices.

## 5.2 Harness env for return-capture publisher

```bash
# Enable real Ableton return capture as source for voice RTP publisher
export CONDUCTOR_VOICE_RETURN_CAPTURE_ENABLED=true

# Number of stereo buses to expose (bus0=ch1/2, bus1=ch3/4, ...)
export CONDUCTOR_VOICE_RETURN_CAPTURE_BUS_COUNT=8

# Capture quality/latency knobs
export CONDUCTOR_VOICE_RETURN_CAPTURE_SAMPLE_RATE=48000
export CONDUCTOR_VOICE_RETURN_CAPTURE_BUFFER_SECONDS=6

# Fallback if capture frames unavailable: silence|synth
export CONDUCTOR_VOICE_RETURN_CAPTURE_FALLBACK=silence

# Optional deterministic note->bus mapping
# Format: note:bus,note:bus
export CONDUCTOR_VOICE_RETURN_CAPTURE_NOTE_BUS_MAP="60:0,62:1,64:2,65:3"
```

## 5.3 Ableton session setup (recommended)

Goal: publish real host audio per voice bus, not synthesized fallback.

1. Audio device
- Use interface/loopback that can deliver multichannel input to harness.
- In Ableton, select that interface for output.
- In macOS, ensure harness input device sees those channels.

2. Bus layout
- Build 8 stereo buses (or as many as you need):
  - bus0 -> outputs 1/2
  - bus1 -> outputs 3/4
  - bus2 -> outputs 5/6
  - ...
- Route target instruments/chains into these bus pairs.

3. MIDI host link
- Enable external MIDI destination that Harness can arm (IAC bus or interface MIDI port).
- In Ableton, enable Track/Remote/Sync as needed on that input.
- Harness uses:
  - channel 1 for note events
  - channel 15 for host-link control/patch/transport

4. Clock/transport
- Harness is transport authority when engine is running + MIDI out armed.
- Verify Ableton receives clock/start/stop from harness.

## 5.4 Harness app setup path

In app Setup panel:
1. `MIDI INPUT`
   - Select MiniLab 3 source
   - Click `ARM MIDI`
2. `MIDI OUTPUT (ABLETON HOST LINK)`
   - Select Ableton/IAC destination
   - Click `ARM OUT`
3. Confirm status lines:
   - MIDI input active
   - MIDI output active
4. Start engine.
5. Confirm `keyboard_state` reaches backend (host link online).

## 5.5 Phone choir + pad voice test flow

1. Ensure at least one phone is connected on `/live` and permissioned.
2. Commit phone audio gate in harness flow.
3. Trigger choir note-on from harness/MIDI.
4. Confirm status line includes voice publisher announce with return bus:
   - `VOICE PUBLISHER note-XX return-bus-Y RTP ...`
5. Trigger note-off.
6. Verify stream tears down cleanly.

If no capture audio available and fallback is `silence`, phones receive silence (expected).
If fallback is `synth`, phones receive synthetic tone instead.

## 5.6 Performance operation model

During show:
- Keep MiniLab focused on musical gestures + macro intent.
- Let harness send transport + patch metadata to Ableton.
- Use choir note/pad triggers to open/close voice streams.
- Keep max concurrent voices within cap (`16`) to avoid overload.

Operational guardrails:
- If stream health degrades, reduce active voices before changing infrastructure.
- Use deterministic note->bus map for critical moments.
- Keep one quick fallback patch in Ableton for emergency continuity.

---

## 6) Rehearsal Script (15-minute smoke test)

1. Start backend with SFU env.
2. Start harness with return-capture env.
3. Open one phone to `/live`.
4. Arm MIDI IN + MIDI OUT in harness.
5. Start engine.
6. Send 4-note phrase from MiniLab; verify:
   - backend receives `voice_publisher_announce`
   - harness logs return-bus RTP publish
   - phone audio responds
7. Toggle to another patch/bank in harness and verify Ableton patch updates.
8. Open Inspector -> Text Runtime:
   - import strict/loose/model
   - push runtime
   - verify status counts/health
9. Perform a cue transition and ensure text continues coherent and voice path stays healthy.

Pass criteria:
- No stuck voice streams after note-off
- No synth fallback unless intentionally configured
- Text runtime status healthy and deterministic

---

## 7) Troubleshooting

## Symptom: Harness builds in SwiftPM but Xcode shows missing `VoiceRTPPublisher` types
Cause:
- `VoiceRTPPublisher.swift` not included in Xcode target sources.
Fix:
- Ensure file is present in `ConductorCore` group and `ConductorCore` sources build phase.

## Symptom: `VOICE PUBLISHER ... NOGO`
Check:
- backend SFU enabled and started
- `CONDUCTOR_SFU_ANNOUNCED_IP` reachable by devices
- UDP port range open

## Symptom: Phones get synth/fallback instead of Ableton return
Check:
- `CONDUCTOR_VOICE_RETURN_CAPTURE_ENABLED=true`
- capture bus count matches available channels
- Ableton output actually reaches harness input channels
- fallback mode currently not masking capture loss

## Symptom: Text runtime not updating in performance
Check:
- Inspector -> Text Runtime status timestamp changes
- backend paths exist and are readable
- model JSON valid
- semantic mode/API key configuration valid when in `OPENAI`

## Symptom: High latency / inconsistent audience audio
Check:
- LAN quality and AP load
- keep venue cohort local
- reduce concurrent voice streams
- confirm no remote devices are assumed in timing critical path

---

## 8) Show-Day Quick Start (Copy/Paste)

```bash
# backend
cd /Users/seb/letgo
export CONDUCTOR_VOICE_STREAM_TRANSPORT=webrtc
export CONDUCTOR_SFU_ENABLED=true
export CONDUCTOR_SFU_ROOM_ID="letgo-room"
export CONDUCTOR_SFU_LISTEN_IP="0.0.0.0"
export CONDUCTOR_SFU_ANNOUNCED_IP="<LAN_OR_PUBLIC_IP>"
export CONDUCTOR_SFU_MAX_SUBSCRIBERS=60
export CONDUCTOR_VOICE_STREAM_MAX_CONCURRENT=16
export CONDUCTOR_MANAGED_SFU_SESSION_PREFIX="letgo"
export CONDUCTOR_MANAGED_SFU_TOKEN_SECRET="change-me-for-show"
export CONDUCTOR_TEXT_STRICT_BANK_PATH="/Users/seb/letgo/show-assets/text/strict.txt"
export CONDUCTOR_TEXT_LOOSE_BANK_PATH="/Users/seb/letgo/show-assets/text/loose.txt"
export CONDUCTOR_TEXT_DIRECTOR_MODEL_PATH="/Users/seb/letgo/harness-swift/Models/ConductorTextDirector.backend.json"
export CONDUCTOR_TEXT_SEMANTIC_MODE=off
npm run dev --workspace backend-realtime
```

```bash
# harness
cd /Users/seb/letgo/harness-swift
export CONDUCTOR_COREML_MODEL_PATH="/Users/seb/letgo/harness-swift/Models/ConductorTextDirector.mlmodelc"
export CONDUCTOR_VOICE_RETURN_CAPTURE_ENABLED=true
export CONDUCTOR_VOICE_RETURN_CAPTURE_BUS_COUNT=8
export CONDUCTOR_VOICE_RETURN_CAPTURE_SAMPLE_RATE=48000
export CONDUCTOR_VOICE_RETURN_CAPTURE_BUFFER_SECONDS=6
export CONDUCTOR_VOICE_RETURN_CAPTURE_FALLBACK=silence
swift run ConductorHarnessApp
```

Then in app:
- ARM MIDI input
- ARM MIDI output
- Start engine
- Confirm phone pool and voice publisher lines
- Open Inspector -> Text Runtime and confirm healthy status

---

## 9) Recommended Next Hardening (post-v1)

- Add in-app Voice Return diagnostics panel:
  - capture running/error
  - available bus count
  - active note->bus map
  - per-track publish/packet counters
- Add one-button “Show Boot” preset loader (text + MIDI + capture + pool checks).
- Persist selected MIDI IN/OUT device IDs and text runtime asset paths per venue profile.
