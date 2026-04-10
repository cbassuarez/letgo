import type { AudioOpsStatePayload } from "@conductor/protocol";
import type { FastifyInstance } from "fastify";

interface AudioRouteDependencies {
  stateHub: {
    snapshot(): AudioOpsStatePayload;
    subscribe(listener: (payload: AudioOpsStatePayload) => void): () => void;
  };
}

export const registerAudioRoutes = async (
  app: FastifyInstance,
  deps: AudioRouteDependencies
): Promise<void> => {
  app.get("/audio/state", async () => ({
    state: deps.stateHub.snapshot()
  }));

  app.get("/audio/stream", async (request, reply) => {
    reply.hijack();
    reply.raw.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no"
    });

    const writeEvent = (event: string, payload: unknown): void => {
      reply.raw.write(`event: ${event}\n`);
      reply.raw.write(`data: ${JSON.stringify(payload)}\n\n`);
    };

    writeEvent("state", deps.stateHub.snapshot());
    const unsubscribe = deps.stateHub.subscribe((payload) => {
      writeEvent("state", payload);
    });

    const heartbeat = setInterval(() => {
      reply.raw.write(": ping\n\n");
    }, 15_000);

    request.raw.on("close", () => {
      clearInterval(heartbeat);
      unsubscribe();
      reply.raw.end();
    });

    request.raw.on("error", () => {
      clearInterval(heartbeat);
      unsubscribe();
      reply.raw.end();
    });
  });
};
