import { describe, expect, it } from "vitest";
import { CrowdLightingField } from "../src/services/crowdLightingField";

const hueIntent = (degrees: number) => {
  const rad = (degrees * Math.PI) / 180;
  return {
    hueX: Math.cos(rad),
    hueY: Math.sin(rad),
    chroma: 0.25,
    luminance: 0.58,
    energy: 0.7,
    updatedAt: Date.now()
  };
};

describe("CrowdLightingField", () => {
  it("handles circular hue wraparound correctly", () => {
    const field = new CrowdLightingField();
    let state = field.snapshot();
    for (let i = 0; i < 8; i += 1) {
      field.update("p1", {
        intent: hueIntent(359),
        influence: 0.7,
        zone: { x: 0.4, y: 0.6 }
      });
      state = field.update("p2", {
        intent: hueIntent(1),
        influence: 0.7,
        zone: { x: 0.6, y: 0.6 }
      });
    }

    const hue = state.targetColor.oklch.h;
    const nearZero = hue <= 8 || hue >= 352;
    expect(nearZero).toBe(true);
  });

  it("drops confidence and raises entropy for split crowd", () => {
    const field = new CrowdLightingField();
    let split = field.snapshot();
    for (let i = 0; i < 8; i += 1) {
      field.update("p1", { intent: hueIntent(0), influence: 0.8, zone: { x: 0.2, y: 0.4 } });
      split = field.update("p2", { intent: hueIntent(180), influence: 0.8, zone: { x: 0.8, y: 0.4 } });
    }

    expect(split.entropy).toBeGreaterThan(0.2);
    expect(split.confidence).toBeLessThan(0.6);
  });

  it("returns zone-aware field cells with target colors", () => {
    const field = new CrowdLightingField();
    const state = field.update("p1", {
      intent: hueIntent(230),
      influence: 0.9,
      zone: { x: 0.2, y: 0.2 }
    });

    expect(state.zoneField.length).toBe(12);
    expect(state.zoneField[0]?.id).toBe("r0c0");
    expect(state.zoneField[0]?.targetColor.hex.startsWith("#")).toBe(true);
  });
});
