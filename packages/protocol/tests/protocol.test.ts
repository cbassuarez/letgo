import { describe, expect, it } from "vitest";
import { deterministicPick, normalizeVector, stableHashToSeed } from "../src/index";

describe("protocol helpers", () => {
  it("normalizes missing vector fields", () => {
    const result = normalizeVector({ textAmount: 2, spatialY: -1 });
    expect(result.textAmount).toBe(1);
    expect(result.spatialY).toBe(0);
    expect(result.compositeBias).toBe(0.5);
  });

  it("returns deterministic hash seed", () => {
    const first = stableHashToSeed("nfc://tag-a");
    const second = stableHashToSeed("nfc://tag-a");
    expect(first).toBe(second);
  });

  it("picks deterministic value for seed", () => {
    const picked = deterministicPick(7, ["a", "b", "c"]);
    expect(picked).toBe("b");
  });
});
