import type { FastifyInstance } from "fastify";

export const registerHealthRoute = async (app: FastifyInstance): Promise<void> => {
  app.get("/health", async () => ({ ok: true, now: Date.now() }));
};
