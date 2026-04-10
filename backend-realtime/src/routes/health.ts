import type { FastifyInstance } from "fastify";
import type { AppConfig } from "../config";

export const registerHealthRoute = async (
  app: FastifyInstance,
  config: Pick<AppConfig, "MAX_CLIENT_DRIFT_MS">
): Promise<void> => {
  app.get("/health", async () => ({
    ok: true,
    status: "ok",
    now: Date.now(),
    time: new Date().toISOString(),
    wsHarnessPath: "/ws/harness",
    wsDevicePath: "/ws/device/:hashedId",
    maxClientDriftMs: config.MAX_CLIENT_DRIFT_MS
  }));
};
