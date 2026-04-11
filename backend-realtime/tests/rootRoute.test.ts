import Fastify from "fastify";
import { afterEach, describe, expect, it } from "vitest";
import { registerRootRoute } from "../src/routes/root";

describe("root route", () => {
  const apps: ReturnType<typeof Fastify>[] = [];

  afterEach(async () => {
    for (const app of apps) {
      await app.close();
    }
    apps.length = 0;
  });

  it("returns service metadata for JSON clients", async () => {
    const app = Fastify();
    apps.push(app);
    await registerRootRoute(app);

    const response = await app.inject({ method: "GET", url: "/" });
    const body = response.json();

    expect(response.statusCode).toBe(200);
    expect(body.ok).toBe(true);
    expect(body.service).toBe("conductor-backend");
    expect(body.endpoints.health).toBe("/health");
    expect(body.endpoints.wsHarness).toBe("/ws/harness");
    expect(body.endpoints.audioState).toBe("/audio/state");
  });

  it("returns an html landing page for browsers", async () => {
    const app = Fastify();
    apps.push(app);
    await registerRootRoute(app);

    const response = await app.inject({
      method: "GET",
      url: "/",
      headers: {
        accept: "text/html"
      }
    });

    expect(response.statusCode).toBe(200);
    expect(response.headers["content-type"]).toContain("text/html");
    expect(response.body).toContain("Conductor Backend Online");
    expect(response.body).toContain("/health");
  });
});
