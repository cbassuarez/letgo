import {
  clamp01,
  type ColorInteractionPolicy,
  type PromptOfferPayload,
  deterministicPick,
  type Role,
  type ShowState,
  stableHashToSeed,
  type CompositorMode,
  type ScriptCandidate
} from "@conductor/protocol";
import { motion, useReducedMotion } from "framer-motion";
import { type CSSProperties, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { DynamicOverlay } from "../components/DynamicOverlay";
import { FixedVideoLayer } from "../components/FixedVideoLayer";
import { PermissionGate } from "../components/PermissionGate";
import { useColorBiasField } from "../hooks/useColorBiasField";
import { useConductorSession } from "../hooks/useConductorSession";
import { useDeviceTextVariance } from "../hooks/useDeviceTextVariance";
import { useParticipantVector } from "../hooks/useParticipantVector";
import { usePhoneVoiceEngine } from "../hooks/usePhoneVoiceEngine";
import { isValidHashedId } from "../lib/identity";
import { BACKEND_HEALTH_URL } from "../lib/wsClient";

const scriptBank: ScriptCandidate[] = [
  {
    id: "line-1",
    arc: "arc1",
    tags: ["arrival", "fear"],
    text: "The cyan night opened and each phone became a tuning fork.",
    weight: 0.85,
    cooldownMs: 15000,
    tone: "confessional"
  },
  {
    id: "line-2",
    arc: "arc2",
    tags: ["control", "breath"],
    text: "Every tilt reshaped the choir of screens into one shared breath.",
    weight: 0.72,
    cooldownMs: 12000,
    tone: "directive"
  },
  {
    id: "line-3",
    arc: "arc3",
    tags: ["release", "chorus"],
    text: "You are not watching the piece. You are one of its vectors.",
    weight: 0.9,
    cooldownMs: 20000,
    tone: "lyrical"
  }
];

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

const outputModeLabel = (rawMode: string): string => {
  const normalized = rawMode.toLowerCase();
  if (normalized.includes("interstitial") || normalized === "off") {
    return "INTER";
  }
  if (normalized === "static") {
    return "STATIC";
  }
  if (normalized === "dynamic") {
    return "DYNAMIC";
  }
  return rawMode.toUpperCase();
};

const defaultOutputModeForShowState = (showState: ShowState | null): "off" | "static" | "dynamic" => {
  if (showState === "main") {
    return "dynamic";
  }
  if (showState === "preshow" || showState === "introduction" || showState === "ending") {
    return "static";
  }
  return "off";
};

type OfflineReason = "engine_off" | "link_reconnecting" | "stream_hold";

const STREAM_DROPOUT_GRACE_MS = 3_000;
const STREAM_RECOVERY_FAIL_TIMEOUT_MS = 5_000;
const LIVE_REVEAL_COUNTDOWN_SECONDS = 3;

const normalizeStreamRef = (value: unknown): string | null => {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
};

const parseMapRecord = (value: unknown): Record<string, unknown> | null => {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  if (typeof value === "string") {
    try {
      return parseMapRecord(JSON.parse(value));
    } catch {
      return null;
    }
  }
  return null;
};

const resolveInterstitialSourceFromPayload = (payload: Record<string, unknown>): string | null => {
  const direct = normalizeStreamRef(payload.showStreamInterstitial);
  if (direct) {
    return direct;
  }
  const map = parseMapRecord(payload.showStreamMap);
  if (!map) {
    return null;
  }
  return normalizeStreamRef(map.interstitial);
};

const buildAutoZone = (hashedId: string): { name: string; x: number; y: number; z: number } => {
  const seed = stableHashToSeed(hashedId);
  const x = ((seed % 1000) + 1) / 1001;
  const y = (((seed >>> 10) % 1000) + 1) / 1001;
  return {
    name: "auto-field",
    x,
    y,
    z: 0.5
  };
};

const buildGeoZone = (
  hashedId: string,
  latitude: number,
  longitude: number
): { name: string; x: number; y: number; z: number } => {
  const normalizedX = ((((longitude + 180) / 360) % 1) + 1) % 1;
  const normalizedY = ((((latitude + 90) / 180) % 1) + 1) % 1;
  const seed = stableHashToSeed(hashedId);
  const microJitter = ((seed % 17) / 17) * 0.01;
  return {
    name: "geo-field",
    x: clamp01(normalizedX + microJitter),
    y: clamp01(normalizedY + microJitter),
    z: 0.5
  };
};

const allShowStates: ShowState[] = [
  "idle",
  "preshow",
  "introduction",
  "main",
  "ending",
  "hold",
  "aborted",
  "recovery"
];

const defaultColorPolicy: ColorInteractionPolicy = {
  enabled: true,
  roles: ["audience", "performer", "observer"],
  showStates: allShowStates
};

const hueDegrees = (hueX: number, hueY: number): number => {
  const degrees = (Math.atan2(hueY, hueX) * 180) / Math.PI;
  return degrees < 0 ? degrees + 360 : degrees;
};

const hueToCss = (hue: number, chroma = 0.5, luminance = 0.5): string => {
  const saturation = Math.round(clamp01(0.18 + chroma * 0.74) * 100);
  const lightness = Math.round(clamp01(0.2 + luminance * 0.56) * 100);
  return `hsl(${Math.round(hue)} ${saturation}% ${lightness}%)`;
};

const parseColorPolicy = (value: unknown): ColorInteractionPolicy => {
  const raw = (value && typeof value === "object" ? value : {}) as Partial<ColorInteractionPolicy>;
  const roles = Array.isArray(raw.roles)
    ? raw.roles.filter(
        (role): role is Role =>
          role === "audience" || role === "performer" || role === "observer" || role === "muted"
      )
    : undefined;
  const showStates = Array.isArray(raw.showStates)
    ? raw.showStates.filter((showState): showState is ShowState => allShowStates.includes(showState))
    : undefined;

  return {
    enabled: typeof raw.enabled === "boolean" ? raw.enabled : defaultColorPolicy.enabled,
    roles: roles && roles.length > 0 ? roles : defaultColorPolicy.roles,
    showStates: showStates && showStates.length > 0 ? showStates : defaultColorPolicy.showStates
  };
};

const isColorPolicyActive = (
  policy: ColorInteractionPolicy,
  role: Role,
  showState: ShowState | null
): boolean => {
  if (!policy.enabled) {
    return false;
  }
  const roleAllowed = !policy.roles || policy.roles.includes(role);
  const stateAllowed = !policy.showStates || !showState || policy.showStates.includes(showState);
  return roleAllowed && stateAllowed;
};

export const DeviceRoute = (): JSX.Element => {
  const { hashedId = "" } = useParams();
  const capabilitiesSupported =
    typeof window !== "undefined" &&
    "WebSocket" in window &&
    "DeviceMotionEvent" in window &&
    "DeviceOrientationEvent" in window;
  const [permissionsDone, setPermissionsDone] = useState(false);
  const [permissions, setPermissions] = useState({
    audio: false,
    geolocation: false,
    motion: false
  });
  const [compositorMode, setCompositorMode] = useState<CompositorMode>("fallback");
  const [backendHealth, setBackendHealth] = useState<{
    ok: boolean;
    checkedAt: number;
    latencyMs: number;
  } | null>(null);
  const [clockNow, setClockNow] = useState(() => Date.now());
  const [selectedVoteOptionId, setSelectedVoteOptionId] = useState<string | null>(null);
  const [controlsOpen, setControlsOpen] = useState(false);
  const [diagnosticsOpen, setDiagnosticsOpen] = useState(false);
  const [uiVisible, setUiVisible] = useState(true);
  const [fixedLayerErrored, setFixedLayerErrored] = useState(false);
  const [fixedLayerReady, setFixedLayerReady] = useState(false);
  const [forceInterstitialRecovery, setForceInterstitialRecovery] = useState(false);
  const [recoveryStartedAt, setRecoveryStartedAt] = useState<number | null>(null);
  const [needsRevealCountdown, setNeedsRevealCountdown] = useState(false);
  const [countdownStep, setCountdownStep] = useState<number | null>(null);
  const [promptDrag, setPromptDrag] = useState({ x: 0, y: 0 });
  const [promptStartAt, setPromptStartAt] = useState<number | null>(null);
  const [dismissedPromptId, setDismissedPromptId] = useState<string | null>(null);
  const [promptInfluenceState, setPromptInfluenceState] = useState({
    promptInfluence: 0,
    directPickInfluence: 0
  });
  const prefersReducedMotion = useReducedMotion();
  const permissionsSentRef = useRef(false);
  const zoneSentRef = useRef(false);
  const handledPhoneCommandRef = useRef<string>("");
  const uiIdleTimerRef = useRef<number | null>(null);
  const holdPromptStartRef = useRef<number | null>(null);
  const lastPromptIdRef = useRef<string>("");

  const session = useConductorSession(hashedId);
  const {
    sendCrowdPickVote,
    sendPhoneAudioAck,
    sendPermissions,
    sendZoneUpdate,
    sendParticipantVector,
    sendPromptResponse
  } = session;
  const participantVector = useParticipantVector(permissionsDone);
  const cuePayload = (session.cue?.payload ?? {}) as Record<string, unknown>;
  const participantRole: Role = "audience";
  const colorPolicy = parseColorPolicy(cuePayload.colorPolicy);
  const colorLayerActive = isColorPolicyActive(colorPolicy, participantRole, session.cue?.showState ?? null);
  const colorBias = useColorBiasField(permissionsDone && colorLayerActive);
  const deviceTextVariance = useDeviceTextVariance(session.textScene, hashedId);
  const { handleCommand } = usePhoneVoiceEngine({
    enabled: permissionsDone && session.phoneAudioPoolState.gateCommitted,
    hashedId,
    onAck: sendPhoneAudioAck
  });
  const autoZone = useMemo(() => buildAutoZone(hashedId), [hashedId]);
  const [liveZone, setLiveZone] = useState(autoZone);

  const seededLine = useMemo(() => {
    const seed = stableHashToSeed(hashedId);
    return deterministicPick(seed, scriptBank).text;
  }, [hashedId]);

  const inferredOutputMode = defaultOutputModeForShowState(session.cue?.showState ?? null);
  const defaultDynamicEnabled = session.cue?.showState === "main";
  const inferredEngineFromAudioPath =
    session.phoneAudioPoolState.quadRouteReady ||
    session.phoneAudioPoolState.gateArmed ||
    session.phoneAudioPoolState.gateCommitted;
  const explicitEngineRunning =
    cuePayload.engineRunning === true || cuePayload.engineRunning === "true";
  const showStateRunning =
    session.cue !== null && session.cue.showState !== "idle";
  const engineRunning =
    explicitEngineRunning || inferredEngineFromAudioPath || showStateRunning;
  const linkOnline = session.connected && session.linkState === "online";
  const rawOutputMode = typeof cuePayload.outputMode === "string" ? cuePayload.outputMode : inferredOutputMode;
  const normalizedOutputMode = rawOutputMode.toLowerCase();
  const interMode = normalizedOutputMode.includes("interstitial") || normalizedOutputMode === "off";
  const fixedStageState =
    session.cue?.showState === "preshow" ||
    session.cue?.showState === "introduction" ||
    session.cue?.showState === "ending";
  const showFixedPlanned = boolFromPayload(cuePayload.showFixed, false) || interMode || fixedStageState;
  const showDynamicPlanned = interMode ? false : boolFromPayload(cuePayload.showDynamic, defaultDynamicEnabled);
  const outputMode = rawOutputMode;
  const interstitialRecoverySource = resolveInterstitialSourceFromPayload(cuePayload);
  const recoveryAgeMs = recoveryStartedAt === null ? 0 : Math.max(0, clockNow - recoveryStartedAt);
  const recoveryFallbackAvailable = Boolean(interstitialRecoverySource);
  const baseOfflineReason: OfflineReason | null = !engineRunning
    ? "engine_off"
    : !linkOnline
      ? "link_reconnecting"
      : null;
  const recoveryStreamFailed =
    forceInterstitialRecovery &&
    (!recoveryFallbackAvailable ||
      (fixedLayerErrored && !fixedLayerReady && recoveryAgeMs >= STREAM_RECOVERY_FAIL_TIMEOUT_MS));
  const offlineReason: OfflineReason | null = baseOfflineReason ?? (recoveryStreamFailed ? "stream_hold" : null);
  const showRecoveryInterstitial =
    permissionsDone &&
    baseOfflineReason === null &&
    forceInterstitialRecovery &&
    !recoveryStreamFailed &&
    recoveryFallbackAvailable;
  const readyForLiveReveal =
    permissionsDone &&
    offlineReason === null &&
    (forceInterstitialRecovery
      ? showRecoveryInterstitial && fixedLayerReady && !fixedLayerErrored
      : true);
  const renderLiveStage =
    permissionsDone &&
    offlineReason === null &&
    !forceInterstitialRecovery &&
    !needsRevealCountdown &&
    countdownStep === null;
  const fixedLayerEnabled = (renderLiveStage && showFixedPlanned) || showRecoveryInterstitial;
  const showDynamicWithFallback = renderLiveStage && showDynamicPlanned;
  const compositorDisplayMode = showDynamicWithFallback
    ? compositorMode === "unsupported"
      ? "fallback"
      : compositorMode
    : "standby";
  const localHue = useMemo(() => hueDegrees(colorBias.intent.hueX, colorBias.intent.hueY), [colorBias.intent.hueX, colorBias.intent.hueY]);
  const localPreviewColor = useMemo(
    () => hueToCss(localHue, colorBias.intent.chroma, colorBias.intent.luminance),
    [colorBias.intent.chroma, colorBias.intent.luminance, localHue]
  );
  const crowdHue = session.lightingState.targetColor.oklch.h;
  const crowdPreviewColor = hueToCss(
    crowdHue,
    session.lightingState.targetColor.oklch.c,
    session.lightingState.targetColor.oklch.l
  );
  const textSceneLine =
    session.proceduralState.textProbability < 0.08 ? "" : (deviceTextVariance.lines[0] ?? seededLine);
  const proceduralClip = session.proceduralState.dynamicBinClipId ?? "none";
  const crowdPickWindow = session.crowdPickWindow;
  const promptOffer = session.promptOffer;
  const activePrompt: PromptOfferPayload | null =
    promptOffer &&
    promptOffer.promptId !== dismissedPromptId &&
    clockNow <= promptOffer.expiresAt
      ? promptOffer
      : null;
  const promptCountdownMs = activePrompt ? Math.max(0, activePrompt.expiresAt - clockNow) : 0;
  const pickWindowIsActive = Boolean(
    crowdPickWindow && clockNow >= crowdPickWindow.opensAt && clockNow <= crowdPickWindow.closesAt
  );
  const pickCountdownMs = crowdPickWindow ? Math.max(0, crowdPickWindow.closesAt - clockNow) : 0;
  const syncHealthy = session.connected && !session.fallbackActive && Math.abs(session.driftMs) <= 350;
  const streamStatus = (() => {
    if (offlineReason === "stream_hold") {
      return "HOLD";
    }
    if (showRecoveryInterstitial) {
      return fixedLayerReady && !fixedLayerErrored ? "RECOVERY READY" : "RECOVERY ARMING";
    }
    if (!showFixedPlanned) {
      return "BYPASS";
    }
    if (fixedLayerErrored) {
      return "UNSTABLE";
    }
    if (fixedLayerReady) {
      return "READY";
    }
    return "ARMING";
  })();
  const offlineTitle =
    offlineReason === "engine_off"
      ? "ENGINE OFFLINE"
      : offlineReason === "link_reconnecting"
        ? "LINK RECONNECTING"
        : "STREAM HOLD";
  const offlineHint =
    offlineReason === "engine_off"
      ? "Operator must start engine to arm live output."
      : offlineReason === "link_reconnecting"
        ? "Hold position while control link renegotiates."
        : "Fallback stream unavailable. Awaiting stable media route.";
  const bumpUiVisibility = useCallback(() => {
    setUiVisible(true);
    if (uiIdleTimerRef.current !== null) {
      window.clearTimeout(uiIdleTimerRef.current);
    }
    uiIdleTimerRef.current = window.setTimeout(() => {
      setUiVisible(controlsOpen || diagnosticsOpen);
    }, 3000);
  }, [controlsOpen, diagnosticsOpen]);

  const goNoGoChecks = [
    {
      label: "BACKEND PING",
      go: backendHealth?.ok ?? false
    },
    {
      label: "WS LINK",
      go: session.connected && session.linkState === "online"
    },
    {
      label: "SYNC CLOCK",
      go: session.connected && !session.fallbackActive && Math.abs(session.driftMs) <= 350
    },
    {
      label: "COMPOSITOR",
      go: compositorDisplayMode === "html-in-canvas" || compositorDisplayMode === "fallback"
    },
    {
      label: "ENGINE",
      go: engineRunning
    },
    {
      label: "COLOR FIELD",
      go: session.connected && session.lightingState.trend !== "hold"
    },
    {
      label: "PHONE AUDIO",
      go: session.phoneAudioPoolState.gateCommitted && session.phoneAudioPoolState.quadRouteReady
    },
    {
      label: "CROWD PICK",
      go: crowdPickWindow ? pickWindowIsActive : false
    }
  ];

  useEffect(() => {
    if (!permissionsDone || !session.connected || permissionsSentRef.current) {
      return;
    }
    sendPermissions(permissions);
    permissionsSentRef.current = true;
  }, [permissions, permissionsDone, sendPermissions, session.connected]);

  useEffect(() => {
    setLiveZone(autoZone);
  }, [autoZone]);

  useEffect(() => {
    if (!permissionsDone || !permissions.geolocation) {
      return;
    }
    if (!navigator.geolocation) {
      return;
    }

    let active = true;
    const watchID = navigator.geolocation.watchPosition(
      (position) => {
        if (!active) {
          return;
        }
        setLiveZone(buildGeoZone(hashedId, position.coords.latitude, position.coords.longitude));
        zoneSentRef.current = false;
      },
      () => {
        // Keep deterministic fallback zone when geolocation is unavailable.
      },
      {
        enableHighAccuracy: false,
        maximumAge: 30_000,
        timeout: 7_000
      }
    );

    return () => {
      active = false;
      navigator.geolocation.clearWatch(watchID);
    };
  }, [hashedId, permissions.geolocation, permissionsDone]);

  useEffect(() => {
    if (!permissionsDone || !session.connected || zoneSentRef.current) {
      return;
    }
    sendZoneUpdate(liveZone);
    zoneSentRef.current = true;
  }, [liveZone, permissionsDone, sendZoneUpdate, session.connected]);

  useEffect(() => {
    if (!permissionsDone || !engineRunning || !renderLiveStage) {
      return;
    }

    let timer: number | null = null;
    const pushVector = (): void => {
      sendParticipantVector({
        vector: participantVector.vector,
        influence: participantVector.influence,
        promptInfluence: promptInfluenceState.promptInfluence,
        directPickInfluence: promptInfluenceState.directPickInfluence,
        compositorMode,
        colorIntent: colorBias.intent,
        updatedAt: Date.now()
      });
      timer = window.setTimeout(pushVector, participantVector.recommendedIntervalMs);
    };
    pushVector();

    return () => {
      if (timer !== null) {
        window.clearTimeout(timer);
      }
    };
  }, [
    compositorMode,
    colorBias.intent,
    engineRunning,
    participantVector.influence,
    participantVector.recommendedIntervalMs,
    participantVector.vector,
    permissionsDone,
    promptInfluenceState.directPickInfluence,
    promptInfluenceState.promptInfluence,
    renderLiveStage,
    sendParticipantVector
  ]);

  useEffect(() => {
    let active = true;
    let timer: number | null = null;

    const pollHealth = async (): Promise<void> => {
      const started = performance.now();
      try {
        const response = await fetch(BACKEND_HEALTH_URL, {
          method: "GET",
          cache: "no-store"
        });
        if (!active) {
          return;
        }
        setBackendHealth({
          ok: response.ok,
          checkedAt: Date.now(),
          latencyMs: Math.round(performance.now() - started)
        });
      } catch {
        if (!active) {
          return;
        }
        setBackendHealth({
          ok: false,
          checkedAt: Date.now(),
          latencyMs: Math.round(performance.now() - started)
        });
      } finally {
        if (active) {
          timer = window.setTimeout(() => void pollHealth(), 7000);
        }
      }
    };

    void pollHealth();

    return () => {
      active = false;
      if (timer !== null) {
        window.clearTimeout(timer);
      }
    };
  }, []);

  useEffect(() => {
    const timer = window.setInterval(() => {
      setClockNow(Date.now());
    }, 250);
    return () => window.clearInterval(timer);
  }, []);

  useEffect(() => {
    setSelectedVoteOptionId(null);
  }, [crowdPickWindow?.id]);

  useEffect(() => {
    if (permissionsDone) {
      return;
    }
    setControlsOpen(false);
    setDiagnosticsOpen(false);
  }, [permissionsDone]);

  useEffect(() => {
    if (!permissionsDone) {
      setUiVisible(true);
      return;
    }

    const onInteract = (): void => bumpUiVisibility();
    window.addEventListener("pointerdown", onInteract, { passive: true });
    window.addEventListener("pointermove", onInteract, { passive: true });
    window.addEventListener("mousemove", onInteract, { passive: true });
    window.addEventListener("touchstart", onInteract, { passive: true });
    window.addEventListener("keydown", onInteract, { passive: true });
    bumpUiVisibility();

    return () => {
      window.removeEventListener("pointerdown", onInteract);
      window.removeEventListener("pointermove", onInteract);
      window.removeEventListener("mousemove", onInteract);
      window.removeEventListener("touchstart", onInteract);
      window.removeEventListener("keydown", onInteract);
      if (uiIdleTimerRef.current !== null) {
        window.clearTimeout(uiIdleTimerRef.current);
      }
    };
  }, [bumpUiVisibility, permissionsDone]);

  useEffect(() => {
    if (controlsOpen || diagnosticsOpen) {
      setUiVisible(true);
      if (uiIdleTimerRef.current !== null) {
        window.clearTimeout(uiIdleTimerRef.current);
      }
      return;
    }
    if (permissionsDone) {
      bumpUiVisibility();
    }
  }, [bumpUiVisibility, controlsOpen, diagnosticsOpen, permissionsDone]);

  useEffect(() => {
    if (!activePrompt) {
      setPromptStartAt(null);
      holdPromptStartRef.current = null;
      return;
    }
    if (activePrompt.promptId !== lastPromptIdRef.current) {
      lastPromptIdRef.current = activePrompt.promptId;
      setPromptStartAt(Date.now());
    }
    if (activePrompt.haptic && typeof navigator !== "undefined" && "vibrate" in navigator) {
      try {
        navigator.vibrate?.(18);
      } catch {
        // ignore
      }
    }
    setUiVisible(true);
  }, [activePrompt]);

  useEffect(() => {
    const timer = window.setInterval(() => {
      setPromptInfluenceState((current) => ({
        promptInfluence: Math.max(0, current.promptInfluence - 0.04),
        directPickInfluence: Math.max(0, current.directPickInfluence - 0.06)
      }));
    }, 240);
    return () => window.clearInterval(timer);
  }, []);

  useEffect(() => {
    if (!session.phoneAudioCommand) {
      return;
    }
    if (handledPhoneCommandRef.current === session.phoneAudioCommand.commandId) {
      return;
    }
    handledPhoneCommandRef.current = session.phoneAudioCommand.commandId;
    void handleCommand(session.phoneAudioCommand);
  }, [handleCommand, session.phoneAudioCommand]);

  useEffect(() => {
    if (!permissionsDone || !fixedLayerEnabled) {
      setFixedLayerReady(false);
    }
  }, [fixedLayerEnabled, permissionsDone]);

  useEffect(() => {
    if (renderLiveStage) {
      return;
    }
    setControlsOpen(false);
    setDiagnosticsOpen(false);
  }, [renderLiveStage]);

  useEffect(() => {
    if (!permissionsDone) {
      setForceInterstitialRecovery(false);
      setRecoveryStartedAt(null);
      setNeedsRevealCountdown(false);
      setCountdownStep(null);
      return;
    }
    if (!baseOfflineReason) {
      return;
    }
    setForceInterstitialRecovery(false);
    setRecoveryStartedAt(null);
    setNeedsRevealCountdown(true);
    setCountdownStep(null);
  }, [baseOfflineReason, permissionsDone]);

  useEffect(() => {
    if (!permissionsDone || baseOfflineReason !== null || forceInterstitialRecovery || !showFixedPlanned || !fixedLayerErrored) {
      return;
    }
    const timer = window.setTimeout(() => {
      setForceInterstitialRecovery(true);
      setRecoveryStartedAt(Date.now());
      setNeedsRevealCountdown(true);
    }, STREAM_DROPOUT_GRACE_MS);
    return () => {
      window.clearTimeout(timer);
    };
  }, [baseOfflineReason, fixedLayerErrored, forceInterstitialRecovery, permissionsDone, showFixedPlanned]);

  useEffect(() => {
    if (!permissionsDone || !forceInterstitialRecovery || recoveryStartedAt !== null) {
      return;
    }
    setRecoveryStartedAt(Date.now());
    setNeedsRevealCountdown(true);
  }, [forceInterstitialRecovery, permissionsDone, recoveryStartedAt]);

  useEffect(() => {
    if (!permissionsDone || !readyForLiveReveal || !needsRevealCountdown || countdownStep !== null) {
      return;
    }
    setCountdownStep(LIVE_REVEAL_COUNTDOWN_SECONDS);
  }, [countdownStep, needsRevealCountdown, permissionsDone, readyForLiveReveal]);

  useEffect(() => {
    if (countdownStep === null) {
      return;
    }
    if (!readyForLiveReveal) {
      setCountdownStep(null);
      return;
    }
    const timer = window.setTimeout(() => {
      if (countdownStep <= 1) {
        setCountdownStep(null);
        setNeedsRevealCountdown(false);
        setForceInterstitialRecovery(false);
        setRecoveryStartedAt(null);
        return;
      }
      setCountdownStep((current) => (current === null ? null : current - 1));
    }, 1000);
    return () => {
      window.clearTimeout(timer);
    };
  }, [countdownStep, readyForLiveReveal]);

  const statusToastLabel = !session.connected
    ? "reconnecting"
    : fixedLayerErrored
      ? "stream hold"
      : null;
  const uiFaded = renderLiveStage && !uiVisible && !controlsOpen && !diagnosticsOpen;
  const diagnosticLines = [
    session.connected ? "Live Link" : "Field Reconnect",
    `Link ${session.linkState}`,
    session.retryInMs !== null ? `Retry ${(session.retryInMs / 1000).toFixed(1)}s` : null,
    `Compositor ${compositorDisplayMode}`,
    backendHealth ? `Ping ${backendHealth.latencyMs}ms` : null,
    `Influence ${(participantVector.influence * 100).toFixed(0)}%`,
    `Audience ${session.audienceVector.participantCount}`,
    `Color ${session.lightingState.trend.toUpperCase()}`,
    `ColorConf ${(session.lightingState.confidence * 100).toFixed(0)}%`,
    `AudioRMS ${(session.audioFeatures.rms * 100).toFixed(0)}%`,
    `Flux ${(session.audioFeatures.flux * 100).toFixed(0)}%`,
    `PhonePool ${session.phoneAudioPoolState.availableDevices.length}`,
    `PhoneGate ${session.phoneAudioPoolState.gateCommitted ? "COMMIT" : "SAFE"}`,
    `Clip ${proceduralClip}`,
    `Cadence ${(session.proceduralState.cutCadence * 100).toFixed(0)}%`,
    `Trans ${session.proceduralState.transitionMode}`,
    `Comp ${session.proceduralState.compositorPreset}`,
    `Split ${session.proceduralState.splitLayout}`,
    `TextP ${(session.proceduralState.textProbability * 100).toFixed(0)}%`,
    `Strict ${(session.proceduralState.strictLooseBlend * 100).toFixed(0)}%`,
    `Variance ${(session.proceduralState.visualVariance * 100).toFixed(0)}%`,
    `CrowdSteer ${(session.proceduralState.crowdSteeringLevel * 100).toFixed(0)}%`,
    `Prompt ${(((session.proceduralState.promptInfluence ?? 0) * 100)).toFixed(0)}%`,
    `Direct ${(((session.proceduralState.directPickInfluence ?? 0) * 100)).toFixed(0)}%`,
    `Drift ${session.driftMs.toFixed(1)}ms`,
    session.fallbackActive ? "Fallback" : "Synced",
    session.fallbackActive ? `FallbackAge ${(session.fallbackAgeMs / 1000).toFixed(1)}s` : null,
    `Engine ${engineRunning ? "ON" : "OFF"}`,
    `Mode ${outputModeLabel(outputMode)}`
  ].filter((line): line is string => Boolean(line));

  const promptActionLabel = (offer: PromptOfferPayload): string => {
    switch (offer.action) {
      case "layout_full":
        return "Set Frame Full";
      case "layout_pip":
        return "Shift To PIP";
      case "layout_split":
        return "Split The Frame";
      case "clip_tension":
        return "Push Tension Clip";
      case "clip_release":
        return "Push Release Clip";
      case "direct_slot_a":
        return "Direct Pick Slot A";
      case "direct_slot_b":
        return "Direct Pick Slot B";
      case "direct_take_next":
        return "Direct Next Take";
      case "cut":
        return "Text Cut";
      case "stretch":
        return "Text Stretch";
      case "echo":
        return "Text Echo";
      case "withhold":
        return "Text Withhold";
      case "warm_shift":
        return "Warm Lighting";
      case "cool_shift":
        return "Cool Lighting";
      case "luma_raise":
        return "Lift Luminance";
      case "luma_lower":
        return "Drop Luminance";
      case "echo_push":
        return "Push Echo";
      case "echo_pull":
        return "Pull Echo";
      case "density_hold":
        return "Hold Density";
      default:
        return offer.action;
    }
  };

  const submitPromptResponse = (
    responseType: "tap" | "drag" | "hold",
    options?: {
      tapChoice?: string;
      dragVector?: { x: number; y: number };
      holdMs?: number;
      slotPick?: { slotId: string; takeId?: string };
    }
  ): void => {
    if (!activePrompt) {
      return;
    }
    const now = Date.now();
    const latencyMs = Math.max(0, now - (promptStartAt ?? now));
    sendPromptResponse({
      promptId: activePrompt.promptId,
      cueVersion: activePrompt.cueVersion,
      responseType,
      tapChoice: options?.tapChoice,
      dragVector: options?.dragVector,
      holdMs: options?.holdMs,
      latencyMs,
      slotPick: options?.slotPick,
      respondedAt: now
    });

    const promptInfluence = clamp01(0.34 + Math.max(0, 1 - latencyMs / Math.max(1, promptCountdownMs || 4000)) * 0.5);
    const directPickInfluence = activePrompt.directPickTargets?.length ? clamp01(promptInfluence * 0.82) : 0;
    setPromptInfluenceState({
      promptInfluence,
      directPickInfluence
    });
    setDismissedPromptId(activePrompt.promptId);
    setPromptStartAt(null);
    holdPromptStartRef.current = null;
  };

  if (!isValidHashedId(hashedId)) {
    return (
      <main className="cyanotype-shell min-h-dvh px-6 py-16">
        <section className="mx-auto max-w-4xl border-t border-cyanotype-200/30 py-10">
          <p className="cyanotype-kicker">LOCKOUT</p>
          <h1 className="mt-4 text-5xl font-semibold leading-[0.95] sm:text-7xl">Participant Link Not Valid</h1>
          <p className="font-display mt-6 text-2xl text-cyanotype-000/86 sm:text-4xl">
            This key is outside tonight’s active field.
          </p>
          <p className="mt-4 max-w-3xl text-cyanotype-100/78">
            This entrance key is not in the performance field. Scan your assigned NFC card to join.
          </p>
          <Link to="/" className="cyanotype-cta mt-8 inline-flex">
            Return To Briefing
          </Link>
        </section>
      </main>
    );
  }

  if (!capabilitiesSupported) {
    return (
      <main className="cyanotype-shell min-h-dvh px-6 py-16">
        <section className="mx-auto max-w-4xl border-t border-cyanotype-200/30 py-10">
          <p className="cyanotype-kicker">LOCKOUT</p>
          <h1 className="mt-4 text-5xl font-semibold leading-[0.95] sm:text-7xl">Device Capabilities Not Supported</h1>
          <p className="font-display mt-6 text-2xl text-cyanotype-000/86 sm:text-4xl">
            Motion APIs are required for this score.
          </p>
          <p className="mt-4 max-w-3xl text-cyanotype-100/78">
            This browser cannot provide the motion/real-time APIs required for live participation.
            Open the same participant link in a modern mobile Chromium browser.
          </p>
          <Link to={`/${hashedId}`} className="cyanotype-cta mt-8 inline-flex">
            Return To Briefing
          </Link>
        </section>
      </main>
    );
  }

  return (
    <main
      className={`live-stage-shell relative min-h-dvh overflow-hidden text-cyanotype-050 ${uiFaded ? "live-ui-faded" : ""}`}
      data-testid="live-stage"
    >
      <FixedVideoLayer
        cue={session.cue}
        logicalNow={session.logicalNow}
        enabled={fixedLayerEnabled}
        forcedSource={showRecoveryInterstitial ? interstitialRecoverySource : null}
        forcedScene={showRecoveryInterstitial ? "interstitial" : null}
        onPlaybackReadyChange={setFixedLayerReady}
        onPlaybackErrorChange={setFixedLayerErrored}
      />
      <DynamicOverlay
        vector={session.vector}
        line={textSceneLine}
        enabled={showDynamicWithFallback}
        influence={participantVector.influence}
        procedural={session.proceduralState}
        onCompositorModeChange={setCompositorMode}
      />

      {renderLiveStage ? (
        <>
          <section className="live-ribbon live-ribbon-top live-ui-layer" data-testid="live-diagnostics-ribbon">
            <button
              type="button"
              className="live-ribbon-button"
              onClick={() => setDiagnosticsOpen((current) => !current)}
              aria-expanded={diagnosticsOpen}
              aria-controls="live-diagnostics-panel"
            >
              {diagnosticsOpen ? "Hide Diagnostics" : "Diagnostics"}
            </button>
          </section>

          {diagnosticsOpen ? (
            <motion.aside
              id="live-diagnostics-panel"
              initial={{ opacity: 0, y: -8 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.24 }}
              className="live-diagnostics-panel live-ui-layer"
              data-testid="live-diagnostics-panel"
            >
              <div className="live-gng-block">
                <p className="live-ribbon-label">GO / NO-GO</p>
                {goNoGoChecks.map((check) => (
                  <div key={check.label} className="live-gng-row">
                    <span className={`live-gng-dot ${check.go ? "go" : "nogo"}`} />
                    <span>{check.label}</span>
                    <span>{check.go ? "GO" : "NOGO"}</span>
                  </div>
                ))}
              </div>
              <div className="live-diagnostics-lines">
                {diagnosticLines.map((line) => (
                  <p key={line}>{line}</p>
                ))}
              </div>
            </motion.aside>
          ) : null}

          <section className="live-ribbon live-ribbon-bottom live-ui-layer" data-testid="live-controls-ribbon">
            <button
              type="button"
              className="live-ribbon-button"
              onClick={() => setControlsOpen((current) => !current)}
              aria-expanded={controlsOpen}
              aria-controls="live-controls-panel"
            >
              {controlsOpen ? "Hide Lighting" : "Lighting"}
            </button>
          </section>

          {controlsOpen ? (
            <motion.section
              id="live-controls-panel"
              initial={{ opacity: 0, y: 12 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.24 }}
              className="live-controls-panel live-ui-layer"
              data-testid="live-controls-panel"
            >
              <div className="color-bias-header">
                <p className="live-ribbon-label">Crowd Color Layer</p>
                <p className="color-bias-subline">
                  Hold or drag to bias hue and luminance. Tilt increases energy and chroma.
                </p>
              </div>
              <div
                className="color-bias-surface"
                style={
                  {
                    touchAction: "none",
                    "--local-color": localPreviewColor,
                    "--crowd-color": crowdPreviewColor
                  } as CSSProperties
                }
                onPointerDown={colorBias.onPointerDown}
                onPointerMove={colorBias.onPointerMove}
                onPointerUp={colorBias.onPointerUp}
                onPointerLeave={colorBias.onPointerLeave}
                onPointerCancel={colorBias.onPointerUp}
              >
                <div className="color-bias-wash" />
                <div className="color-bias-grid" />
                <div
                  className={`color-bias-cursor ${colorBias.interacting ? "active" : ""}`}
                  style={{
                    left: `${(colorBias.pointer.x * 100).toFixed(2)}%`,
                    top: `${(colorBias.pointer.y * 100).toFixed(2)}%`,
                    borderColor: localPreviewColor,
                    boxShadow: `0 0 22px ${localPreviewColor}`
                  }}
                />
                <div className="color-bias-readout">
                  <p>Your Hue {Math.round(localHue)}°</p>
                  <p>Field Target {session.lightingState.targetColor.hex}</p>
                  <p className={`directive-${session.lightingState.trend}`}>
                    {session.lightingState.trend.toUpperCase()} · {(session.lightingState.confidence * 100).toFixed(0)}% CONF
                  </p>
                </div>
              </div>
              <div className="color-bias-meta">
                <p>Local Energy {(colorBias.intent.energy * 100).toFixed(0)}%</p>
                <p>Local Chroma {(colorBias.intent.chroma * 100).toFixed(0)}%</p>
                <p>Luminance {(colorBias.intent.luminance * 100).toFixed(0)}%</p>
                <p>Consensus {(session.lightingState.confidence * 100).toFixed(0)}%</p>
                <p>Entropy {(session.lightingState.entropy * 100).toFixed(0)}%</p>
                <p>Audience {session.lightingState.participantCount}</p>
                <p>SceneV {session.textScene.sceneVersion}</p>
                <p>PickEpoch {session.textScene.pickEpoch}</p>
              </div>
              {crowdPickWindow ? (
                <div className="crowd-pick-strip mt-3">
                  <p className="live-ribbon-label">
                    Crowd Pick {pickWindowIsActive ? "LIVE" : "Standby"} ·
                    {" "}
                    {pickWindowIsActive ? `${Math.ceil(pickCountdownMs / 1000)}s` : "closed"}
                  </p>
                  <div className="crowd-pick-options">
                    {crowdPickWindow.options.map((option) => (
                      <button
                        key={option.id}
                        type="button"
                        className={`crowd-pick-button ${selectedVoteOptionId === option.id ? "selected" : ""}`}
                        disabled={!pickWindowIsActive}
                        onClick={() => {
                          setSelectedVoteOptionId(option.id);
                          sendCrowdPickVote({
                            windowId: crowdPickWindow.id,
                            optionId: option.id,
                            votedAt: Date.now()
                          });
                        }}
                      >
                        {option.label}
                      </button>
                    ))}
                  </div>
                  {session.crowdPickResult ? (
                    <p className="crowd-pick-result">
                      Last: {session.crowdPickResult.winnerLabel ?? "HOLD"} ·
                      {" "}
                      {session.crowdPickResult.applied ? "applied" : "pending"}
                    </p>
                  ) : null}
                </div>
              ) : null}
            </motion.section>
          ) : null}

          {activePrompt ? (
            <motion.section
              initial={{ opacity: 0, y: 12 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.22 }}
              className="live-prompt-card live-ui-layer"
              data-testid="live-prompt-card"
            >
              <p className="live-ribbon-label">
                Prompt · {activePrompt.domain.toUpperCase()} · {Math.ceil(promptCountdownMs / 1000)}s
              </p>
              <p className="live-prompt-title">{promptActionLabel(activePrompt)}</p>
              {activePrompt.affordance === "tap" ? (
                <div className="live-prompt-actions">
                  {(activePrompt.directPickTargets && activePrompt.directPickTargets.length > 0
                    ? activePrompt.directPickTargets
                    : [
                        { slotId: "primary", label: "Primary" },
                        { slotId: "secondary", label: "Secondary" }
                      ]
                  ).map((choice) => (
                    <button
                      key={choice.slotId}
                      type="button"
                      className="live-prompt-button"
                      onClick={() =>
                        submitPromptResponse("tap", {
                          tapChoice: choice.label ?? choice.slotId,
                          slotPick: activePrompt.directPickTargets
                            ? {
                                slotId: choice.slotId,
                                takeId: choice.takeId
                              }
                            : undefined
                        })
                      }
                    >
                      {choice.label ?? choice.slotId}
                    </button>
                  ))}
                </div>
              ) : null}
              {activePrompt.affordance === "drag" ? (
                <div
                  className="live-prompt-drag-surface"
                  role="button"
                  tabIndex={0}
                  onPointerDown={(event) => {
                    bumpUiVisibility();
                    const rect = event.currentTarget.getBoundingClientRect();
                    const x = clamp01((event.clientX - rect.left) / Math.max(1, rect.width));
                    const y = clamp01((event.clientY - rect.top) / Math.max(1, rect.height));
                    setPromptDrag({
                      x: (x - 0.5) * 2,
                      y: (y - 0.5) * 2
                    });
                  }}
                  onPointerMove={(event) => {
                    if (event.buttons <= 0) {
                      return;
                    }
                    const rect = event.currentTarget.getBoundingClientRect();
                    const x = clamp01((event.clientX - rect.left) / Math.max(1, rect.width));
                    const y = clamp01((event.clientY - rect.top) / Math.max(1, rect.height));
                    setPromptDrag({
                      x: (x - 0.5) * 2,
                      y: (y - 0.5) * 2
                    });
                  }}
                  onPointerUp={() =>
                    submitPromptResponse("drag", {
                      dragVector: promptDrag
                    })
                  }
                  onKeyDown={(event) => {
                    if (event.key === "Enter" || event.key === " ") {
                      submitPromptResponse("drag", {
                        dragVector: promptDrag
                      });
                    }
                  }}
                >
                  <span>Drag To Steer</span>
                  <span>
                    X {promptDrag.x.toFixed(2)} · Y {promptDrag.y.toFixed(2)}
                  </span>
                </div>
              ) : null}
              {activePrompt.affordance === "hold" ? (
                <button
                  type="button"
                  className="live-prompt-button live-prompt-hold"
                  onPointerDown={() => {
                    holdPromptStartRef.current = Date.now();
                    bumpUiVisibility();
                  }}
                  onPointerUp={() =>
                    submitPromptResponse("hold", {
                      holdMs: Math.max(0, Date.now() - (holdPromptStartRef.current ?? Date.now()))
                    })
                  }
                  onPointerLeave={() => {
                    holdPromptStartRef.current = null;
                  }}
                >
                  Hold To Commit
                </button>
              ) : null}
            </motion.section>
          ) : null}
        </>
      ) : null}

      {renderLiveStage && statusToastLabel ? (
        <motion.p
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.24 }}
          className="live-status-toast live-ui-layer"
          data-testid="live-status-toast"
        >
          {statusToastLabel}
        </motion.p>
      ) : null}

      {permissionsDone && offlineReason ? (
        <section className="live-offline-shell" data-testid="live-offline-shell">
          <motion.article
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: prefersReducedMotion ? 0 : 0.26 }}
            className="live-offline-card"
            data-testid="live-offline-card"
            data-offline-reason={offlineReason}
          >
            <p className="live-offline-kicker">Mission Control</p>
            <h2 className="live-offline-title">{offlineTitle}</h2>
            <p className="live-offline-hint">{offlineHint}</p>
            <div className="live-offline-grid">
              <p>Engine</p>
              <p>{engineRunning ? "RUNNING" : "OFFLINE"}</p>
              <p>Link</p>
              <p>{linkOnline ? "ONLINE" : "RECONNECTING"}</p>
              <p>Stream</p>
              <p>{streamStatus}</p>
              <p>Sync</p>
              <p>{syncHealthy ? "LOCKED" : "UNSTABLE"}</p>
              <p>Audience</p>
              <p>{String(session.audienceVector.participantCount)}</p>
            </div>
          </motion.article>
        </section>
      ) : null}

      {permissionsDone && countdownStep !== null ? (
        <motion.section
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ duration: prefersReducedMotion ? 0 : 0.24 }}
          className="live-countdown-shell"
          data-testid="live-reveal-countdown"
        >
          <motion.article
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: prefersReducedMotion ? 0 : 0.26 }}
            className="live-countdown-card"
          >
            <p className="live-countdown-kicker">Mission Control</p>
            <p className="live-countdown-title">Live Stage In</p>
            <div className="live-countdown-figure">
              <p className="live-countdown-value" aria-live="polite">
                {String(countdownStep).padStart(2, "0")}
              </p>
              <p className="live-countdown-unit">sec</p>
            </div>
            <div
              className="live-countdown-progress"
              role="progressbar"
              aria-valuenow={LIVE_REVEAL_COUNTDOWN_SECONDS - countdownStep + 1}
              aria-valuemin={0}
              aria-valuemax={LIVE_REVEAL_COUNTDOWN_SECONDS}
            >
              <span
                style={{
                  width: `${((LIVE_REVEAL_COUNTDOWN_SECONDS - countdownStep + 1) / LIVE_REVEAL_COUNTDOWN_SECONDS) * 100}%`
                }}
              />
            </div>
            <p className="live-countdown-hint">Holding until stream stabilizes.</p>
          </motion.article>
        </motion.section>
      ) : null}

      {!permissionsDone ? (
        <section className="live-permission-overlay" data-testid="live-permission-overlay">
          <PermissionGate
            onDone={(granted) => {
              permissionsSentRef.current = false;
              zoneSentRef.current = false;
              setPermissions(granted);
              setPermissionsDone(true);
            }}
          />
        </section>
      ) : null}
    </main>
  );
};
