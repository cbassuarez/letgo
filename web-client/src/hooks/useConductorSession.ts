import {
  type AudioFeaturePayload,
  type CrowdPickResultPayload,
  type CrowdPickVotePayload,
  type CrowdPickWindowPayload,
  type LightingStatePayload,
  normalizeVector,
  type AudienceVectorPayload,
  type CueCommand,
  type DevicePermissions,
  type DeviceZone,
  type ParticipantVectorPayload,
  type ParamVector,
  type ShowSceneKey,
  type ShowSnapshotPayload,
  type ShowState,
  type ShowStreamMap,
  type PhoneAudioAckPayload,
  type PhoneAudioCommandPayload,
  type PhoneAudioPoolStatePayload,
  type GroupStemStartPayload,
  type GroupStemStopPayload,
  type KeyboardPatchChangePayload,
  type KeyboardStatePayload,
  type PromptOfferPayload,
  type PromptResponsePayload,
  type ProgramProceduralState,
  type SyncPacket,
  type TextScenePayload,
  type VoiceStreamStartPayload,
  type VoiceStreamStopPayload,
  type WireEnvelope
} from "@conductor/protocol";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { readFallbackSnapshot, saveFallbackSnapshot } from "../lib/fallbackStore";
import { SyncClock } from "../lib/syncClock";
import { createSessionSocket, sendEnvelope } from "../lib/wsClient";

export type SessionLinkState = "connecting" | "online" | "degraded" | "offline" | "backoff";

interface SessionState {
  cue: CueCommand | null;
  vector: ParamVector;
  driftMs: number;
  connected: boolean;
  fallbackActive: boolean;
  fallbackAgeMs: number;
  linkState: SessionLinkState;
  retryInMs: number | null;
  logicalNow: number;
  audienceVector: AudienceVectorPayload;
  lightingState: LightingStatePayload;
  audioFeatures: AudioFeaturePayload;
  phoneAudioPoolState: PhoneAudioPoolStatePayload;
  crowdPickWindow: CrowdPickWindowPayload | null;
  crowdPickResult: CrowdPickResultPayload | null;
  proceduralState: ProgramProceduralState;
  textScene: TextScenePayload;
  phoneAudioCommand: PhoneAudioCommandPayload | null;
  keyboardState: KeyboardStatePayload | null;
  keyboardPatchChange: KeyboardPatchChangePayload | null;
  voiceStreamStart: VoiceStreamStartPayload | null;
  voiceStreamStop: VoiceStreamStopPayload | null;
  groupStemStart: GroupStemStartPayload | null;
  groupStemStop: GroupStemStopPayload | null;
  promptOffer: PromptOfferPayload | null;
  sendPermissions: (permissions: DevicePermissions) => void;
  sendZoneUpdate: (zone: DeviceZone) => void;
  sendParticipantVector: (payload: ParticipantVectorPayload) => void;
  sendPhoneAudioAck: (payload: PhoneAudioAckPayload) => void;
  sendCrowdPickVote: (payload: CrowdPickVotePayload) => void;
  sendPromptResponse: (payload: PromptResponsePayload) => void;
}

const defaultVector = normalizeVector({});
const defaultAudienceVector: AudienceVectorPayload = {
  vector: defaultVector,
  participantCount: 0,
  updatedAt: 0,
  compositorModes: {}
};

const defaultLightingState: LightingStatePayload = {
  targetColor: {
    oklch: { l: 0.56, c: 0.12, h: 220 },
    hex: "#2f5f8e"
  },
  confidence: 0,
  entropy: 0,
  stability: 1,
  trend: "hold",
  participantCount: 0,
  updatedAt: 0,
  zoneField: []
};

const defaultAudioFeatures: AudioFeaturePayload = {
  rms: 0,
  spectralCentroid: 0.5,
  flux: 0.5,
  transientDensity: 0,
  updatedAt: 0
};

const defaultPhoneAudioPoolState: PhoneAudioPoolStatePayload = {
  gateArmed: false,
  gateCommitted: false,
  quadRouteReady: false,
  availableDevices: [],
  activeVoices: {},
  updatedAt: 0
};

const defaultTextScene: TextScenePayload = {
  sceneVersion: 0,
  pickEpoch: 0,
  cueId: "idle:0",
  anchor: "center-center",
  lineCount: 1,
  cutMode: "hold",
  alpha: 0.85,
  fontScale: 1,
  weight: 0.6,
  durationMs: 4200,
  lines: [],
  guardrails: {
    maxOffsetX: 0.08,
    maxOffsetY: 0.06,
    minContrast: 4.5,
    minDurationMs: 2400
  }
};

const defaultProceduralState: ProgramProceduralState = {
  epoch: 0,
  seed: 0,
  updatedAt: 0,
  dynamicBinSelection: 0.5,
  dynamicBinIndex: 0,
  dynamicBinClipId: null,
  dynamicBinManifest: [],
  cutCadence: 0.5,
  transitionMode: "cut",
  compositorPreset: "blend",
  splitLayout: "none",
  fade: 0,
  textProbability: 0.5,
  strictLooseBlend: 0.5,
  visualVariance: 0.5,
  crowdSteeringLevel: 0,
  performerVector: defaultVector,
  audienceVector: defaultVector,
  textBlend: {
    mode: "always-mixed",
    probability: 0.5,
    strictRatio: 0.5,
    looseRatio: 0.5
  }
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

const isShowState = (value: unknown): value is ShowState =>
  typeof value === "string" && allShowStates.includes(value as ShowState);
const showSceneKeys: ShowSceneKey[] = [
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

const isRecord = (value: unknown): value is Record<string, unknown> =>
  Boolean(value) && typeof value === "object" && !Array.isArray(value);

const parseSceneKey = (value: unknown): ShowSceneKey | null =>
  typeof value === "string" && showSceneKeys.includes(value as ShowSceneKey)
    ? (value as ShowSceneKey)
    : null;

const parseBoolean = (value: unknown, fallback = false): boolean => {
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

const defaultOutputModeForState = (showState: ShowState | null): "off" | "static" | "dynamic" => {
  if (showState === "main") {
    return "dynamic";
  }
  if (showState === "preshow" || showState === "introduction" || showState === "ending") {
    return "static";
  }
  return "off";
};

const normalizeStreamUrl = (value: unknown): string | null => {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
};

const parseStreamMapFromUnknown = (value: unknown): ShowStreamMap => {
  if (isRecord(value)) {
    return showSceneKeys.reduce<ShowStreamMap>((acc, key) => {
      const maybe = normalizeStreamUrl(value[key]);
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
  const fromFields = showSceneKeys.reduce<ShowStreamMap>((acc, key) => {
    const maybe = normalizeStreamUrl(payload[streamPayloadFieldByScene[key]]);
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

const inferActiveSceneFromState = (
  showState: ShowState | null,
  payload: Record<string, unknown>,
  streamMap: ShowStreamMap
): ShowSceneKey | null => {
  const explicit = parseSceneKey(payload.showActiveScene ?? payload.activeSceneKey);
  const outputModeRaw = typeof payload.outputMode === "string" ? payload.outputMode.toLowerCase() : "";
  const outputMode = outputModeRaw.length > 0 ? outputModeRaw : defaultOutputModeForState(showState);
  const interstitialActive = parseBoolean(
    payload.interstitialActive,
    outputMode.includes("interstitial") || outputMode === "off"
  );
  const explicitAllowed =
    explicit &&
    ((showState === "preshow" && explicit === "preshow") ||
      (showState === "introduction" && explicit === "introduction") ||
      (showState === "ending" && explicit === "ending") ||
      (showState === "main" && (explicit === "mainStatic" || explicit === "mainDynamic")) ||
      (explicit === "interstitial" && interstitialActive) ||
      ((showState === "idle" || showState === "hold" || showState === "aborted" || showState === "recovery") &&
        explicit === "interstitial"));

  if (explicitAllowed) {
    return explicit;
  }

  if (showState === "preshow") {
    return streamMap.preshow ? "preshow" : null;
  }
  if (showState === "introduction") {
    return streamMap.introduction ? "introduction" : null;
  }
  if (showState === "ending") {
    return streamMap.ending ? "ending" : null;
  }
  if (interstitialActive && streamMap.interstitial) {
    return "interstitial";
  }
  if (showState === "main") {
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

const resolveCueVersion = (incomingVersion: unknown, payload: Record<string, unknown>, fallback = 0): number => {
  const payloadVersionRaw = payload.cueVersion;
  const payloadVersion =
    typeof payloadVersionRaw === "number"
      ? payloadVersionRaw
      : typeof payloadVersionRaw === "string"
        ? Number(payloadVersionRaw)
        : NaN;
  const normalizedIncoming = typeof incomingVersion === "number" ? incomingVersion : NaN;
  const candidates = [normalizedIncoming, payloadVersion, fallback].filter((value) => Number.isFinite(value));
  if (candidates.length === 0) {
    return 0;
  }
  return Math.max(...candidates);
};

const materializeStreamCuePayload = (
  basePayload: Record<string, unknown>,
  options?: {
    showState?: ShowState | null;
    streamMapOverride?: ShowStreamMap;
    activeSceneOverride?: ShowSceneKey | null;
    cueVersionOverride?: number | null;
  }
): Record<string, unknown> => {
  const nextPayload: Record<string, unknown> = { ...basePayload };
  const streamMap: ShowStreamMap = {
    ...parseStreamMapFromPayload(basePayload),
    ...(options?.streamMapOverride ?? {})
  };
  const hasStreamMap = Object.keys(streamMap).length > 0;

  if (hasStreamMap) {
    nextPayload.showStreamMap = streamMap;
    for (const key of showSceneKeys) {
      const maybe = streamMap[key];
      if (maybe) {
        nextPayload[streamPayloadFieldByScene[key]] = maybe;
      }
    }
  }

  const activeScene =
    parseSceneKey(options?.activeSceneOverride ?? null) ??
    inferActiveSceneFromState(options?.showState ?? null, nextPayload, streamMap);
  if (activeScene) {
    nextPayload.showActiveScene = activeScene;
    nextPayload.activeSceneKey = activeScene;
    const activeRef = streamMap[activeScene];
    if (activeRef) {
      nextPayload.showFixedMediaRef = activeRef;
      nextPayload.showFixedMediaMime = "application/vnd.apple.mpegurl";
    }
  }

  if (typeof options?.cueVersionOverride === "number") {
    nextPayload.cueVersion = options.cueVersionOverride;
  }

  return nextPayload;
};

export const computeReconnectDelayMs = (attempt: number, jitterSeed: number = 0.5): number => {
  const normalizedAttempt = Math.max(1, attempt);
  const unclampedBase = 1000 * Math.pow(2, normalizedAttempt - 1);
  const base = Math.min(30_000, unclampedBase);
  const normalizedJitter = Math.max(0, Math.min(1, jitterSeed));
  const signedJitter = (normalizedJitter - 0.5) * 0.5; // -25%..+25%
  return Math.max(1000, Math.min(30_000, Math.round(base * (1 + signedJitter))));
};

export const linkStateFromSilence = (silenceMs: number): SessionLinkState => {
  if (silenceMs > 12_000) {
    return "offline";
  }
  if (silenceMs > 8_000) {
    return "degraded";
  }
  return "online";
};

export const useConductorSession = (hashedId: string): SessionState => {
  const fallback = useMemo(() => readFallbackSnapshot(hashedId), [hashedId]);

  const [cue, setCue] = useState<CueCommand | null>(fallback?.cue ?? null);
  const [vector, setVector] = useState<ParamVector>(fallback?.vector ?? defaultVector);
  const [connected, setConnected] = useState(false);
  const [fallbackActive, setFallbackActive] = useState(Boolean(fallback));
  const [fallbackAgeMs, setFallbackAgeMs] = useState(() =>
    fallback ? Math.max(0, Date.now() - fallback.savedAt) : 0
  );
  const [logicalNow, setLogicalNow] = useState(cue?.logicalTime ?? 0);
  const [linkState, setLinkState] = useState<SessionLinkState>("connecting");
  const [retryInMs, setRetryInMs] = useState<number | null>(null);
  const [audienceVector, setAudienceVector] = useState<AudienceVectorPayload>(defaultAudienceVector);
  const [lightingState, setLightingState] = useState<LightingStatePayload>(defaultLightingState);
  const [audioFeatures, setAudioFeatures] = useState<AudioFeaturePayload>(defaultAudioFeatures);
  const [phoneAudioPoolState, setPhoneAudioPoolState] = useState<PhoneAudioPoolStatePayload>(
    defaultPhoneAudioPoolState
  );
  const [crowdPickWindow, setCrowdPickWindow] = useState<CrowdPickWindowPayload | null>(null);
  const [crowdPickResult, setCrowdPickResult] = useState<CrowdPickResultPayload | null>(null);
  const [proceduralState, setProceduralState] = useState<ProgramProceduralState>(defaultProceduralState);
  const [textScene, setTextScene] = useState<TextScenePayload>(defaultTextScene);
  const [phoneAudioCommand, setPhoneAudioCommand] = useState<PhoneAudioCommandPayload | null>(null);
  const [keyboardState, setKeyboardState] = useState<KeyboardStatePayload | null>(null);
  const [keyboardPatchChange, setKeyboardPatchChange] = useState<KeyboardPatchChangePayload | null>(null);
  const [voiceStreamStart, setVoiceStreamStart] = useState<VoiceStreamStartPayload | null>(null);
  const [voiceStreamStop, setVoiceStreamStop] = useState<VoiceStreamStopPayload | null>(null);
  const [groupStemStart, setGroupStemStart] = useState<GroupStemStartPayload | null>(null);
  const [groupStemStop, setGroupStemStop] = useState<GroupStemStopPayload | null>(null);
  const [promptOffer, setPromptOffer] = useState<PromptOfferPayload | null>(null);

  const clockRef = useRef(new SyncClock());
  const cueRef = useRef<CueCommand | null>(fallback?.cue ?? null);
  const vectorRef = useRef<ParamVector>(fallback?.vector ?? defaultVector);
  const cueReceivedAtRef = useRef<number>(Date.now());
  const socketRef = useRef<WebSocket | null>(null);
  const stoppedRef = useRef(false);
  const reconnectAttemptRef = useRef(0);
  const retryDeadlineMsRef = useRef<number | null>(null);
  const reconnectTimerRef = useRef<number | null>(null);
  const lastActivityAtRef = useRef<number>(Date.now());
  const linkStateRef = useRef<SessionLinkState>("connecting");
  const fallbackActivatedAtRef = useRef<number | null>(fallback ? Date.now() : null);
  const fallbackActiveRef = useRef<boolean>(Boolean(fallback));
  const lastCueEnvelopeSentAtRef = useRef<number>(Date.now());

  const shouldApplyCueCandidate = useCallback(
    (nextVersion: number, nextCueId: string, envelopeSentAt: number): boolean => {
      const currentVersion = cueRef.current?.version ?? -1;
      if (nextVersion > currentVersion) {
        return true;
      }
      if (nextVersion < currentVersion) {
        return false;
      }

      if (envelopeSentAt > lastCueEnvelopeSentAtRef.current) {
        return true;
      }
      if (envelopeSentAt < lastCueEnvelopeSentAtRef.current) {
        return false;
      }

      return cueRef.current ? cueRef.current.cueId !== nextCueId : true;
    },
    []
  );

  const sendWithSocket = useCallback(<T>(kind: WireEnvelope<T>["kind"], data: T): void => {
    const socket = socketRef.current;
    if (!socket) {
      return;
    }
    sendEnvelope(socket, kind, data);
  }, []);

  const sendPermissions = useCallback(
    (permissions: DevicePermissions): void => {
      sendWithSocket("permissions", permissions);
    },
    [sendWithSocket]
  );

  const sendZoneUpdate = useCallback(
    (zone: DeviceZone): void => {
      sendWithSocket("zone_update", zone);
    },
    [sendWithSocket]
  );

  const sendParticipantVector = useCallback(
    (payload: ParticipantVectorPayload): void => {
      sendWithSocket("participant_vector", payload);
    },
    [sendWithSocket]
  );

  const sendPhoneAudioAck = useCallback(
    (payload: PhoneAudioAckPayload): void => {
      sendWithSocket("phone_audio_ack", payload);
    },
    [sendWithSocket]
  );

  const sendCrowdPickVote = useCallback(
    (payload: CrowdPickVotePayload): void => {
      sendWithSocket("crowd_pick_vote", payload);
    },
    [sendWithSocket]
  );

  const sendPromptResponse = useCallback(
    (payload: PromptResponsePayload): void => {
      sendWithSocket("prompt_response", payload);
    },
    [sendWithSocket]
  );

  useEffect(() => {
    stoppedRef.current = false;

    const setLink = (next: SessionLinkState): void => {
      linkStateRef.current = next;
      setLinkState(next);
    };

    const persistFallback = (): void => {
      if (cueRef.current) {
        saveFallbackSnapshot(hashedId, { cue: cueRef.current, vector: vectorRef.current });
      }
    };

    const scheduleReconnect = (): void => {
      if (stoppedRef.current) {
        return;
      }

      reconnectAttemptRef.current += 1;
      const delayMs = computeReconnectDelayMs(reconnectAttemptRef.current, Math.random());
      retryDeadlineMsRef.current = Date.now() + delayMs;
      setRetryInMs(delayMs);
      setLink("backoff");

      if (reconnectTimerRef.current !== null) {
        window.clearTimeout(reconnectTimerRef.current);
      }

      reconnectTimerRef.current = window.setTimeout(() => {
        reconnectTimerRef.current = null;
        connectSocket();
      }, delayMs);
    };

    const handleDisconnected = (): void => {
      setConnected(false);
      fallbackActiveRef.current = true;
      setFallbackActive(true);
      fallbackActivatedAtRef.current = Date.now();
      persistFallback();
    };

    const connectSocket = (): void => {
      if (stoppedRef.current) {
        return;
      }

      socketRef.current?.close();
      setLink("connecting");
      setRetryInMs(null);
      retryDeadlineMsRef.current = null;

      const socket = createSessionSocket(hashedId);
      socketRef.current = socket;

      socket.addEventListener("open", () => {
        if (stoppedRef.current || socketRef.current !== socket) {
          return;
        }
        reconnectAttemptRef.current = 0;
        lastActivityAtRef.current = Date.now();
        setConnected(true);
        fallbackActiveRef.current = false;
        setFallbackActive(false);
        fallbackActivatedAtRef.current = null;
        setRetryInMs(null);
        retryDeadlineMsRef.current = null;
        setLink("online");
      });

      socket.addEventListener("error", () => {
        if (stoppedRef.current || socketRef.current !== socket) {
          return;
        }
        if (linkStateRef.current === "online") {
          setLink("degraded");
        }
      });

      socket.addEventListener("close", () => {
        if (socketRef.current !== socket) {
          return;
        }
        socketRef.current = null;
        if (stoppedRef.current) {
          return;
        }
        handleDisconnected();
        setLink("offline");
        scheduleReconnect();
      });

      socket.addEventListener("message", (event) => {
        if (stoppedRef.current || socketRef.current !== socket) {
          return;
        }
        lastActivityAtRef.current = Date.now();
        if (linkStateRef.current !== "online") {
          setLink("online");
        }

        const envelope = JSON.parse(event.data) as WireEnvelope;
        const envelopeSentAt =
          typeof envelope.sentAt === "number" && Number.isFinite(envelope.sentAt)
            ? envelope.sentAt
            : Date.now();

        if (envelope.kind === "show_snapshot") {
          const snapshot = envelope.data as Partial<ShowSnapshotPayload>;
          if (typeof snapshot.logicalTime === "number" && Number.isFinite(snapshot.logicalTime)) {
            setLogicalNow(snapshot.logicalTime);
          }

          if (isShowState(snapshot.state) && typeof snapshot.logicalTime === "number" && Number.isFinite(snapshot.logicalTime)) {
            const basePayload = isRecord(snapshot.cuePayload)
              ? snapshot.cuePayload
              : ((cueRef.current?.payload ?? {}) as Record<string, unknown>);
            const payload = materializeStreamCuePayload(basePayload, {
              showState: snapshot.state,
              streamMapOverride: parseStreamMapFromUnknown(snapshot.streamMap),
              activeSceneOverride: parseSceneKey(snapshot.activeScene),
              cueVersionOverride:
                typeof snapshot.cueVersion === "number" && Number.isFinite(snapshot.cueVersion)
                  ? snapshot.cueVersion
                  : null
            });
            const nextVersion = resolveCueVersion(
              typeof snapshot.cueVersion === "number" ? snapshot.cueVersion : snapshot.version,
              payload,
              cueRef.current?.version ?? 0
            );
            const nextCueId =
              typeof snapshot.cueId === "string"
                ? snapshot.cueId
                : `${snapshot.state}:${Math.round(snapshot.logicalTime)}:snapshot`;
            if (!shouldApplyCueCandidate(nextVersion, nextCueId, envelopeSentAt)) {
              return;
            }

            const nextCue: CueCommand = {
              cueId: nextCueId,
              showState: snapshot.state,
              logicalTime: snapshot.logicalTime,
              payload,
              version: nextVersion,
              action: cueRef.current?.action ?? "jump"
            };
            cueRef.current = nextCue;
            lastCueEnvelopeSentAtRef.current = envelopeSentAt;
            cueReceivedAtRef.current = Date.now();
            setCue(nextCue);
          }
        }

        if (envelope.kind === "cue") {
          const inboundCue = envelope.data as CueCommand;
          const payload = materializeStreamCuePayload((inboundCue.payload ?? {}) as Record<string, unknown>, {
            showState: inboundCue.showState,
            streamMapOverride: parseStreamMapFromPayload((cueRef.current?.payload ?? {}) as Record<string, unknown>),
            activeSceneOverride:
              parseSceneKey((inboundCue.payload as Record<string, unknown> | undefined)?.showActiveScene) ??
              parseSceneKey((inboundCue.payload as Record<string, unknown> | undefined)?.activeSceneKey)
          });
          const nextVersion = resolveCueVersion(inboundCue.version, payload, cueRef.current?.version ?? 0);
          if (!shouldApplyCueCandidate(nextVersion, inboundCue.cueId, envelopeSentAt)) {
            return;
          }

          const nextCue: CueCommand = {
            ...inboundCue,
            payload,
            version: nextVersion
          };

          cueRef.current = nextCue;
          lastCueEnvelopeSentAtRef.current = envelopeSentAt;
          cueReceivedAtRef.current = Date.now();
          setCue(nextCue);
          setLogicalNow(nextCue.logicalTime);
        }

        if (envelope.kind === "param_vector") {
          const nextVector = normalizeVector(envelope.data as Partial<ParamVector>);
          vectorRef.current = nextVector;
          setVector(nextVector);
        }

        if (envelope.kind === "audience_vector") {
          const payload = envelope.data as AudienceVectorPayload;
          setAudienceVector({
            ...payload,
            vector: normalizeVector(payload.vector)
          });
        }

        if (envelope.kind === "lighting_state") {
          const payload = envelope.data as LightingStatePayload;
          setLightingState(payload);
        }

        if (envelope.kind === "audio_features") {
          setAudioFeatures(envelope.data as AudioFeaturePayload);
        }

        if (envelope.kind === "phone_audio_pool_state") {
          setPhoneAudioPoolState(envelope.data as PhoneAudioPoolStatePayload);
        }

        if (envelope.kind === "crowd_pick_window") {
          setCrowdPickWindow(envelope.data as CrowdPickWindowPayload);
        }

        if (envelope.kind === "crowd_pick_result") {
          setCrowdPickResult(envelope.data as CrowdPickResultPayload);
        }

        if (envelope.kind === "text_scene") {
          setTextScene(envelope.data as TextScenePayload);
        }

        if (envelope.kind === "procedural_state") {
          setProceduralState(envelope.data as ProgramProceduralState);
        }

        if (envelope.kind === "phone_audio_command") {
          setPhoneAudioCommand(envelope.data as PhoneAudioCommandPayload);
        }

        if (envelope.kind === "keyboard_state") {
          setKeyboardState(envelope.data as KeyboardStatePayload);
        }

        if (envelope.kind === "keyboard_patch_change") {
          setKeyboardPatchChange(envelope.data as KeyboardPatchChangePayload);
        }

        if (envelope.kind === "voice_stream_start") {
          setVoiceStreamStart(envelope.data as VoiceStreamStartPayload);
        }

        if (envelope.kind === "voice_stream_stop") {
          setVoiceStreamStop(envelope.data as VoiceStreamStopPayload);
        }

        if (envelope.kind === "group_stem_start") {
          setGroupStemStart(envelope.data as GroupStemStartPayload);
        }

        if (envelope.kind === "group_stem_stop") {
          setGroupStemStop(envelope.data as GroupStemStopPayload);
        }

        if (envelope.kind === "prompt_offer") {
          setPromptOffer(envelope.data as PromptOfferPayload);
        }

        if (envelope.kind === "sync") {
          const packet = envelope.data as SyncPacket;
          if (packet.kind === "ping") {
            const now = Date.now();
            const drift = clockRef.current.observe({
              serverTime: packet.serverTime,
              clientTime: now,
              receivedAt: now
            });
            setLogicalNow((current: number) => clockRef.current.estimateLogicalNow(current));

            sendEnvelope(socket, "sync", {
              kind: "pong",
              serverTime: packet.serverTime,
              clientTime: now,
              rtt: 0,
              driftEstimate: drift
            } satisfies SyncPacket);
          }
        }
      });
    };

    connectSocket();

    const logicalTimer = window.setInterval(() => {
      if (cueRef.current) {
        const elapsed = Date.now() - cueReceivedAtRef.current;
        setLogicalNow(Math.max(cueRef.current.logicalTime, cueRef.current.logicalTime + elapsed));
      }

      if (fallbackActiveRef.current) {
        const activatedAt = fallbackActivatedAtRef.current ?? Date.now();
        setFallbackAgeMs(Math.max(0, Date.now() - activatedAt));
      } else {
        setFallbackAgeMs(0);
      }

      setPromptOffer((current) => {
        if (!current) {
          return current;
        }
        if (Date.now() > current.expiresAt) {
          return null;
        }
        return current;
      });
    }, 200);

    const supervisionTimer = window.setInterval(() => {
      if (retryDeadlineMsRef.current !== null) {
        setRetryInMs(Math.max(0, retryDeadlineMsRef.current - Date.now()));
      } else {
        setRetryInMs(null);
      }

      if (!socketRef.current || socketRef.current.readyState !== WebSocket.OPEN) {
        return;
      }

      const silenceMs = Date.now() - lastActivityAtRef.current;
      const targetState = linkStateFromSilence(silenceMs);

      if (targetState === "degraded" && linkStateRef.current === "online") {
        setLink("degraded");
        return;
      }

      if (targetState === "offline") {
        socketRef.current.close();
      }
    }, 1000);

    return () => {
      stoppedRef.current = true;
      window.clearInterval(logicalTimer);
      window.clearInterval(supervisionTimer);
      if (reconnectTimerRef.current !== null) {
        window.clearTimeout(reconnectTimerRef.current);
      }
      retryDeadlineMsRef.current = null;
      socketRef.current?.close();
    };
  }, [hashedId, shouldApplyCueCandidate]);

  return {
    cue,
    vector,
    driftMs: clockRef.current.getDrift(),
    connected,
    fallbackActive,
    fallbackAgeMs,
    linkState,
    retryInMs,
    logicalNow,
    audienceVector,
    lightingState,
    audioFeatures,
    phoneAudioPoolState,
    crowdPickWindow,
    crowdPickResult,
    proceduralState,
    textScene,
    phoneAudioCommand,
    keyboardState,
    keyboardPatchChange,
    voiceStreamStart,
    voiceStreamStop,
    groupStemStart,
    groupStemStop,
    promptOffer,
    sendPermissions,
    sendZoneUpdate,
    sendParticipantVector,
    sendPhoneAudioAck,
    sendCrowdPickVote,
    sendPromptResponse
  };
};
