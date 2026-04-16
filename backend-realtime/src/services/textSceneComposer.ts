import {
  clamp01,
  stableHashToSeed,
  type AudioFeaturePayload,
  type CrowdPickResultPayload,
  type ParamVector,
  type TextSceneLine,
  type TextScenePayload
} from "@conductor/protocol";

interface ScriptCandidate {
  id: string;
  text: string;
  weight: number;
}

interface GeneratedScenePool {
  generatedAt: number;
  candidates: ScriptCandidate[];
}

const strictScriptBank: ScriptCandidate[] = [
  { id: "line-1", text: "The cyan night opened and each phone became a tuning fork.", weight: 0.84 },
  { id: "line-2", text: "Every tilt reshaped the choir of screens into one shared breath.", weight: 0.76 },
  { id: "line-3", text: "You are not watching the piece. You are one of its vectors.", weight: 0.91 },
  { id: "line-4", text: "The hall keeps remembering what the crowd just decided.", weight: 0.79 },
  { id: "line-5", text: "A signal becomes a sentence the moment we choose together.", weight: 0.82 }
];

const looseSourceBank: ScriptCandidate[] = [
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

  snapshot(): TextScenePayload {
    return this.currentScene;
  }

  compose(input: {
    cueId: string;
    vector: Partial<ParamVector>;
    audioFeatures?: AudioFeaturePayload;
    pickResult?: CrowdPickResultPayload | null;
    pickEpoch?: number;
    textBlend?: { probability?: number; strictRatio?: number };
  }): TextScenePayload {
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

    const strictScored = strictScriptBank
      .map((candidate) => ({
        candidate,
        score:
          candidate.weight +
          strictRatio * 0.32 +
          vector.textAmount * 0.26 +
          vector.compositeBias * 0.19 +
          audio.rms * 0.15 +
          (pickLabel.includes("focus") ? 0.08 : 0)
      }))
      .sort((lhs, rhs) => rhs.score - lhs.score);

    const looseScored = [...generatedPool, ...looseSourceBank]
      .map((candidate) => ({
        candidate,
        score:
          candidate.weight +
          looseRatio * 0.35 +
          vector.compositeBias * 0.21 +
          audio.flux * 0.16 +
          audio.transientDensity * 0.12 +
          (pickLabel.includes("echo") ? 0.08 : 0) +
          (pickLabel.includes("scatter") ? 0.08 : 0)
      }))
      .sort((lhs, rhs) => rhs.score - lhs.score);

    const requestedLineCount = textProbability < 0.08 ? 0 : this.decideLineCount(vector, audio, pickLabel);
    const blendCounts = this.allocateBlendCounts(requestedLineCount, strictRatio);

    const strictSelected = strictScored.slice(0, blendCounts.strict).map((entry) => entry.candidate);
    const looseSelected = looseScored.slice(0, blendCounts.loose).map((entry) => entry.candidate);
    const selected = [...strictSelected, ...looseSelected];
    const lines = selected.map((candidate, index) =>
      this.buildSceneLine(candidate, {
        cueId: input.cueId,
        sceneVersion: this.sceneVersion + 1,
        lineIndex: index,
        pickEpoch: input.pickEpoch ?? 0
      })
    );

    const cutMode = this.decideCutMode(audio, pickLabel);
    const anchor = this.decideAnchor(pickLabel);
    const durationMs = Math.max(
      defaultScene.guardrails.minDurationMs,
      Math.round(2200 + 4200 * (0.28 + textProbability * 0.36 + audio.rms * 0.36))
    );

    this.sceneVersion += 1;
    this.currentScene = {
      sceneVersion: this.sceneVersion,
      pickEpoch: input.pickEpoch ?? 0,
      cueId: input.cueId,
      anchor,
      lineCount: lines.length,
      cutMode,
      alpha: clamp01((0.42 + vector.compositeBias * 0.36) * textProbability),
      fontScale: 0.8 + vector.textAmount * 0.55,
      weight: clamp01(0.33 + vector.compositeBias * 0.42 + audio.transientDensity * 0.15 + looseRatio * 0.1),
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

  private getGeneratedPool(input: {
    cueId: string;
    pickEpoch: number;
    vector: ParamVector;
    pickLabel: string;
    strictRatio: number;
  }): ScriptCandidate[] {
    const cueBucket = input.cueId.split(":").slice(0, 2).join(":");
    const key = `${cueBucket}:${input.pickEpoch}:${Math.round(input.vector.textAmount * 10)}:${Math.round(input.strictRatio * 10)}:${input.pickLabel}`;
    const now = Date.now();
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
    this.generatedPoolCache.set(key, {
      generatedAt: now,
      candidates: generated
    });

    if (this.generatedPoolCache.size > 120) {
      const oldest = [...this.generatedPoolCache.entries()].sort((lhs, rhs) => lhs[1].generatedAt - rhs[1].generatedAt)[0];
      if (oldest) {
        this.generatedPoolCache.delete(oldest[0]);
      }
    }

    return generated;
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
        weight: clamp01(0.55 + (input.strictRatio * 0.2) + ((seed % 100) / 1000))
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
      const mutateCount = 1 + (seed % 3); // 1..3
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
