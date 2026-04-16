import {
  clamp01,
  normalizeVector,
  type AudienceVectorPayload,
  type CompositorMode,
  type ParamVector
} from "@conductor/protocol";

interface ParticipantSample {
  vector: ParamVector;
  influence: number;
  promptInfluence: number;
  directPickInfluence: number;
  compositorMode: CompositorMode;
  updatedAt: number;
}

export class AudienceVectorField {
  private readonly samples = new Map<string, ParticipantSample>();
  private smoothedVector: ParamVector = normalizeVector({
    textAmount: 0.5,
    compositeBias: 0.5,
    audioGain: 0.5,
    spatialX: 0.5,
    spatialY: 0.5,
    spatialZ: 0.5
  });

  update(
    hashedId: string,
    sample: {
      vector: Partial<ParamVector>;
      influence: number;
      promptInfluence?: number;
      directPickInfluence?: number;
      compositorMode: CompositorMode;
      updatedAt?: number;
    }
  ): AudienceVectorPayload {
    const existing = this.samples.get(hashedId);
    const previousPromptInfluence = existing?.promptInfluence ?? 0;
    const previousDirectPickInfluence = existing?.directPickInfluence ?? 0;
    this.samples.set(hashedId, {
      vector: normalizeVector(sample.vector),
      influence: clamp01(sample.influence),
      promptInfluence: clamp01(sample.promptInfluence ?? previousPromptInfluence),
      directPickInfluence: clamp01(sample.directPickInfluence ?? previousDirectPickInfluence),
      compositorMode: sample.compositorMode,
      updatedAt: sample.updatedAt ?? Date.now()
    });
    return this.snapshot();
  }

  updatePromptInfluence(
    hashedId: string,
    sample: {
      promptInfluence: number;
      directPickInfluence: number;
      updatedAt?: number;
    }
  ): AudienceVectorPayload {
    const existing = this.samples.get(hashedId);
    if (!existing) {
      return this.snapshot();
    }
    this.samples.set(hashedId, {
      ...existing,
      promptInfluence: clamp01(sample.promptInfluence),
      directPickInfluence: clamp01(sample.directPickInfluence),
      updatedAt: sample.updatedAt ?? Date.now()
    });
    return this.snapshot();
  }

  remove(hashedId: string): AudienceVectorPayload {
    this.samples.delete(hashedId);
    return this.snapshot();
  }

  snapshot(): AudienceVectorPayload {
    const values = [...this.samples.values()];
    const count = values.length;

    if (count === 0) {
      this.smoothedVector = normalizeVector({
        textAmount: 0.5,
        compositeBias: 0.5,
        audioGain: 0.5,
        spatialX: 0.5,
        spatialY: 0.5,
        spatialZ: 0.5
      });
      return {
        vector: this.smoothedVector,
        participantCount: 0,
        updatedAt: Date.now(),
        compositorModes: {},
        promptInfluence: 0,
        directPickInfluence: 0,
        wavefront: {
          intensity: 0,
          phase: 0.5,
          decay: 1
        }
      };
    }

    const weightedVectorTotals = values.reduce(
      (acc, sample) => {
        const weight =
          0.4 +
          sample.influence * 0.6 +
          sample.promptInfluence * 0.25 +
          sample.directPickInfluence * 0.35;
        acc.totalWeight += weight;
        acc.textAmount += sample.vector.textAmount * weight;
        acc.compositeBias += sample.vector.compositeBias * weight;
        acc.audioGain += sample.vector.audioGain * weight;
        acc.spatialX += sample.vector.spatialX * weight;
        acc.spatialY += sample.vector.spatialY * weight;
        acc.spatialZ += sample.vector.spatialZ * weight;
        acc.promptInfluence += sample.promptInfluence;
        acc.directPickInfluence += sample.directPickInfluence;
        return acc;
      },
      {
        totalWeight: 0,
        textAmount: 0,
        compositeBias: 0,
        audioGain: 0,
        spatialX: 0,
        spatialY: 0,
        spatialZ: 0,
        promptInfluence: 0,
        directPickInfluence: 0
      }
    );

    const compositorModes = values.reduce<Record<string, number>>((acc, sample) => {
      acc[sample.compositorMode] = (acc[sample.compositorMode] ?? 0) + 1;
      return acc;
    }, {});

    const normalizationWeight = Math.max(0.001, weightedVectorTotals.totalWeight);
    const immediate = normalizeVector({
      textAmount: weightedVectorTotals.textAmount / normalizationWeight,
      compositeBias: weightedVectorTotals.compositeBias / normalizationWeight,
      audioGain: weightedVectorTotals.audioGain / normalizationWeight,
      spatialX: weightedVectorTotals.spatialX / normalizationWeight,
      spatialY: weightedVectorTotals.spatialY / normalizationWeight,
      spatialZ: weightedVectorTotals.spatialZ / normalizationWeight
    });
    if (count === 1) {
      // Prevent one participant from fully steering the field.
      this.smoothedVector = normalizeVector({
        textAmount: immediate.textAmount * 0.6 + 0.5 * 0.4,
        compositeBias: immediate.compositeBias * 0.6 + 0.5 * 0.4,
        audioGain: immediate.audioGain * 0.6 + 0.5 * 0.4,
        spatialX: immediate.spatialX * 0.6 + 0.5 * 0.4,
        spatialY: immediate.spatialY * 0.6 + 0.5 * 0.4,
        spatialZ: immediate.spatialZ * 0.6 + 0.5 * 0.4
      });
    } else if (count >= 3) {
      const smoothing = Math.min(0.45, 0.18 + Math.min(1, count / 24) * 0.27);
      this.smoothedVector = normalizeVector({
        textAmount: this.smoothedVector.textAmount + (immediate.textAmount - this.smoothedVector.textAmount) * smoothing,
        compositeBias:
          this.smoothedVector.compositeBias + (immediate.compositeBias - this.smoothedVector.compositeBias) * smoothing,
        audioGain: this.smoothedVector.audioGain + (immediate.audioGain - this.smoothedVector.audioGain) * smoothing,
        spatialX: this.smoothedVector.spatialX + (immediate.spatialX - this.smoothedVector.spatialX) * smoothing,
        spatialY: this.smoothedVector.spatialY + (immediate.spatialY - this.smoothedVector.spatialY) * smoothing,
        spatialZ: this.smoothedVector.spatialZ + (immediate.spatialZ - this.smoothedVector.spatialZ) * smoothing
      });
    } else {
      this.smoothedVector = immediate;
    }

    const wavefront = computeWavefront(values);

    return {
      vector: this.smoothedVector,
      participantCount: count,
      updatedAt: Date.now(),
      compositorModes,
      promptInfluence: clamp01(weightedVectorTotals.promptInfluence / count),
      directPickInfluence: clamp01(weightedVectorTotals.directPickInfluence / count),
      wavefront
    };
  }
}

const computeWavefront = (
  values: ParticipantSample[]
): { intensity: number; phase: number; decay: number } => {
  if (values.length < 2) {
    const sample = values[0];
    if (!sample) {
      return { intensity: 0, phase: 0.5, decay: 1 };
    }
    const phase =
      ((Math.atan2(sample.vector.spatialY - 0.5, sample.vector.spatialX - 0.5) / (2 * Math.PI)) + 1) %
      1;
    return { intensity: 0.2, phase, decay: 0.92 };
  }

  let nearestTotal = 0;
  let phaseSin = 0;
  let phaseCos = 0;
  for (let index = 0; index < values.length; index += 1) {
    const sample = values[index];
    let nearest = Number.POSITIVE_INFINITY;
    for (let otherIndex = 0; otherIndex < values.length; otherIndex += 1) {
      if (index === otherIndex) {
        continue;
      }
      const other = values[otherIndex];
      const dx = sample.vector.spatialX - other.vector.spatialX;
      const dy = sample.vector.spatialY - other.vector.spatialY;
      const distance = Math.hypot(dx, dy);
      if (distance < nearest) {
        nearest = distance;
      }
    }
    nearestTotal += Number.isFinite(nearest) ? nearest : 0.5;
    const angle = Math.atan2(sample.vector.spatialY - 0.5, sample.vector.spatialX - 0.5);
    phaseSin += Math.sin(angle);
    phaseCos += Math.cos(angle);
  }

  const averageNearest = nearestTotal / values.length;
  const coherence = clamp01(1 - averageNearest * 2.4);
  const crowdFactor = clamp01(values.length / 200);
  const intensity = clamp01(coherence * 0.7 + crowdFactor * 0.3);
  const phase = ((Math.atan2(phaseSin / values.length, phaseCos / values.length) / (2 * Math.PI)) + 1) % 1;
  const decay = clamp01(0.62 + (1 - intensity) * 0.3);
  return {
    intensity,
    phase,
    decay
  };
};
