import { describe, expect, it } from "vitest";
import { AudienceVectorField } from "../src/services/audienceVectorField";

describe("AudienceVectorField", () => {
  it("aggregates participant vectors and tracks compositor modes", () => {
    const field = new AudienceVectorField();

    field.update("a1", {
      vector: { textAmount: 1, spatialX: 0.2 },
      influence: 0.7,
      compositorMode: "html-in-canvas"
    });
    const aggregate = field.update("a2", {
      vector: { textAmount: 0.5, spatialX: 0.8 },
      influence: 0.5,
      compositorMode: "fallback"
    });

    expect(aggregate.participantCount).toBe(2);
    expect(aggregate.vector.textAmount).toBeCloseTo(0.75, 4);
    expect(aggregate.vector.spatialX).toBeCloseTo(0.5, 4);
    expect(aggregate.compositorModes["html-in-canvas"]).toBe(1);
    expect(aggregate.compositorModes.fallback).toBe(1);
  });

  it("returns neutral vector when field empties", () => {
    const field = new AudienceVectorField();
    field.update("a1", {
      vector: { textAmount: 1 },
      influence: 1,
      compositorMode: "html-in-canvas"
    });
    const aggregate = field.remove("a1");
    expect(aggregate.participantCount).toBe(0);
    expect(aggregate.vector.compositeBias).toBe(0.5);
  });
});
