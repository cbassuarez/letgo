import { clamp01, normalizeVector, type ParamVector } from "@conductor/protocol";
import { useEffect, useMemo, useRef, useState } from "react";

export interface ParticipantSignalState {
  motion: number;
  tiltBeta: number;
  tiltGamma: number;
  touchX: number;
  touchY: number;
  touchPressure: number;
  touching: boolean;
  lastInteractionAt: number;
}

interface ParticipantVectorResult {
  vector: ParamVector;
  influence: number;
  recommendedIntervalMs: number;
}

export const mapSignalsToVector = (signals: ParticipantSignalState): ParamVector => {
  const motion = clamp01(signals.motion);
  const x = clamp01((signals.tiltGamma + 90) / 180);
  const y = clamp01((signals.tiltBeta + 180) / 360);
  const pressure = clamp01(signals.touchPressure);
  const touchBlend = signals.touching ? 0.65 : 0.35;

  return normalizeVector({
    textAmount: clamp01(motion * 0.8 + pressure * 0.2),
    compositeBias: clamp01((signals.touchX + x) / 2),
    audioGain: clamp01(motion * 0.6 + touchBlend * pressure + 0.2),
    spatialX: clamp01((x + signals.touchX) / 2),
    spatialY: clamp01((y + signals.touchY) / 2),
    spatialZ: clamp01(0.35 + motion * 0.65)
  });
};

export const computeAdaptiveIntervalMs = (influence: number): number => {
  if (influence > 0.75) {
    return 90;
  }
  if (influence > 0.45) {
    return 140;
  }
  return 240;
};

export const useParticipantVector = (enabled: boolean): ParticipantVectorResult => {
  const [signals, setSignals] = useState<ParticipantSignalState>({
    motion: 0,
    tiltBeta: 0,
    tiltGamma: 0,
    touchX: 0.5,
    touchY: 0.5,
    touchPressure: 0,
    touching: false,
    lastInteractionAt: Date.now()
  });
  const rootRef = useRef<HTMLElement | null>(null);

  useEffect(() => {
    rootRef.current = document.documentElement;
  }, []);

  useEffect(() => {
    if (!enabled) {
      return;
    }

    const onOrientation = (event: DeviceOrientationEvent): void => {
      setSignals((current) => ({
        ...current,
        tiltBeta: event.beta ?? current.tiltBeta,
        tiltGamma: event.gamma ?? current.tiltGamma,
        lastInteractionAt: Date.now()
      }));
    };

    const onMotion = (event: DeviceMotionEvent): void => {
      const acceleration = event.accelerationIncludingGravity;
      const magnitude = Math.min(
        1,
        Math.sqrt(
          Math.pow(acceleration?.x ?? 0, 2) +
            Math.pow(acceleration?.y ?? 0, 2) +
            Math.pow(acceleration?.z ?? 0, 2)
        ) / 30
      );
      setSignals((current) => ({
        ...current,
        motion: magnitude,
        lastInteractionAt: Date.now()
      }));
    };

    const onPointer = (event: PointerEvent): void => {
      const target = rootRef.current;
      if (!target) {
        return;
      }
      const rect = target.getBoundingClientRect();
      const x = clamp01((event.clientX - rect.left) / Math.max(1, rect.width));
      const y = clamp01((event.clientY - rect.top) / Math.max(1, rect.height));
      setSignals((current) => ({
        ...current,
        touchX: x,
        touchY: y,
        touchPressure: event.pressure ?? current.touchPressure,
        touching: event.type !== "pointerup" && event.type !== "pointercancel",
        lastInteractionAt: Date.now()
      }));
    };

    window.addEventListener("deviceorientation", onOrientation);
    window.addEventListener("devicemotion", onMotion);
    window.addEventListener("pointerdown", onPointer);
    window.addEventListener("pointermove", onPointer);
    window.addEventListener("pointerup", onPointer);
    window.addEventListener("pointercancel", onPointer);

    return () => {
      window.removeEventListener("deviceorientation", onOrientation);
      window.removeEventListener("devicemotion", onMotion);
      window.removeEventListener("pointerdown", onPointer);
      window.removeEventListener("pointermove", onPointer);
      window.removeEventListener("pointerup", onPointer);
      window.removeEventListener("pointercancel", onPointer);
    };
  }, [enabled]);

  const vector = useMemo(() => mapSignalsToVector(signals), [signals]);

  const influence = useMemo(() => {
    const activity = (vector.textAmount + vector.audioGain + vector.spatialZ) / 3;
    const freshness = clamp01(1 - (Date.now() - signals.lastInteractionAt) / 10_000);
    return clamp01(activity * 0.75 + freshness * 0.25);
  }, [signals.lastInteractionAt, vector.audioGain, vector.spatialZ, vector.textAmount]);

  return {
    vector,
    influence,
    recommendedIntervalMs: computeAdaptiveIntervalMs(influence)
  };
};
