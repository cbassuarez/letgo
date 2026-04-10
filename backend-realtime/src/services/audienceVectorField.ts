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
      return {
        vector: normalizeVector({}),
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

    return {
      vector: normalizeVector({
        textAmount: vectorTotals.textAmount / count,
        compositeBias: vectorTotals.compositeBias / count,
        audioGain: vectorTotals.audioGain / count,
        spatialX: vectorTotals.spatialX / count,
        spatialY: vectorTotals.spatialY / count,
        spatialZ: vectorTotals.spatialZ / count
      }),
      participantCount: count,
      updatedAt: Date.now(),
      compositorModes
    };
  }
}
