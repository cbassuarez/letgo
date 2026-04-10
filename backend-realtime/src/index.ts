import Fastify from "fastify";
import cors from "@fastify/cors";
import websocket from "@fastify/websocket";
import Redis from "ioredis";
import { Pool } from "pg";
import { config } from "./config";
import { registerHealthRoute } from "./routes/health";
import { registerIdentityRoutes } from "./routes/identity";
import { registerLogbookRoutes } from "./routes/logbook";
import { registerWsRoutes } from "./routes/ws";
import { IdentityService } from "./services/identityService";
import { ReplayService } from "./services/replayService";
import { ShowOrchestrator } from "./services/showOrchestrator";
import { SyncService } from "./services/syncService";
import {
  GoogleSheetsLogbookStore,
  MemoryLogbookStore
} from "./stores/logbookStore";
import { MemoryReplayStore, PostgresReplayStore } from "./stores/replayStore";
import { MemorySessionStore, RedisSessionStore } from "./stores/sessionStore";
import { logger } from "./utils/logger";

const bootstrap = async (): Promise<void> => {
  const app = Fastify({ logger: false });
  await app.register(cors, {
    origin: true
  });
  await app.register(websocket);

  const identityService = new IdentityService(config.SESSION_SALT);
  const show = new ShowOrchestrator();
  const sync = new SyncService(config.MAX_CLIENT_DRIFT_MS);

  const sessionStore = config.REDIS_URL
    ? new RedisSessionStore(new Redis(config.REDIS_URL))
    : new MemorySessionStore();

  const replayStore = config.POSTGRES_URL
    ? new PostgresReplayStore(new Pool({ connectionString: config.POSTGRES_URL }))
    : new MemoryReplayStore();

  if (replayStore instanceof PostgresReplayStore) {
    await replayStore.init();
  }

  const replayService = new ReplayService(replayStore);
  const logbookStore =
    config.LOGBOOK_GOOGLE_SHEET_ID &&
    config.LOGBOOK_GOOGLE_SERVICE_ACCOUNT_EMAIL &&
    config.LOGBOOK_GOOGLE_PRIVATE_KEY
      ? GoogleSheetsLogbookStore.fromEnv({
          LOGBOOK_GOOGLE_SHEET_ID: config.LOGBOOK_GOOGLE_SHEET_ID,
          LOGBOOK_GOOGLE_SERVICE_ACCOUNT_EMAIL: config.LOGBOOK_GOOGLE_SERVICE_ACCOUNT_EMAIL,
          LOGBOOK_GOOGLE_PRIVATE_KEY: config.LOGBOOK_GOOGLE_PRIVATE_KEY,
          LOGBOOK_GOOGLE_SHEET_TAB: config.LOGBOOK_GOOGLE_SHEET_TAB
        })
      : new MemoryLogbookStore();

  await registerHealthRoute(app, config);
  await registerIdentityRoutes(app, {
    identityService,
    sessions: sessionStore
  });
  await registerLogbookRoutes(app, {
    identityService,
    sessions: sessionStore,
    store: logbookStore
  });
  await registerWsRoutes(app, {
    config,
    identityService,
    replayService,
    show,
    sync,
    sessions: sessionStore
  });

  await app.listen({ port: config.PORT, host: config.HOST });
  logger.info("backend-realtime listening", {
    host: config.HOST,
    port: config.PORT,
    env: config.NODE_ENV
  });
};

bootstrap().catch((error: Error) => {
  logger.error("failed to start backend-realtime", {
    message: error.message
  });
  process.exit(1);
});
