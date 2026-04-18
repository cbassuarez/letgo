import {
  clamp01,
  stableHashToSeed,
  type ParamVector
} from "@conductor/protocol";
import { logger } from "../utils/logger";
import type { ScriptCandidate } from "./textSceneComposer";

export type TextSemanticMode = "off" | "openai";

interface TextSemanticGeneratorRuntimeOptions {
  mode?: TextSemanticMode;
  openAiApiKey?: string | null;
  openAiModel?: string;
  refreshMs?: number;
  ttlMs?: number;
  timeoutMs?: number;
  maxCandidates?: number;
  now?: () => number;
}

export interface TextSemanticGeneratorStatus {
  mode: TextSemanticMode;
  enabled: boolean;
  provider: "openai" | "none";
  model: string | null;
  apiKeyConfigured: boolean;
  refreshMs: number;
  ttlMs: number;
  timeoutMs: number;
  cacheEntries: number;
  inFlight: number;
  lastSuccessAt: number | null;
  lastError: string | null;
}

interface TextSemanticContext {
  cueId: string;
  pickLabel: string;
  strictRatio: number;
  vector: ParamVector;
  strictBank: ScriptCandidate[];
  looseBank: ScriptCandidate[];
}

interface SemanticCacheEntry {
  updatedAt: number;
  candidates: ScriptCandidate[];
}

const bannedTextPatterns: RegExp[] = [
  /\bjourney\b/i,
  /\bgrowth\b/i,
  /\bhealing\b/i,
  /\btherapy\b/i,
  /\btrauma\b/i,
  /\btranscend/i,
  /\bsavior\b/i
];

const sanitizeLine = (value: string): string =>
  value
    .replace(/\s+/g, " ")
    .replace(/\.{2,}/g, ".")
    .replace(/\s+([,.;!?])/g, "$1")
    .trim();

const passesGuardrails = (text: string): boolean =>
  !bannedTextPatterns.some((pattern) => pattern.test(text));

const parseNumber = (value: unknown): number | null =>
  typeof value === "number"
    ? Number.isFinite(value)
      ? value
      : null
    : typeof value === "string"
      ? Number.isFinite(Number(value))
        ? Number(value)
        : null
      : null;

const extractAssistantText = (payload: Record<string, unknown>): string | null => {
  if (typeof payload.output_text === "string" && payload.output_text.trim().length > 0) {
    return payload.output_text.trim();
  }

  const choices = payload.choices;
  if (Array.isArray(choices) && choices.length > 0) {
    const first = choices[0];
    if (first && typeof first === "object" && !Array.isArray(first)) {
      const record = first as Record<string, unknown>;
      const message = record.message;
      if (message && typeof message === "object" && !Array.isArray(message)) {
        const messageRecord = message as Record<string, unknown>;
        const content = messageRecord.content;
        if (typeof content === "string" && content.trim().length > 0) {
          return content.trim();
        }
        if (Array.isArray(content)) {
          const chunks = content
            .map((entry) => {
              if (typeof entry === "string") {
                return entry;
              }
              if (entry && typeof entry === "object" && !Array.isArray(entry)) {
                const chunk = entry as Record<string, unknown>;
                return typeof chunk.text === "string" ? chunk.text : "";
              }
              return "";
            })
            .filter((chunk) => chunk.trim().length > 0);
          if (chunks.length > 0) {
            return chunks.join("\n").trim();
          }
        }
      }
    }
  }

  return null;
};

const extractCandidateArray = (value: unknown): unknown[] => {
  if (Array.isArray(value)) {
    return value;
  }
  if (value && typeof value === "object" && !Array.isArray(value)) {
    const record = value as Record<string, unknown>;
    if (Array.isArray(record.candidates)) {
      return record.candidates as unknown[];
    }
    if (Array.isArray(record.lines)) {
      return record.lines as unknown[];
    }
  }
  return [];
};

export class TextSemanticGeneratorRuntime {
  private mode: TextSemanticMode;
  private openAiApiKey: string | null;
  private openAiModel: string;
  private readonly refreshMs: number;
  private readonly ttlMs: number;
  private readonly timeoutMs: number;
  private readonly maxCandidates: number;
  private readonly now: () => number;

  private readonly cache = new Map<string, SemanticCacheEntry>();
  private readonly inFlight = new Map<string, Promise<void>>();
  private lastSuccessAt: number | null = null;
  private lastError: string | null = null;

  constructor(options: TextSemanticGeneratorRuntimeOptions = {}) {
    this.mode = options.mode ?? "off";
    this.openAiApiKey = normalizeSecret(options.openAiApiKey);
    this.openAiModel = normalizeModel(options.openAiModel);
    this.refreshMs = Math.max(1_000, options.refreshMs ?? 12_000);
    this.ttlMs = Math.max(this.refreshMs, options.ttlMs ?? 70_000);
    this.timeoutMs = Math.max(1_000, options.timeoutMs ?? 4_500);
    this.maxCandidates = Math.max(2, Math.min(16, options.maxCandidates ?? 6));
    this.now = options.now ?? Date.now;
  }

  configure(input: {
    mode?: TextSemanticMode;
    openAiApiKey?: string | null;
    openAiModel?: string;
  }): void {
    if (input.mode) {
      this.mode = input.mode;
    }
    if (input.openAiApiKey !== undefined) {
      this.openAiApiKey = normalizeSecret(input.openAiApiKey);
    }
    if (input.openAiModel) {
      this.openAiModel = normalizeModel(input.openAiModel);
    }
  }

  status(): TextSemanticGeneratorStatus {
    return {
      mode: this.mode,
      enabled: this.mode !== "off",
      provider: this.mode === "openai" ? "openai" : "none",
      model: this.mode === "openai" ? this.openAiModel : null,
      apiKeyConfigured: this.openAiApiKey !== null,
      refreshMs: this.refreshMs,
      ttlMs: this.ttlMs,
      timeoutMs: this.timeoutMs,
      cacheEntries: this.cache.size,
      inFlight: this.inFlight.size,
      lastSuccessAt: this.lastSuccessAt,
      lastError: this.lastError
    };
  }

  suggest(context: TextSemanticContext): ScriptCandidate[] {
    if (this.mode === "off") {
      return [];
    }

    const key = this.cacheKey(context);
    const now = this.now();
    const cached = this.cache.get(key);

    if (!cached || now - cached.updatedAt > this.refreshMs) {
      this.enqueueRefresh(key, context);
    }

    if (!cached || now - cached.updatedAt > this.ttlMs) {
      return [];
    }
    return cached.candidates;
  }

  private enqueueRefresh(key: string, context: TextSemanticContext): void {
    if (this.inFlight.has(key)) {
      return;
    }

    const task = this.refreshKey(key, context).finally(() => {
      this.inFlight.delete(key);
    });
    this.inFlight.set(key, task);
  }

  private async refreshKey(key: string, context: TextSemanticContext): Promise<void> {
    if (this.mode !== "openai") {
      return;
    }
    if (!this.openAiApiKey) {
      this.lastError = "semantic mode is openai but no API key is configured";
      return;
    }

    try {
      const prompt = buildSemanticPrompt(context, this.maxCandidates);
      const payload = {
        model: this.openAiModel,
        temperature: 0.7,
        response_format: { type: "json_object" as const },
        messages: [
          {
            role: "system",
            content:
              "You generate concise cinematic lines for a participatory live film. Output valid JSON only."
          },
          {
            role: "user",
            content: prompt
          }
        ]
      };

      const abort = new AbortController();
      const timeout = setTimeout(() => abort.abort(), this.timeoutMs);
      const response = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${this.openAiApiKey}`
        },
        body: JSON.stringify(payload),
        signal: abort.signal
      });
      clearTimeout(timeout);

      if (!response.ok) {
        const text = await response.text();
        throw new Error(`openai request failed (${response.status}): ${text.slice(0, 240)}`);
      }

      const decoded = (await response.json()) as Record<string, unknown>;
      const assistantText = extractAssistantText(decoded);
      if (!assistantText) {
        throw new Error("openai response did not include assistant content");
      }

      let candidateSource: unknown = assistantText;
      try {
        candidateSource = JSON.parse(assistantText);
      } catch {
        // Keep raw string; parser below can still fail with a clear error.
      }

      const candidates = this.parseCandidates(candidateSource, context);
      if (candidates.length === 0) {
        throw new Error("openai semantic generation returned no usable candidates");
      }

      this.cache.set(key, {
        updatedAt: this.now(),
        candidates
      });
      this.lastSuccessAt = this.now();
      this.lastError = null;
      logger.info("text semantic candidates refreshed", {
        mode: this.mode,
        model: this.openAiModel,
        candidateCount: candidates.length
      });
    } catch (error) {
      this.lastError = error instanceof Error ? error.message : "unknown semantic generation error";
      logger.warn("text semantic generation failed", {
        mode: this.mode,
        message: this.lastError
      });
    }
  }

  private parseCandidates(source: unknown, context: TextSemanticContext): ScriptCandidate[] {
    const rawCandidates = extractCandidateArray(source);
    if (rawCandidates.length === 0 && typeof source === "string") {
      const parsed = source
        .split(/\r?\n/)
        .map((line) => line.trim())
        .filter((line) => line.length > 0)
        .map((line) => ({ text: line }));
      return this.normalizeCandidates(parsed, context);
    }
    return this.normalizeCandidates(rawCandidates, context);
  }

  private normalizeCandidates(source: unknown[], context: TextSemanticContext): ScriptCandidate[] {
    const dedupe = new Set<string>();
    const seedBase = stableHashToSeed(
      `${context.cueId}:${Math.round(context.strictRatio * 100)}:${context.pickLabel}`
    );
    const normalized: ScriptCandidate[] = [];

    for (let index = 0; index < source.length && normalized.length < this.maxCandidates; index += 1) {
      const entry = source[index];
      let textValue = "";
      let weightValue = 0.7;

      if (typeof entry === "string") {
        textValue = entry;
      } else if (entry && typeof entry === "object" && !Array.isArray(entry)) {
        const record = entry as Record<string, unknown>;
        if (typeof record.text === "string") {
          textValue = record.text;
        } else if (typeof record.line === "string") {
          textValue = record.line;
        }
        weightValue = clamp01(parseNumber(record.weight) ?? 0.7);
      } else {
        continue;
      }

      const text = sanitizeLine(textValue);
      if (text.length < 12 || text.length > 260 || !passesGuardrails(text)) {
        continue;
      }

      const key = text.toLowerCase();
      if (dedupe.has(key)) {
        continue;
      }
      dedupe.add(key);

      const idSeed = seedBase + index * 31;
      normalized.push({
        id: `sem-${idSeed.toString(16)}-${index}`,
        text,
        weight: clamp01(Math.max(0.35, weightValue))
      });
    }

    return normalized;
  }

  private cacheKey(context: TextSemanticContext): string {
    const cueBucket = context.cueId.split(":").slice(0, 2).join(":");
    const textBucket = Math.round(context.vector.textAmount * 10);
    const biasBucket = Math.round(context.vector.compositeBias * 10);
    const strictBucket = Math.round(context.strictRatio * 10);
    const pick = context.pickLabel.trim().toLowerCase();
    return `${cueBucket}:${strictBucket}:${textBucket}:${biasBucket}:${pick}`;
  }
}

const normalizeSecret = (value: string | null | undefined): string | null => {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
};

const normalizeModel = (value: string | null | undefined): string =>
  typeof value === "string" && value.trim().length > 0 ? value.trim() : "gpt-4.1-mini";

const collectExamples = (bank: ScriptCandidate[], count: number): string[] =>
  bank
    .slice(0, count)
    .map((entry) => sanitizeLine(entry.text))
    .filter((line) => line.length > 0);

const buildSemanticPrompt = (context: TextSemanticContext, maxCandidates: number): string => {
  const strictExamples = collectExamples(context.strictBank, 6);
  const looseExamples = collectExamples(context.looseBank, 6);

  return [
    "Return JSON in this exact shape:",
    '{"candidates":[{"text":"string","weight":0.0}]}',
    "",
    "Constraints:",
    "- First-person intimate tone, concise, cinematic.",
    "- Avoid therapy / trauma / transcendence / savior / tech-hype language.",
    "- No mention of prompts, AI, model, or instructions.",
    "- Keep each line between 12 and 180 characters.",
    "",
    `Context cueId: ${context.cueId}`,
    `Context pickLabel: ${context.pickLabel || "none"}`,
    `Context strictRatio: ${context.strictRatio.toFixed(2)}`,
    `Vector text/composite/audio: ${context.vector.textAmount.toFixed(2)} / ${context.vector.compositeBias.toFixed(2)} / ${context.vector.audioGain.toFixed(2)}`,
    "",
    `Generate ${maxCandidates} candidates total.`,
    "",
    "Strict corpus examples:",
    ...strictExamples.map((line) => `- ${line}`),
    "",
    "Loose corpus examples:",
    ...looseExamples.map((line) => `- ${line}`)
  ].join("\n");
};
