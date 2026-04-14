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
      compositorMode: CompositorMode;
      updatedAt?: number;
    }
  ): AudienceVectorPayload {
    this.samples.set(hashedId, {
      vector: normalizeVector(sample.vector),
      influence: clamp01(sample.influence),
      compositorMode: sample.compositorMode,
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
        compositorModes: {}
      };
    }

    const vectorTotals = values.reduce(
      (acc, sample) => {
        acc.textAmount += sample.vector.textAmount;
        acc.compositeBias += sample.vector.compositeBias;
        acc.audioGain += sample.vector.audioGain;
        acc.spatialX += sample.vector.spatialX;
        acc.spatialY += sample.vector.spatialY;
        acc.spatialZ += sample.vector.spatialZ;
        return acc;
      },
      {
        textAmount: 0,
        compositeBias: 0,
        audioGain: 0,
        spatialX: 0,
        spatialY: 0,
        spatialZ: 0
      }
    );

    const compositorModes = values.reduce<Record<string, number>>((acc, sample) => {
      acc[sample.compositorMode] = (acc[sample.compositorMode] ?? 0) + 1;
      return acc;
    }, {});

    const immediate = normalizeVector({
      textAmount: vectorTotals.textAmount / count,
      compositeBias: vectorTotals.compositeBias / count,
      audioGain: vectorTotals.audioGain / count,
      spatialX: vectorTotals.spatialX / count,
      spatialY: vectorTotals.spatialY / count,
      spatialZ: vectorTotals.spatialZ / count
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

    return {
      vector: this.smoothedVector,
      participantCount: count,
      updatedAt: Date.now(),
      compositorModes
    };
  }
}
