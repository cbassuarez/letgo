import { beforeEach, describe, expect, it } from "vitest";
import { readFallbackSnapshot, saveFallbackSnapshot } from "../src/lib/fallbackStore";

describe("fallbackStore", () => {
  beforeEach(() => {
    localStorage.clear();
  });

  it("persists snapshot by hashed id", () => {
    saveFallbackSnapshot("abc", {
      cue: {
        cueId: "preshow:0",
        showState: "preshow",
        logicalTime: 0,
        payload: {},
        version: 1,
        action: "start"
      },
      vector: {
        textAmount: 0.2,
        compositeBias: 0.5,
        audioGain: 0.5,
        spatialX: 0.1,
        spatialY: 0.2,
        spatialZ: 0.3
      }
    });

    const snapshot = readFallbackSnapshot("abc");
    expect(snapshot?.cue?.cueId).toBe("preshow:0");
  });
});
