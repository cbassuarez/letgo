import { describe, expect, it } from "vitest";
import { SyncClock } from "../src/lib/syncClock";

describe("SyncClock", () => {
  it("averages drift samples", () => {
    const clock = new SyncClock();

    clock.observe({
      serverTime: 1000,
      clientTime: 1060,
      receivedAt: 1100
    });
    const drift = clock.observe({
      serverTime: 2000,
      clientTime: 2070,
      receivedAt: 2100
    });

    expect(drift).toBeGreaterThan(0);
    expect(clock.getDrift()).toBe(drift);
  });
});
