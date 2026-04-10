import { clamp01, type ColorIntentPayload } from "@conductor/protocol";
import { useEffect, useMemo, useRef, useState } from "react";

interface ColorBiasFieldResult {
  intent: ColorIntentPayload;
  pointer: { x: number; y: number };
  interacting: boolean;
  onPointerDown: (event: React.PointerEvent<HTMLElement>) => void;
  onPointerMove: (event: React.PointerEvent<HTMLElement>) => void;
  onPointerUp: () => void;
  onPointerLeave: () => void;
}

const neutralIntent = (): ColorIntentPayload => ({
  hueX: 1,
  hueY: 0,
  chroma: 0.12,
  luminance: 0.56,
  energy: 0.2,
  updatedAt: Date.now()
});

const clampSigned = (value: number): number => Math.min(1, Math.max(-1, value));
const lerp = (start: number, end: number, alpha: number): number => start + (end - start) * alpha;

interface ColorBiasInputs {
  pointer: { x: number; y: number };
  tilt: { beta: number; gamma: number; motion: number };
  active: boolean;
  idleMs: number;
}

interface ColorIntentTargets {
  hueX: number;
  hueY: number;
  chroma: number;
  luminance: number;
  energy: number;
}

export const deriveColorIntentTargets = ({
  pointer,
  tilt,
  active,
  idleMs
}: ColorBiasInputs): ColorIntentTargets => {
  const dx = pointer.x - 0.5;
  const dy = pointer.y - 0.5;
  const distance = clamp01(Math.hypot(dx, dy) * 1.4);
  const angle = Math.atan2(dy, dx);

  let targetHueX = Math.cos(angle);
  let targetHueY = Math.sin(angle);
  let targetLuminance = clamp01(0.24 + (1 - pointer.y) * 0.62);
  let targetChroma = clamp01(0.08 + distance * 0.5);
  let targetEnergy = clamp01(0.18 + distance * 0.35 + tilt.motion * 0.45);

  const tiltMod = clamp01(Math.abs(tilt.gamma) / 90 * 0.55 + Math.abs(tilt.beta) / 180 * 0.45);
  targetChroma = clamp01(targetChroma + tiltMod * 0.24);
  targetEnergy = clamp01(targetEnergy + tiltMod * 0.2 + (active ? 0.22 : 0));

  const decaying = !active && idleMs > 1400;
  if (decaying) {
    const decayAlpha = clamp01((idleMs - 1400) / 4200);
    targetHueX = lerp(targetHueX, 1, decayAlpha);
    targetHueY = lerp(targetHueY, 0, decayAlpha);
    targetLuminance = lerp(targetLuminance, 0.56, decayAlpha);
    targetChroma = lerp(targetChroma, 0.12, decayAlpha);
    targetEnergy = lerp(targetEnergy, 0.16, decayAlpha);
  }

  const hueNorm = Math.hypot(targetHueX, targetHueY);
  return {
    hueX: hueNorm < 0.001 ? 1 : clampSigned(targetHueX / hueNorm),
    hueY: hueNorm < 0.001 ? 0 : clampSigned(targetHueY / hueNorm),
    chroma: targetChroma,
    luminance: targetLuminance,
    energy: targetEnergy
  };
};

export const useColorBiasField = (enabled: boolean): ColorBiasFieldResult => {
  const [intent, setIntent] = useState<ColorIntentPayload>(() => neutralIntent());
  const [pointer, setPointer] = useState({ x: 0.5, y: 0.5 });
  const [interacting, setInteracting] = useState(false);
  const pointerRef = useRef(pointer);
  const interactingRef = useRef(interacting);
  const lastInteractionAtRef = useRef(Date.now());
  const tiltRef = useRef({ beta: 0, gamma: 0, motion: 0 });

  useEffect(() => {
    pointerRef.current = pointer;
  }, [pointer]);

  useEffect(() => {
    interactingRef.current = interacting;
  }, [interacting]);

  useEffect(() => {
    if (!enabled) {
      setInteracting(false);
      setIntent(neutralIntent());
      return;
    }

    const onOrientation = (event: DeviceOrientationEvent): void => {
      tiltRef.current = {
        ...tiltRef.current,
        beta: event.beta ?? tiltRef.current.beta,
        gamma: event.gamma ?? tiltRef.current.gamma
      };
    };

    const onMotion = (event: DeviceMotionEvent): void => {
      const acceleration = event.accelerationIncludingGravity;
      const magnitude = Math.min(
        1,
        Math.sqrt(
          Math.pow(acceleration?.x ?? 0, 2) +
            Math.pow(acceleration?.y ?? 0, 2) +
            Math.pow(acceleration?.z ?? 0, 2)
        ) / 35
      );
      tiltRef.current = {
        ...tiltRef.current,
        motion: magnitude
      };
    };

    const interval = window.setInterval(() => {
      const currentPointer = pointerRef.current;
      const active = interactingRef.current;
      const tilt = tiltRef.current;
      const idleMs = Date.now() - lastInteractionAtRef.current;
      const targets = deriveColorIntentTargets({
        pointer: currentPointer,
        tilt,
        active,
        idleMs
      });
      const alpha = active ? 0.34 : 0.18;

      setIntent((current) => {
        const blendedX = lerp(current.hueX, targets.hueX, alpha);
        const blendedY = lerp(current.hueY, targets.hueY, alpha);
        const norm = Math.hypot(blendedX, blendedY);
        return {
          hueX: norm < 0.001 ? 1 : clampSigned(blendedX / norm),
          hueY: norm < 0.001 ? 0 : clampSigned(blendedY / norm),
          chroma: lerp(current.chroma, targets.chroma, alpha),
          luminance: lerp(current.luminance, targets.luminance, alpha),
          energy: lerp(current.energy, targets.energy, alpha),
          updatedAt: Date.now()
        };
      });
    }, 90);

    window.addEventListener("deviceorientation", onOrientation);
    window.addEventListener("devicemotion", onMotion);

    return () => {
      window.clearInterval(interval);
      window.removeEventListener("deviceorientation", onOrientation);
      window.removeEventListener("devicemotion", onMotion);
    };
  }, [enabled]);

  const pointerFromEvent = (event: React.PointerEvent<HTMLElement>) => {
    const rect = event.currentTarget.getBoundingClientRect();
    const x = clamp01((event.clientX - rect.left) / Math.max(1, rect.width));
    const y = clamp01((event.clientY - rect.top) / Math.max(1, rect.height));
    return { x, y };
  };

  const result = useMemo<ColorBiasFieldResult>(
    () => ({
      intent,
      pointer,
      interacting,
      onPointerDown: (event) => {
        const next = pointerFromEvent(event);
        setPointer(next);
        setInteracting(true);
        lastInteractionAtRef.current = Date.now();
      },
      onPointerMove: (event) => {
        if (!interactingRef.current) {
          return;
        }
        const next = pointerFromEvent(event);
        setPointer(next);
        lastInteractionAtRef.current = Date.now();
      },
      onPointerUp: () => {
        setInteracting(false);
        lastInteractionAtRef.current = Date.now();
      },
      onPointerLeave: () => {
        setInteracting(false);
      }
    }),
    [intent, interacting, pointer]
  );

  return result;
};
