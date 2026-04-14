import {
  clamp01,
  type ColorInteractionPolicy,
  deterministicPick,
  type Role,
  type ShowState,
  stableHashToSeed,
  type CompositorMode,
  type ScriptCandidate
} from "@conductor/protocol";
import { motion } from "framer-motion";
import { type CSSProperties, useEffect, useMemo, useRef, useState } from "react";
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
import { BACKEND_HTTP_ORIGIN } from "../lib/api";
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
  if (normalized === "interstitial" || normalized === "off") {
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
  const permissionsSentRef = useRef(false);
  const zoneSentRef = useRef(false);
  const handledPhoneCommandRef = useRef<string>("");

  const session = useConductorSession(hashedId);
  const {
    sendCrowdPickVote,
    sendPhoneAudioAck,
    sendPermissions,
    sendZoneUpdate,
    sendParticipantVector
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

  const defaultDynamicEnabled = session.cue?.showState === "main";
  const engineRunning = boolFromPayload(cuePayload.engineRunning, false);
  const rawOutputMode = typeof cuePayload.outputMode === "string" ? cuePayload.outputMode : "legacy";
  const interMode = rawOutputMode.toLowerCase() === "interstitial" || rawOutputMode.toLowerCase() === "off";
  const showFixed = engineRunning && (boolFromPayload(cuePayload.showFixed, false) || interMode);
  const showDynamic = engineRunning && boolFromPayload(cuePayload.showDynamic, defaultDynamicEnabled);
  const outputMode = rawOutputMode;
  const compositorDisplayMode = showDynamic
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
  const textSceneStyle = {
    transform: `translate(${(deviceTextVariance.spec.offsetX * 100).toFixed(2)}%, ${(deviceTextVariance.spec.offsetY * 100).toFixed(2)}%)`,
    opacity: clamp01((session.textScene.alpha + deviceTextVariance.spec.alphaBias) * session.proceduralState.textProbability),
    fontWeight: Math.round(360 + clamp01(session.textScene.weight + deviceTextVariance.spec.weightBias) * 420)
  } as CSSProperties;
  const proceduralClip = session.proceduralState.dynamicBinClipId ?? "none";
  const crowdPickWindow = session.crowdPickWindow;
  const pickWindowIsActive = Boolean(
    crowdPickWindow && clockNow >= crowdPickWindow.opensAt && clockNow <= crowdPickWindow.closesAt
  );
  const pickCountdownMs = crowdPickWindow ? Math.max(0, crowdPickWindow.closesAt - clockNow) : 0;

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
    if (!permissionsDone || !engineRunning) {
      return;
    }

    let timer: number | null = null;
    const pushVector = (): void => {
      sendParticipantVector({
        vector: participantVector.vector,
        influence: participantVector.influence,
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
    if (!session.phoneAudioCommand) {
      return;
    }
    if (handledPhoneCommandRef.current === session.phoneAudioCommand.commandId) {
      return;
    }
    handledPhoneCommandRef.current = session.phoneAudioCommand.commandId;
    void handleCommand(session.phoneAudioCommand);
  }, [handleCommand, session.phoneAudioCommand]);

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
          <Link to="/" className="cyanotype-cta mt-8 inline-flex">
            Return To Briefing
          </Link>
        </section>
      </main>
    );
  }

  return (
    <main className="cyanotype-shell relative min-h-dvh overflow-hidden text-cyanotype-050">
      <div className="cyanotype-atmosphere absolute inset-0" />

      {!permissionsDone ? (
        <PermissionGate
          onDone={(granted) => {
            permissionsSentRef.current = false;
            zoneSentRef.current = false;
            setPermissions(granted);
            setPermissionsDone(true);
          }}
        />
      ) : null}

      {permissionsDone ? (
        <>
          <FixedVideoLayer cue={session.cue} logicalNow={session.logicalNow} enabled={showFixed} />
          <DynamicOverlay
            vector={session.vector}
            line={textSceneLine}
            enabled={showDynamic}
            influence={participantVector.influence}
            procedural={session.proceduralState}
            onCompositorModeChange={setCompositorMode}
          />
          {textSceneLine ? (
            <motion.section
              initial={{ opacity: 0, y: 5 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.4 }}
              className="device-variance-text absolute left-1/2 top-[18%] z-20 w-[min(90vw,860px)] -translate-x-1/2 px-4 text-center"
              style={textSceneStyle}
            >
              <p className="cyanotype-kicker">CANONICAL SCENE · LOCAL VARIANCE</p>
              {deviceTextVariance.lines.map((line, index) => (
                <p
                  key={`scene-line-${session.textScene.sceneVersion}-${index}`}
                  className="font-display mt-2 text-2xl leading-tight text-cyanotype-000/94 sm:text-4xl"
                >
                  {line}
                </p>
              ))}
            </motion.section>
          ) : null}
          <motion.section
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5 }}
            className="color-bias-shell absolute inset-x-0 bottom-0 px-5 pb-5 sm:px-8 sm:pb-7"
          >
            <div className="color-bias-header">
              <p className="cyanotype-kicker">Crowd Color Layer</p>
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
                <p className="cyanotype-kicker">
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
          {!engineRunning || !session.connected ? (
            <motion.section
              initial={{ opacity: 0 }}
              animate={{ opacity: 1, y: [0, -3, 0] }}
              transition={{ y: { duration: 6.5, repeat: Infinity, ease: "easeInOut" } }}
              className="cyanotype-standby absolute bottom-8 left-1/2 w-[min(94vw,920px)] -translate-x-1/2 px-6 py-8 sm:px-8"
            >
              <p className="cyanotype-kicker">{session.connected ? "STANDBY" : "RECONNECTING"}</p>
              <h2 className="mt-3 text-4xl font-semibold leading-[0.95] sm:text-6xl">
                {session.connected
                  ? "This phone is armed and ready."
                  : "The field link is recovering."}
              </h2>
              <p className="font-display mt-6 text-2xl text-cyanotype-000/88 sm:text-4xl">
                {session.connected
                  ? "Stay present. Your vector feed is primed."
                  : "Hold. Reacquiring sync pulse and audience field."}
              </p>
              <p className="mt-4 max-w-3xl text-sm leading-relaxed text-cyanotype-100/80 sm:text-base">
                {session.connected
                  ? "Hold your device naturally. Participation is now automatic; no manual position tuning is required."
                  : "Stay on this screen. Your participant key and logbook access remain active while the link retries."}
              </p>
            </motion.section>
          ) : null}

          <motion.aside
            initial={{ opacity: 0, y: -12 }}
            animate={{ opacity: 1, y: 0 }}
            className="hud-strip absolute left-4 top-4 w-[min(92vw,420px)] px-4 py-3 text-[11px] uppercase tracking-[0.16em] text-cyanotype-100/84"
          >
            <div className="gng-block mb-3">
              <p className="cyanotype-kicker mb-2">GO / NO-GO</p>
              {goNoGoChecks.map((check) => (
                <div key={check.label} className="gng-row">
                  <span className={`gng-dot ${check.go ? "go" : "nogo"}`} />
                  <span>{check.label}</span>
                  <span>{check.go ? "GO" : "NOGO"}</span>
                </div>
              ))}
            </div>
            <p>{session.connected ? "Live Link" : "Field Reconnect"}</p>
            <p>Link {session.linkState}</p>
            {session.retryInMs !== null ? <p>Retry {(session.retryInMs / 1000).toFixed(1)}s</p> : null}
            <p>Compositor {compositorDisplayMode}</p>
            {backendHealth ? <p>Ping {backendHealth.latencyMs}ms</p> : null}
            <p>Influence {(participantVector.influence * 100).toFixed(0)}%</p>
            <p>Audience {session.audienceVector.participantCount}</p>
            <p>Color {session.lightingState.trend.toUpperCase()}</p>
            <p>ColorConf {(session.lightingState.confidence * 100).toFixed(0)}%</p>
            <p>AudioRMS {(session.audioFeatures.rms * 100).toFixed(0)}%</p>
            <p>Flux {(session.audioFeatures.flux * 100).toFixed(0)}%</p>
            <p>PhonePool {session.phoneAudioPoolState.availableDevices.length}</p>
            <p>PhoneGate {session.phoneAudioPoolState.gateCommitted ? "COMMIT" : "SAFE"}</p>
            <p>Clip {proceduralClip}</p>
            <p>Cadence {(session.proceduralState.cutCadence * 100).toFixed(0)}%</p>
            <p>Trans {session.proceduralState.transitionMode}</p>
            <p>Comp {session.proceduralState.compositorPreset}</p>
            <p>Split {session.proceduralState.splitLayout}</p>
            <p>TextP {(session.proceduralState.textProbability * 100).toFixed(0)}%</p>
            <p>Strict {(session.proceduralState.strictLooseBlend * 100).toFixed(0)}%</p>
            <p>Variance {(session.proceduralState.visualVariance * 100).toFixed(0)}%</p>
            <p>CrowdSteer {(session.proceduralState.crowdSteeringLevel * 100).toFixed(0)}%</p>
            <p>Drift {session.driftMs.toFixed(1)}ms</p>
            <p>{session.fallbackActive ? "Fallback" : "Synced"}</p>
            {session.fallbackActive ? <p>FallbackAge {(session.fallbackAgeMs / 1000).toFixed(1)}s</p> : null}
            <p>Engine {engineRunning ? "ON" : "OFF"}</p>
            <p>Mode {outputModeLabel(outputMode)}</p>
            <a
              href={`${BACKEND_HTTP_ORIGIN}/lighting/engineer`}
              target="_blank"
              rel="noreferrer"
              className="mt-3 inline-flex text-cyanotype-000 underline"
            >
              Open Lighting Endpoint
            </a>
            <a
              href={`${BACKEND_HTTP_ORIGIN}/audio/state`}
              target="_blank"
              rel="noreferrer"
              className="mt-3 inline-flex text-cyanotype-000 underline"
            >
              Open Audio Endpoint
            </a>
            <Link to={`/${hashedId}/logbook`} className="mt-3 inline-flex text-cyanotype-000 underline">
              Sign Digital Logbook
            </Link>
          </motion.aside>
        </>
      ) : null}
    </main>
  );
};
