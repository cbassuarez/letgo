# Architecture Notes

## Control Plane

1. Swift harness emits `CueCommand` to backend via WebSocket.
2. Backend stamps and fan-outs cue stream to all connected devices.
3. Phone clients estimate drift from `SyncPacket` ping/pong and bias playback clock.
4. Dynamic parameters are merged from three sources:
   - deterministic scene payload
   - harness live vectors
   - per-device variant seed and permissions

## Replay Model

- Every cue, selection decision, and device uplink is persisted as `ReplayEvent`.
- Replay mode can inject events back into the bus while disabling live writes.
- Freeze-frame helper captures a window around a cue timestamp.

## Data Policy

- Device identity is hashed and stable per production NFC tag.
- Retain only pseudonymous operational data required for rehearsal replay.
- Purge/export policy should be configured by environment retention settings.
