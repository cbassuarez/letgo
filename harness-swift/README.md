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

## Run

```bash
cd harness-swift
swift test
swift run ConductorHarnessApp
```
