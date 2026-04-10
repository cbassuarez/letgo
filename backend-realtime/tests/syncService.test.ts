import { describe, expect, it } from "vitest";
import { SyncService } from "../src/services/syncService";

describe("SyncService", () => {
  it("flags drift over threshold", () => {
    const service = new SyncService(100);
    const result = service.evaluatePong(
      {
        kind: "pong",
        serverTime: 1000,
        clientTime: 1250,
        rtt: 0,
        driftEstimate: 0
      },
      1200
    );

    expect(result.shouldResync).toBe(true);
    expect(result.driftEstimate).toBeGreaterThan(100);
  });
});
