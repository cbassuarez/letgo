import {
  clamp01,
  type ColorIntentPayload,
  type LightingDirective,
  type LightingStatePayload,
  type LightingTargetColor,
  type LightingZoneCell
} from "@conductor/protocol";

interface LightingSample {
  intent: ColorIntentPayload;
  influence: number;
  updatedAt: number;
  zoneX: number;
  zoneY: number;
}

interface Oklch {
  l: number;
  c: number;
  h: number;
}

const HUE_BIN_COUNT = 12;
const HALF_LIFE_MS = 6000;
const ZONE_COLS = 4;
const ZONE_ROWS = 3;
const DEFAULT_OKLCH: Oklch = {
  l: 0.56,
  c: 0.12,
  h: 220
};

export class CrowdLightingField {
  private readonly samples = new Map<string, LightingSample>();
  private smoothed: LightingStatePayload = this.buildEmptyState();
  private listeners = new Set<(payload: LightingStatePayload) => void>();

  update(
    hashedId: string,
    sample: {
      intent: Partial<ColorIntentPayload>;
      influence: number;
      updatedAt?: number;
      zone?: { x: number; y: number };
    }
  ): LightingStatePayload {
    const intent = normalizeColorIntent(sample.intent);
    this.samples.set(hashedId, {
      intent,
      influence: clamp01(sample.influence),
      updatedAt: sample.updatedAt ?? intent.updatedAt,
      zoneX: clamp01(sample.zone?.x ?? 0.5),
      zoneY: clamp01(sample.zone?.y ?? 0.5)
    });

    return this.recompute();
  }

  remove(hashedId: string): LightingStatePayload {
    this.samples.delete(hashedId);
    return this.recompute();
  }

  snapshot(): LightingStatePayload {
    return this.smoothed;
  }

  subscribe(listener: (payload: LightingStatePayload) => void): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  private recompute(): LightingStatePayload {
    const raw = this.computeRawState();
    this.smoothed = this.smooth(raw, this.smoothed);
    for (const listener of this.listeners) {
      listener(this.smoothed);
    }
    return this.smoothed;
  }

  private computeRawState(): LightingStatePayload {
    const now = Date.now();
    const values = [...this.samples.values()];
    if (values.length === 0) {
      return this.buildEmptyState(now);
    }

    const weighted = values
      .map((sample) => ({
        sample,
        weight: this.weightForSample(sample, now)
      }))
      .filter((entry) => entry.weight > 0.001);

    if (weighted.length === 0) {
      return this.buildEmptyState(now);
    }

    const aggregate = aggregateOklch(weighted.map((entry) => ({ intent: entry.sample.intent, weight: entry.weight })));
    const entropy = computeEntropy(weighted.map((entry) => ({ intent: entry.sample.intent, weight: entry.weight })));
    const confidence = clamp01(aggregate.resultant * (1 - entropy * 0.72));

    const oklch: Oklch = {
      l: clamp01(aggregate.l),
      c: clamp01(aggregate.c * (0.55 + aggregate.energy * 0.65)),
      h: aggregate.h
    };
    const targetColor = toLightingTarget(oklch);
    const zoneField = this.computeZoneField(weighted, targetColor);

    return {
      targetColor,
      confidence,
      entropy,
      stability: confidence,
      trend: toDirective(confidence, entropy),
      participantCount: weighted.length,
      updatedAt: now,
      zoneField
    };
  }

  private smooth(raw: LightingStatePayload, previous: LightingStatePayload): LightingStatePayload {
    if (previous.participantCount === 0 && raw.participantCount === 0) {
      return raw;
    }

    const prevLch = previous.targetColor.oklch;
    const nextLch = raw.targetColor.oklch;
    const alpha = raw.confidence >= previous.confidence ? 0.34 : 0.19;

    const hueBlend = blendHue(prevLch.h, nextLch.h, alpha);
    const smoothedOklch: Oklch = {
      l: lerp(prevLch.l, nextLch.l, alpha),
      c: lerp(prevLch.c, nextLch.c, alpha),
      h: hueBlend
    };
    const targetColor = toLightingTarget(smoothedOklch);
    const hueDelta = circularDelta(prevLch.h, nextLch.h) / 180;
    const luminanceDelta = Math.abs(prevLch.l - nextLch.l);
    const chromaDelta = Math.abs(prevLch.c - nextLch.c);
    const motion = clamp01((hueDelta + luminanceDelta + chromaDelta) / 3);
    const stability = clamp01(1 - motion * 1.15);
    const confidence = lerp(previous.confidence, raw.confidence, 0.28);
    const entropy = lerp(previous.entropy, raw.entropy, 0.24);

    return {
      ...raw,
      targetColor,
      confidence,
      entropy,
      stability,
      trend: toDirective(confidence, entropy),
      zoneField: raw.zoneField
    };
  }

  private computeZoneField(
    weightedSamples: Array<{ sample: LightingSample; weight: number }>,
    globalTarget: LightingTargetColor
  ): LightingZoneCell[] {
    const cells: LightingZoneCell[] = [];
    for (let row = 0; row < ZONE_ROWS; row += 1) {
      for (let col = 0; col < ZONE_COLS; col += 1) {
        const x = (col + 0.5) / ZONE_COLS;
        const y = (row + 0.5) / ZONE_ROWS;
        const localEntries = weightedSamples
          .map(({ sample, weight }) => {
            const dx = sample.zoneX - x;
            const dy = sample.zoneY - y;
            const d2 = dx * dx + dy * dy;
            const proximity = Math.exp(-d2 / 0.08);
            return {
              intent: sample.intent,
              weight: weight * proximity
            };
          })
          .filter((entry) => entry.weight > 0.0005);

        if (localEntries.length === 0) {
          cells.push({
            id: `r${row}c${col}`,
            x,
            y,
            participantDensity: 0,
            confidence: 0,
            entropy: 0,
            targetColor: globalTarget
          });
          continue;
        }

        const localAggregate = aggregateOklch(localEntries);
        const localEntropy = computeEntropy(localEntries);
        const localConfidence = clamp01(localAggregate.resultant * (1 - localEntropy * 0.72));
        const localTarget = toLightingTarget({
          l: clamp01(localAggregate.l),
          c: clamp01(localAggregate.c * (0.48 + localAggregate.energy * 0.62)),
          h: localAggregate.h
        });
        const participantDensity = clamp01(localEntries.reduce((acc, entry) => acc + entry.weight, 0) / 1.8);

        cells.push({
          id: `r${row}c${col}`,
          x,
          y,
          participantDensity,
          confidence: localConfidence,
          entropy: localEntropy,
          targetColor: localTarget
        });
      }
    }
    return cells;
  }

  private weightForSample(sample: LightingSample, now: number): number {
    const ageMs = Math.max(0, now - sample.updatedAt);
    const recency = Math.pow(0.5, ageMs / HALF_LIFE_MS);
    const influenceWeight = 0.35 + sample.influence * 0.65;
    const energyWeight = 0.28 + sample.intent.energy * 0.72;
    return Math.min(0.95, influenceWeight * energyWeight * recency);
  }

  private buildEmptyState(now: number = Date.now()): LightingStatePayload {
    const targetColor = toLightingTarget(DEFAULT_OKLCH);
    const zoneField: LightingZoneCell[] = [];
    for (let row = 0; row < ZONE_ROWS; row += 1) {
      for (let col = 0; col < ZONE_COLS; col += 1) {
        zoneField.push({
          id: `r${row}c${col}`,
          x: (col + 0.5) / ZONE_COLS,
          y: (row + 0.5) / ZONE_ROWS,
          participantDensity: 0,
          confidence: 0,
          entropy: 0,
          targetColor
        });
      }
    }

    return {
      targetColor,
      confidence: 0,
      entropy: 0,
      stability: 1,
      trend: "hold",
      participantCount: 0,
      updatedAt: now,
      zoneField
    };
  }
}

const normalizeColorIntent = (intent: Partial<ColorIntentPayload>): ColorIntentPayload => {
  const hueX = clampSigned(intent.hueX ?? 1);
  const hueY = clampSigned(intent.hueY ?? 0);
  const norm = Math.hypot(hueX, hueY);
  const unitX = norm < 0.001 ? 1 : hueX / norm;
  const unitY = norm < 0.001 ? 0 : hueY / norm;

  return {
    hueX: unitX,
    hueY: unitY,
    chroma: clamp01(intent.chroma ?? 0.12),
    luminance: clamp01(intent.luminance ?? 0.56),
    energy: clamp01(intent.energy ?? 0.42),
    updatedAt: intent.updatedAt ?? Date.now()
  };
};

const aggregateOklch = (entries: Array<{ intent: ColorIntentPayload; weight: number }>) => {
  const totalWeight = entries.reduce((acc, entry) => acc + entry.weight, 0);
  if (totalWeight <= 0.0001) {
    return {
      l: DEFAULT_OKLCH.l,
      c: DEFAULT_OKLCH.c,
      h: DEFAULT_OKLCH.h,
      resultant: 0,
      energy: 0
    };
  }

  let hueX = 0;
  let hueY = 0;
  let luminance = 0;
  let chroma = 0;
  let energy = 0;

  for (const entry of entries) {
    hueX += entry.intent.hueX * entry.weight;
    hueY += entry.intent.hueY * entry.weight;
    luminance += entry.intent.luminance * entry.weight;
    chroma += entry.intent.chroma * entry.weight;
    energy += entry.intent.energy * entry.weight;
  }

  const norm = Math.hypot(hueX, hueY);
  const hue = norm < 0.0001 ? DEFAULT_OKLCH.h : normalizeHueDegrees((Math.atan2(hueY, hueX) * 180) / Math.PI);
  const resultant = clamp01(norm / totalWeight);

  return {
    l: luminance / totalWeight,
    c: chroma / totalWeight,
    h: hue,
    resultant,
    energy: energy / totalWeight
  };
};

const computeEntropy = (entries: Array<{ intent: ColorIntentPayload; weight: number }>): number => {
  const bins = new Array<number>(HUE_BIN_COUNT).fill(0);
  let total = 0;
  for (const entry of entries) {
    const hue = normalizeHueDegrees((Math.atan2(entry.intent.hueY, entry.intent.hueX) * 180) / Math.PI);
    const index = Math.min(HUE_BIN_COUNT - 1, Math.floor((hue / 360) * HUE_BIN_COUNT));
    bins[index] += entry.weight;
    total += entry.weight;
  }

  if (total <= 0.00001) {
    return 0;
  }

  let entropy = 0;
  for (const bin of bins) {
    if (bin <= 0) {
      continue;
    }
    const p = bin / total;
    entropy -= p * Math.log(p);
  }
  return clamp01(entropy / Math.log(HUE_BIN_COUNT));
};

const toDirective = (confidence: number, entropy: number): LightingDirective => {
  if (confidence >= 0.68 && entropy <= 0.5) {
    return "go";
  }
  if (confidence >= 0.38) {
    return "caution";
  }
  return "hold";
};

const toLightingTarget = (oklch: Oklch): LightingTargetColor => ({
  oklch: {
    l: clamp01(oklch.l),
    c: clamp01(oklch.c),
    h: normalizeHueDegrees(oklch.h)
  },
  hex: oklchToHex(oklch)
});

const oklchToHex = (oklch: Oklch): string => {
  const hRad = (normalizeHueDegrees(oklch.h) * Math.PI) / 180;
  const a = oklch.c * Math.cos(hRad);
  const b = oklch.c * Math.sin(hRad);

  const l_ = oklch.l + 0.3963377774 * a + 0.2158037573 * b;
  const m_ = oklch.l - 0.1055613458 * a - 0.0638541728 * b;
  const s_ = oklch.l - 0.0894841775 * a - 1.291485548 * b;

  const l = l_ * l_ * l_;
  const m = m_ * m_ * m_;
  const s = s_ * s_ * s_;

  const rLin = +4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
  const gLin = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
  const bLin = -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s;

  const r = linearToSrgb8(rLin);
  const g = linearToSrgb8(gLin);
  const b8 = linearToSrgb8(bLin);
  return `#${toHex(r)}${toHex(g)}${toHex(b8)}`;
};

const linearToSrgb8 = (value: number): number => {
  const clamped = clamp01(value);
  const srgb = clamped <= 0.0031308 ? 12.92 * clamped : 1.055 * Math.pow(clamped, 1 / 2.4) - 0.055;
  return Math.round(clamp01(srgb) * 255);
};

const toHex = (value: number): string => value.toString(16).padStart(2, "0");

const normalizeHueDegrees = (value: number): number => {
  const normalized = value % 360;
  return normalized < 0 ? normalized + 360 : normalized;
};

const clampSigned = (value: number): number => Math.min(1, Math.max(-1, value));

const lerp = (start: number, end: number, alpha: number): number => start + (end - start) * alpha;

const blendHue = (start: number, end: number, alpha: number): number =>
  normalizeHueDegrees(start + shortestHueDelta(start, end) * alpha);

const shortestHueDelta = (from: number, to: number): number => {
  const raw = normalizeHueDegrees(to) - normalizeHueDegrees(from);
  if (raw > 180) {
    return raw - 360;
  }
  if (raw < -180) {
    return raw + 360;
  }
  return raw;
};

const circularDelta = (from: number, to: number): number => Math.abs(shortestHueDelta(from, to));
