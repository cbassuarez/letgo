import Fastify from "fastify";
import { afterEach, describe, expect, it } from "vitest";
import type { LightingStatePayload } from "@conductor/protocol";
import { registerLightingRoutes } from "../src/routes/lighting";

describe("lighting routes", () => {
  const apps: ReturnType<typeof Fastify>[] = [];

  afterEach(async () => {
    for (const app of apps) {
      await app.close();
    }
    apps.length = 0;
  });

  it("returns current lighting snapshot", async () => {
    const app = Fastify();
    apps.push(app);

    const state: LightingStatePayload = {
      targetColor: {
        oklch: { l: 0.55, c: 0.2, h: 220 },
        hex: "#336699"
      },
      confidence: 0.67,
      entropy: 0.24,
      stability: 0.71,
      trend: "go",
      participantCount: 12,
      updatedAt: Date.now(),
      zoneField: []
    };

    await registerLightingRoutes(app, {
      field: {
        snapshot: () => state,
        subscribe: () => () => undefined
      }
    });

    const res = await app.inject({ method: "GET", url: "/lighting/state" });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.state.targetColor.hex).toBe("#336699");
    expect(body.state.trend).toBe("go");
  });

  it("serves engineer page html", async () => {
    const app = Fastify();
    apps.push(app);

    await registerLightingRoutes(app, {
      field: {
        snapshot: () =>
          ({
            targetColor: {
              oklch: { l: 0.56, c: 0.12, h: 220 },
              hex: "#446688"
            },
            confidence: 0,
            entropy: 0,
            stability: 1,
            trend: "hold",
            participantCount: 0,
            updatedAt: Date.now(),
            zoneField: []
          }) satisfies LightingStatePayload,
        subscribe: () => () => undefined
      }
    });

    const res = await app.inject({ method: "GET", url: "/lighting/engineer" });
    expect(res.statusCode).toBe(200);
    expect(res.headers["content-type"]).toContain("text/html");
    expect(res.body).toContain("Lighting Engineer Feed");
    expect(res.body).toContain("/lighting/stream");
  });
});
