import Fastify from "fastify";
import { afterEach, describe, expect, it } from "vitest";
import { registerHealthRoute } from "../src/routes/health";

describe("health route", () => {
  const apps: ReturnType<typeof Fastify>[] = [];

  afterEach(async () => {
    for (const app of apps) {
      await app.close();
    }
    apps.length = 0;
  });

  it("returns additive link metadata", async () => {
    const app = Fastify();
    apps.push(app);

    await registerHealthRoute(app, { MAX_CLIENT_DRIFT_MS: 100 });

    const res = await app.inject({ method: "GET", url: "/health" });
    const body = res.json();

    expect(res.statusCode).toBe(200);
    expect(body.ok).toBe(true);
    expect(body.status).toBe("ok");
    expect(typeof body.now).toBe("number");
    expect(typeof body.time).toBe("string");
    expect(body.wsHarnessPath).toBe("/ws/harness");
    expect(body.wsDevicePath).toBe("/ws/device/:hashedId");
    expect(body.maxClientDriftMs).toBe(100);
  });
});
