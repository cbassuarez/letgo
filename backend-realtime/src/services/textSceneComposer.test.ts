import { describe, expect, it } from "vitest";
import { TextSceneComposerService } from "./textSceneComposer";

describe("TextSceneComposerService", () => {
  it("returns no visible lines when text probability is near zero", () => {
    const composer = new TextSceneComposerService();
    const scene = composer.compose({
      cueId: "main:1000",
      vector: { textAmount: 0.8, compositeBias: 0.5 },
      textBlend: {
        probability: 0.02,
        strictRatio: 0.5
      }
    });

    expect(scene.lineCount).toBe(0);
    expect(scene.lines.length).toBe(0);
    expect(scene.alpha).toBeLessThan(0.05);
  });

  it("uses mixed strict and loose pipelines when enough lines are available", () => {
    const composer = new TextSceneComposerService();
    const scene = composer.compose({
      cueId: "main:2000",
      vector: {
        textAmount: 0.95,
        compositeBias: 0.65,
        audioGain: 0.5,
        spatialX: 0.5,
        spatialY: 0.5,
        spatialZ: 0.5
      },
      audioFeatures: {
        rms: 0.8,
        spectralCentroid: 0.4,
        flux: 0.7,
        transientDensity: 0.75,
        updatedAt: Date.now()
      },
      textBlend: {
        probability: 0.95,
        strictRatio: 0.5
      },
      pickResult: {
        windowId: "w1",
        winnerOptionId: "focus",
        winnerLabel: "Focus Chorus",
        totalVotes: 120,
        quorumTarget: 70,
        margin: 0.22,
        applied: true,
        updatedAt: Date.now()
      }
    });

    const ids = scene.lines.map((line) => line.id);
    expect(ids.some((id) => id.startsWith("line-"))).toBe(true);
    expect(ids.some((id) => id.startsWith("loose-"))).toBe(true);
  });
});
