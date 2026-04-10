import { describe, expect, it } from "vitest";
import { ReplayService } from "../src/services/replayService";
import { MemoryReplayStore } from "../src/stores/replayStore";

describe("ReplayService", () => {
  it("returns freeze-frame window", async () => {
    const store = new MemoryReplayStore();
    const replay = new ReplayService(store);

    await replay.record({
      type: "cue",
      timestamp: 1000,
      logicalTime: 0,
      source: "harness",
      payload: { cue: "preshow" }
    });
    await replay.record({
      type: "cue",
      timestamp: 2000,
      logicalTime: 1000,
      source: "harness",
      payload: { cue: "introduction" }
    });

    const frame = await replay.freezeFrame(2000, 200, 200);
    expect(frame).toHaveLength(1);
    expect(frame[0]?.payload.cue).toBe("introduction");
  });
});
