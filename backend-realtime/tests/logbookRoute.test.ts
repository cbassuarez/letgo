import Fastify from "fastify";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { registerLogbookRoutes } from "../src/routes/logbook";
import { IdentityService } from "../src/services/identityService";
import { MemoryLogbookStore } from "../src/stores/logbookStore";
import { MemorySessionStore } from "../src/stores/sessionStore";

describe("logbook routes", () => {
  const apps: ReturnType<typeof Fastify>[] = [];
  const identity = new IdentityService("test-salt");
  const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

  beforeEach(() => {
    vi.restoreAllMocks();
  });

  afterEach(async () => {
    for (const app of apps) {
      await app.close();
    }
    apps.length = 0;
  });

  it("upserts and reads a participant entry", async () => {
    const app = Fastify();
    apps.push(app);

    const sessions = new MemorySessionStore();
    const store = new MemoryLogbookStore();
    const profile = identity.getOrCreateProfile({ rawToken: "tag://participant-a" });
    await sessions.upsert(profile);

    await registerLogbookRoutes(app, {
      identityService: identity,
      sessions,
      store
    });

    const putRes = await app.inject({
      method: "PUT",
      url: `/logbook/${profile.hashedId}`,
      payload: {
        signer: "Ari",
        message: "I felt the room drift into one breath."
      }
    });

    expect(putRes.statusCode).toBe(200);
    const getRes = await app.inject({
      method: "GET",
      url: `/logbook/${profile.hashedId}`
    });
    expect(getRes.statusCode).toBe(200);
    expect(getRes.json().entry.signer).toBe("Ari");
  });

  it("blocks writes for unknown participants", async () => {
    const app = Fastify();
    apps.push(app);
    const store = new MemoryLogbookStore();
    const sessions = new MemorySessionStore();
    const profile = identity.getOrCreateProfile({ rawToken: "tag://participant-b" });

    await registerLogbookRoutes(app, {
      identityService: identity,
      sessions,
      store
    });

    const res = await app.inject({
      method: "PUT",
      url: `/logbook/${profile.hashedId}`,
      payload: {
        signer: "Rowan",
        message: "Unregistered writers should not post."
      }
    });

    expect(res.statusCode).toBe(403);
    expect(res.json().error).toBe("non_participant");
  });

  it("returns public feed with cursor pagination", async () => {
    const app = Fastify();
    apps.push(app);
    const sessions = new MemorySessionStore();
    const store = new MemoryLogbookStore();

    const p1 = identity.getOrCreateProfile({ rawToken: "tag://participant-c1" });
    const p2 = identity.getOrCreateProfile({ rawToken: "tag://participant-c2" });
    const p3 = identity.getOrCreateProfile({ rawToken: "tag://participant-c3" });
    await sessions.upsert(p1);
    await sessions.upsert(p2);
    await sessions.upsert(p3);

    await registerLogbookRoutes(app, {
      identityService: identity,
      sessions,
      store
    });

    const put1 = await app.inject({
      method: "PUT",
      url: `/logbook/${p1.hashedId}`,
      payload: { signer: "A1", message: "Entry one." }
    });
    expect(put1.statusCode).toBe(200);
    await wait(8);
    const put2 = await app.inject({
      method: "PUT",
      url: `/logbook/${p2.hashedId}`,
      payload: { signer: "B2", message: "Entry two." }
    });
    expect(put2.statusCode).toBe(200);
    await wait(8);
    const put3 = await app.inject({
      method: "PUT",
      url: `/logbook/${p3.hashedId}`,
      payload: { signer: "C3", message: "Entry three." }
    });
    expect(put3.statusCode).toBe(200);

    const firstPage = await app.inject({
      method: "GET",
      url: "/logbook?limit=2"
    });
    expect(firstPage.statusCode).toBe(200);
    const firstJson = firstPage.json();
    expect(firstJson.entries).toHaveLength(2);
    expect(firstJson.nextCursor).toBeTypeOf("string");

    const secondPage = await app.inject({
      method: "GET",
      url: `/logbook?limit=2&cursor=${encodeURIComponent(firstJson.nextCursor)}`
    });
    expect(secondPage.statusCode).toBe(200);
    expect(secondPage.json().entries).toHaveLength(1);
  });
});
