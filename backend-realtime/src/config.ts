import { z } from "zod";

const envSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  PORT: z.coerce.number().default(8787),
  HOST: z.string().default("0.0.0.0"),
  REDIS_URL: z.string().optional(),
  POSTGRES_URL: z.string().optional(),
  SESSION_SALT: z.string().default("conductor-film-session-salt"),
  REPLAY_RETENTION_HOURS: z.coerce.number().default(24),
  MAX_CLIENT_DRIFT_MS: z.coerce.number().default(100)
});

export type AppConfig = z.infer<typeof envSchema>;

export const config: AppConfig = envSchema.parse(process.env);
