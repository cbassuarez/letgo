import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { SessionStore } from "../stores/sessionStore";
import { IdentityService } from "../services/identityService";

interface IdentityRouteDependencies {
  identityService: IdentityService;
  sessions: SessionStore;
}

const resolveBody = z.object({
  rawToken: z.string().min(3),
  role: z.enum(["audience", "performer", "observer", "muted"]).optional(),
  permissions: z
    .object({
      audio: z.boolean().optional(),
      geolocation: z.boolean().optional(),
      motion: z.boolean().optional()
    })
    .optional()
});

export const registerIdentityRoutes = async (
  app: FastifyInstance,
  deps: IdentityRouteDependencies
): Promise<void> => {
  app.post("/identity/resolve", async (request, reply) => {
    const parseResult = resolveBody.safeParse(request.body);
    if (!parseResult.success) {
      return reply.status(400).send({
        error: "invalid_request",
        details: parseResult.error.flatten()
      });
    }

    const profile = deps.identityService.getOrCreateProfile(parseResult.data);
    await deps.sessions.upsert(profile);

    return {
      hashedId: profile.hashedId,
      profile
    };
  });

  app.get("/identity/:hashedId", async (request, reply) => {
    const hashedId = (request.params as { hashedId: string }).hashedId;

    if (!deps.identityService.validateHashedId(hashedId)) {
      return reply.status(400).send({ error: "invalid_hashed_id" });
    }

    const profile = await deps.sessions.get(hashedId);
    if (!profile) {
      return reply.status(404).send({ error: "unknown_participant" });
    }

    return { profile };
  });
};
