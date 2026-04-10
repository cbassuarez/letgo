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

## Development

```bash
npm run dev --workspace backend-realtime
```
