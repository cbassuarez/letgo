import { useEffect, useRef } from "react";
import type { CueCommand } from "@conductor/protocol";

interface FixedVideoLayerProps {
  cue: CueCommand | null;
  logicalNow: number;
  enabled: boolean;
}

const mediaForState: Record<string, string> = {
  preshow: "/media/preshow.mp4",
  introduction: "/media/introduction.mp4",
  main: "/media/show-fixed.mp4",
  ending: "/media/ending.mp4",
  interstitial: "/media/interstitial-loop.mp4"
};

const boolFromPayload = (value: unknown, fallback = false): boolean => {
  if (typeof value === "boolean") {
    return value;
  }
  if (typeof value === "string") {
    const normalized = value.toLowerCase();
    if (normalized === "true") {
      return true;
    }
    if (normalized === "false") {
      return false;
    }
  }
  return fallback;
};

export const FixedVideoLayer = ({ cue, logicalNow, enabled }: FixedVideoLayerProps): JSX.Element | null => {
  if (!enabled) {
    return null;
  }

  const ref = useRef<HTMLVideoElement | null>(null);
  const payload = (cue?.payload ?? {}) as Record<string, unknown>;
  const interstitialActive = boolFromPayload(payload.interstitialActive, payload.outputMode === "interstitial");
  const showFixedLaneId = typeof payload.showFixedLaneId === "string" ? payload.showFixedLaneId : null;
  const source = interstitialActive
    ? mediaForState.interstitial
    : showFixedLaneId
      ? `/media/show-fixed/${showFixedLaneId}.mp4`
    : cue
      ? mediaForState[cue.showState] ?? mediaForState.main
      : mediaForState.preshow;
  const shouldLoop = boolFromPayload(payload.outputLoop, true);

  useEffect(() => {
    const video = ref.current;
    if (!video || !cue) {
      return;
    }

    if (interstitialActive) {
      return;
    }

    const targetTime = logicalNow / 1000;
    if (Math.abs(video.currentTime - targetTime) > 0.2) {
      video.currentTime = targetTime;
    }
  }, [cue, logicalNow, interstitialActive]);

  return (
    <video
      ref={ref}
      className="absolute inset-0 h-full w-full object-cover"
      src={source}
      playsInline
      muted
      autoPlay
      loop={shouldLoop}
    />
  );
};
