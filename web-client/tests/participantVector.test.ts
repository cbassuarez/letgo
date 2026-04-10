import { describe, expect, it } from "vitest";
import {
  computeAdaptiveIntervalMs,
  mapSignalsToVector,
  type ParticipantSignalState
} from "../src/hooks/useParticipantVector";

const signals: ParticipantSignalState = {
  motion: 0.8,
  tiltBeta: 40,
  tiltGamma: -20,
  touchX: 0.7,
  touchY: 0.4,
  touchPressure: 0.5,
  touching: true,
  lastInteractionAt: Date.now()
};

describe("participant vector mapping", () => {
  it("maps physical signals into normalized vectors", () => {
    const vector = mapSignalsToVector(signals);
    expect(vector.textAmount).toBeGreaterThanOrEqual(0);
    expect(vector.textAmount).toBeLessThanOrEqual(1);
    expect(vector.spatialX).toBeGreaterThan(0);
    expect(vector.spatialY).toBeGreaterThan(0);
    expect(vector.audioGain).toBeGreaterThan(0.2);
  });

  it("adapts send interval by influence", () => {
    expect(computeAdaptiveIntervalMs(0.9)).toBe(90);
    expect(computeAdaptiveIntervalMs(0.6)).toBe(140);
    expect(computeAdaptiveIntervalMs(0.2)).toBe(240);
  });
});
