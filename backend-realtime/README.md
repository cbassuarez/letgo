# backend-realtime

Realtime conductor backend for cue fan-out, sync packets, session identity, and replay persistence.

## Endpoints

- `GET /health`
- `POST /identity/resolve`
- `GET /identity/:hashedId`
- `WS /ws/harness`
- `WS /ws/device/:hashedId`

## Environment

- `PORT`
- `HOST`
- `SESSION_SALT`
- `REDIS_URL` (optional)
- `POSTGRES_URL` (optional)
- `MAX_CLIENT_DRIFT_MS` (default `100`)
- `CONDUCTOR_TEXT_BANK_PATH` (optional combined strict/loose JSON source)
- `CONDUCTOR_TEXT_STRICT_BANK_PATH` (optional strict-only JSON/txt source)
- `CONDUCTOR_TEXT_LOOSE_BANK_PATH` (optional loose-only JSON/txt source)
- `CONDUCTOR_TEXT_BANK_REFRESH_MS` (default `3000`; hot-reload interval)
- `CONDUCTOR_TEXT_DIRECTOR_MODEL_PATH` (optional backend text model JSON path)
- `CONDUCTOR_TEXT_DIRECTOR_MODEL_REFRESH_MS` (default `3000`; hot-reload interval)
- `CONDUCTOR_TEXT_SEMANTIC_MODE` (`off` or `openai`)
- `CONDUCTOR_TEXT_SEMANTIC_OPENAI_API_KEY` (optional; can fall back to `OPENAI_API_KEY`)
- `CONDUCTOR_TEXT_SEMANTIC_OPENAI_MODEL` (default `gpt-4.1-mini`)
- `CONDUCTOR_TEXT_SEMANTIC_REFRESH_MS` (default `12000`)
- `CONDUCTOR_TEXT_SEMANTIC_TTL_MS` (default `70000`)
- `CONDUCTOR_TEXT_SEMANTIC_TIMEOUT_MS` (default `4500`)

### Text Bank File Formats

- Combined JSON:
  - `{ "strict": [...], "loose": [...] }`
  - `strict` and `loose` entries can be strings or objects:
    - `"a text line"`
    - `{ "id": "line-1", "text": "a text line", "weight": 0.8 }`
- Single-bank JSON:
  - `["line A", "line B"]`
  - `{ "candidates": [...] }`
- Single-bank text:
  - one line per text phrase
  - optional delimiter format: `id|weight|text` or `weight|text`

### Backend Text Model Format

- Optional JSON model file for audience text scoring (hot-reloaded):
  - `kind: "text-director-linear-v1"`
  - `featureOrder`: 14 named features
  - `outputs`: `score`, `displayDuration`, `compositeAlpha`, `fontSize`, `fontWeight`

### Runtime Control Envelope (Harness ↔ Backend)

- Harness can update backend text runtime without restart using:
  - `kind: "text_runtime_update"`
  - payload supports:
    - `requestStatus`
    - `reload`
    - `strictCandidates`
    - `looseCandidates`
    - `modelPayloadJSON`
    - `semanticMode`
- Backend reports runtime health via:
  - `kind: "text_runtime_status"`
  - includes strict/loose counts + source labels, warnings, model health, and semantic runtime telemetry.

## Development

```bash
npm run dev --workspace backend-realtime
```
