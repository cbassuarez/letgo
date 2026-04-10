import type { ReplayEvent } from "@conductor/protocol";
import { Pool } from "pg";

export interface ReplayStore {
  append(event: ReplayEvent): Promise<void>;
  between(startMs: number, endMs: number): Promise<ReplayEvent[]>;
  latest(limit: number): Promise<ReplayEvent[]>;
}

export class MemoryReplayStore implements ReplayStore {
  private readonly events: ReplayEvent[] = [];

  async append(event: ReplayEvent): Promise<void> {
    this.events.push(event);
  }

  async between(startMs: number, endMs: number): Promise<ReplayEvent[]> {
    return this.events.filter((event) => event.timestamp >= startMs && event.timestamp <= endMs);
  }

  async latest(limit: number): Promise<ReplayEvent[]> {
    return this.events.slice(Math.max(0, this.events.length - limit));
  }
}

export class PostgresReplayStore implements ReplayStore {
  constructor(private readonly pool: Pool) {}

  async init(): Promise<void> {
    await this.pool.query(`
      CREATE TABLE IF NOT EXISTS replay_events (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        timestamp BIGINT NOT NULL,
        logical_time BIGINT NOT NULL,
        cue_id TEXT,
        source TEXT NOT NULL,
        payload JSONB NOT NULL
      )
    `);
  }

  async append(event: ReplayEvent): Promise<void> {
    await this.pool.query(
      `
      INSERT INTO replay_events(id, type, timestamp, logical_time, cue_id, source, payload)
      VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb)
      ON CONFLICT (id) DO NOTHING
      `,
      [
        event.id,
        event.type,
        event.timestamp,
        event.logicalTime,
        event.cueId ?? null,
        event.source,
        JSON.stringify(event.payload)
      ]
    );
  }

  async between(startMs: number, endMs: number): Promise<ReplayEvent[]> {
    const result = await this.pool.query(
      `
      SELECT id, type, timestamp, logical_time, cue_id, source, payload
      FROM replay_events
      WHERE timestamp >= $1 AND timestamp <= $2
      ORDER BY timestamp ASC
      `,
      [startMs, endMs]
    );
    return result.rows.map(toReplayEvent);
  }

  async latest(limit: number): Promise<ReplayEvent[]> {
    const result = await this.pool.query(
      `
      SELECT id, type, timestamp, logical_time, cue_id, source, payload
      FROM replay_events
      ORDER BY timestamp DESC
      LIMIT $1
      `,
      [limit]
    );
    return result.rows.map(toReplayEvent).reverse();
  }
}

const toReplayEvent = (row: {
  id: string;
  type: string;
  timestamp: number;
  logical_time: number;
  cue_id: string | null;
  source: "harness" | "backend" | "phone";
  payload: Record<string, unknown>;
}): ReplayEvent => ({
  id: row.id,
  type: row.type as ReplayEvent["type"],
  timestamp: Number(row.timestamp),
  logicalTime: Number(row.logical_time),
  cueId: row.cue_id ?? undefined,
  source: row.source,
  payload: row.payload
});
