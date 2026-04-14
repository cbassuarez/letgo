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
  type PhoneAudioAckPayload,
  type PhoneAudioCommandPayload,
  type PhoneAudioPoolStatePayload,
  type ProgramProceduralState,
  type SyncPacket,
  type TextScenePayload,
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
  sendPermissions: (permissions: DevicePermissions) => void;
  sendZoneUpdate: (zone: DeviceZone) => void;
  sendParticipantVector: (payload: ParticipantVectorPayload) => void;
  sendPhoneAudioAck: (payload: PhoneAudioAckPayload) => void;
  sendCrowdPickVote: (payload: CrowdPickVotePayload) => void;
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

export const computeReconnectDelayMs = (attempt: number, jitterSeed: number = 0.5): number => {
  const normalizedAttempt = Math.max(1, attempt);
  const unclampedBase = 1000 * Math.pow(2, normalizedAttempt - 1);
  const base = Math.min(30_000, unclampedBase);
  const normalizedJitter = Math.max(0, Math.min(1, jitterSeed));
  const signedJitter = (normalizedJitter - 0.5) * 0.5; // -25%..+25%
  return Math.max(1000, Math.min(30_000, Math.round(base * (1 + signedJitter))));
};

export const linkStateFromSilence = (silenceMs: number): SessionLinkState => {
  if (silenceMs > 30_000) {
    return "offline";
  }
  if (silenceMs > 20_000) {
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

        if (envelope.kind === "show_snapshot") {
          const snapshot = envelope.data as { logicalTime: number };
          setLogicalNow(snapshot.logicalTime);
        }

        if (envelope.kind === "cue") {
          const nextCue = envelope.data as CueCommand;
          cueRef.current = nextCue;
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
  }, [hashedId]);

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
    sendPermissions,
    sendZoneUpdate,
    sendParticipantVector,
    sendPhoneAudioAck,
    sendCrowdPickVote
  };
};
