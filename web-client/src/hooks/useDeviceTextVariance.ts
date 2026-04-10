import {
  clamp01,
  stableHashToSeed,
  type DeviceVarianceSpec,
  type TextScenePayload
} from "@conductor/protocol";
import { useMemo } from "react";

export interface DeviceTextVariance {
  lines: string[];
  spec: DeviceVarianceSpec;
}

export const deriveDeviceVariance = (
  scene: TextScenePayload,
  hashedId: string
): DeviceTextVariance => {
  const seed = stableHashToSeed(`${hashedId}:${scene.sceneVersion}:${scene.pickEpoch}`);
  const centered = (value: number): number => (value - 0.5) * 2;
  const maxOffsetX = clamp01(scene.guardrails.maxOffsetX);
  const maxOffsetY = clamp01(scene.guardrails.maxOffsetY);
  const offsetX = centered(((seed >>> 4) % 1000) / 1000) * maxOffsetX;
  const offsetY = centered(((seed >>> 14) % 1000) / 1000) * maxOffsetY;
  const alphaBias = centered(((seed >>> 6) % 1000) / 1000) * 0.08;
  const weightBias = centered(((seed >>> 8) % 1000) / 1000) * 0.12;
  const cadenceBiasMs = Math.round(centered(((seed >>> 10) % 1000) / 1000) * 220);
  const variantWordIndexes = [seed % 3, (seed >>> 5) % 3, (seed >>> 9) % 3];

  const lines = scene.lines.map((line, index) => {
    if (!line.variants || line.variants.length === 0) {
      return line.baseText;
    }
    const variantIndex = (seed + index * 17) % line.variants.length;
    return line.variants[variantIndex] ?? line.baseText;
  });

  return {
    lines,
    spec: {
      seed,
      sceneVersion: scene.sceneVersion,
      pickEpoch: scene.pickEpoch,
      offsetX,
      offsetY,
      alphaBias,
      weightBias,
      cadenceBiasMs,
      variantWordIndexes
    }
  };
};

export const useDeviceTextVariance = (
  scene: TextScenePayload,
  hashedId: string
): DeviceTextVariance =>
  useMemo(() => deriveDeviceVariance(scene, hashedId), [hashedId, scene]);
