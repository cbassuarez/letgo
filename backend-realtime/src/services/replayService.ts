import type { ReplayEvent } from "@conductor/protocol";
import { ulid } from "ulid";
import type { ReplayStore } from "../stores/replayStore";

export class ReplayService {
  constructor(private readonly store: ReplayStore) {}

  async record(event: Omit<ReplayEvent, "id">): Promise<ReplayEvent> {
    const persisted: ReplayEvent = {
      ...event,
      id: ulid()
    };
    await this.store.append(persisted);
    return persisted;
  }

  async latest(limit = 300): Promise<ReplayEvent[]> {
    return this.store.latest(limit);
  }

  async freezeFrame(centerTimestamp: number, beforeMs = 5000, afterMs = 5000): Promise<ReplayEvent[]> {
    return this.store.between(centerTimestamp - beforeMs, centerTimestamp + afterMs);
  }
}
