import { z } from "zod";

const boolFromEnv = z.preprocess((value) => {
  if (typeof value === "boolean") {
    return value;
  }
  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase();
    if (["1", "true", "yes", "on"].includes(normalized)) {
      return true;
    }
    if (["0", "false", "no", "off"].includes(normalized)) {
      return false;
    }
  }
  return value;
}, z.boolean());

const envSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  PORT: z.coerce.number().default(8787),
  HOST: z.string().default("0.0.0.0"),
  REDIS_URL: z.string().optional(),
  POSTGRES_URL: z.string().optional(),
  SESSION_SALT: z.string().default("conductor-film-session-salt"),
  REPLAY_RETENTION_HOURS: z.coerce.number().default(24),
  MAX_CLIENT_DRIFT_MS: z.coerce.number().default(100),
  LOGBOOK_GOOGLE_SHEET_ID: z.string().optional(),
  LOGBOOK_GOOGLE_SERVICE_ACCOUNT_EMAIL: z.string().optional(),
  LOGBOOK_GOOGLE_PRIVATE_KEY: z.string().optional(),
  LOGBOOK_GOOGLE_SHEET_TAB: z.string().default("logbook"),
  CONDUCTOR_HLS_BASE_URL: z.string().optional(),
  CONDUCTOR_HLS_CATALOG_URL: z.string().optional(),
  CONDUCTOR_HLS_STREAM_MAP: z.string().optional(),
  CONDUCTOR_HLS_MAIN_URL: z.string().optional(),
  CONDUCTOR_HLS_INTERSTITIAL_URL: z.string().optional(),
  CONDUCTOR_HLS_PRESHOW_URL: z.string().optional(),
  CONDUCTOR_HLS_INTRODUCTION_URL: z.string().optional(),
  CONDUCTOR_HLS_MAIN_STATIC_URL: z.string().optional(),
  CONDUCTOR_HLS_MAIN_DYNAMIC_URL: z.string().optional(),
  CONDUCTOR_HLS_ENDING_URL: z.string().optional(),
  CONDUCTOR_INTERSTITIAL_NO_REPEAT: z.coerce.number().default(2),
  CONDUCTOR_DYNAMIC_SWITCH_QUANTUM_MS: z.coerce.number().default(250),
  CONDUCTOR_ORIENTATION_SWITCH_DEBOUNCE_MS: z.coerce.number().default(250),
  CONDUCTOR_TEXT_BANK_PATH: z.string().optional(),
  CONDUCTOR_TEXT_STRICT_BANK_PATH: z.string().optional(),
  CONDUCTOR_TEXT_LOOSE_BANK_PATH: z.string().optional(),
  CONDUCTOR_TEXT_BANK_REFRESH_MS: z.coerce.number().default(3_000),
  CONDUCTOR_TEXT_DIRECTOR_MODEL_PATH: z.string().optional(),
  CONDUCTOR_TEXT_DIRECTOR_MODEL_REFRESH_MS: z.coerce.number().default(3_000),
  CONDUCTOR_TEXT_SEMANTIC_MODE: z.enum(["off", "openai"]).default("off"),
  CONDUCTOR_TEXT_SEMANTIC_OPENAI_API_KEY: z.string().optional(),
  CONDUCTOR_TEXT_SEMANTIC_OPENAI_MODEL: z.string().default("gpt-4.1-mini"),
  CONDUCTOR_TEXT_SEMANTIC_REFRESH_MS: z.coerce.number().default(12_000),
  CONDUCTOR_TEXT_SEMANTIC_TTL_MS: z.coerce.number().default(70_000),
  CONDUCTOR_TEXT_SEMANTIC_TIMEOUT_MS: z.coerce.number().default(4_500),
  CONDUCTOR_MANAGED_SFU_BASE_URL: z.string().optional(),
  CONDUCTOR_GROUP_STEM_BASE_URL: z.string().optional(),
  CONDUCTOR_VOICE_STREAM_CODEC: z.enum(["opus", "aac", "pcm"]).default("opus"),
  CONDUCTOR_GROUP_STREAM_CODEC: z.enum(["opus", "aac", "pcm"]).default("aac"),
  CONDUCTOR_VOICE_STREAM_TTL_MS: z.coerce.number().default(30_000),
  CONDUCTOR_VOICE_STREAM_MAX_CONCURRENT: z.coerce.number().default(16),
  CONDUCTOR_VOICE_STREAM_TRANSPORT: z.enum(["hls", "webrtc"]).default("hls"),
  CONDUCTOR_MANAGED_SFU_SESSION_PREFIX: z.string().default("letgo"),
  CONDUCTOR_MANAGED_SFU_TOKEN_SECRET: z.string().default("managed-sfu-token"),
  CONDUCTOR_SFU_ENABLED: boolFromEnv.default(false),
  CONDUCTOR_SFU_ROOM_ID: z.string().default("letgo-room"),
  CONDUCTOR_SFU_LISTEN_IP: z.string().default("0.0.0.0"),
  CONDUCTOR_SFU_ANNOUNCED_IP: z.string().optional(),
  CONDUCTOR_SFU_RTC_MIN_PORT: z.coerce.number().optional(),
  CONDUCTOR_SFU_RTC_MAX_PORT: z.coerce.number().optional(),
  CONDUCTOR_SFU_MAX_SUBSCRIBERS: z.coerce.number().default(60),
  CONDUCTOR_SFU_ICE_SERVERS_JSON: z.string().optional()
});

export type AppConfig = z.infer<typeof envSchema>;

export const config: AppConfig = envSchema.parse(process.env);
