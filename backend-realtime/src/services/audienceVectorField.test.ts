import { describe, expect, it } from "vitest";
import { AudienceVectorField } from "./audienceVectorField";

describe("AudienceVectorField", () => {
  it("caps single participant dominance with neutral anchoring", () => {
    const field = new AudienceVectorField();
    const snapshot = field.update("solo", {
      vector: {
        textAmount: 1,
        compositeBias: 1,
        audioGain: 1,
        spatialX: 1,
        spatialY: 1,
        spatialZ: 1
      },
      influence: 1,
      compositorMode: "fallback"
    });

    expect(snapshot.participantCount).toBe(1);
    expect(snapshot.vector.textAmount).toBeGreaterThan(0.5);
    expect(snapshot.vector.textAmount).toBeLessThanOrEqual(0.82);
    expect(snapshot.vector.compositeBias).toBeLessThanOrEqual(0.82);
  });

  it("smooths abrupt direction changes across snapshots", () => {
    const field = new AudienceVectorField();
    field.update("a", {
      vector: { textAmount: 1, compositeBias: 1, audioGain: 1, spatialX: 1, spatialY: 1, spatialZ: 1 },
      influence: 1,
      compositorMode: "fallback"
    });
    const before = field.snapshot().vector.textAmount;
    field.update("a", {
      vector: { textAmount: 0, compositeBias: 0, audioGain: 0, spatialX: 0, spatialY: 0, spatialZ: 0 },
      influence: 1,
      compositorMode: "fallback"
    });
    const after = field.snapshot().vector.textAmount;

    expect(before).toBeGreaterThan(after);
    expect(after).toBeGreaterThanOrEqual(0.18);
  });
});
