import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import {
  TEXT_DIRECTOR_FEATURE_ORDER,
  TextDirectorModelRuntime
} from "./textDirectorModel";

const tempDirs: string[] = [];

const buildModelPayload = (): Record<string, unknown> => ({
  kind: "text-director-linear-v1",
  version: "test",
  featureOrder: [...TEXT_DIRECTOR_FEATURE_ORDER],
  outputs: {
    score: {
      intercept: 0.1,
      coefficients: [0.9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      min: 0,
      max: 1
    },
    displayDuration: {
      intercept: 4,
      coefficients: [0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      min: 1,
      max: 15
    },
    compositeAlpha: {
      intercept: 0.2,
      coefficients: [0, 0, 0, 0, 0.7, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      min: 0,
      max: 1
    },
    fontSize: {
      intercept: 0.3,
      coefficients: [0, 0, 0, 0.4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      min: 0,
      max: 1
    },
    fontWeight: {
      intercept: 0.2,
      coefficients: [0.2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      min: 0,
      max: 1
    }
  }
});

const createModelPath = (payload: Record<string, unknown>): string => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "text-director-model-"));
  tempDirs.push(dir);
  const modelPath = path.join(dir, "model.json");
  fs.writeFileSync(modelPath, JSON.stringify(payload), "utf8");
  return modelPath;
};

describe("TextDirectorModelRuntime", () => {
  afterEach(() => {
    for (const dir of tempDirs.splice(0)) {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  it("loads a valid model and predicts bounded outputs", () => {
    const modelPath = createModelPath(buildModelPayload());
    const runtime = new TextDirectorModelRuntime({
      modelPath,
      refreshMs: 1
    });

    const prediction = runtime.predict({
      cueId: "main:1000",
      candidateText: "A candidate line",
      candidateWeight: 0.8,
      vector: {
        textAmount: 0.7,
        compositeBias: 0.6,
        audioGain: 0.5,
        spatialX: 0.5,
        spatialY: 0.5,
        spatialZ: 0.5
      },
      audio: {
        rms: 0.3,
        spectralCentroid: 0.4,
        flux: 0.5,
        transientDensity: 0.2,
        updatedAt: Date.now()
      }
    });

    expect(prediction).not.toBeNull();
    expect(prediction?.score).toBeGreaterThan(0.7);
    expect(prediction?.displayDuration).toBeGreaterThanOrEqual(1);
    expect(prediction?.displayDuration).toBeLessThanOrEqual(15);
    expect(runtime.health().active).toBe(true);
  });

  it("keeps previous model active when a reload file becomes invalid", () => {
    const modelPath = createModelPath(buildModelPayload());
    let now = 1_000;
    const runtime = new TextDirectorModelRuntime({
      modelPath,
      refreshMs: 1,
      now: () => now
    });

    const first = runtime.predict({
      cueId: "main:1000",
      candidateText: "Stable line",
      candidateWeight: 0.7,
      vector: {
        textAmount: 0.5,
        compositeBias: 0.5,
        audioGain: 0.5,
        spatialX: 0.5,
        spatialY: 0.5,
        spatialZ: 0.5
      },
      audio: {
        rms: 0.4,
        spectralCentroid: 0.5,
        flux: 0.4,
        transientDensity: 0.4,
        updatedAt: Date.now()
      }
    });
    expect(first).not.toBeNull();

    fs.writeFileSync(modelPath, "{ invalid-json", "utf8");
    now += 10;
    runtime.refresh();

    const second = runtime.predict({
      cueId: "main:1000",
      candidateText: "Stable line",
      candidateWeight: 0.7,
      vector: {
        textAmount: 0.5,
        compositeBias: 0.5,
        audioGain: 0.5,
        spatialX: 0.5,
        spatialY: 0.5,
        spatialZ: 0.5
      },
      audio: {
        rms: 0.4,
        spectralCentroid: 0.5,
        flux: 0.4,
        transientDensity: 0.4,
        updatedAt: Date.now()
      }
    });

    expect(second).not.toBeNull();
    expect(second?.score).toBe(first?.score);
    expect(runtime.health().active).toBe(true);
  });
});
