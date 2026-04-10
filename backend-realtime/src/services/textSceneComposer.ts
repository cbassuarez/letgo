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

const scriptBank: ScriptCandidate[] = [
  { id: "line-1", text: "The cyan night opened and each phone became a tuning fork.", weight: 0.84 },
  { id: "line-2", text: "Every tilt reshaped the choir of screens into one shared breath.", weight: 0.76 },
  { id: "line-3", text: "You are not watching the piece. You are one of its vectors.", weight: 0.91 },
  { id: "line-4", text: "The hall keeps remembering what the crowd just decided.", weight: 0.79 },
  { id: "line-5", text: "A signal becomes a sentence the moment we choose together.", weight: 0.82 }
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

  snapshot(): TextScenePayload {
    return this.currentScene;
  }

  compose(input: {
    cueId: string;
    vector: Partial<ParamVector>;
    audioFeatures?: AudioFeaturePayload;
    pickResult?: CrowdPickResultPayload | null;
    pickEpoch?: number;
  }): TextScenePayload {
    const vector = this.normalizeVector(input.vector);
    const audio = input.audioFeatures ?? fallbackAudioFeatures;
    const pickLabel = input.pickResult?.winnerLabel?.toLowerCase() ?? "";

    const scored = scriptBank
      .map((candidate) => ({
        candidate,
        score:
          candidate.weight +
          vector.textAmount * 0.28 +
          vector.compositeBias * 0.2 +
          audio.rms * 0.18 +
          (pickLabel.includes("chorus") ? 0.12 : 0) +
          (pickLabel.includes("focus") ? 0.08 : 0)
      }))
      .sort((lhs, rhs) => rhs.score - lhs.score);

    const lineCount = this.decideLineCount(vector, audio, pickLabel);
    const selected = scored.slice(0, lineCount).map((entry) => entry.candidate);
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
      Math.round(2200 + 4200 * (0.3 + vector.textAmount * 0.4 + audio.rms * 0.3))
    );

    this.sceneVersion += 1;
    this.currentScene = {
      sceneVersion: this.sceneVersion,
      pickEpoch: input.pickEpoch ?? 0,
      cueId: input.cueId,
      anchor,
      lineCount: lines.length,
      cutMode,
      alpha: clamp01(0.56 + vector.compositeBias * 0.38),
      fontScale: 0.8 + vector.textAmount * 0.55,
      weight: clamp01(0.35 + vector.compositeBias * 0.5 + audio.transientDensity * 0.15),
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
