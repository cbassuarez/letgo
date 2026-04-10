import { describe, expect, it } from "vitest";
import { deriveDeviceVariance } from "../src/hooks/useDeviceTextVariance";

const scene = {
  sceneVersion: 3,
  pickEpoch: 2,
  cueId: "main:1200",
  anchor: "center-center" as const,
  lineCount: 2,
  cutMode: "hold" as const,
  alpha: 0.8,
  fontScale: 1,
  weight: 0.6,
  durationMs: 4200,
  lines: [
    {
      id: "line-1",
      baseText: "The crowd keeps breathing in phase.",
      variants: ["The audience keeps breathing in phase.", "The crowd keeps breathing as one."]
    },
    {
      id: "line-2",
      baseText: "Signals become language in motion.",
      variants: ["Pulses become language in motion.", "Signals become phrase in motion."]
    }
  ],
  guardrails: {
    maxOffsetX: 0.08,
    maxOffsetY: 0.06,
    minContrast: 4.5,
    minDurationMs: 2400
  }
};

describe("deriveDeviceVariance", () => {
  it("is deterministic per device + scene", () => {
    const first = deriveDeviceVariance(scene, "abc123");
    const second = deriveDeviceVariance(scene, "abc123");
    expect(first).toEqual(second);
  });

  it("changes variance between devices while preserving guardrails", () => {
    const left = deriveDeviceVariance(scene, "device-left");
    const right = deriveDeviceVariance(scene, "device-right");

    expect(left.spec.seed).not.toBe(right.spec.seed);
    expect(Math.abs(left.spec.offsetX)).toBeLessThanOrEqual(scene.guardrails.maxOffsetX);
    expect(Math.abs(left.spec.offsetY)).toBeLessThanOrEqual(scene.guardrails.maxOffsetY);
    expect(left.lines.length).toBe(scene.lineCount);
  });
});
