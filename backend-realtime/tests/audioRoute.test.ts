import type { AudioOpsStatePayload } from "@conductor/protocol";
import Fastify from "fastify";
import { afterEach, describe, expect, it } from "vitest";
import { registerAudioRoutes } from "../src/routes/audio";

describe("audio routes", () => {
  const apps: ReturnType<typeof Fastify>[] = [];

  afterEach(async () => {
    for (const app of apps) {
      await app.close();
    }
    apps.length = 0;
  });

  it("returns audio ops snapshot", async () => {
    const app = Fastify();
    apps.push(app);
    const state: AudioOpsStatePayload = {
      audioFeatures: {
        rms: 0.4,
        spectralCentroid: 0.6,
        flux: 0.3,
        transientDensity: 0.2,
        updatedAt: Date.now()
      },
      phoneAudioPool: {
        gateArmed: true,
        gateCommitted: true,
        quadRouteReady: true,
        availableDevices: ["a", "b"],
        activeVoices: { a: 60 },
        updatedAt: Date.now()
      },
      pickWindow: null,
      pickResult: null,
      textScene: {
        sceneVersion: 1,
        pickEpoch: 1,
        cueId: "main:100",
        anchor: "center-center",
        lineCount: 1,
        cutMode: "hold",
        alpha: 0.8,
        fontScale: 1,
        weight: 0.6,
        durationMs: 3000,
        lines: [],
        guardrails: {
          maxOffsetX: 0.08,
          maxOffsetY: 0.06,
          minContrast: 4.5,
          minDurationMs: 2400
        }
      },
      updatedAt: Date.now()
    };

    await registerAudioRoutes(app, {
      stateHub: {
        snapshot: () => state,
        subscribe: () => () => undefined
      }
    });

    const res = await app.inject({ method: "GET", url: "/audio/state" });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.state.phoneAudioPool.gateCommitted).toBe(true);
    expect(body.state.audioFeatures.rms).toBe(0.4);
  });
});
