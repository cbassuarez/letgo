import { clamp01, type AudioFeaturePayload, type ParamVector } from "@conductor/protocol";
import fs from "node:fs";
import { logger } from "../utils/logger";

export const TEXT_DIRECTOR_FEATURE_ORDER = [
  "weight",
  "arc",
  "textLength",
  "textAmount",
  "compositeBias",
  "audioGain",
  "spatialX",
  "spatialY",
  "spatialZ",
  "isMain",
  "audioRMS",
  "audioSpectralCentroid",
  "videoLuminance",
  "videoMotion"
] as const;

export type TextDirectorFeatureName = (typeof TEXT_DIRECTOR_FEATURE_ORDER)[number];

const requiredOutputs = [
  "score",
  "displayDuration",
  "compositeAlpha",
  "fontSize",
  "fontWeight"
] as const;

type TextDirectorOutputName = (typeof requiredOutputs)[number];

interface TextDirectorLinearOutputConfig {
  intercept: number;
  coefficients: number[];
  min?: number;
  max?: number;
}

export interface TextDirectorLinearModelV1 {
  kind: "text-director-linear-v1";
  version: string;
  featureOrder: TextDirectorFeatureName[];
  outputs: Record<TextDirectorOutputName, TextDirectorLinearOutputConfig>;
  metadata?: Record<string, unknown>;
}

export interface TextDirectorModelHealth {
  active: boolean;
  summary: string;
  modelPath: string | null;
  source: "none" | "path" | "inline";
  sourceLabel?: string | null;
  version?: string | null;
  lastLoadedAt: number | null;
  runtimeFailures: number;
}

export interface TextDirectorRuntimeInput {
  cueId: string;
  candidateText: string;
  candidateWeight: number;
  vector: ParamVector;
  audio: AudioFeaturePayload;
}

export interface TextDirectorPrediction {
  score: number;
  displayDuration: number;
  compositeAlpha: number;
  fontSize: number;
  fontWeight: number;
}

interface TextDirectorModelRuntimeOptions {
  modelPath?: string | null;
  refreshMs?: number;
  now?: () => number;
}

interface ParsedOutputModel {
  output: TextDirectorOutputName;
  config: TextDirectorLinearOutputConfig;
}

const defaultOutputRanges: Record<TextDirectorOutputName, { min: number; max: number }> = {
  score: { min: 0, max: 1 },
  displayDuration: { min: 1, max: 15 },
  compositeAlpha: { min: 0, max: 1 },
  fontSize: { min: 0, max: 1 },
  fontWeight: { min: 0, max: 1 }
};

const parseFinite = (value: unknown): number | null =>
  typeof value === "number" && Number.isFinite(value) ? value : null;

const clampByRange = (value: number, min: number, max: number): number =>
  Math.max(min, Math.min(max, value));

const arcFromCueId = (cueId: string): number => {
  const normalized = cueId.toLowerCase();
  if (normalized.includes("preshow") || normalized.includes("introduction")) {
    return 1;
  }
  if (normalized.includes("ending")) {
    return 3;
  }
  return 2;
};

export class TextDirectorModelRuntime {
  private readonly modelPath: string | null;
  private readonly refreshMs: number;
  private readonly now: () => number;

  private model: TextDirectorLinearModelV1 | null = null;
  private inlineModel: TextDirectorLinearModelV1 | null = null;
  private inlineSourceLabel: string | null = null;
  private lastCheckedAt = 0;
  private lastLoadedAt: number | null = null;
  private lastLoadedMtimeMs: number | null = null;
  private runtimeFailures = 0;
  private lastError: string | null = null;

  constructor(options: TextDirectorModelRuntimeOptions = {}) {
    this.modelPath = normalizePath(options.modelPath);
    this.refreshMs = Math.max(250, options.refreshMs ?? 3_000);
    this.now = options.now ?? Date.now;
    this.refresh(true);
  }

  refresh(force = false): void {
    if (!this.modelPath) {
      return;
    }

    const now = this.now();
    if (!force && now - this.lastCheckedAt < this.refreshMs) {
      return;
    }
    this.lastCheckedAt = now;

    let stat: fs.Stats;
    try {
      stat = fs.statSync(this.modelPath);
    } catch (error) {
      const message = error instanceof Error ? error.message : "unknown stat error";
      this.publishError(`model path missing: ${message}`);
      return;
    }

    if (!force && this.lastLoadedMtimeMs !== null && stat.mtimeMs === this.lastLoadedMtimeMs) {
      return;
    }

    let raw: string;
    try {
      raw = fs.readFileSync(this.modelPath, "utf8");
    } catch (error) {
      const message = error instanceof Error ? error.message : "unknown read error";
      this.publishError(`failed reading model file: ${message}`);
      return;
    }

    let parsed: unknown;
    try {
      parsed = JSON.parse(raw);
    } catch (error) {
      const message = error instanceof Error ? error.message : "unknown parse error";
      this.publishError(`invalid model JSON: ${message}`);
      return;
    }

    const validation = validateModelPayload(parsed);
    if (!validation.ok) {
      this.publishError(validation.reason);
      return;
    }

    this.model = validation.model;
    this.lastLoadedAt = now;
    this.lastLoadedMtimeMs = stat.mtimeMs;
    this.lastError = null;
    this.runtimeFailures = 0;
    logger.info("text-director model activated", {
      path: this.modelPath,
      version: validation.model.version,
      featureCount: validation.model.featureOrder.length
    });
  }

  setInlineModel(input: unknown, sourceLabel = "runtime-inline"): { ok: true } | { ok: false; reason: string } {
    const validation = validateModelPayload(input);
    if (!validation.ok) {
      this.publishError(`inline model rejected: ${validation.reason}`);
      return { ok: false, reason: validation.reason };
    }

    this.inlineModel = validation.model;
    this.inlineSourceLabel = sourceLabel;
    this.lastLoadedAt = this.now();
    this.lastError = null;
    this.runtimeFailures = 0;
    logger.info("text-director inline model activated", {
      sourceLabel,
      version: validation.model.version,
      featureCount: validation.model.featureOrder.length
    });
    return { ok: true };
  }

  clearInlineModel(): void {
    this.inlineModel = null;
    this.inlineSourceLabel = null;
  }

  predict(input: TextDirectorRuntimeInput): TextDirectorPrediction | null {
    const model = this.inlineModel ?? this.model;
    if (!model) {
      return null;
    }

    try {
      const featureMap = buildFeatureMap(input);
      const featureValues = model.featureOrder.map((featureName) => featureMap[featureName]);
      const outputs = {} as TextDirectorPrediction;

      for (const output of requiredOutputs) {
        const config = model.outputs[output];
        const score = predictLinear(config.intercept, config.coefficients, featureValues);
        const min = parseFinite(config.min) ?? defaultOutputRanges[output].min;
        const max = parseFinite(config.max) ?? defaultOutputRanges[output].max;
        outputs[output] = clampByRange(score, min, max);
      }

      outputs.score = clamp01(outputs.score);
      return outputs;
    } catch (error) {
      this.runtimeFailures += 1;
      const message = error instanceof Error ? error.message : "unknown inference error";
      this.publishError(`runtime prediction failed: ${message}`);
      return null;
    }
  }

  health(): TextDirectorModelHealth {
    const activeModel = this.inlineModel ?? this.model;
    const activeSource: "none" | "path" | "inline" = this.inlineModel
      ? "inline"
      : this.model
        ? "path"
        : "none";

    if (this.modelPath === null && this.inlineModel === null) {
      return {
        active: false,
        summary: "Text-director model disabled (no path configured).",
        modelPath: null,
        source: "none",
        sourceLabel: null,
        version: null,
        lastLoadedAt: null,
        runtimeFailures: 0
      };
    }

    if (!activeModel) {
      return {
        active: false,
        summary: this.lastError ?? "Text-director model unavailable.",
        modelPath: this.modelPath,
        source: "none",
        sourceLabel: null,
        version: null,
        lastLoadedAt: this.lastLoadedAt,
        runtimeFailures: this.runtimeFailures
      };
    }

    const sourceLabel =
      activeSource === "inline"
        ? (this.inlineSourceLabel ?? "runtime-inline")
        : this.modelPath;
    return {
      active: true,
      summary: "Text-director model active.",
      modelPath: this.modelPath,
      source: activeSource,
      sourceLabel,
      version: activeModel.version,
      lastLoadedAt: this.lastLoadedAt,
      runtimeFailures: this.runtimeFailures
    };
  }

  private publishError(message: string): void {
    if (this.lastError === message) {
      return;
    }
    this.lastError = message;
    logger.warn("text-director model warning", {
      path: this.modelPath,
      message
    });
  }
}

const normalizePath = (path: string | null | undefined): string | null => {
  if (typeof path !== "string") {
    return null;
  }
  const trimmed = path.trim();
  return trimmed.length > 0 ? trimmed : null;
};

const predictLinear = (intercept: number, coefficients: number[], features: number[]): number => {
  let total = intercept;
  const maxLength = Math.min(coefficients.length, features.length);
  for (let index = 0; index < maxLength; index += 1) {
    total += coefficients[index] * features[index];
  }
  return total;
};

const buildFeatureMap = (input: TextDirectorRuntimeInput): Record<TextDirectorFeatureName, number> => {
  const textLength = Math.min(1, Math.max(0, input.candidateText.length / 200));
  const vector = input.vector;
  const audio = input.audio;
  const audioRms = clamp01(audio.rms);
  const audioSpectral = clamp01(audio.spectralCentroid);
  const videoMotion = clamp01(audio.flux * 0.7 + audio.transientDensity * 0.3);
  const videoLuminance = clamp01(vector.compositeBias * 0.6 + vector.audioGain * 0.4);

  return {
    weight: clamp01(input.candidateWeight),
    arc: arcFromCueId(input.cueId),
    textLength,
    textAmount: clamp01(vector.textAmount),
    compositeBias: clamp01(vector.compositeBias),
    audioGain: clamp01(vector.audioGain),
    spatialX: clamp01(vector.spatialX),
    spatialY: clamp01(vector.spatialY),
    spatialZ: clamp01(vector.spatialZ),
    isMain: input.cueId.toLowerCase().includes("main") ? 1 : 0,
    audioRMS: audioRms,
    audioSpectralCentroid: audioSpectral,
    videoLuminance,
    videoMotion
  };
};

const validateModelPayload = (
  value: unknown
): { ok: true; model: TextDirectorLinearModelV1 } | { ok: false; reason: string } => {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return { ok: false, reason: "model payload must be an object" };
  }

  const record = value as Record<string, unknown>;
  if (record.kind !== "text-director-linear-v1") {
    return { ok: false, reason: "unsupported model kind (expected text-director-linear-v1)" };
  }

  const version = typeof record.version === "string" && record.version.trim().length > 0
    ? record.version
    : "0";

  const featureOrder = parseFeatureOrder(record.featureOrder);
  if (!featureOrder.ok) {
    return featureOrder;
  }

  const outputsValue = record.outputs;
  if (!outputsValue || typeof outputsValue !== "object" || Array.isArray(outputsValue)) {
    return { ok: false, reason: "outputs must be an object" };
  }
  const outputsRecord = outputsValue as Record<string, unknown>;
  const parsedOutputs: Partial<Record<TextDirectorOutputName, TextDirectorLinearOutputConfig>> = {};

  for (const output of requiredOutputs) {
    const parsed = parseOutputConfig(output, outputsRecord[output], featureOrder.featureOrder);
    if (!parsed.ok) {
      return parsed;
    }
    parsedOutputs[output] = parsed.config;
  }

  return {
    ok: true,
    model: {
      kind: "text-director-linear-v1",
      version,
      featureOrder: featureOrder.featureOrder,
      outputs: parsedOutputs as Record<TextDirectorOutputName, TextDirectorLinearOutputConfig>,
      metadata:
        record.metadata && typeof record.metadata === "object" && !Array.isArray(record.metadata)
          ? (record.metadata as Record<string, unknown>)
          : undefined
    }
  };
};

const parseFeatureOrder = (
  value: unknown
): { ok: true; featureOrder: TextDirectorFeatureName[] } | { ok: false; reason: string } => {
  if (!Array.isArray(value) || value.length === 0) {
    return { ok: false, reason: "featureOrder must be a non-empty array" };
  }

  const parsed: TextDirectorFeatureName[] = [];
  for (const entry of value) {
    if (typeof entry !== "string") {
      return { ok: false, reason: "featureOrder entries must be strings" };
    }
    if (!TEXT_DIRECTOR_FEATURE_ORDER.includes(entry as TextDirectorFeatureName)) {
      return { ok: false, reason: `unknown feature in featureOrder: ${entry}` };
    }
    parsed.push(entry as TextDirectorFeatureName);
  }

  if (parsed.length !== TEXT_DIRECTOR_FEATURE_ORDER.length) {
    return {
      ok: false,
      reason: `featureOrder length mismatch (expected ${TEXT_DIRECTOR_FEATURE_ORDER.length}, got ${parsed.length})`
    };
  }

  return { ok: true, featureOrder: parsed };
};

const parseOutputConfig = (
  output: TextDirectorOutputName,
  value: unknown,
  featureOrder: TextDirectorFeatureName[]
): { ok: true; config: TextDirectorLinearOutputConfig } | { ok: false; reason: string } => {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return { ok: false, reason: `output ${output} must be an object` };
  }
  const record = value as Record<string, unknown>;

  const intercept = parseFinite(record.intercept);
  if (intercept === null) {
    return { ok: false, reason: `output ${output} requires numeric intercept` };
  }

  let coefficients: number[] = [];
  if (Array.isArray(record.coefficients)) {
    coefficients = record.coefficients.map((entry) => parseFinite(entry) ?? Number.NaN);
  } else if (record.features && typeof record.features === "object" && !Array.isArray(record.features)) {
    const featureMap = record.features as Record<string, unknown>;
    coefficients = featureOrder.map((featureName) => parseFinite(featureMap[featureName]) ?? Number.NaN);
  } else {
    return {
      ok: false,
      reason: `output ${output} requires coefficients array or features object`
    };
  }

  if (coefficients.length !== featureOrder.length) {
    return {
      ok: false,
      reason: `output ${output} coefficient length mismatch (expected ${featureOrder.length}, got ${coefficients.length})`
    };
  }
  if (coefficients.some((entry) => !Number.isFinite(entry))) {
    return { ok: false, reason: `output ${output} has non-finite coefficient values` };
  }

  return {
    ok: true,
    config: {
      intercept,
      coefficients,
      min: parseFinite(record.min) ?? undefined,
      max: parseFinite(record.max) ?? undefined
    }
  };
};
