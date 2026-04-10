import { describe, expect, it } from "vitest";
import { deriveColorIntentTargets } from "../src/hooks/useColorBiasField";

describe("deriveColorIntentTargets", () => {
  it("returns normalized hue vector and bounded values", () => {
    const result = deriveColorIntentTargets({
      pointer: { x: 0.12, y: 0.88 },
      tilt: { beta: 18, gamma: -22, motion: 0.7 },
      active: true,
      idleMs: 0
    });

    const hueNorm = Math.hypot(result.hueX, result.hueY);
    expect(hueNorm).toBeCloseTo(1, 3);
    expect(result.chroma).toBeGreaterThanOrEqual(0);
    expect(result.chroma).toBeLessThanOrEqual(1);
    expect(result.luminance).toBeGreaterThanOrEqual(0);
    expect(result.luminance).toBeLessThanOrEqual(1);
    expect(result.energy).toBeGreaterThanOrEqual(0);
    expect(result.energy).toBeLessThanOrEqual(1);
  });

  it("decays back toward neutral after sustained idle", () => {
    const active = deriveColorIntentTargets({
      pointer: { x: 0.9, y: 0.1 },
      tilt: { beta: 0, gamma: 0, motion: 0.2 },
      active: true,
      idleMs: 100
    });
    const idle = deriveColorIntentTargets({
      pointer: { x: 0.9, y: 0.1 },
      tilt: { beta: 0, gamma: 0, motion: 0.2 },
      active: false,
      idleMs: 6000
    });

    expect(idle.hueX).toBeGreaterThan(active.hueX);
    expect(Math.abs(idle.hueY)).toBeLessThan(Math.abs(active.hueY));
    expect(idle.chroma).toBeLessThan(active.chroma);
    expect(idle.energy).toBeLessThan(active.energy);
  });
});
