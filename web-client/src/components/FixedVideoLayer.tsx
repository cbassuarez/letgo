import { useEffect, useMemo, useRef, useState } from "react";
import type { CueCommand } from "@conductor/protocol";

interface FixedVideoLayerProps {
  cue: CueCommand | null;
  logicalNow: number;
  enabled: boolean;
}

const mediaForState: Record<string, string> = {
  preshow: "media/preshow.mp4",
  introduction: "media/introduction.mp4",
  main: "media/show-fixed.mp4",
  ending: "media/ending.mp4",
  interstitial: "media/interstitial-loop.mp4"
};

const toBaseAssetUrl = (path: string): string => {
  const base = import.meta.env.BASE_URL ?? "/";
  const normalizedBase = base.endsWith("/") ? base : `${base}/`;
  const normalizedPath = path.startsWith("/") ? path.slice(1) : path;
  return `${normalizedBase}${normalizedPath}`;
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
  const [videoReady, setVideoReady] = useState(false);
  const [videoFailed, setVideoFailed] = useState(false);
  const payload = (cue?.payload ?? {}) as Record<string, unknown>;
  const outputMode = typeof payload.outputMode === "string" ? payload.outputMode.toLowerCase() : "";
  const interstitialActive = boolFromPayload(
    payload.interstitialActive,
    outputMode.includes("interstitial") || outputMode === "off"
  );
  const showFixedLaneId = typeof payload.showFixedLaneId === "string" ? payload.showFixedLaneId : null;
  const source = useMemo(() => (interstitialActive
    ? toBaseAssetUrl(mediaForState.interstitial)
    : showFixedLaneId
      ? toBaseAssetUrl(`media/show-fixed/${showFixedLaneId}.mp4`)
    : cue
      ? toBaseAssetUrl(mediaForState[cue.showState] ?? mediaForState.main)
      : toBaseAssetUrl(mediaForState.preshow)), [cue, interstitialActive, showFixedLaneId]);
  const shouldLoop = boolFromPayload(payload.outputLoop, true);
  const fallbackLabel = interstitialActive ? "INTERSTITIAL" : (cue?.showState ?? "preshow").toUpperCase();

  useEffect(() => {
    setVideoReady(false);
    setVideoFailed(false);
  }, [source]);

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
    <div className="fixed-video-layer" data-testid="fixed-video-layer">
      <video
        ref={ref}
        className={`fixed-video-surface ${videoReady && !videoFailed ? "ready" : ""}`}
        src={source}
        playsInline
        muted
        autoPlay
        loop={shouldLoop}
        onLoadedData={() => setVideoReady(true)}
        onCanPlay={() => setVideoReady(true)}
        onError={() => setVideoFailed(true)}
      />
      {!videoReady || videoFailed ? (
        <div className="fixed-video-fallback" data-testid="fixed-video-fallback">
          <div className="fixed-video-fallback-scan" />
          <p className="fixed-video-fallback-label">{fallbackLabel}</p>
        </div>
      ) : null}
    </div>
  );
};
