import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { IdentityService } from "../services/identityService";
import type { LogbookEntryRecord, LogbookStore } from "../stores/logbookStore";
import type { SessionStore } from "../stores/sessionStore";

interface LogbookRouteDependencies {
  identityService: IdentityService;
  sessions: SessionStore;
  store: LogbookStore;
}

interface CursorPayload {
  updatedAt: number;
  hashedId: string;
}

const putEntryBody = z.object({
  signer: z.string().min(2).max(60),
  message: z.string().min(4).max(900)
});

const listQuery = z.object({
  cursor: z.string().optional(),
  limit: z.coerce.number().int().min(1).max(50).default(20)
});

const WRITE_COOLDOWN_MS = 4000;
const lastWriteByHashedId = new Map<string, number>();

export const registerLogbookRoutes = async (
  app: FastifyInstance,
  deps: LogbookRouteDependencies
): Promise<void> => {
  const ensureSession = async (hashedId: string): Promise<void> => {
    const existing = await deps.sessions.get(hashedId);
    if (existing) {
      return;
    }
    await deps.sessions.upsert(deps.identityService.profileFromHashedId(hashedId));
  };

  app.put("/logbook/:hashedId", async (request, reply) => {
    const hashedId = (request.params as { hashedId: string }).hashedId;
    if (!deps.identityService.validateHashedId(hashedId)) {
      return reply.status(400).send({ error: "invalid_hashed_id" });
    }

    const bodyResult = putEntryBody.safeParse(request.body);
    if (!bodyResult.success) {
      return reply.status(400).send({
        error: "invalid_request",
        details: bodyResult.error.flatten()
      });
    }

    await ensureSession(hashedId);

    const now = Date.now();
    const lastWriteAt = lastWriteByHashedId.get(hashedId) ?? 0;
    if (now - lastWriteAt < WRITE_COOLDOWN_MS) {
      return reply.status(429).send({
        error: "rate_limited",
        retryAfterMs: WRITE_COOLDOWN_MS - (now - lastWriteAt)
      });
    }

    const signer = normalizeText(bodyResult.data.signer, 60);
    const message = normalizeText(bodyResult.data.message, 900);
    if (signer.length < 2 || message.length < 4) {
      return reply.status(400).send({
        error: "invalid_content",
        message: "Signer and message must include readable text."
      });
    }

    const current = await deps.store.getByHashedId(hashedId);
    const entry: LogbookEntryRecord = {
      hashedId,
      signer,
      message,
      createdAt: current?.createdAt ?? now,
      updatedAt: now
    };

    const saved = await deps.store.upsert(entry);
    lastWriteByHashedId.set(hashedId, now);

    return {
      entry: toParticipantEntry(saved)
    };
  });

  app.get("/logbook/:hashedId", async (request, reply) => {
    const hashedId = (request.params as { hashedId: string }).hashedId;
    if (!deps.identityService.validateHashedId(hashedId)) {
      return reply.status(400).send({ error: "invalid_hashed_id" });
    }

    await ensureSession(hashedId);

    const entry = await deps.store.getByHashedId(hashedId);
    if (!entry) {
      return reply.status(404).send({ error: "not_found" });
    }

    return {
      entry: toParticipantEntry(entry)
    };
  });

  app.get("/logbook", async (request, reply) => {
    const queryResult = listQuery.safeParse(request.query);
    if (!queryResult.success) {
      return reply.status(400).send({
        error: "invalid_query",
        details: queryResult.error.flatten()
      });
    }

    const { cursor, limit } = queryResult.data;
    const cursorPayload = cursor ? decodeCursor(cursor) : null;
    if (cursor && !cursorPayload) {
      return reply.status(400).send({ error: "invalid_cursor" });
    }

    const entries = (await deps.store.list())
      .sort((a, b) => {
        if (b.updatedAt !== a.updatedAt) {
          return b.updatedAt - a.updatedAt;
        }
        return b.hashedId.localeCompare(a.hashedId);
      })
      .filter((entry) => isAfterCursor(entry, cursorPayload));

    const page = entries.slice(0, limit);
    const hasMore = entries.length > page.length;
    const nextCursor = hasMore && page.length > 0 ? encodeCursor(page[page.length - 1]) : null;

    return {
      entries: page.map(toPublicEntry),
      nextCursor
    };
  });
};

const normalizeText = (value: string, maxLength: number): string =>
  value
    .replace(/[\u0000-\u001F\u007F]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, maxLength);

const toPublicEntry = (entry: LogbookEntryRecord) => ({
  participantTag: `${entry.hashedId.slice(0, 6)}-${entry.hashedId.slice(-4)}`,
  signer: entry.signer,
  message: entry.message,
  createdAt: entry.createdAt,
  updatedAt: entry.updatedAt
});

const toParticipantEntry = (entry: LogbookEntryRecord) => ({
  signer: entry.signer,
  message: entry.message,
  createdAt: entry.createdAt,
  updatedAt: entry.updatedAt
});

const encodeCursor = (entry: Pick<LogbookEntryRecord, "updatedAt" | "hashedId">): string => {
  const payload: CursorPayload = {
    updatedAt: entry.updatedAt,
    hashedId: entry.hashedId
  };
  return Buffer.from(JSON.stringify(payload), "utf8").toString("base64url");
};

const decodeCursor = (cursor: string): CursorPayload | null => {
  try {
    const decoded = JSON.parse(Buffer.from(cursor, "base64url").toString("utf8")) as CursorPayload;
    if (!Number.isFinite(decoded.updatedAt) || typeof decoded.hashedId !== "string") {
      return null;
    }
    return decoded;
  } catch {
    return null;
  }
};

const isAfterCursor = (entry: LogbookEntryRecord, cursor: CursorPayload | null): boolean => {
  if (!cursor) {
    return true;
  }

  if (entry.updatedAt < cursor.updatedAt) {
    return true;
  }

  if (entry.updatedAt > cursor.updatedAt) {
    return false;
  }

  return entry.hashedId.localeCompare(cursor.hashedId) < 0;
};
