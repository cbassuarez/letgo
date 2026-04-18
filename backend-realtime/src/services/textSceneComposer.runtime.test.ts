import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import type {
  TextDirectorModelHealth,
  TextDirectorModelRuntime,
  TextDirectorRuntimeInput,
  TextDirectorPrediction
} from "./textDirectorModel";
import { TextSceneComposerService } from "./textSceneComposer";

const tempDirs: string[] = [];

const withTempDir = (): string => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "text-scene-runtime-"));
  tempDirs.push(dir);
  return dir;
};

const stubModelRuntime = (predict: (candidateText: string) => TextDirectorPrediction | null) =>
  ({
    refresh: () => {},
    predict: (input: TextDirectorRuntimeInput) => predict(input.candidateText),
    health: (): TextDirectorModelHealth => ({
      active: true,
      summary: "stub",
      modelPath: null,
      source: "inline",
      lastLoadedAt: Date.now(),
      runtimeFailures: 0
    })
  } as const);

describe("TextSceneComposerService runtime loading", () => {
  afterEach(() => {
    for (const dir of tempDirs.splice(0)) {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  it("loads strict and loose script banks from files and hot-reloads updates", () => {
    const dir = withTempDir();
    const strictPath = path.join(dir, "strict.txt");
    const loosePath = path.join(dir, "loose.txt");
    fs.writeFileSync(strictPath, "strict-first line\nstrict-second line\n", "utf8");
    fs.writeFileSync(loosePath, "loose-first line\n", "utf8");

    let now = 1_000;
    const composer = new TextSceneComposerService({
      now: () => now,
      bankRuntime: {
        strictPath,
        loosePath,
        refreshMs: 50
      }
    });

    const strictScene = composer.compose({
      cueId: "main:100",
      vector: { textAmount: 0.1, compositeBias: 0.5 },
      textBlend: {
        probability: 0.5,
        strictRatio: 1
      }
    });
    expect(strictScene.lines[0]?.baseText).toContain("strict");

    const looseScene = composer.compose({
      cueId: "main:101",
      vector: { textAmount: 0.1, compositeBias: 0.5 },
      textBlend: {
        probability: 0.5,
        strictRatio: 0
      }
    });
    expect(looseScene.lines[0]?.baseText).toContain("loose");

    fs.writeFileSync(strictPath, "strict-reloaded line\n", "utf8");
    now += 200;
    composer.reloadScriptBanks(true);
    const reloadedScene = composer.compose({
      cueId: "main:102",
      vector: { textAmount: 0.1, compositeBias: 0.5 },
      textBlend: {
        probability: 0.5,
        strictRatio: 1
      }
    });
    expect(reloadedScene.lines[0]?.baseText).toContain("strict-reloaded");
  });

  it("uses optional model runtime to influence line ranking and style", () => {
    const dir = withTempDir();
    const strictPath = path.join(dir, "strict.json");
    fs.writeFileSync(
      strictPath,
      JSON.stringify({
        strict: [
          { id: "s1", text: "candidate one", weight: 0.5 },
          { id: "s2", text: "candidate two", weight: 0.5 }
        ]
      }),
      "utf8"
    );

    const withoutModel = new TextSceneComposerService({
      bankRuntime: {
        strictPath
      }
    });
    const baseline = withoutModel.compose({
      cueId: "main:200",
      vector: { textAmount: 0.1, compositeBias: 0.4, audioGain: 0.5, spatialX: 0.5, spatialY: 0.5, spatialZ: 0.5 },
      textBlend: {
        probability: 0.5,
        strictRatio: 1
      }
    });

    const withModel = new TextSceneComposerService({
      bankRuntime: {
        strictPath
      },
      modelRuntime: stubModelRuntime((text) =>
        text.includes("two")
          ? {
              score: 1,
              displayDuration: 15,
              compositeAlpha: 1,
              fontSize: 1,
              fontWeight: 1
            }
          : {
              score: 0,
              displayDuration: 1,
              compositeAlpha: 0.1,
              fontSize: 0.2,
              fontWeight: 0.2
            }
      ) as unknown as TextDirectorModelRuntime
    });
    const modeled = withModel.compose({
      cueId: "main:201",
      vector: { textAmount: 0.1, compositeBias: 0.4, audioGain: 0.5, spatialX: 0.5, spatialY: 0.5, spatialZ: 0.5 },
      textBlend: {
        probability: 0.5,
        strictRatio: 1
      }
    });

    expect(modeled.lines[0]?.baseText).toContain("two");
    expect(modeled.durationMs).toBeGreaterThanOrEqual(baseline.durationMs);
    expect(modeled.alpha).toBeGreaterThanOrEqual(baseline.alpha);
  });
});
