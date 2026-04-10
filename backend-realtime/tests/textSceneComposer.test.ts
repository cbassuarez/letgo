import { describe, expect, it } from "vitest";
import { TextSceneComposerService } from "../src/services/textSceneComposer";

describe("TextSceneComposerService", () => {
  it("builds scenes with constrained rewrite variants", () => {
    const service = new TextSceneComposerService();
    const scene = service.compose({
      cueId: "main:1200",
      vector: {
        textAmount: 0.9,
        compositeBias: 0.8,
        audioGain: 0.7,
        spatialX: 0.5,
        spatialY: 0.5,
        spatialZ: 0.5
      },
      pickEpoch: 2,
      pickResult: {
        windowId: "pick-1",
        winnerOptionId: "chorus",
        winnerLabel: "Chorus",
        totalVotes: 12,
        quorumTarget: 8,
        margin: 0.5,
        applied: true,
        updatedAt: Date.now()
      }
    });

    expect(scene.sceneVersion).toBeGreaterThan(0);
    expect(scene.lineCount).toBeGreaterThanOrEqual(1);
    expect(scene.lineCount).toBeLessThanOrEqual(3);
    expect(scene.lines.length).toBe(scene.lineCount);
    for (const line of scene.lines) {
      expect(line.variants.length).toBeGreaterThan(0);
      expect(line.variants.length).toBeLessThanOrEqual(4);
    }
  });
});
