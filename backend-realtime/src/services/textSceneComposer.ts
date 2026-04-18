import {
  clamp01,
  stableHashToSeed,
  type AudioFeaturePayload,
  type CrowdPickResultPayload,
  type ParamVector,
  type TextSceneLine,
  type TextScenePayload
} from "@conductor/protocol";
import fs from "node:fs";
import {
  type TextDirectorModelHealth,
  type TextDirectorModelRuntime,
  type TextDirectorPrediction
} from "./textDirectorModel";
import {
  type TextSemanticGeneratorRuntime,
  type TextSemanticGeneratorStatus,
  type TextSemanticMode
} from "./textSemanticGenerator";
import { logger } from "../utils/logger";

export interface ScriptCandidate {
  id: string;
  text: string;
  weight: number;
}

interface GeneratedScenePool {
  generatedAt: number;
  candidates: ScriptCandidate[];
}

interface CandidateScoreEntry {
  candidate: ScriptCandidate;
  score: number;
  prediction: TextDirectorPrediction | null;
}

interface TextBankRuntimeOptions {
  combinedPath?: string | null;
  strictPath?: string | null;
  loosePath?: string | null;
  refreshMs?: number;
}

interface TextSceneComposerServiceOptions {
  now?: () => number;
  bankRuntime?: TextBankRuntimeOptions;
  modelRuntime?: TextDirectorModelRuntime;
  semanticRuntime?: TextSemanticGeneratorRuntime;
}

type TextBankSource = "combined" | "strict" | "loose";

interface BankSourceState {
  path: string | null;
  lastMtimeMs: number | null;
  lastWarning: string | null;
}

export interface TextRuntimeStatus {
  updatedAt: number;
  strictCount: number;
  looseCount: number;
  strictSource: string;
  looseSource: string;
  warnings: string[];
  modelHealth: TextDirectorModelHealth | null;
  semantic: TextSemanticGeneratorStatus | null;
}

const defaultStrictScriptBank: ScriptCandidate[] = [
  { id: "line-1", text: "The cyan night opened and each phone became a tuning fork.", weight: 0.84 },
  { id: "line-2", text: "Every tilt reshaped the choir of screens into one shared breath.", weight: 0.76 },
  { id: "line-3", text: "You are not watching the piece. You are one of its vectors.", weight: 0.91 },
  { id: "line-4", text: "The hall keeps remembering what the crowd just decided.", weight: 0.79 },
  { id: "line-5", text: "A signal becomes a sentence the moment we choose together.", weight: 0.82 }
];

const defaultLooseSourceBank: ScriptCandidate[] = [
  { id: "loose-1", text: "Bring your thumb to the edge and the frame starts breathing.", weight: 0.68 },
  { id: "loose-2", text: "We borrow the room’s pulse and print it as temporary weather.", weight: 0.66 },
  { id: "loose-3", text: "A chorus can be statistical and still feel like a body.", weight: 0.72 },
  { id: "loose-4", text: "No single screen leads, but all of them bend the horizon.", weight: 0.7 },
  { id: "loose-5", text: "The cut becomes a vote, then a tremor, then a sentence.", weight: 0.74 }
];

const rewriteLexicon: Record<string, string[]> = {
  cyan: ["indigo", "electric", "midnight"],
  phone: ["device", "handset", "screen"],
  screens: ["signals", "panels", "frames"],
  crowd: ["audience", "assembly", "field"],
  chose: ["called", "voted", "selected"],
  decided: ["voted", "selected", "resolved"],
  signal: ["pulse", "tone", "wave"],
  sentence: ["phrase", "line", "utterance"],
  choose: ["vote", "select", "call"],
  together: ["in chorus", "as one", "in phase"],
  watching: ["observing", "tracking", "measuring"],
  vectors: ["coordinates", "currents", "directions"],
  breath: ["rhythm", "tempo", "current"]
};

const bannedTextPatterns: RegExp[] = [
  /\bjourney\b/i,
  /\bgrowth\b/i,
  /\bhealing\b/i,
  /\btherapy\b/i,
  /\btrauma\b/i,
  /\btranscend/i,
  /\bsavior\b/i
];

const fallbackAudioFeatures: AudioFeaturePayload = {
  rms: 0,
  spectralCentroid: 0.5,
  flux: 0.5,
  transientDensity: 0,
  updatedAt: 0
};

const defaultScene: TextScenePayload = {
  sceneVersion: 0,
  pickEpoch: 0,
  cueId: "idle:0",
  anchor: "center-center",
  lineCount: 1,
  cutMode: "hold",
  alpha: 0.84,
  fontScale: 1,
  weight: 0.62,
  durationMs: 4600,
  lines: [],
  guardrails: {
    maxOffsetX: 0.08,
    maxOffsetY: 0.06,
    minContrast: 4.5,
    minDurationMs: 2400
  }
};

export class TextSceneComposerService {
  private sceneVersion = 0;
  private currentScene: TextScenePayload = defaultScene;
  private readonly generatedPoolCache = new Map<string, GeneratedScenePool>();
  private strictScriptBank: ScriptCandidate[] = [...defaultStrictScriptBank];
  private looseSourceBank: ScriptCandidate[] = [...defaultLooseSourceBank];
  private strictSourceLabel = "default:strict";
  private looseSourceLabel = "default:loose";

  private readonly now: () => number;
  private readonly modelRuntime?: TextDirectorModelRuntime;
  private readonly semanticRuntime?: TextSemanticGeneratorRuntime;
  private readonly bankRefreshMs: number;
  private lastBankCheckAt = 0;
  private readonly bankSourceState: Record<TextBankSource, BankSourceState>;

  constructor(options: TextSceneComposerServiceOptions = {}) {
    this.now = options.now ?? Date.now;
    this.modelRuntime = options.modelRuntime;
    this.semanticRuntime = options.semanticRuntime;
    this.bankRefreshMs = Math.max(250, options.bankRuntime?.refreshMs ?? 3_000);
    this.bankSourceState = {
      combined: {
        path: normalizePath(options.bankRuntime?.combinedPath),
        lastMtimeMs: null,
        lastWarning: null
      },
      strict: {
        path: normalizePath(options.bankRuntime?.strictPath),
        lastMtimeMs: null,
        lastWarning: null
      },
      loose: {
        path: normalizePath(options.bankRuntime?.loosePath),
        lastMtimeMs: null,
        lastWarning: null
      }
    };
    this.refreshExternalResources(true);
  }

  snapshot(): TextScenePayload {
    return this.currentScene;
  }

  scriptBankSnapshot(): { strict: ScriptCandidate[]; loose: ScriptCandidate[] } {
    return {
      strict: [...this.strictScriptBank],
      loose: [...this.looseSourceBank]
    };
  }

  modelHealth(): TextDirectorModelHealth | null {
    return this.modelRuntime?.health() ?? null;
  }

  runtimeStatus(): TextRuntimeStatus {
    const warnings = Object.values(this.bankSourceState)
      .map((entry) => entry.lastWarning)
      .filter((warning): warning is string => typeof warning === "string" && warning.length > 0);

    return {
      updatedAt: this.now(),
      strictCount: this.strictScriptBank.length,
      looseCount: this.looseSourceBank.length,
      strictSource: this.strictSourceLabel,
      looseSource: this.looseSourceLabel,
      warnings,
      modelHealth: this.modelRuntime?.health() ?? null,
      semantic: this.semanticRuntime?.status() ?? null
    };
  }

  setRuntimeScriptBanks(input: {
    strictCandidates?: Array<Partial<ScriptCandidate>>;
    looseCandidates?: Array<Partial<ScriptCandidate>>;
    sourceLabel?: string;
  }): { ok: boolean; warnings: string[] } {
    const warnings: string[] = [];
    const source = normalizePath(input.sourceLabel) ?? "runtime";

    if (input.strictCandidates) {
      const parsed = this.parseCandidates(input.strictCandidates, "strict", `${source}:strict`);
      if (parsed.length > 0) {
        this.strictScriptBank = parsed;
        this.strictSourceLabel = `${source}:strict`;
      } else {
        warnings.push("strict candidate list contained no usable lines");
      }
    }

    if (input.looseCandidates) {
      const parsed = this.parseCandidates(input.looseCandidates, "loose", `${source}:loose`);
      if (parsed.length > 0) {
        this.looseSourceBank = parsed;
        this.looseSourceLabel = `${source}:loose`;
      } else {
        warnings.push("loose candidate list contained no usable lines");
      }
    }

    if (warnings.length > 0) {
      logger.warn("runtime script bank update warnings", {
        source,
        warnings
      });
    } else if (input.strictCandidates || input.looseCandidates) {
      logger.info("runtime script banks updated", {
        source,
        strictCount: this.strictScriptBank.length,
        looseCount: this.looseSourceBank.length
      });
    }

    return {
      ok: warnings.length === 0,
      warnings
    };
  }

  setRuntimeModelPayload(
    payload: unknown,
    sourceLabel = "runtime"
  ): { ok: true } | { ok: false; reason: string } {
    if (!this.modelRuntime) {
      return { ok: false, reason: "model runtime is not configured" };
    }
    return this.modelRuntime.setInlineModel(payload, sourceLabel);
  }

  setSemanticMode(mode: TextSemanticMode): void {
    this.semanticRuntime?.configure({ mode });
  }

  configureSemanticRuntime(input: {
    mode?: TextSemanticMode;
    openAiApiKey?: string | null;
    openAiModel?: string;
  }): void {
    this.semanticRuntime?.configure(input);
  }

  reloadScriptBanks(force = true): void {
    this.refreshScriptBanks(force);
  }

  reloadModelRuntime(force = true): void {
    this.modelRuntime?.refresh(force);
  }

  compose(input: {
    cueId: string;
    vector: Partial<ParamVector>;
    audioFeatures?: AudioFeaturePayload;
    pickResult?: CrowdPickResultPayload | null;
    pickEpoch?: number;
    textBlend?: { probability?: number; strictRatio?: number };
  }): TextScenePayload {
    this.refreshExternalResources(false);

    const vector = this.normalizeVector(input.vector);
    const audio = input.audioFeatures ?? fallbackAudioFeatures;
    const pickLabel = input.pickResult?.winnerLabel?.toLowerCase() ?? "";
    const textProbability = clamp01(input.textBlend?.probability ?? vector.textAmount);
    const strictRatio = clamp01(input.textBlend?.strictRatio ?? 0.5);
    const looseRatio = clamp01(1 - strictRatio);

    const generatedPool = this.getGeneratedPool({
      cueId: input.cueId,
      pickEpoch: input.pickEpoch ?? 0,
      vector,
      pickLabel,
      strictRatio
    });

    const strictScored = this.strictScriptBank
      .map((candidate) =>
        this.scoreStrictCandidate(candidate, {
          cueId: input.cueId,
          pickLabel,
          strictRatio,
          vector,
          audio
        })
      )
      .sort((lhs, rhs) => rhs.score - lhs.score);

    const looseScored = [...generatedPool, ...this.looseSourceBank]
      .map((candidate) =>
        this.scoreLooseCandidate(candidate, {
          cueId: input.cueId,
          pickLabel,
          looseRatio,
          vector,
          audio
        })
      )
      .sort((lhs, rhs) => rhs.score - lhs.score);

    const requestedLineCount = textProbability < 0.08 ? 0 : this.decideLineCount(vector, audio, pickLabel);
    const blendCounts = this.allocateBlendCounts(requestedLineCount, strictRatio);

    const strictSelected = strictScored.slice(0, blendCounts.strict);
    const looseSelected = looseScored.slice(0, blendCounts.loose);
    const selected = [...strictSelected, ...looseSelected];
    const lines = selected.map((entry, index) =>
      this.buildSceneLine(entry.candidate, {
        cueId: input.cueId,
        sceneVersion: this.sceneVersion + 1,
        lineIndex: index,
        pickEpoch: input.pickEpoch ?? 0
      })
    );

    const cutMode = this.decideCutMode(audio, pickLabel);
    const anchor = this.decideAnchor(pickLabel);
    const heuristicDurationMs = Math.max(
      defaultScene.guardrails.minDurationMs,
      Math.round(2200 + 4200 * (0.28 + textProbability * 0.36 + audio.rms * 0.36))
    );
    const heuristicAlpha = clamp01((0.42 + vector.compositeBias * 0.36) * textProbability);
    const heuristicFontScale = 0.8 + vector.textAmount * 0.55;
    const heuristicWeight = clamp01(
      0.33 + vector.compositeBias * 0.42 + audio.transientDensity * 0.15 + looseRatio * 0.1
    );

    const modelStyle = this.deriveModelStyle(selected.map((entry) => entry.prediction));
    const durationMs = modelStyle
      ? Math.max(
          defaultScene.guardrails.minDurationMs,
          Math.round(heuristicDurationMs * 0.62 + modelStyle.durationMs * 0.38)
        )
      : heuristicDurationMs;
    const alpha = modelStyle
      ? clamp01((heuristicAlpha * 0.7 + modelStyle.alpha * 0.3) * (0.75 + textProbability * 0.25))
      : heuristicAlpha;
    const fontScale = modelStyle
      ? clamp01Number(heuristicFontScale * 0.65 + modelStyle.fontScale * 0.35, 0.65, 1.75)
      : heuristicFontScale;
    const weight = modelStyle
      ? clamp01(heuristicWeight * 0.65 + modelStyle.weight * 0.35)
      : heuristicWeight;

    this.sceneVersion += 1;
    this.currentScene = {
      sceneVersion: this.sceneVersion,
      pickEpoch: input.pickEpoch ?? 0,
      cueId: input.cueId,
      anchor,
      lineCount: lines.length,
      cutMode,
      alpha,
      fontScale,
      weight,
      durationMs,
      lines,
      guardrails: {
        maxOffsetX: 0.08,
        maxOffsetY: 0.06,
        minContrast: 4.5,
        minDurationMs: 2400
      }
    };

    return this.currentScene;
  }

  private refreshExternalResources(force: boolean): void {
    this.refreshScriptBanks(force);
    this.modelRuntime?.refresh(force);
  }

  private refreshScriptBanks(force: boolean): void {
    const hasAnySource = Object.values(this.bankSourceState).some((entry) => Boolean(entry.path));
    if (!hasAnySource) {
      return;
    }

    const now = this.now();
    if (!force && now - this.lastBankCheckAt < this.bankRefreshMs) {
      return;
    }
    this.lastBankCheckAt = now;

    const combinedLoaded = this.loadCombinedBankIfChanged(force);
    if (combinedLoaded.strict && combinedLoaded.strict.length > 0) {
      this.strictScriptBank = combinedLoaded.strict;
      this.strictSourceLabel = `combined:${this.bankSourceState.combined.path ?? "unknown"}:strict`;
    }
    if (combinedLoaded.loose && combinedLoaded.loose.length > 0) {
      this.looseSourceBank = combinedLoaded.loose;
      this.looseSourceLabel = `combined:${this.bankSourceState.combined.path ?? "unknown"}:loose`;
    }

    const strictLoaded = this.loadSingleBankIfChanged("strict", force);
    if (strictLoaded && strictLoaded.length > 0) {
      this.strictScriptBank = strictLoaded;
      this.strictSourceLabel = `file:${this.bankSourceState.strict.path ?? "unknown"}`;
    }

    const looseLoaded = this.loadSingleBankIfChanged("loose", force);
    if (looseLoaded && looseLoaded.length > 0) {
      this.looseSourceBank = looseLoaded;
      this.looseSourceLabel = `file:${this.bankSourceState.loose.path ?? "unknown"}`;
    }
  }

  private loadCombinedBankIfChanged(force: boolean): { strict?: ScriptCandidate[]; loose?: ScriptCandidate[] } {
    const source = this.bankSourceState.combined;
    if (!source.path) {
      return {};
    }

    const loaded = this.readSourceIfChanged("combined", source.path, force);
    if (loaded === null) {
      return {};
    }

    let parsed: unknown;
    try {
      parsed = JSON.parse(loaded.raw);
    } catch (error) {
      const message = error instanceof Error ? error.message : "unknown parse error";
      this.warnSource("combined", `invalid JSON in combined script bank: ${message}`);
      return {};
    }

    const strictValue = extractScriptBankCandidateSource(parsed, "strict");
    const looseValue = extractScriptBankCandidateSource(parsed, "loose");
    const strict = strictValue ? this.parseCandidates(strictValue, "strict", "combined:strict") : [];
    const loose = looseValue ? this.parseCandidates(looseValue, "loose", "combined:loose") : [];

    if (strict.length === 0 && loose.length === 0) {
      this.warnSource("combined", "combined script bank did not contain strict/loose candidate arrays");
      return {};
    }

    this.clearSourceWarning("combined");
    logger.info("text script bank reloaded", {
      source: "combined",
      path: loaded.path,
      strictCount: strict.length,
      looseCount: loose.length
    });
    return {
      strict: strict.length > 0 ? strict : undefined,
      loose: loose.length > 0 ? loose : undefined
    };
  }

  private loadSingleBankIfChanged(sourceKey: "strict" | "loose", force: boolean): ScriptCandidate[] | null {
    const source = this.bankSourceState[sourceKey];
    if (!source.path) {
      return null;
    }

    const loaded = this.readSourceIfChanged(sourceKey, source.path, force);
    if (loaded === null) {
      return null;
    }

    const parsed = this.parseScriptBankSource(loaded.raw, sourceKey, loaded.path);
    if (parsed.length === 0) {
      this.warnSource(sourceKey, `${sourceKey} bank at ${loaded.path} resolved to zero usable lines`);
      return null;
    }

    this.clearSourceWarning(sourceKey);
    logger.info("text script bank reloaded", {
      source: sourceKey,
      path: loaded.path,
      lineCount: parsed.length
    });
    return parsed;
  }

  private readSourceIfChanged(
    sourceKey: TextBankSource,
    path: string,
    force: boolean
  ): { raw: string; path: string } | null {
    const sourceState = this.bankSourceState[sourceKey];
    let stat: fs.Stats;
    try {
      stat = fs.statSync(path);
    } catch (error) {
      const message = error instanceof Error ? error.message : "unknown stat error";
      this.warnSource(sourceKey, `${sourceKey} script bank unavailable: ${message}`);
      return null;
    }

    if (!force && sourceState.lastMtimeMs !== null && stat.mtimeMs === sourceState.lastMtimeMs) {
      return null;
    }

    try {
      const raw = fs.readFileSync(path, "utf8");
      sourceState.lastMtimeMs = stat.mtimeMs;
      return { raw, path };
    } catch (error) {
      const message = error instanceof Error ? error.message : "unknown read error";
      this.warnSource(sourceKey, `${sourceKey} script bank read failed: ${message}`);
      return null;
    }
  }

  private parseScriptBankSource(raw: string, prefix: "strict" | "loose", sourceLabel: string): ScriptCandidate[] {
    const trimmed = raw.trim();
    if (trimmed.length === 0) {
      return [];
    }

    if (trimmed.startsWith("{") || trimmed.startsWith("[")) {
      try {
        const parsed = JSON.parse(trimmed);
        const candidateSource = extractScriptBankCandidateSource(parsed, prefix) ?? parsed;
        return this.parseCandidates(candidateSource, prefix, sourceLabel);
      } catch (error) {
        const message = error instanceof Error ? error.message : "unknown parse error";
        this.warnSource(prefix, `${prefix} script bank JSON parse failed (${sourceLabel}): ${message}`);
      }
    }

    return this.parseTextLines(raw, prefix);
  }

  private parseCandidates(
    source: unknown,
    prefix: "strict" | "loose",
    sourceLabel: string
  ): ScriptCandidate[] {
    if (!Array.isArray(source)) {
      return [];
    }

    const candidates: ScriptCandidate[] = [];
    const seenText = new Set<string>();
    for (let index = 0; index < source.length; index += 1) {
      const candidate = source[index];
      const parsed = this.parseCandidateEntry(candidate, prefix, index);
      if (!parsed) {
        continue;
      }
      const key = parsed.text.toLowerCase();
      if (seenText.has(key)) {
        continue;
      }
      seenText.add(key);
      candidates.push(parsed);
    }

    if (candidates.length === 0) {
      this.warnSource(prefix, `no valid ${prefix} candidates found in ${sourceLabel}`);
    }
    return candidates;
  }

  private parseCandidateEntry(
    value: unknown,
    prefix: "strict" | "loose",
    index: number
  ): ScriptCandidate | null {
    if (typeof value === "string") {
      const text = this.sanitizeGeneratedText(value);
      if (text.length === 0 || !this.passesGuardrails(text)) {
        return null;
      }
      return {
        id: `${prefix}-${index + 1}`,
        text,
        weight: 0.7
      };
    }

    if (!value || typeof value !== "object" || Array.isArray(value)) {
      return null;
    }

    const record = value as Record<string, unknown>;
    const textValue = record.text ?? record.line ?? record.baseText ?? record.content;
    if (typeof textValue !== "string") {
      return null;
    }
    const text = this.sanitizeGeneratedText(textValue);
    if (text.length === 0 || !this.passesGuardrails(text)) {
      return null;
    }

    const idValue = typeof record.id === "string" ? record.id.trim() : "";
    const weightValue = toFiniteNumber(record.weight);
    return {
      id: idValue.length > 0 ? idValue : `${prefix}-${index + 1}`,
      text,
      weight: clamp01(weightValue ?? 0.7)
    };
  }

  private parseTextLines(raw: string, prefix: "strict" | "loose"): ScriptCandidate[] {
    const lines = raw.split(/\r?\n/);
    const candidates: ScriptCandidate[] = [];
    const seenText = new Set<string>();

    for (let index = 0; index < lines.length; index += 1) {
      const line = lines[index].trim();
      if (line.length === 0 || line.startsWith("#") || line.startsWith("//")) {
        continue;
      }
      const parsed = parseDelimitedLine(line);
      const text = this.sanitizeGeneratedText(parsed.text);
      if (text.length === 0 || !this.passesGuardrails(text)) {
        continue;
      }
      const key = text.toLowerCase();
      if (seenText.has(key)) {
        continue;
      }
      seenText.add(key);
      candidates.push({
        id: parsed.id ?? `${prefix}-${candidates.length + 1}`,
        text,
        weight: clamp01(parsed.weight ?? 0.7)
      });
    }

    return candidates;
  }

  private warnSource(source: TextBankSource, message: string): void {
    const state = this.bankSourceState[source];
    if (state.lastWarning === message) {
      return;
    }
    state.lastWarning = message;
    logger.warn("text bank warning", {
      source,
      message
    });
  }

  private clearSourceWarning(source: TextBankSource): void {
    this.bankSourceState[source].lastWarning = null;
  }

  private scoreStrictCandidate(
    candidate: ScriptCandidate,
    context: {
      cueId: string;
      pickLabel: string;
      strictRatio: number;
      vector: ParamVector;
      audio: AudioFeaturePayload;
    }
  ): CandidateScoreEntry {
    const heuristicScore =
      candidate.weight +
      context.strictRatio * 0.32 +
      context.vector.textAmount * 0.26 +
      context.vector.compositeBias * 0.19 +
      context.audio.rms * 0.15 +
      (context.pickLabel.includes("focus") ? 0.08 : 0);
    const prediction = this.modelRuntime?.predict({
      cueId: context.cueId,
      candidateText: candidate.text,
      candidateWeight: candidate.weight,
      vector: context.vector,
      audio: context.audio
    }) ?? null;

    return {
      candidate,
      score: this.blendWithModelPrediction(heuristicScore, prediction),
      prediction
    };
  }

  private scoreLooseCandidate(
    candidate: ScriptCandidate,
    context: {
      cueId: string;
      pickLabel: string;
      looseRatio: number;
      vector: ParamVector;
      audio: AudioFeaturePayload;
    }
  ): CandidateScoreEntry {
    const heuristicScore =
      candidate.weight +
      context.looseRatio * 0.35 +
      context.vector.compositeBias * 0.21 +
      context.audio.flux * 0.16 +
      context.audio.transientDensity * 0.12 +
      (context.pickLabel.includes("echo") ? 0.08 : 0) +
      (context.pickLabel.includes("scatter") ? 0.08 : 0);
    const prediction = this.modelRuntime?.predict({
      cueId: context.cueId,
      candidateText: candidate.text,
      candidateWeight: candidate.weight,
      vector: context.vector,
      audio: context.audio
    }) ?? null;

    return {
      candidate,
      score: this.blendWithModelPrediction(heuristicScore, prediction),
      prediction
    };
  }

  private blendWithModelPrediction(heuristicScore: number, prediction: TextDirectorPrediction | null): number {
    if (!prediction) {
      return heuristicScore;
    }
    return heuristicScore * 0.58 + prediction.score * 0.42;
  }

  private deriveModelStyle(predictions: Array<TextDirectorPrediction | null>): {
    durationMs: number;
    alpha: number;
    fontScale: number;
    weight: number;
  } | null {
    const entries = predictions.filter((entry): entry is TextDirectorPrediction => entry !== null);
    if (entries.length === 0) {
      return null;
    }

    const totals = entries.reduce(
      (acc, entry) => {
        acc.duration += entry.displayDuration;
        acc.alpha += entry.compositeAlpha;
        acc.fontSize += entry.fontSize;
        acc.fontWeight += entry.fontWeight;
        return acc;
      },
      { duration: 0, alpha: 0, fontSize: 0, fontWeight: 0 }
    );
    const count = entries.length;
    const avgDurationSec = totals.duration / count;
    const avgFontSize = clamp01(totals.fontSize / count);
    return {
      durationMs: Math.round(clamp01Number(avgDurationSec, 1, 15) * 1_000),
      alpha: clamp01(totals.alpha / count),
      fontScale: clamp01Number(0.65 + avgFontSize * 1.1, 0.65, 1.75),
      weight: clamp01(totals.fontWeight / count)
    };
  }

  private getGeneratedPool(input: {
    cueId: string;
    pickEpoch: number;
    vector: ParamVector;
    pickLabel: string;
    strictRatio: number;
  }): ScriptCandidate[] {
    const cueBucket = input.cueId.split(":").slice(0, 2).join(":");
    const key = `${cueBucket}:${input.pickEpoch}:${Math.round(input.vector.textAmount * 10)}:${Math.round(input.strictRatio * 10)}:${input.pickLabel}`;
    const now = this.now();
    const cached = this.generatedPoolCache.get(key);
    if (cached && now - cached.generatedAt < 70_000) {
      return cached.candidates;
    }

    const generated = this.generateCandidates({
      seed: stableHashToSeed(`${key}:${now >> 12}`),
      pickLabel: input.pickLabel,
      strictRatio: input.strictRatio,
      vector: input.vector
    });
    const semanticGenerated =
      this.semanticRuntime?.suggest({
        cueId: input.cueId,
        pickLabel: input.pickLabel,
        strictRatio: input.strictRatio,
        vector: input.vector,
        strictBank: this.strictScriptBank,
        looseBank: this.looseSourceBank
      }) ?? [];
    const merged = mergeUniqueCandidates([...semanticGenerated, ...generated]);
    this.generatedPoolCache.set(key, {
      generatedAt: now,
      candidates: merged
    });

    if (this.generatedPoolCache.size > 120) {
      const oldest = [...this.generatedPoolCache.entries()].sort((lhs, rhs) => lhs[1].generatedAt - rhs[1].generatedAt)[0];
      if (oldest) {
        this.generatedPoolCache.delete(oldest[0]);
      }
    }

    return merged;
  }

  private generateCandidates(input: {
    seed: number;
    pickLabel: string;
    strictRatio: number;
    vector: ParamVector;
  }): ScriptCandidate[] {
    const subjects = [
      "the frame",
      "the screen edge",
      "the signal band",
      "this room",
      "the current layer",
      "our shared surface"
    ];
    const verbs = ["folds", "tilts", "holds", "cuts", "threads", "drifts", "splits", "cascades"];
    const objects = [
      "into static grain",
      "through a narrow split",
      "toward the center hold",
      "into a colder hue",
      "toward a live seam",
      "through the next cue"
    ];
    const tails = [
      "while everyone watches it settle.",
      "before the room resolves.",
      "and the line keeps moving.",
      "until the vote closes.",
      "and no device leads alone.",
      "while the field keeps score."
    ];

    const emphasis = input.pickLabel.includes("echo")
      ? "Echo stays active."
      : input.pickLabel.includes("scatter")
        ? "Scatter keeps the edges alive."
        : input.pickLabel.includes("focus")
          ? "Focus tightens the center."
          : "The cue stays open.";

    const candidates: ScriptCandidate[] = [];
    for (let index = 0; index < 8; index += 1) {
      const seed = input.seed + index * 37;
      const subject = subjects[seed % subjects.length];
      const verb = verbs[(seed >>> 3) % verbs.length];
      const object = objects[(seed >>> 5) % objects.length];
      const tail = tails[(seed >>> 7) % tails.length];
      const densityHint =
        input.vector.textAmount > 0.62 ? "Keep speaking inside the frame." : "Hold the line short.";
      const text = this.sanitizeGeneratedText(
        `${subject} ${verb} ${object} ${tail} ${emphasis} ${densityHint}`
      );
      if (!this.passesGuardrails(text)) {
        continue;
      }
      candidates.push({
        id: `gen-${seed.toString(16)}-${index}`,
        text,
        weight: clamp01(0.55 + input.strictRatio * 0.2 + (seed % 100) / 1000)
      });
    }

    return candidates.slice(0, 6);
  }

  private sanitizeGeneratedText(text: string): string {
    return text
      .replace(/\s+/g, " ")
      .replace(/\.{2,}/g, ".")
      .replace(/\s+([,.;!?])/g, "$1")
      .trim();
  }

  private passesGuardrails(text: string): boolean {
    return !bannedTextPatterns.some((pattern) => pattern.test(text));
  }

  private buildSceneLine(
    candidate: ScriptCandidate,
    context: { cueId: string; sceneVersion: number; lineIndex: number; pickEpoch: number }
  ): TextSceneLine {
    const variants = this.generateConstrainedVariants(candidate.text, context);
    return {
      id: candidate.id,
      baseText: candidate.text,
      variants
    };
  }

  private generateConstrainedVariants(
    source: string,
    context: { cueId: string; sceneVersion: number; lineIndex: number; pickEpoch: number }
  ): string[] {
    const words = source.split(/\s+/);
    const candidateIndexes = words
      .map((word, index) => ({ index, key: sanitizeToken(word) }))
      .filter((item) => rewriteLexicon[item.key] && rewriteLexicon[item.key].length > 0);

    if (candidateIndexes.length === 0) {
      return [source];
    }

    const seedBase = stableHashToSeed(
      `${context.cueId}:${context.sceneVersion}:${context.pickEpoch}:${context.lineIndex}`
    );
    const variants = new Set<string>([source]);

    for (let variantIndex = 0; variantIndex < 4; variantIndex += 1) {
      const seed = seedBase + variantIndex * 131;
      const mutateCount = 1 + (seed % 3);
      const mutable = [...candidateIndexes];
      const clone = [...words];

      for (let mutation = 0; mutation < mutateCount && mutable.length > 0; mutation += 1) {
        const pick = (seed + mutation * 17) % mutable.length;
        const { index, key } = mutable.splice(pick, 1)[0];
        const options = rewriteLexicon[key] ?? [];
        if (options.length === 0) {
          continue;
        }
        const option = options[(seed + mutation * 23) % options.length];
        clone[index] = preservePunctuation(clone[index], option);
      }

      variants.add(clone.join(" "));
    }

    return [...variants].slice(0, 4);
  }

  private decideLineCount(
    vector: ParamVector,
    audio: AudioFeaturePayload,
    pickLabel: string
  ): number {
    const score = vector.textAmount * 0.5 + audio.rms * 0.35 + audio.transientDensity * 0.15;
    if (pickLabel.includes("chorus")) {
      return 3;
    }
    if (score > 0.72) {
      return 3;
    }
    if (score > 0.45) {
      return 2;
    }
    return 1;
  }

  private allocateBlendCounts(lineCount: number, strictRatio: number): { strict: number; loose: number } {
    if (lineCount <= 0) {
      return { strict: 0, loose: 0 };
    }
    if (lineCount === 1) {
      return strictRatio >= 0.5 ? { strict: 1, loose: 0 } : { strict: 0, loose: 1 };
    }

    const targetStrict = Math.round(lineCount * strictRatio);
    const strict = Math.min(lineCount - 1, Math.max(1, targetStrict));
    return {
      strict,
      loose: lineCount - strict
    };
  }

  private decideCutMode(audio: AudioFeaturePayload, pickLabel: string): TextScenePayload["cutMode"] {
    if (pickLabel.includes("echo") || audio.flux > 0.62) {
      return "crossfade";
    }
    if (pickLabel.includes("scatter") || audio.transientDensity > 0.58) {
      return "stutter";
    }
    return "hold";
  }

  private decideAnchor(pickLabel: string): TextScenePayload["anchor"] {
    if (pickLabel.includes("scatter")) {
      return "center-left";
    }
    if (pickLabel.includes("focus")) {
      return "center-center";
    }
    if (pickLabel.includes("echo")) {
      return "lower-center";
    }
    return "center-center";
  }

  private normalizeVector(vector: Partial<ParamVector>): ParamVector {
    return {
      textAmount: clamp01(vector.textAmount ?? 0),
      compositeBias: clamp01(vector.compositeBias ?? 0.5),
      audioGain: clamp01(vector.audioGain ?? 0.5),
      spatialX: clamp01(vector.spatialX ?? 0.5),
      spatialY: clamp01(vector.spatialY ?? 0.5),
      spatialZ: clamp01(vector.spatialZ ?? 0.5)
    };
  }
}

const sanitizeToken = (token: string): string =>
  token.toLowerCase().replace(/^[^a-z0-9]+|[^a-z0-9]+$/gi, "");

const preservePunctuation = (original: string, replacement: string): string => {
  const leading = original.match(/^[^a-z0-9]*/i)?.[0] ?? "";
  const trailing = original.match(/[^a-z0-9]*$/i)?.[0] ?? "";
  const isCapitalized = /^[A-Z]/.test(original);
  const next = isCapitalized
    ? `${replacement.charAt(0).toUpperCase()}${replacement.slice(1)}`
    : replacement;
  return `${leading}${next}${trailing}`;
};

const normalizePath = (value: string | null | undefined): string | null => {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
};

const parseDelimitedLine = (line: string): { id?: string; weight?: number; text: string } => {
  const tokens = line.split("|").map((token) => token.trim());
  if (tokens.length >= 3 && tokens[1]) {
    const weight = toFiniteNumber(tokens[1]);
    if (weight !== null) {
      return {
        id: tokens[0] || undefined,
        weight,
        text: tokens.slice(2).join(" | ")
      };
    }
  }
  if (tokens.length >= 2) {
    const weight = toFiniteNumber(tokens[0]);
    if (weight !== null) {
      return {
        weight,
        text: tokens.slice(1).join(" | ")
      };
    }
    return {
      id: tokens[0] || undefined,
      text: tokens.slice(1).join(" | ")
    };
  }
  return { text: line };
};

const toFiniteNumber = (value: unknown): number | null =>
  typeof value === "number"
    ? Number.isFinite(value)
      ? value
      : null
    : typeof value === "string" && value.trim().length > 0
      ? Number.isFinite(Number(value))
        ? Number(value)
        : null
      : null;

const clamp01Number = (value: number, min: number, max: number): number =>
  Math.max(min, Math.min(max, value));

const mergeUniqueCandidates = (candidates: ScriptCandidate[]): ScriptCandidate[] => {
  const seen = new Set<string>();
  const merged: ScriptCandidate[] = [];
  for (const candidate of candidates) {
    const key = sanitizeGenerated(candidate.text);
    if (!key || seen.has(key)) {
      continue;
    }
    seen.add(key);
    merged.push(candidate);
  }
  return merged;
};

const sanitizeGenerated = (value: string): string =>
  value
    .trim()
    .toLowerCase()
    .replace(/\s+/g, " ");

const extractScriptBankCandidateSource = (
  value: unknown,
  bank: "strict" | "loose"
): unknown[] | null => {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }

  const record = value as Record<string, unknown>;
  const directKeys =
    bank === "strict"
      ? ["strict", "strictScriptBank", "strictBank", "strictLines"]
      : ["loose", "looseSourceBank", "looseBank", "looseLines"];

  for (const key of directKeys) {
    if (Array.isArray(record[key])) {
      return record[key] as unknown[];
    }
  }

  if (record.banks && typeof record.banks === "object" && !Array.isArray(record.banks)) {
    const nested = record.banks as Record<string, unknown>;
    for (const key of directKeys) {
      if (Array.isArray(nested[key])) {
        return nested[key] as unknown[];
      }
    }
  }

  if (Array.isArray(record.candidates)) {
    return record.candidates as unknown[];
  }
  if (Array.isArray(record.lines)) {
    return record.lines as unknown[];
  }

  return null;
};
