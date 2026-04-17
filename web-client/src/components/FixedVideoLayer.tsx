import Hls from "hls.js";
import { useEffect, useMemo, useRef, useState } from "react";
import type { CueCommand, ShowSceneKey, ShowStreamMap } from "@conductor/protocol";

interface FixedVideoLayerProps {
  cue: CueCommand | null;
  pendingCue?: CueCommand | null;
  logicalNow: number;
  enabled: boolean;
  forcedSource?: string | null;
  forcedScene?: ShowSceneKey | null;
  onPlaybackErrorChange?: (hasError: boolean) => void;
  onPlaybackReadyChange?: (isReady: boolean) => void;
}

const hlsMimeType = "application/vnd.apple.mpegurl";
const localDevMediaForState: Record<string, string> = {
  preshow: "media/preshow.mp4",
  introduction: "media/introduction.mp4",
  main: "media/show-fixed.mp4",
  ending: "media/ending.mp4",
  interstitial: "media/interstitial-loop.mp4"
};
const sceneKeys: ShowSceneKey[] = [
  "interstitial",
  "preshow",
  "introduction",
  "mainStatic",
  "mainDynamic",
  "ending"
];
const streamPayloadFieldByScene: Record<ShowSceneKey, string> = {
  interstitial: "showStreamInterstitial",
  preshow: "showStreamPreshow",
  introduction: "showStreamIntroduction",
  mainStatic: "showStreamMainStatic",
  mainDynamic: "showStreamMainDynamic",
  ending: "showStreamEnding"
};

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

const normalizeUrl = (value: unknown): string | null => {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
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

const parseSceneKey = (value: unknown): ShowSceneKey | null =>
  typeof value === "string" && sceneKeys.includes(value as ShowSceneKey)
    ? (value as ShowSceneKey)
    : null;

const defaultOutputModeForState = (showState: CueCommand["showState"] | null): "off" | "static" | "dynamic" => {
  if (showState === "main") {
    return "dynamic";
  }
  if (showState === "preshow" || showState === "introduction" || showState === "ending") {
    return "static";
  }
  return "off";
};

const parseStreamMapFromUnknown = (value: unknown): ShowStreamMap => {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    const record = value as Record<string, unknown>;
    return sceneKeys.reduce<ShowStreamMap>((acc, key) => {
      const maybe = normalizeUrl(record[key]);
      if (maybe) {
        acc[key] = maybe;
      }
      return acc;
    }, {});
  }

  if (typeof value === "string") {
    try {
      return parseStreamMapFromUnknown(JSON.parse(value));
    } catch {
      return {};
    }
  }

  return {};
};

const parseStreamMapFromPayload = (payload: Record<string, unknown>): ShowStreamMap => {
  const fromMap = parseStreamMapFromUnknown(payload.showStreamMap);
  const fromFields = sceneKeys.reduce<ShowStreamMap>((acc, key) => {
    const maybe = normalizeUrl(payload[streamPayloadFieldByScene[key]]);
    if (maybe) {
      acc[key] = maybe;
    }
    return acc;
  }, {});

  return {
    ...fromMap,
    ...fromFields
  };
};

const resolveCueVersion = (cue: CueCommand | null, payload: Record<string, unknown>): number => {
  const payloadVersionRaw = payload.cueVersion;
  const parsedPayloadVersion =
    typeof payloadVersionRaw === "number"
      ? payloadVersionRaw
      : typeof payloadVersionRaw === "string"
        ? Number(payloadVersionRaw)
        : NaN;
  const candidates = [
    cue?.version,
    Number.isFinite(parsedPayloadVersion) ? parsedPayloadVersion : undefined
  ].filter((value): value is number => typeof value === "number" && Number.isFinite(value));
  return candidates.length > 0 ? Math.max(...candidates) : 0;
};

const resolveActiveScene = (
  cue: CueCommand | null,
  payload: Record<string, unknown>,
  streamMap: ShowStreamMap,
  interstitialActive: boolean
): ShowSceneKey | null => {
  const explicit = parseSceneKey(payload.showActiveScene ?? payload.activeSceneKey);
  const explicitAllowed =
    explicit &&
    ((cue?.showState === "preshow" && explicit === "preshow") ||
      (cue?.showState === "introduction" && explicit === "introduction") ||
      (cue?.showState === "ending" && explicit === "ending") ||
      (cue?.showState === "main" && (explicit === "mainStatic" || explicit === "mainDynamic")) ||
      (explicit === "interstitial" && interstitialActive) ||
      ((cue?.showState === "idle" ||
        cue?.showState === "hold" ||
        cue?.showState === "aborted" ||
        cue?.showState === "recovery") &&
        explicit === "interstitial"));

  if (explicitAllowed) {
    return explicit;
  }

  if (cue?.showState === "preshow" && streamMap.preshow) {
    return "preshow";
  }
  if (cue?.showState === "introduction" && streamMap.introduction) {
    return "introduction";
  }
  if (cue?.showState === "ending" && streamMap.ending) {
    return "ending";
  }
  if (interstitialActive && streamMap.interstitial) {
    return "interstitial";
  }

  const outputMode = typeof payload.outputMode === "string" ? payload.outputMode.toLowerCase() : "";
  if (cue?.showState === "main") {
    if (outputMode.includes("dynamic")) {
      return streamMap.mainDynamic ? "mainDynamic" : null;
    }
    if (outputMode.includes("static") || outputMode === "program") {
      return streamMap.mainStatic ? "mainStatic" : null;
    }
    return (streamMap.mainDynamic ? "mainDynamic" : null) ?? (streamMap.mainStatic ? "mainStatic" : null);
  }

  return null;
};

const resolveSource = (
  cue: CueCommand | null,
  payload: Record<string, unknown>,
  interstitialActive: boolean,
  streamMap: ShowStreamMap,
  activeScene: ShowSceneKey | null
): string | null => {
  const explicitFixedMediaRef =
    normalizeUrl(payload.showFixedMediaRef) ??
    normalizeUrl(payload.showFixedMediaUrl) ??
    normalizeUrl(payload.showFixedSrc);
  if (explicitFixedMediaRef) {
    return toSharedMediaUrl(explicitFixedMediaRef);
  }

  if (activeScene && streamMap[activeScene]) {
    return toSharedMediaUrl(streamMap[activeScene]!);
  }

  if (cue?.showState === "preshow" && streamMap.preshow) {
    return toSharedMediaUrl(streamMap.preshow);
  }
  if (cue?.showState === "introduction" && streamMap.introduction) {
    return toSharedMediaUrl(streamMap.introduction);
  }
  if (cue?.showState === "ending" && streamMap.ending) {
    return toSharedMediaUrl(streamMap.ending);
  }
  if (cue?.showState === "main") {
    const outputMode = typeof payload.outputMode === "string" ? payload.outputMode.toLowerCase() : "";
    if (outputMode.includes("dynamic") && streamMap.mainDynamic) {
      return toSharedMediaUrl(streamMap.mainDynamic);
    }
    if ((outputMode.includes("static") || outputMode === "program") && streamMap.mainStatic) {
      return toSharedMediaUrl(streamMap.mainStatic);
    }
    if (streamMap.mainDynamic) {
      return toSharedMediaUrl(streamMap.mainDynamic);
    }
    if (streamMap.mainStatic) {
      return toSharedMediaUrl(streamMap.mainStatic);
    }
  }
  if (interstitialActive && streamMap.interstitial) {
    return toSharedMediaUrl(streamMap.interstitial);
  }

  const env = import.meta.env as Record<string, string | undefined>;
  const allowLocalFallback = boolFromPayload(env.VITE_ENABLE_LOCAL_MEDIA_FALLBACK, false);
  if (!allowLocalFallback) {
    return null;
  }

  if (interstitialActive) {
    return toBaseAssetUrl(localDevMediaForState.interstitial);
  }
  if (cue) {
    return toBaseAssetUrl(localDevMediaForState[cue.showState] ?? localDevMediaForState.main);
  }
  return toBaseAssetUrl(localDevMediaForState.preshow);
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

export const FixedVideoLayer = ({
  cue,
  pendingCue = null,
  logicalNow,
  enabled,
  forcedSource = null,
  forcedScene = null,
  onPlaybackReadyChange,
  onPlaybackErrorChange
}: FixedVideoLayerProps): JSX.Element | null => {
  if (!enabled) {
    return null;
  }

  const ref = useRef<HTMLVideoElement | null>(null);
  const hlsRef = useRef<Hls | null>(null);
  const prewarmHlsRef = useRef<Hls | null>(null);
  const [videoReady, setVideoReady] = useState(false);
  const [videoFailed, setVideoFailed] = useState(false);

  const payload = (cue?.payload ?? {}) as Record<string, unknown>;
  const outputModeRaw = typeof payload.outputMode === "string" ? payload.outputMode.toLowerCase() : "";
  const outputMode = outputModeRaw.length > 0 ? outputModeRaw : defaultOutputModeForState(cue?.showState ?? null);
  const interstitialActive = boolFromPayload(
    payload.interstitialActive,
    outputMode.includes("interstitial") || outputMode === "off"
  );
  const streamMap = useMemo(() => parseStreamMapFromPayload(payload), [payload]);
  const activeScene = useMemo(
    () => resolveActiveScene(cue, payload, streamMap, interstitialActive),
    [cue, payload, streamMap, interstitialActive]
  );
  const effectiveScene = forcedScene ?? activeScene;
  const cueVersion = useMemo(() => resolveCueVersion(cue, payload), [cue, payload]);
  const resolvedSource = useMemo(
    () => resolveSource(cue, payload, interstitialActive, streamMap, effectiveScene),
    [cue, payload, interstitialActive, streamMap, effectiveScene]
  );
  const source = forcedSource ?? resolvedSource;
  const pendingPayload = (pendingCue?.payload ?? {}) as Record<string, unknown>;
  const pendingOutputModeRaw = typeof pendingPayload.outputMode === "string" ? pendingPayload.outputMode.toLowerCase() : "";
  const pendingOutputMode =
    pendingOutputModeRaw.length > 0 ? pendingOutputModeRaw : defaultOutputModeForState(pendingCue?.showState ?? null);
  const pendingInterstitialActive = boolFromPayload(
    pendingPayload.interstitialActive,
    pendingOutputMode.includes("interstitial") || pendingOutputMode === "off"
  );
  const pendingStreamMap = useMemo(() => parseStreamMapFromPayload(pendingPayload), [pendingPayload]);
  const pendingActiveScene = useMemo(
    () => resolveActiveScene(pendingCue, pendingPayload, pendingStreamMap, pendingInterstitialActive),
    [pendingCue, pendingPayload, pendingStreamMap, pendingInterstitialActive]
  );
  const pendingSource = useMemo(
    () => resolveSource(pendingCue, pendingPayload, pendingInterstitialActive, pendingStreamMap, pendingActiveScene),
    [pendingCue, pendingPayload, pendingInterstitialActive, pendingStreamMap, pendingActiveScene]
  );
  const explicitMimeHint =
    normalizeUrl(payload.showFixedMediaMime) ??
    normalizeUrl(payload.showFixedMime);
  const hlsSource = source ? looksLikeHlsSource(source, explicitMimeHint) : false;
  const pendingExplicitMimeHint =
    normalizeUrl(pendingPayload.showFixedMediaMime) ??
    normalizeUrl(pendingPayload.showFixedMime);
  const pendingHlsSource = pendingSource ? looksLikeHlsSource(pendingSource, pendingExplicitMimeHint) : false;
  const shouldLoop = hlsSource ? false : boolFromPayload(payload.outputLoop, true);
  const playbackBindingKey = `${source ?? "none"}::${effectiveScene ?? "none"}::${cueVersion}`;

  useEffect(() => {
    setVideoReady(false);
    setVideoFailed(false);
    onPlaybackReadyChange?.(false);
    onPlaybackErrorChange?.(false);
  }, [onPlaybackErrorChange, onPlaybackReadyChange, playbackBindingKey]);

  useEffect(() => {
    if (source === null) {
      onPlaybackReadyChange?.(false);
      return;
    }
    if (videoFailed) {
      onPlaybackReadyChange?.(false);
      return;
    }
    onPlaybackReadyChange?.(videoReady);
  }, [onPlaybackReadyChange, source, videoFailed, videoReady]);

  useEffect(() => {
    if (!pendingSource || pendingSource === source || isJsdomEnvironment()) {
      return;
    }

    const prewarmVideo = document.createElement("video");
    prewarmVideo.preload = "auto";
    prewarmVideo.muted = true;
    prewarmVideo.playsInline = true;
    let cancelled = false;

    const cleanup = (): void => {
      cancelled = true;
      if (prewarmHlsRef.current) {
        prewarmHlsRef.current.destroy();
        prewarmHlsRef.current = null;
      }
      try {
        prewarmVideo.pause();
      } catch {
        // noop
      }
      prewarmVideo.removeAttribute("src");
    };

    if (!pendingHlsSource || prewarmVideo.canPlayType(hlsMimeType)) {
      prewarmVideo.src = pendingSource;
      try {
        prewarmVideo.load();
      } catch {
        // noop
      }
      return cleanup;
    }

    if (!Hls.isSupported()) {
      return cleanup;
    }

    const hls = new Hls({
      lowLatencyMode: true,
      backBufferLength: 60
    });
    prewarmHlsRef.current = hls;

    hls.on(Hls.Events.ERROR, (_event, data) => {
      if (!data.fatal || cancelled) {
        return;
      }
      cleanup();
    });
    hls.on(Hls.Events.MEDIA_ATTACHED, () => {
      if (cancelled) {
        return;
      }
      hls.loadSource(pendingSource);
    });
    hls.attachMedia(prewarmVideo);

    return cleanup;
  }, [pendingHlsSource, pendingSource, source]);

  useEffect(() => () => {
    if (hlsRef.current) {
      hlsRef.current.destroy();
      hlsRef.current = null;
    }
    if (prewarmHlsRef.current) {
      prewarmHlsRef.current.destroy();
      prewarmHlsRef.current = null;
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

    if (!source) {
      setVideoFailed(true);
      onPlaybackReadyChange?.(false);
      onPlaybackErrorChange?.(true);
      return;
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
      onPlaybackReadyChange?.(false);
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
      if (data.type === Hls.ErrorTypes.NETWORK_ERROR) {
        hls.startLoad();
        return;
      }
      if (data.type === Hls.ErrorTypes.MEDIA_ERROR) {
        hls.recoverMediaError();
        return;
      }
      setVideoFailed(true);
      onPlaybackReadyChange?.(false);
      onPlaybackErrorChange?.(true);
    });

    hls.on(Hls.Events.MANIFEST_PARSED, () => {
      setVideoReady(true);
      setVideoFailed(false);
      onPlaybackReadyChange?.(true);
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
  }, [hlsSource, onPlaybackErrorChange, onPlaybackReadyChange, playbackBindingKey, source]);

  useEffect(() => {
    const video = ref.current;
    if (!video || !cue || !source) {
      return;
    }

    if (interstitialActive || hlsSource || effectiveScene === "interstitial") {
      return;
    }

    const targetTime = logicalNow / 1000;
    if (Math.abs(video.currentTime - targetTime) > 0.2) {
      video.currentTime = targetTime;
    }
  }, [cue, effectiveScene, hlsSource, interstitialActive, logicalNow, source]);

  return (
    <div
      className="fixed-video-layer"
      data-testid="fixed-video-layer"
      data-active-source={source ?? "none"}
      data-active-scene={effectiveScene ?? "none"}
    >
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
          onPlaybackReadyChange?.(true);
          onPlaybackErrorChange?.(false);
        }}
        onError={() => {
          setVideoFailed(true);
          onPlaybackReadyChange?.(false);
          onPlaybackErrorChange?.(true);
        }}
      />
    </div>
  );
};
