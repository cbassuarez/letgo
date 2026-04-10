# Conductor Film Platform

A monorepo for a conducted, confessional cinema system split across one projector surface and a field of NFC-identified phone participants.

## Runtime Topology

- `harness-swift`: macOS Swift harness app (operator console, timeline authority, cue transport, MIDI, audio routing, text selection).
- `backend-realtime`: Render-hosted Fastify/WebSocket service (session identity, sync bus, replay event store, heartbeats).
- `web-client`: Vite/React/Tailwind phone client (hashed route identity, permission bootstrap, synced media, dynamic overlays).
- `packages/protocol`: shared TypeScript protocol types and deterministic helper utilities.

## Show Spine

Deterministic fixed backbone with dynamic overlay layer:

`preshow -> introduction -> main(showFixed + showDynamic in parallel) -> ending`

## Design Goals

- Swift harness is the timeline source of truth.
- Device sync target ~100 ms with drift correction.
- Stable hashed NFC identity per phone with per-device permissions and variant parameters.
- Graceful reconnect + local fallback behavior.
- Replay-first rehearsal tooling.

## Monorepo Commands

```bash
npm run dev:backend
npm run dev:web
npm run typecheck
npm run test
```

## Notes

- This is an implementation scaffold intended for iterative rehearsal-focused development.
- Infrastructure defaults to managed internet deployment (Render + Redis + Postgres).
