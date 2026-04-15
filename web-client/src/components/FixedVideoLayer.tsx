import Hls from "hls.js";
import { useEffect, useMemo, useRef, useState } from "react";
import type { CueCommand } from "@conductor/protocol";

interface FixedVideoLayerProps {
  cue: CueCommand | null;
  logicalNow: number;
  enabled: boolean;
  onPlaybackErrorChange?: (hasError: boolean) => void;
}

const mediaForState: Record<string, string> = {
  preshow: "media/preshow.mp4",
  introduction: "media/introduction.mp4",
  main: "media/show-fixed.mp4",
  ending: "media/ending.mp4",
  interstitial: "media/interstitial-loop.mp4"
};
const hlsMimeType = "application/vnd.apple.mpegurl";

const toBaseAssetUrl = (path: string): string => {
  const base = import.meta.env.BASE_URL ?? "/";
  const normalizedBase = base.endsWith("/") ? base : `${base}/`;
  const normalizedPath = path.startsWith("/") ? path.slice(1) : path;
  return `${normalizedBase}${normalizedPath}`;
};

const toSharedMediaUrl = (value: string): string => {
  if (/^https?:\/\//i.test(value)) {
    return value;
  }
  return toBaseAssetUrl(value);
};

const looksLikeHlsSource = (source: string, mimeHint: string | null): boolean => {
  if (mimeHint?.toLowerCase().includes("mpegurl")) {
    return true;
  }
  return /\.m3u8($|[?#])/i.test(source);
};

const isJsdomEnvironment = (): boolean =>
  typeof navigator !== "undefined" && navigator.userAgent.toLowerCase().includes("jsdom");

const safePlay = (video: HTMLVideoElement): void => {
  if (isJsdomEnvironment()) {
    return;
  }
  try {
    const playAttempt = video.play();
    if (playAttempt && typeof playAttempt.catch === "function") {
      void playAttempt.catch(() => undefined);
    }
  } catch {
    // JSDOM does not implement media playback APIs.
  }
};

const resetVideoElement = (video: HTMLVideoElement): void => {
  if (isJsdomEnvironment()) {
    video.removeAttribute("src");
    return;
  }
  try {
    video.pause();
  } catch {
    // JSDOM does not implement media playback APIs.
  }
  video.removeAttribute("src");
  try {
    video.load();
  } catch {
    // JSDOM does not implement media playback APIs.
  }
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

export const FixedVideoLayer = ({
  cue,
  logicalNow,
  enabled,
  onPlaybackErrorChange
}: FixedVideoLayerProps): JSX.Element | null => {
  if (!enabled) {
    return null;
  }

  const ref = useRef<HTMLVideoElement | null>(null);
  const hlsRef = useRef<Hls | null>(null);
  const [videoReady, setVideoReady] = useState(false);
  const [videoFailed, setVideoFailed] = useState(false);
  const payload = (cue?.payload ?? {}) as Record<string, unknown>;
  const outputMode = typeof payload.outputMode === "string" ? payload.outputMode.toLowerCase() : "";
  const interstitialActive = boolFromPayload(
    payload.interstitialActive,
    outputMode.includes("interstitial") || outputMode === "off"
  );
  const explicitFixedMediaRef = typeof payload.showFixedMediaRef === "string"
    ? payload.showFixedMediaRef
    : typeof payload.showFixedMediaUrl === "string"
      ? payload.showFixedMediaUrl
      : typeof payload.showFixedSrc === "string"
        ? payload.showFixedSrc
        : null;
  const explicitMimeHint = typeof payload.showFixedMediaMime === "string"
    ? payload.showFixedMediaMime
    : typeof payload.showFixedMime === "string"
      ? payload.showFixedMime
      : null;
  const source = useMemo(() => {
    if (explicitFixedMediaRef) {
      return toSharedMediaUrl(explicitFixedMediaRef);
    }
    if (interstitialActive) {
      return toBaseAssetUrl(mediaForState.interstitial);
    }
    if (cue) {
      return toBaseAssetUrl(mediaForState[cue.showState] ?? mediaForState.main);
    }
    return toBaseAssetUrl(mediaForState.preshow);
  }, [cue, explicitFixedMediaRef, interstitialActive]);
  const hlsSource = looksLikeHlsSource(source, explicitMimeHint);
  const shouldLoop = hlsSource ? false : boolFromPayload(payload.outputLoop, true);
  const fallbackLabel = interstitialActive ? "INTERSTITIAL" : (cue?.showState ?? "preshow").toUpperCase();

  useEffect(() => {
    setVideoReady(false);
    setVideoFailed(false);
    onPlaybackErrorChange?.(false);
  }, [onPlaybackErrorChange, source]);

  useEffect(() => () => {
    if (hlsRef.current) {
      hlsRef.current.destroy();
      hlsRef.current = null;
    }
  }, []);

  useEffect(() => {
    const video = ref.current;
    if (!video) {
      return;
    }

    if (hlsRef.current) {
      hlsRef.current.destroy();
      hlsRef.current = null;
    }

    resetVideoElement(video);

    if (!hlsSource) {
      video.src = source;
      safePlay(video);
      return;
    }

    if (video.canPlayType(hlsMimeType)) {
      video.src = source;
      safePlay(video);
      return;
    }

    if (!Hls.isSupported()) {
      setVideoFailed(true);
      onPlaybackErrorChange?.(true);
      return;
    }

    const hls = new Hls({
      lowLatencyMode: true,
      backBufferLength: 90
    });
    hlsRef.current = hls;

    hls.on(Hls.Events.ERROR, (_event, data) => {
      if (!data.fatal) {
        return;
      }
      setVideoFailed(true);
      onPlaybackErrorChange?.(true);
      if (data.type === Hls.ErrorTypes.NETWORK_ERROR) {
        hls.startLoad();
        return;
      }
      if (data.type === Hls.ErrorTypes.MEDIA_ERROR) {
        hls.recoverMediaError();
        return;
      }
      hls.destroy();
      if (hlsRef.current === hls) {
        hlsRef.current = null;
      }
    });

    hls.on(Hls.Events.MANIFEST_PARSED, () => {
      setVideoReady(true);
      setVideoFailed(false);
      onPlaybackErrorChange?.(false);
      safePlay(video);
    });

    hls.on(Hls.Events.MEDIA_ATTACHED, () => {
      hls.loadSource(source);
    });
    hls.attachMedia(video);

    return () => {
      hls.destroy();
      if (hlsRef.current === hls) {
        hlsRef.current = null;
      }
    };
  }, [hlsSource, onPlaybackErrorChange, source]);

  useEffect(() => {
    const video = ref.current;
    if (!video || !cue) {
      return;
    }

    if (interstitialActive || hlsSource) {
      return;
    }

    const targetTime = logicalNow / 1000;
    if (Math.abs(video.currentTime - targetTime) > 0.2) {
      video.currentTime = targetTime;
    }
  }, [cue, hlsSource, logicalNow, interstitialActive]);

  return (
    <div className="fixed-video-layer" data-testid="fixed-video-layer" data-active-source={source}>
      <video
        ref={ref}
        className={`fixed-video-surface ${videoReady && !videoFailed ? "ready" : ""}`}
        playsInline
        muted
        autoPlay
        loop={shouldLoop}
        crossOrigin="anonymous"
        onLoadedData={() => setVideoReady(true)}
        onCanPlay={() => {
          setVideoReady(true);
          setVideoFailed(false);
          onPlaybackErrorChange?.(false);
        }}
        onError={() => {
          setVideoFailed(true);
          onPlaybackErrorChange?.(true);
        }}
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
