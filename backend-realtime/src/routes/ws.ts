import {
  type AudioFeaturePayload,
  type AudioOpsStatePayload,
  type AudienceVectorPayload,
  type CueActivationAckPayload,
  clamp01,
  type ColorIntentPayload,
  type CompositorMode,
  type CrowdPickVotePayload,
  type CrowdPickResultPayload,
  type CueCommand,
  type ShowState,
  type ShowSceneKey,
  type ShowSnapshotPayload,
  type ShowStreamMap,
  type ShowCatalogClipEntry,
  type ShowMediaCatalog,
  isCueCommand,
  type LightingStatePayload,
  normalizeVector,
  type ParamVector,
  type ParticipantVectorPayload,
  type PhoneAudioAckPayload,
  type PhoneAudioCommandPayload,
  type PhoneAudioPoolStatePayload,
  type PushDeckEventPayload,
  type PushPadLabelsPayload,
  type PushDeckBankDomain,
  type ProgramProceduralState,
  type PromptOfferPayload,
  type PromptResponsePayload,
  stableHashToSeed,
  type TakeTimingPolicy,
  type EchoCapsByStem,
  type EchoStem,
  type GroupStemDescriptor,
  type GroupStemStartPayload,
  type GroupStemStopPayload,
  type KeyboardPatchChangePayload,
  type KeyboardStatePayload,
  type VoicePublisherAnnouncePayload,
  type PushDeckMLParamKey,
  type TextBlendState,
  type TextRuntimeStatusPayload,
  type TextRuntimeUpdatePayload,
  type SyncPacket,
  type TextScenePayload,
  type TransitionMode,
  type CompositorPreset,
  type SplitLayout,
  type VoiceStreamStartPayload,
  type VoiceStreamStopPayload,
  type VoiceStreamSubscribePayload,
  type VoiceStreamSubscribedPayload,
  type VoiceStreamUnsubscribePayload,
  type VoiceStreamIceCandidatePayload,
  type VoiceStreamDescriptor,
  type WireEnvelope
} from "@conductor/protocol";
import type { FastifyInstance } from "fastify";
import type { WebSocket } from "ws";
import type { AppConfig } from "../config";
import { AudienceVectorField } from "../services/audienceVectorField";
import type { AudioOpsStateHub } from "../services/audioOpsStateHub";
import {
  type SyncHealthSample,
  buildCueTimingSchedule
} from "../services/cueTimingScheduler";
import type { CrowdPickPulseService } from "../services/crowdPickPulse";
import { CrowdLightingField } from "../services/crowdLightingField";
import { IdentityService } from "../services/identityService";
import { PhoneChoirSpatialAllocator } from "../services/phoneChoirSpatialAllocator";
import type { PhoneAudioPoolService } from "../services/phoneAudioPool";
import { ReplayService } from "../services/replayService";
import { ShowOrchestrator } from "../services/showOrchestrator";
import { SyncService } from "../services/syncService";
import type { TextSceneComposerService } from "../services/textSceneComposer";
import { PromptOrchestrator } from "../services/promptOrchestrator";
import type { SessionStore } from "../stores/sessionStore";
import { logger } from "../utils/logger";
import { ManagedSFUCoordinator } from "../services/managedSfuCoordinator";
import { MediasoupVoiceService } from "../services/mediasoupVoiceService";
import {
  findCatalogClipById,
  inferCatalogUrlFromBaseUrl,
  loadShowMediaCatalog,
  pickCatalogClip,
  streamMapFromCatalogStaticEntries
} from "../services/showMediaCatalog";

interface WsDependencies {
  config: AppConfig;
  audioOpsStateHub: AudioOpsStateHub;
  crowdPickPulse: CrowdPickPulseService;
  identityService: IdentityService;
  lightingField: CrowdLightingField;
  phoneAudioPool: PhoneAudioPoolService;
  replayService: ReplayService;
  show: ShowOrchestrator;
  sync: SyncService;
  sessions: SessionStore;
  textSceneComposer: TextSceneComposerService;
}

type HarnessInbound =
  | { kind: "cue"; data: CueCommand }
  | {
      kind: "command";
      data: {
        action: "start" | "hold" | "jump" | "abort" | "recover";
        targetState?: CueCommand["showState"];
        payload?: Record<string, unknown>;
      };
    }
  | { kind: "param_vector"; data: Partial<ParamVector> }
  | { kind: "replay"; data: { action: "latest" | "freeze"; centerTimestamp?: number } }
  | { kind: "audio_features"; data: Partial<AudioFeaturePayload> }
  | { kind: "phone_audio_pool_state"; data: Partial<PhoneAudioPoolStatePayload> }
  | { kind: "phone_audio_command"; data: Partial<PhoneAudioCommandPayload> }
  | { kind: "keyboard_state"; data: Partial<KeyboardStatePayload> }
  | { kind: "keyboard_patch_change"; data: Partial<KeyboardPatchChangePayload> }
  | { kind: "voice_publisher_announce"; data: Partial<VoicePublisherAnnouncePayload> }
  | { kind: "push_pad_labels"; data: Partial<PushPadLabelsPayload> }
  | { kind: "text_scene"; data: Partial<TextScenePayload> & { cueId?: string } }
  | { kind: "text_runtime_update"; data: Partial<TextRuntimeUpdatePayload> }
  | { kind: "procedural_state"; data: Partial<ProgramProceduralState> }
  | { kind: "telemetry"; data: Record<string, unknown> };

type DeviceInbound =
  | { kind: "sync"; data: SyncPacket }
  | { kind: "telemetry"; data: Record<string, unknown> }
  | { kind: "participant_vector"; data: Partial<ParticipantVectorPayload> & { vector?: Partial<ParamVector> } }
  | { kind: "zone_update"; data: { name: string; x: number; y: number; z?: number } }
  | { kind: "permissions"; data: { audio?: boolean; geolocation?: boolean; motion?: boolean } }
  | { kind: "ack"; data: CueActivationAckPayload }
  | { kind: "phone_audio_ack"; data: Partial<PhoneAudioAckPayload> }
  | { kind: "voice_stream_subscribe"; data: Partial<VoiceStreamSubscribePayload> }
  | { kind: "voice_stream_unsubscribe"; data: Partial<VoiceStreamUnsubscribePayload> }
  | { kind: "voice_stream_ice"; data: Partial<VoiceStreamIceCandidatePayload> }
  | { kind: "push_deck_event"; data: Partial<PushDeckEventPayload> }
  | { kind: "crowd_pick_vote"; data: Partial<CrowdPickVotePayload> }
  | { kind: "prompt_response"; data: Partial<PromptResponsePayload> };

const parse = <T>(raw: string): T | null => {
  try {
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
};

const send = (socket: WebSocket, payload: unknown): void => {
  socket.send(JSON.stringify(payload));
};

export const registerWsRoutes = async (app: FastifyInstance, deps: WsDependencies): Promise<void> => {
  const harnessSockets = new Set<WebSocket>();
  const deviceSockets = new Map<string, WebSocket>();
  const audienceField = new AudienceVectorField();
  const choirAllocator = new PhoneChoirSpatialAllocator();
  const pendingVoiceAcks = new Map<
    string,
    {
      note: number;
      targetHashedId: string;
      command: PhoneAudioCommandPayload;
      timeout: NodeJS.Timeout;
      failoverAttempts: number;
    }
  >();
  const managedSfuCoordinator = new ManagedSFUCoordinator({
    baseUrl: deps.config.CONDUCTOR_MANAGED_SFU_BASE_URL,
    groupStemBaseUrl: deps.config.CONDUCTOR_GROUP_STEM_BASE_URL ?? deps.config.CONDUCTOR_MANAGED_SFU_BASE_URL,
    voiceCodec: deps.config.CONDUCTOR_VOICE_STREAM_CODEC,
    groupCodec: deps.config.CONDUCTOR_GROUP_STREAM_CODEC,
    streamTtlMs: deps.config.CONDUCTOR_VOICE_STREAM_TTL_MS,
    sessionPrefix: deps.config.CONDUCTOR_MANAGED_SFU_SESSION_PREFIX,
    tokenSecret: deps.config.CONDUCTOR_MANAGED_SFU_TOKEN_SECRET
  });
  const parseIceServers = (): Array<{ urls: string | string[]; username?: string; credential?: string }> => {
    const raw = deps.config.CONDUCTOR_SFU_ICE_SERVERS_JSON;
    if (!raw || raw.trim().length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(raw);
      if (!Array.isArray(parsed)) {
        return [];
      }
      const servers: Array<{ urls: string | string[]; username?: string; credential?: string }> = [];
      for (const entry of parsed) {
        const record =
          entry && typeof entry === "object" && !Array.isArray(entry)
            ? (entry as Record<string, unknown>)
            : null;
        if (!record || (!Array.isArray(record.urls) && typeof record.urls !== "string")) {
          continue;
        }
        const urls = Array.isArray(record.urls)
          ? record.urls.filter((url): url is string => typeof url === "string" && url.trim().length > 0)
          : record.urls;
        const server: { urls: string | string[]; username?: string; credential?: string } = {
          urls
        };
        if (typeof record.username === "string" && record.username.trim().length > 0) {
          server.username = record.username;
        }
        if (typeof record.credential === "string" && record.credential.trim().length > 0) {
          server.credential = record.credential;
        }
        servers.push(server);
      }
      return servers;
    } catch {
      logger.warn("failed to parse CONDUCTOR_SFU_ICE_SERVERS_JSON");
      return [];
    }
  };
  const mediasoupVoiceService = new MediasoupVoiceService({
    enabled:
      deps.config.CONDUCTOR_SFU_ENABLED ||
      deps.config.CONDUCTOR_VOICE_STREAM_TRANSPORT === "webrtc",
    roomId: deps.config.CONDUCTOR_SFU_ROOM_ID,
    listenIp: deps.config.CONDUCTOR_SFU_LISTEN_IP,
    announcedIp: deps.config.CONDUCTOR_SFU_ANNOUNCED_IP,
    rtcMinPort: deps.config.CONDUCTOR_SFU_RTC_MIN_PORT,
    rtcMaxPort: deps.config.CONDUCTOR_SFU_RTC_MAX_PORT,
    maxSubscribers: Math.max(1, deps.config.CONDUCTOR_SFU_MAX_SUBSCRIBERS),
    iceServers: parseIceServers()
  });
  await mediasoupVoiceService.start();
  const maxConcurrentVoiceStreams = Math.max(1, Math.min(64, deps.config.CONDUCTOR_VOICE_STREAM_MAX_CONCURRENT));
  const activeVoiceStreamsByNote = new Map<number, Map<string, VoiceStreamDescriptor>>();
  const activeGroupStemByTarget = new Map<string, GroupStemDescriptor>();
  const pushContinuousThrottleMs = 24;
  const pushLastForwardAt = new Map<string, number>();
  const pushPendingContinuousEvents = new Map<
    string,
    {
      payload: PushDeckEventPayload;
      timeout: NodeJS.Timeout;
    }
  >();
  const promptOrchestrator = new PromptOrchestrator();
  const promptInfluenceByDevice = new Map<string, { promptInfluence: number; directPickInfluence: number }>();
  const echoByStem: Record<EchoStem, number> = {
    pads: 0,
    hotas: 0,
    choir: 0,
    fx: 0
  };
  let globalEchoProbability = 0;
  let latestKeyboardState: KeyboardStatePayload | null = null;
  const wsApp = app as unknown as {
    get: (
      path: string,
      opts: { websocket: true },
      handler: (socket: WebSocket, req: { params: { hashedId?: string } }) => void | Promise<void>
    ) => void;
  };

  let lastTextComposeAt = 0;
  let lastAudioFeatures: AudioFeaturePayload = {
    rms: 0,
    spectralCentroid: 0.5,
    flux: 0.5,
    transientDensity: 0,
    updatedAt: 0
  };
  let lastPushPadLabels: PushPadLabelsPayload | null = null;
  let baseProceduralState = createDefaultProceduralState(deps.show.snapshot().vector);
  let effectiveProceduralState = baseProceduralState;
  const defaultColorPolicy = {
    enabled: true,
    roles: ["audience", "performer", "observer"],
    showStates: ["idle", "preshow", "introduction", "main", "ending", "hold", "aborted", "recovery"]
  } as const;

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
  const voicePublisherSessionId = `${deps.config.CONDUCTOR_MANAGED_SFU_SESSION_PREFIX}-voice`;
  const normalizeVoiceDescriptorForTransport = (
    descriptor: VoiceStreamDescriptor,
    note: number
  ): VoiceStreamDescriptor => {
    if (!mediasoupVoiceService.isEnabled()) {
      return descriptor;
    }
    return {
      ...descriptor,
      sessionId: voicePublisherSessionId,
      trackId: `note-${Math.max(0, Math.min(127, Math.round(note)))}`,
      codec: "opus"
    };
  };

  const normalizeStreamURL = (value: unknown): string | null => {
    if (typeof value !== "string") {
      return null;
    }
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : null;
  };

  const inferMediaMimeType = (mediaRef: string): string => {
    const normalized = mediaRef.split(/[?#]/, 1)[0]?.toLowerCase() ?? "";
    if (normalized.endsWith(".m3u8")) {
      return "application/vnd.apple.mpegurl";
    }
    if (normalized.endsWith(".mp4") || normalized.endsWith(".m4v")) {
      return "video/mp4";
    }
    if (normalized.endsWith(".mov")) {
      return "video/quicktime";
    }
    if (normalized.endsWith(".webm")) {
      return "video/webm";
    }
    return "application/octet-stream";
  };

  const joinUrlPath = (base: string, path: string): string => {
    const normalizedBase = base.endsWith("/") ? base.slice(0, -1) : base;
    const normalizedPath = path.startsWith("/") ? path.slice(1) : path;
    return `${normalizedBase}/${normalizedPath}`;
  };

  const asRecord = (value: unknown): Record<string, unknown> | null => {
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      return null;
    }
    return value as Record<string, unknown>;
  };

  const parseBoolean = (value: unknown, fallback = false): boolean => {
    if (typeof value === "boolean") {
      return value;
    }
    if (typeof value === "string") {
      if (value === "true") {
        return true;
      }
      if (value === "false") {
        return false;
      }
    }
    return fallback;
  };

  const parseSceneKey = (value: unknown): ShowSceneKey | null => {
    if (typeof value !== "string") {
      return null;
    }
    return sceneKeys.includes(value as ShowSceneKey) ? (value as ShowSceneKey) : null;
  };

  const defaultOutputModeForState = (showState: ShowState): "static" | "dynamic" | "off" => {
    if (showState === "main") {
      return "dynamic";
    }
    if (showState === "preshow" || showState === "introduction" || showState === "ending") {
      return "static";
    }
    return "off";
  };

  const resolveEchoCapsByScene = (scene: ShowSceneKey | null): EchoCapsByStem => {
    const key = scene ?? "interstitial";
    if (key === "mainDynamic") {
      return {
        pads: { floor: 0.02, cap: 0.28 },
        hotas: { floor: 0.01, cap: 0.24 },
        choir: { floor: 0.02, cap: 0.32 },
        fx: { floor: 0.01, cap: 0.26 }
      };
    }
    if (key === "mainStatic") {
      return {
        pads: { floor: 0.01, cap: 0.2 },
        hotas: { floor: 0.01, cap: 0.18 },
        choir: { floor: 0.02, cap: 0.24 },
        fx: { floor: 0.01, cap: 0.2 }
      };
    }
    if (key === "ending") {
      return {
        pads: { floor: 0.01, cap: 0.16 },
        hotas: { floor: 0.01, cap: 0.16 },
        choir: { floor: 0.02, cap: 0.2 },
        fx: { floor: 0.01, cap: 0.18 }
      };
    }
    return {
      pads: { floor: 0.01, cap: 0.14 },
      hotas: { floor: 0.01, cap: 0.14 },
      choir: { floor: 0.01, cap: 0.18 },
      fx: { floor: 0.01, cap: 0.16 }
    };
  };

  const parseStreamMap = (payload: Record<string, unknown>): ShowStreamMap => {
    const map: ShowStreamMap = {};

    const rawMap = payload.showStreamMap;
    const rawMapRecord =
      asRecord(rawMap) ??
      (() => {
        if (typeof rawMap !== "string") {
          return null;
        }
        try {
          return asRecord(JSON.parse(rawMap));
        } catch {
          return null;
        }
      })();
    if (rawMapRecord) {
      for (const key of sceneKeys) {
        const value = normalizeStreamURL(rawMapRecord[key]);
        if (value) {
          map[key] = value;
        }
      }
    }

    for (const key of sceneKeys) {
      const value = normalizeStreamURL(payload[streamPayloadFieldByScene[key]]);
      if (value) {
        map[key] = value;
      }
    }

    return map;
  };

  const defaultProductionCatalogURL = "https://media.letgofilm.com/show-raw-apr22-original/catalog.json";
  const configuredBaseURL = normalizeStreamURL(deps.config.CONDUCTOR_HLS_BASE_URL);
  const configuredCatalogURL =
    normalizeStreamURL(deps.config.CONDUCTOR_HLS_CATALOG_URL) ??
    (configuredBaseURL
      ? inferCatalogUrlFromBaseUrl(configuredBaseURL)
      : deps.config.NODE_ENV === "production"
        ? defaultProductionCatalogURL
        : null);

  let loadedCatalog: ShowMediaCatalog | null = null;
  if (configuredCatalogURL) {
    loadedCatalog = await loadShowMediaCatalog(configuredCatalogURL);
  }

  const buildConfiguredStreamMap = (catalogStaticMap: ShowStreamMap = {}): ShowStreamMap => {
    const fromBaseURL: ShowStreamMap = configuredBaseURL
      ? {
          interstitial: joinUrlPath(configuredBaseURL, "interstitial/interstitial.m3u8"),
          preshow: joinUrlPath(configuredBaseURL, "preshow/preshow.m3u8"),
          introduction: joinUrlPath(configuredBaseURL, "introduction/introduction.m3u8"),
          mainStatic: joinUrlPath(configuredBaseURL, "main/main.m3u8"),
          mainDynamic: joinUrlPath(configuredBaseURL, "main/main.m3u8"),
          ending: joinUrlPath(configuredBaseURL, "ending/ending.m3u8")
        }
      : {};

    const mainLegacy = normalizeStreamURL(deps.config.CONDUCTOR_HLS_MAIN_URL);
    const fromEnvFields: ShowStreamMap = {};
    const fieldMap: Record<ShowSceneKey, string | undefined> = {
      interstitial: deps.config.CONDUCTOR_HLS_INTERSTITIAL_URL,
      preshow: deps.config.CONDUCTOR_HLS_PRESHOW_URL,
      introduction: deps.config.CONDUCTOR_HLS_INTRODUCTION_URL,
      mainStatic: deps.config.CONDUCTOR_HLS_MAIN_STATIC_URL ?? mainLegacy ?? undefined,
      mainDynamic: deps.config.CONDUCTOR_HLS_MAIN_DYNAMIC_URL ?? mainLegacy ?? undefined,
      ending: deps.config.CONDUCTOR_HLS_ENDING_URL
    };
    for (const key of sceneKeys) {
      const value = normalizeStreamURL(fieldMap[key]);
      if (value) {
        fromEnvFields[key] = value;
      }
    }

    const rawMap = deps.config.CONDUCTOR_HLS_STREAM_MAP;
    const fromJson: ShowStreamMap = {};
    if (rawMap) {
      try {
        const parsed = JSON.parse(rawMap) as Record<string, unknown>;
        for (const key of sceneKeys) {
          const value = normalizeStreamURL(parsed[key]);
          if (value) {
            fromJson[key] = value;
          }
        }
      } catch {
        logger.warn("invalid CONDUCTOR_HLS_STREAM_MAP json", {
          value: rawMap
        });
      }
    }

    return {
      ...fromBaseURL,
      ...catalogStaticMap,
      ...fromJson,
      ...fromEnvFields
    };
  };

  let configuredStreamMap: ShowStreamMap = buildConfiguredStreamMap(
    loadedCatalog ? streamMapFromCatalogStaticEntries(loadedCatalog) : {}
  );

  const mergeStreamMaps = (base: ShowStreamMap, incoming: ShowStreamMap): ShowStreamMap => {
    if (Object.keys(incoming).length === 0) {
      return base;
    }
    return {
      ...base,
      ...incoming
    };
  };

  const inferActiveSceneFromCue = (cue: CueCommand, streamMap: ShowStreamMap): ShowSceneKey | null => {
    const payload = (cue.payload ?? {}) as Record<string, unknown>;
    const outputModeRaw = typeof payload.outputMode === "string" ? payload.outputMode.toLowerCase() : "";
    const outputMode = outputModeRaw.length > 0 ? outputModeRaw : defaultOutputModeForState(cue.showState);
    const interstitialActive = parseBoolean(
      payload.interstitialActive,
      outputMode.includes("interstitial") || outputMode === "off"
    );
    const explicit = parseSceneKey(payload.showActiveScene ?? payload.activeSceneKey);
    if (explicit) {
      if (explicit === "interstitial") {
        return interstitialActive ? "interstitial" : null;
      }
      // Trust explicit scene hints from harness so mode commits can move
      // off interstitial immediately, even before full stream maps resolve.
      return explicit;
    }

    if (cue.showState === "preshow") {
      return "preshow";
    }
    if (cue.showState === "introduction") {
      return "introduction";
    }
    if (cue.showState === "ending") {
      return "ending";
    }
    if (interstitialActive && streamMap.interstitial) {
      return "interstitial";
    }
    if (cue.showState === "main") {
      if (outputMode.includes("dynamic")) {
        return "mainDynamic";
      }
      if (outputMode.includes("static") || outputMode === "program") {
        return "mainStatic";
      }
      return (streamMap.mainDynamic ? "mainDynamic" : null) ?? (streamMap.mainStatic ? "mainStatic" : null);
    }
    return null;
  };

  const fallbackOutputForState = (
    showState: ShowState
  ): {
    outputMode: string;
    showFixed: boolean;
    showDynamic: boolean;
    interstitialActive: boolean;
  } => {
    switch (showState) {
      case "preshow":
      case "introduction":
      case "ending":
        return {
          outputMode: "static",
          showFixed: true,
          showDynamic: false,
          interstitialActive: false
        };
      case "main":
        return {
          outputMode: "dynamic",
          showFixed: false,
          showDynamic: true,
          interstitialActive: false
        };
      case "idle":
      case "hold":
      case "aborted":
      case "recovery":
      default:
        return {
          outputMode: "off",
          showFixed: true,
          showDynamic: false,
          interstitialActive: true
        };
    }
  };

  const buildSnapshotCue = (): CueCommand => {
    const snapshot = deps.show.snapshot();
    const output = fallbackOutputForState(snapshot.state);
    return {
      cueId: `${snapshot.state}:${Math.round(snapshot.logicalTime)}:snapshot`,
      showState: snapshot.state,
      logicalTime: snapshot.logicalTime,
      payload: {
        ...output,
        vector: snapshot.vector,
        colorPolicy: defaultColorPolicy,
        engineRunning: snapshot.state !== "idle"
      },
      version: snapshot.version,
      action: "jump"
    };
  };
  let latestCue: CueCommand = withCueTiming(buildSnapshotCue(), Date.now());
  let latestStreamMap: ShowStreamMap = mergeStreamMaps(
    configuredStreamMap,
    parseStreamMap((latestCue.payload ?? {}) as Record<string, unknown>)
  );
  let latestActiveScene: ShowSceneKey | null = inferActiveSceneFromCue(latestCue, latestStreamMap);
  let latestCueVersion = latestCue.version;
  let latestCatalog: ShowMediaCatalog | null = loadedCatalog;
  let latestCatalogVersion: string | null = latestCatalog?.version ?? null;
  let latestInterstitialClipId: string | null = null;
  let latestDynamicClipId: string | null = null;
  const interstitialNoRepeatWindow = Math.max(0, Math.min(8, Math.round(deps.config.CONDUCTOR_INTERSTITIAL_NO_REPEAT)));
  const dynamicSwitchQuantumMs = Math.max(
    50,
    Math.min(2_000, Math.round(deps.config.CONDUCTOR_DYNAMIC_SWITCH_QUANTUM_MS))
  );
  const orientationSwitchDebounceMs = Math.max(
    50,
    Math.min(2_000, Math.round(deps.config.CONDUCTOR_ORIENTATION_SWITCH_DEBOUNCE_MS))
  );
  let interstitialRecentClipIds: string[] = [];
  let interstitialRotationTimer: NodeJS.Timeout | null = null;
  let dynamicClipCommitTimer: NodeJS.Timeout | null = null;
  let pendingDynamicClipId: string | null = null;
  let catalogManagedDynamicClipIds = new Set<string>();
  const syncHealthByDevice = new Map<string, SyncHealthSample>();
  const activationDeltaSamplesMs: number[] = [];
  const activationMissSamplesMs: number[] = [];

  interface ScheduledCueTelemetryEntry {
    cueId: string;
    cueVersion: number;
    activateAtMs: number;
    issuedAtMs: number;
    leadMs: number;
    timingPolicy: string;
    timingCohort: string;
    cohortSize: number;
    cohortP95RttMs: number;
  }

  const cueTimingByCueId = new Map<string, ScheduledCueTelemetryEntry>();

  const parseFiniteNumber = (value: unknown): number | null => {
    if (typeof value === "number" && Number.isFinite(value)) {
      return value;
    }
    if (typeof value === "string") {
      const parsed = Number(value);
      return Number.isFinite(parsed) ? parsed : null;
    }
    return null;
  };

  const clipByMasterUrl = (
    clips: ShowCatalogClipEntry[],
    masterUrl: string | undefined
  ): ShowCatalogClipEntry | null => {
    if (!masterUrl) {
      return null;
    }
    return clips.find((clip) => clip.masterUrl === masterUrl) ?? null;
  };

  const interstitialCatalogClips = (): ShowCatalogClipEntry[] => latestCatalog?.interstitial ?? [];
  const dynamicCatalogClips = (): ShowCatalogClipEntry[] => latestCatalog?.dynamic ?? [];

  const dynamicManifestFromCatalog = (
    catalog: ShowMediaCatalog | null
  ): ProgramProceduralState["dynamicBinManifest"] => {
    if (!catalog || catalog.dynamic.length === 0) {
      return [];
    }
    return catalog.dynamic.map((clip) => ({
      id: clip.clipId,
      mediaRef: clip.masterUrl,
      tags: Array.isArray(clip.tags) ? clip.tags.filter((tag): tag is string => typeof tag === "string") : [],
      weight: Math.max(0, Number.isFinite(clip.weight) ? clip.weight : 1),
      scopes: ["mainDynamic", "dynamic"]
    }));
  };

  const syncDynamicManifestFromCatalog = (catalog: ShowMediaCatalog | null): void => {
    const nextManifest = dynamicManifestFromCatalog(catalog);
    if (nextManifest.length === 0) {
      return;
    }

    const currentManifest = baseProceduralState.dynamicBinManifest;
    const currentIsCatalogManaged =
      currentManifest.length === 0 ||
      (catalogManagedDynamicClipIds.size > 0 &&
        currentManifest.every((clip) => catalogManagedDynamicClipIds.has(clip.id)));

    if (!currentIsCatalogManaged) {
      return;
    }

    const previousClipId = baseProceduralState.dynamicBinClipId;
    const fallbackIndex = Math.max(0, Math.min(nextManifest.length - 1, baseProceduralState.dynamicBinIndex));
    const nextIndexCandidate = previousClipId ? nextManifest.findIndex((clip) => clip.id === previousClipId) : -1;
    const nextIndex = nextIndexCandidate >= 0 ? nextIndexCandidate : fallbackIndex;
    const nextSelection =
      nextManifest.length <= 1 ? 0 : nextIndex / Math.max(1, nextManifest.length - 1);
    const nextClipId = nextManifest[nextIndex]?.id ?? null;

    baseProceduralState = normalizeProceduralState(
      {
        ...baseProceduralState,
        dynamicBinManifest: nextManifest,
        dynamicBinIndex: nextIndex,
        dynamicBinSelection: nextSelection,
        dynamicBinClipId: nextClipId
      },
      baseProceduralState
    );
    effectiveProceduralState = normalizeProceduralState(
      {
        ...effectiveProceduralState,
        dynamicBinManifest: nextManifest,
        dynamicBinIndex: nextIndex,
        dynamicBinSelection: nextSelection,
        dynamicBinClipId: nextClipId
      },
      effectiveProceduralState
    );
    catalogManagedDynamicClipIds = new Set(nextManifest.map((clip) => clip.id));
  };

  const applyCatalog = (catalog: ShowMediaCatalog | null): void => {
    latestCatalog = catalog;
    latestCatalogVersion = catalog?.version ?? null;
    configuredStreamMap = buildConfiguredStreamMap(
      catalog ? streamMapFromCatalogStaticEntries(catalog) : {}
    );
    latestStreamMap = mergeStreamMaps(configuredStreamMap, latestStreamMap);
    syncDynamicManifestFromCatalog(catalog);

    const interstitialMatch = clipByMasterUrl(interstitialCatalogClips(), latestStreamMap.interstitial);
    latestInterstitialClipId = interstitialMatch?.clipId ?? catalog?.interstitial[0]?.clipId ?? null;
    interstitialRecentClipIds = latestInterstitialClipId ? [latestInterstitialClipId] : [];
    const dynamicMatch = clipByMasterUrl(dynamicCatalogClips(), latestStreamMap.mainDynamic);
    latestDynamicClipId = dynamicMatch?.clipId ?? catalog?.dynamic[0]?.clipId ?? null;
  };

  applyCatalog(latestCatalog);

  let catalogRefreshTimer: NodeJS.Timeout | null = null;
  const refreshCatalog = async (): Promise<void> => {
    if (!configuredCatalogURL) {
      return;
    }
    const next = await loadShowMediaCatalog(configuredCatalogURL);
    if (!next) {
      return;
    }
    if (latestCatalogVersion === next.version) {
      return;
    }
    applyCatalog(next);
    broadcastShowSnapshot();
  };

  if (configuredCatalogURL) {
    catalogRefreshTimer = setInterval(() => {
      void refreshCatalog();
    }, 15_000);
    catalogRefreshTimer.unref();
  }

  const percentile = (values: number[], q: number): number => {
    if (values.length === 0) {
      return 0;
    }
    const sorted = [...values].sort((lhs, rhs) => lhs - rhs);
    const index = Math.max(0, Math.min(sorted.length - 1, Math.ceil((sorted.length - 1) * q)));
    return sorted[index] ?? sorted[sorted.length - 1] ?? 0;
  };

  const resolveCueTimingFromPayload = (
    cue: CueCommand,
    nowMs: number
  ): Required<Pick<CueCommand, "activateAtMs" | "issuedAtMs" | "leadMs" | "timingPolicy" | "timingCohort">> => {
    const payload = (cue.payload ?? {}) as Record<string, unknown>;
    const activateAtMs = parseFiniteNumber(cue.activateAtMs ?? payload.activateAtMs);
    const issuedAtMs = parseFiniteNumber(cue.issuedAtMs ?? payload.issuedAtMs);
    const leadMs = parseFiniteNumber(cue.leadMs ?? payload.leadMs);
    const timingPolicyRaw = typeof cue.timingPolicy === "string" ? cue.timingPolicy : payload.timingPolicy;
    const timingCohortRaw = typeof cue.timingCohort === "string" ? cue.timingCohort : payload.timingCohort;

    if (
      activateAtMs !== null &&
      issuedAtMs !== null &&
      leadMs !== null &&
      typeof timingPolicyRaw === "string" &&
      typeof timingCohortRaw === "string"
    ) {
      return {
        activateAtMs,
        issuedAtMs,
        leadMs,
        timingPolicy: timingPolicyRaw as CueCommand["timingPolicy"] & string,
        timingCohort: timingCohortRaw as CueCommand["timingCohort"] & string
      };
    }

    const schedule = buildCueTimingSchedule(
      Object.fromEntries(syncHealthByDevice.entries()),
      [...deviceSockets.keys()],
      nowMs
    );

    return {
      activateAtMs: schedule.timing.activateAtMs,
      issuedAtMs: schedule.timing.issuedAtMs,
      leadMs: schedule.timing.leadMs,
      timingPolicy: schedule.timing.timingPolicy,
      timingCohort: schedule.timing.timingCohort
    };
  };

  function withCueTiming(cue: CueCommand, nowMs: number): CueCommand {
    const payload = (cue.payload ?? {}) as Record<string, unknown>;
    const timing = resolveCueTimingFromPayload(cue, nowMs);
    const nextPayload: Record<string, unknown> = {
      ...payload,
      activateAtMs: timing.activateAtMs,
      issuedAtMs: timing.issuedAtMs,
      leadMs: timing.leadMs,
      timingPolicy: timing.timingPolicy,
      timingCohort: timing.timingCohort
    };

    return {
      ...cue,
      payload: nextPayload,
      activateAtMs: timing.activateAtMs,
      issuedAtMs: timing.issuedAtMs,
      leadMs: timing.leadMs,
      timingPolicy: timing.timingPolicy,
      timingCohort: timing.timingCohort
    };
  }

  const emitCueTimingTelemetry = (entry: ScheduledCueTelemetryEntry): void => {
    broadcastToHarness({
      kind: "telemetry",
      data: {
        kind: "cue_timing_schedule",
        cueId: entry.cueId,
        cueVersion: entry.cueVersion,
        activateAtMs: entry.activateAtMs,
        issuedAtMs: entry.issuedAtMs,
        leadMs: entry.leadMs,
        timingPolicy: entry.timingPolicy,
        timingCohort: entry.timingCohort,
        cohortSize: entry.cohortSize,
        cohortP95RttMs: entry.cohortP95RttMs
      },
      sentAt: Date.now()
    } satisfies WireEnvelope);
  };

  const rememberCueTiming = (cue: CueCommand): void => {
    const payload = (cue.payload ?? {}) as Record<string, unknown>;
    const activateAtMs = parseFiniteNumber(cue.activateAtMs ?? payload.activateAtMs);
    const issuedAtMs = parseFiniteNumber(cue.issuedAtMs ?? payload.issuedAtMs);
    const leadMs = parseFiniteNumber(cue.leadMs ?? payload.leadMs);
    const timingPolicy = typeof cue.timingPolicy === "string" ? cue.timingPolicy : payload.timingPolicy;
    const timingCohort = typeof cue.timingCohort === "string" ? cue.timingCohort : payload.timingCohort;
    if (
      activateAtMs === null ||
      issuedAtMs === null ||
      leadMs === null ||
      typeof timingPolicy !== "string" ||
      typeof timingCohort !== "string"
    ) {
      return;
    }
    const cohort = buildCueTimingSchedule(
      Object.fromEntries(syncHealthByDevice.entries()),
      [...deviceSockets.keys()],
      issuedAtMs
    );
    const entry: ScheduledCueTelemetryEntry = {
      cueId: cue.cueId,
      cueVersion: cue.version,
      activateAtMs,
      issuedAtMs,
      leadMs,
      timingPolicy,
      timingCohort,
      cohortSize: cohort.cohortSize,
      cohortP95RttMs: cohort.cohortP95RttMs
    };
    cueTimingByCueId.set(cue.cueId, entry);
    emitCueTimingTelemetry(entry);
  };

  const emitCueActivationMetrics = (cueId: string): void => {
    if (activationDeltaSamplesMs.length === 0) {
      return;
    }
    const p50SkewMs = percentile(activationDeltaSamplesMs, 0.5);
    const p95SkewMs = percentile(activationDeltaSamplesMs, 0.95);
    const p95MissMs = percentile(activationMissSamplesMs, 0.95);
    broadcastToHarness({
      kind: "telemetry",
      data: {
        kind: "cue_timing_metrics",
        cueId,
        sampleCount: activationDeltaSamplesMs.length,
        p50SkewMs,
        p95SkewMs,
        p95MissMs
      },
      sentAt: Date.now()
    } satisfies WireEnvelope);
  };

  const recordCueActivationAck = (
    source: "device" | "harness",
    cueId: string,
    activatedAtMsRaw: unknown,
    activationDeltaMsRaw: unknown,
    metadata: Record<string, unknown>
  ): void => {
    const timing = cueTimingByCueId.get(cueId);
    if (!timing) {
      return;
    }
    const activatedAtMs = parseFiniteNumber(activatedAtMsRaw) ?? Date.now();
    const derivedDeltaMs = activatedAtMs - timing.activateAtMs;
    const activationDeltaMs = parseFiniteNumber(activationDeltaMsRaw) ?? derivedDeltaMs;
    activationDeltaSamplesMs.push(activationDeltaMs);
    if (activationDeltaSamplesMs.length > 400) {
      activationDeltaSamplesMs.splice(0, activationDeltaSamplesMs.length - 400);
    }
    activationMissSamplesMs.push(Math.max(0, activationDeltaMs));
    if (activationMissSamplesMs.length > 400) {
      activationMissSamplesMs.splice(0, activationMissSamplesMs.length - 400);
    }

    broadcastToHarness({
      kind: "telemetry",
      data: {
        kind: "cue_activation_ack",
        source,
        cueId,
        activatedAtMs,
        activationDeltaMs,
        ...metadata
      },
      sentAt: Date.now()
    } satisfies WireEnvelope);

    emitCueActivationMetrics(cueId);
  };

  const syncCueMediaState = (cue: CueCommand): void => {
    const payload = (cue.payload ?? {}) as Record<string, unknown>;
    latestStreamMap = mergeStreamMaps(
      configuredStreamMap,
      mergeStreamMaps(latestStreamMap, parseStreamMap(payload))
    );
    const incomingCatalogVersion = typeof payload.showCatalogVersion === "string" ? payload.showCatalogVersion : null;
    if (incomingCatalogVersion && incomingCatalogVersion.length > 0) {
      latestCatalogVersion = incomingCatalogVersion;
    }
    const incomingInterstitialClipId =
      typeof payload.showInterstitialClipId === "string" ? payload.showInterstitialClipId : null;
    const incomingDynamicClipId =
      typeof payload.showDynamicClipId === "string" ? payload.showDynamicClipId : null;
    if (incomingInterstitialClipId) {
      latestInterstitialClipId = incomingInterstitialClipId;
      interstitialRecentClipIds.push(incomingInterstitialClipId);
      if (interstitialRecentClipIds.length > 24) {
        interstitialRecentClipIds.splice(0, interstitialRecentClipIds.length - 24);
      }
    } else {
      const inferred = clipByMasterUrl(interstitialCatalogClips(), latestStreamMap.interstitial);
      if (inferred?.clipId) {
        latestInterstitialClipId = inferred.clipId;
      }
    }
    if (incomingDynamicClipId) {
      latestDynamicClipId = incomingDynamicClipId;
    } else {
      const inferred = clipByMasterUrl(dynamicCatalogClips(), latestStreamMap.mainDynamic);
      if (inferred?.clipId) {
        latestDynamicClipId = inferred.clipId;
      }
    }
    const activeScene = inferActiveSceneFromCue(cue, latestStreamMap);
    if (activeScene) {
      latestActiveScene = activeScene;
    }
    latestCueVersion = Math.max(latestCueVersion, cue.version);
    rememberCueTiming(cue);
  };

  const buildShowSnapshotPayload = (): ShowSnapshotPayload => {
    const snapshot = deps.show.snapshot();
    const cuePayload = (latestCue.payload ?? {}) as Record<string, unknown>;
    const cuePayloadWithMedia: Record<string, unknown> = {
      ...cuePayload,
      showInterstitialClipId: latestInterstitialClipId ?? undefined,
      showDynamicClipId: latestDynamicClipId ?? undefined,
      showCatalogVersion: latestCatalogVersion ?? undefined,
      dynamicSwitchQuantumMs,
      orientationSwitchDebounceMs
    };
    latestStreamMap = mergeStreamMaps(
      configuredStreamMap,
      mergeStreamMaps(latestStreamMap, parseStreamMap(cuePayloadWithMedia))
    );
    const activeScene = inferActiveSceneFromCue(latestCue, latestStreamMap);
    if (activeScene) {
      latestActiveScene = activeScene;
    }
    latestCueVersion = Math.max(latestCueVersion, latestCue.version, snapshot.version);
    const activateAtMs = parseFiniteNumber(latestCue.activateAtMs ?? cuePayload.activateAtMs);
    const issuedAtMs = parseFiniteNumber(latestCue.issuedAtMs ?? cuePayload.issuedAtMs);
    const leadMs = parseFiniteNumber(latestCue.leadMs ?? cuePayload.leadMs);
    const timingPolicy =
      typeof latestCue.timingPolicy === "string"
        ? latestCue.timingPolicy
        : typeof cuePayload.timingPolicy === "string"
          ? cuePayload.timingPolicy
          : undefined;
    const timingCohort =
      typeof latestCue.timingCohort === "string"
        ? latestCue.timingCohort
        : typeof cuePayload.timingCohort === "string"
          ? cuePayload.timingCohort
          : undefined;

    return {
      state: snapshot.state,
      logicalTime: snapshot.logicalTime,
      version: snapshot.version,
      vector: snapshot.vector,
      cueId: latestCue.cueId,
      cueVersion: latestCueVersion,
      activeScene: latestActiveScene ?? undefined,
      streamMap: Object.keys(latestStreamMap).length > 0 ? latestStreamMap : undefined,
      showInterstitialClipId: latestInterstitialClipId ?? undefined,
      showDynamicClipId: latestDynamicClipId ?? undefined,
      showCatalogVersion: latestCatalogVersion ?? undefined,
      cuePayload: cuePayloadWithMedia,
      authorityMode: promptOrchestrator.authorityMode(),
      promptPolicy: promptOrchestrator.policy(),
      cohortSalt: promptOrchestrator.currentCohortSalt(),
      sharedUniqueMix: promptOrchestrator.sharedUniqueMix(),
      echoCapsByStem: resolveEchoCapsByScene(latestActiveScene),
      activateAtMs: activateAtMs ?? undefined,
      issuedAtMs: issuedAtMs ?? undefined,
      leadMs: leadMs ?? undefined,
      timingPolicy:
        typeof timingPolicy === "string"
          ? (timingPolicy as NonNullable<ShowSnapshotPayload["timingPolicy"]>)
          : undefined,
      timingCohort:
        typeof timingCohort === "string"
          ? (timingCohort as NonNullable<ShowSnapshotPayload["timingCohort"]>)
          : undefined
    };
  };

  const enrichCuePayload = (cue: CueCommand): CueCommand => {
    const nowMs = Date.now();
    const timedCue = withCueTiming(cue, nowMs);
    const timedPayload = (timedCue.payload ?? {}) as Record<string, unknown>;
    const payload = (cue.payload ?? {}) as Record<string, unknown>;
    latestStreamMap = mergeStreamMaps(
      configuredStreamMap,
      mergeStreamMaps(latestStreamMap, parseStreamMap(timedPayload))
    );
    const activeScene = inferActiveSceneFromCue(timedCue, latestStreamMap) ?? latestActiveScene;
    if (activeScene) {
      latestActiveScene = activeScene;
    }
    latestCueVersion = Math.max(latestCueVersion, timedCue.version);
    const outputFallback = fallbackOutputForState(timedCue.showState);

    const nextPayload: Record<string, unknown> = {
      ...payload,
      ...timedPayload,
      cueVersion: latestCueVersion,
      outputMode:
        typeof timedPayload.outputMode === "string" && timedPayload.outputMode.trim().length > 0
          ? timedPayload.outputMode
          : outputFallback.outputMode,
      showFixed: parseBoolean(timedPayload.showFixed, outputFallback.showFixed),
      showDynamic: parseBoolean(timedPayload.showDynamic, outputFallback.showDynamic),
      interstitialActive: parseBoolean(timedPayload.interstitialActive, outputFallback.interstitialActive),
      showInterstitialClipId: latestInterstitialClipId,
      showDynamicClipId: latestDynamicClipId,
      showCatalogVersion: latestCatalogVersion,
      dynamicSwitchQuantumMs,
      orientationSwitchDebounceMs,
      showStreamMap: latestStreamMap
    };

    for (const key of sceneKeys) {
      const value = latestStreamMap[key];
      if (value) {
        nextPayload[streamPayloadFieldByScene[key]] = value;
      }
    }

    if (latestActiveScene) {
      nextPayload.showActiveScene = latestActiveScene;
      nextPayload.activeSceneKey = latestActiveScene;
      const activeRef = latestStreamMap[latestActiveScene];
      if (activeRef) {
        nextPayload.showFixedMediaRef = activeRef;
        nextPayload.showFixedMediaMime = inferMediaMimeType(activeRef);
      }
    }

    return {
      ...timedCue,
      payload: nextPayload,
      version: latestCueVersion
    };
  };

  const clearInterstitialRotationTimer = (): void => {
    if (interstitialRotationTimer) {
      clearTimeout(interstitialRotationTimer);
      interstitialRotationTimer = null;
    }
  };

  const clearDynamicClipCommitTimer = (): void => {
    if (dynamicClipCommitTimer) {
      clearTimeout(dynamicClipCommitTimer);
      dynamicClipCommitTimer = null;
    }
  };

  const shouldRunInterstitialRoulette = (): boolean => {
    if (latestActiveScene !== "interstitial") {
      return false;
    }
    const payload = (latestCue.payload ?? {}) as Record<string, unknown>;
    const engineRunning = parseBoolean(payload.engineRunning, latestCue.showState !== "idle");
    return engineRunning;
  };

  const dispatchMediaCueUpdate = (
    reason: string,
    options: {
      streamMapOverride?: ShowStreamMap;
      payloadOverride?: Record<string, unknown>;
      forceActiveScene?: ShowSceneKey;
    }
  ): CueCommand | null => {
    const snapshot = deps.show.snapshot();
    latestCueVersion = Math.max(latestCueVersion, latestCue.version) + 1;
    latestStreamMap = mergeStreamMaps(
      configuredStreamMap,
      mergeStreamMaps(latestStreamMap, options.streamMapOverride ?? {})
    );

    const payloadBase = (latestCue.payload ?? {}) as Record<string, unknown>;
    const payload: Record<string, unknown> = {
      ...payloadBase,
      cueVersion: latestCueVersion,
      dynamicSwitchQuantumMs,
      orientationSwitchDebounceMs,
      showCatalogVersion: latestCatalogVersion ?? undefined,
      showInterstitialClipId: latestInterstitialClipId ?? undefined,
      showDynamicClipId: latestDynamicClipId ?? undefined,
      showStreamMap: latestStreamMap,
      ...options.payloadOverride
    };

    for (const key of sceneKeys) {
      const value = latestStreamMap[key];
      if (value) {
        payload[streamPayloadFieldByScene[key]] = value;
      }
    }

    const forcedScene = options.forceActiveScene;
    if (forcedScene) {
      payload.showActiveScene = forcedScene;
      payload.activeSceneKey = forcedScene;
      const activeRef = latestStreamMap[forcedScene];
      if (activeRef) {
        payload.showFixedMediaRef = activeRef;
        payload.showFixedMediaMime = inferMediaMimeType(activeRef);
      }
    }

    const cue: CueCommand = {
      cueId: `media:${reason}:${latestCueVersion}:${Date.now()}`,
      showState: latestCue.showState,
      logicalTime: snapshot.logicalTime,
      payload,
      version: latestCueVersion,
      action: "jump"
    };

    const dispatchedCue = broadcastCue(cue);
    latestCue = dispatchedCue;
    broadcastShowSnapshot();
    return dispatchedCue;
  };

  const scheduleNextInterstitialRotation = (delayMs: number): void => {
    clearInterstitialRotationTimer();
    interstitialRotationTimer = setTimeout(() => {
      if (!shouldRunInterstitialRoulette()) {
        clearInterstitialRotationTimer();
        return;
      }
      const selected = pickCatalogClip(
        interstitialCatalogClips(),
        interstitialRecentClipIds,
        interstitialNoRepeatWindow
      );
      if (!selected) {
        return;
      }
      latestInterstitialClipId = selected.clipId;
      interstitialRecentClipIds.push(selected.clipId);
      if (interstitialRecentClipIds.length > 32) {
        interstitialRecentClipIds.splice(0, interstitialRecentClipIds.length - 32);
      }

      const dispatched = dispatchMediaCueUpdate("interstitial_roulette", {
        streamMapOverride: {
          interstitial: selected.masterUrl
        },
        payloadOverride: {
          outputMode: "interstitial_loop",
          showFixed: true,
          showDynamic: false,
          interstitialActive: true,
          showInterstitialClipId: selected.clipId
        },
        forceActiveScene: "interstitial"
      });
      const leadMs = parseFiniteNumber(
        dispatched?.leadMs ?? ((dispatched?.payload ?? {}) as Record<string, unknown>).leadMs
      ) ?? 0;
      const nextDelay = Math.max(500, selected.durationMs - Math.round(leadMs));
      scheduleNextInterstitialRotation(nextDelay);
    }, Math.max(250, Math.round(delayMs)));
    interstitialRotationTimer.unref();
  };

  const ensureInterstitialRoulette = (): void => {
    if (!shouldRunInterstitialRoulette()) {
      clearInterstitialRotationTimer();
      return;
    }
    if (interstitialRotationTimer) {
      return;
    }
    const clips = interstitialCatalogClips();
    if (clips.length === 0) {
      return;
    }

    const currentClip =
      findCatalogClipById(clips, latestInterstitialClipId) ??
      clipByMasterUrl(clips, latestStreamMap.interstitial) ??
      null;
    if (!currentClip) {
      scheduleNextInterstitialRotation(10);
      return;
    }
    latestInterstitialClipId = currentClip.clipId;
    interstitialRecentClipIds.push(currentClip.clipId);
    if (interstitialRecentClipIds.length > 32) {
      interstitialRecentClipIds.splice(0, interstitialRecentClipIds.length - 32);
    }
    const cuePayload = (latestCue.payload ?? {}) as Record<string, unknown>;
    if (
      latestStreamMap.interstitial !== currentClip.masterUrl ||
      cuePayload.showInterstitialClipId !== currentClip.clipId
    ) {
      dispatchMediaCueUpdate("interstitial_seed", {
        streamMapOverride: {
          interstitial: currentClip.masterUrl
        },
        payloadOverride: {
          outputMode: "interstitial_loop",
          showFixed: true,
          showDynamic: false,
          interstitialActive: true,
          showInterstitialClipId: currentClip.clipId
        },
        forceActiveScene: "interstitial"
      });
    }
    scheduleNextInterstitialRotation(currentClip.durationMs);
  };

  const flushDynamicClipCommit = (): void => {
    clearDynamicClipCommitTimer();
    const targetClipId = pendingDynamicClipId;
    pendingDynamicClipId = null;
    if (!targetClipId) {
      return;
    }
    const target = findCatalogClipById(dynamicCatalogClips(), targetClipId);
    if (!target) {
      return;
    }
    if (target.clipId === latestDynamicClipId && latestStreamMap.mainDynamic === target.masterUrl) {
      return;
    }
    latestDynamicClipId = target.clipId;
    dispatchMediaCueUpdate("dynamic_clip_commit", {
      streamMapOverride: {
        mainDynamic: target.masterUrl
      },
      payloadOverride: {
        showDynamicClipId: target.clipId
      }
    });
  };

  const scheduleDynamicClipCommit = (clipId: string | null): void => {
    if (!clipId) {
      return;
    }
    pendingDynamicClipId = clipId;
    if (dynamicClipCommitTimer) {
      return;
    }
    const now = Date.now();
    const quantum = Math.max(50, dynamicSwitchQuantumMs);
    const remainder = now % quantum;
    const delayMs = remainder === 0 ? quantum : quantum - remainder;
    dynamicClipCommitTimer = setTimeout(() => {
      flushDynamicClipCommit();
    }, Math.max(5, delayMs));
    dynamicClipCommitTimer.unref();
  };

  const updateMediaSchedulersAfterCue = (cue: CueCommand): void => {
    const payload = (cue.payload ?? {}) as Record<string, unknown>;
    latestCatalogVersion = typeof payload.showCatalogVersion === "string" ? payload.showCatalogVersion : latestCatalogVersion;
    latestInterstitialClipId =
      (typeof payload.showInterstitialClipId === "string" ? payload.showInterstitialClipId : latestInterstitialClipId) ??
      clipByMasterUrl(interstitialCatalogClips(), latestStreamMap.interstitial)?.clipId ??
      null;
    latestDynamicClipId =
      (typeof payload.showDynamicClipId === "string" ? payload.showDynamicClipId : latestDynamicClipId) ??
      clipByMasterUrl(dynamicCatalogClips(), latestStreamMap.mainDynamic)?.clipId ??
      null;
    ensureInterstitialRoulette();
    if (latestActiveScene === "mainDynamic") {
      scheduleDynamicClipCommit(effectiveProceduralState.dynamicBinClipId ?? latestDynamicClipId);
    } else {
      clearDynamicClipCommitTimer();
      pendingDynamicClipId = null;
    }
  };

  deps.crowdPickPulse.tick(0, Date.now());
  const initialPulse = deps.crowdPickPulse.snapshot();
  deps.audioOpsStateHub.setPickWindow(initialPulse.window);
  deps.audioOpsStateHub.setPickResult(initialPulse.result);

  const initialScene = deps.textSceneComposer.compose({
    cueId: "idle:0",
    vector: deps.show.snapshot().vector,
    audioFeatures: lastAudioFeatures,
    pickResult: initialPulse.result,
    pickEpoch: initialPulse.pickEpoch,
    textBlend: {
      probability: baseProceduralState.textProbability,
      strictRatio: baseProceduralState.strictLooseBlend
    }
  });
  deps.audioOpsStateHub.setTextScene(initialScene);
  deps.audioOpsStateHub.setProceduralState(baseProceduralState);
  ensureInterstitialRoulette();

  wsApp.get("/ws/harness", { websocket: true }, (socket) => {
    harnessSockets.add(socket);
    logger.info("ws socket opened", { role: "harness" });
    pushInitialSnapshot(socket, "harness");

    socket.on("close", (code, reason) => {
      logger.info("ws socket closed", {
        role: "harness",
        code,
        reason: decodeCloseReason(reason)
      });
      harnessSockets.delete(socket);
    });
    socket.on("error", (error) => {
      logger.warn("ws socket error", { role: "harness", message: String(error) });
    });

    socket.on("message", async (raw: Buffer) => {
      const inbound = parse<HarnessInbound>(raw.toString());
      if (!inbound) {
        return;
      }

      if (inbound.kind === "cue" && isCueCommand(inbound.data)) {
        const scheduledCue = withCueTiming(inbound.data, Date.now());
        latestCue = scheduledCue;
        await deps.replayService.record({
          type: "cue",
          timestamp: Date.now(),
          logicalTime: scheduledCue.logicalTime,
          cueId: scheduledCue.cueId,
          source: "harness",
          payload: scheduledCue.payload
        });
        broadcastCue(scheduledCue);
        broadcastShowSnapshot();
        composeAndBroadcastTextScene(true, scheduledCue.cueId);
        return;
      }

      if (inbound.kind === "command") {
        try {
          const cue = withCueTiming(
            deps.show.applyAction(
              inbound.data.action,
              Date.now(),
              inbound.data.targetState,
              inbound.data.payload ?? {}
            ),
            Date.now()
          );
          latestCue = cue;

          await deps.replayService.record({
            type: "cue",
            timestamp: Date.now(),
            logicalTime: cue.logicalTime,
            cueId: cue.cueId,
            source: "harness",
            payload: cue.payload
          });

          broadcastCue(cue);
          broadcastShowSnapshot();
          composeAndBroadcastTextScene(true, cue.cueId);
        } catch (error) {
          send(socket, {
            kind: "error",
            data: {
              message: error instanceof Error ? error.message : "Unknown command error"
            },
            sentAt: Date.now()
          } satisfies WireEnvelope);
        }
        return;
      }

      if (inbound.kind === "param_vector") {
        const vector = deps.show.updateVector(inbound.data);
        baseProceduralState = normalizeProceduralState(
          {
            ...baseProceduralState,
            performerVector: vector
          },
          baseProceduralState
        );
        composeAndBroadcastProceduralState();

        await deps.replayService.record({
          type: "telemetry",
          timestamp: Date.now(),
          logicalTime: deps.show.snapshot().logicalTime,
          source: "harness",
          payload: { ...vector }
        });

        broadcastToDevices({
          kind: "param_vector",
          data: vector,
          sentAt: Date.now()
        } satisfies WireEnvelope);
        composeAndBroadcastTextScene(false);
        return;
      }

      if (inbound.kind === "procedural_state") {
        if (
          Array.isArray(inbound.data.dynamicBinManifest) &&
          inbound.data.dynamicBinManifest.length > 0
        ) {
          // Explicit harness manifests opt out of catalog-managed dynamic bins.
          catalogManagedDynamicClipIds.clear();
        }
        baseProceduralState = normalizeProceduralState(inbound.data, baseProceduralState);
        composeAndBroadcastProceduralState();
        composeAndBroadcastTextScene(true);
        return;
      }

      if (inbound.kind === "replay") {
        const data =
          inbound.data.action === "freeze"
            ? await deps.replayService.freezeFrame(inbound.data.centerTimestamp ?? Date.now())
            : await deps.replayService.latest();

        send(socket, {
          kind: "replay",
          data,
          sentAt: Date.now()
        } satisfies WireEnvelope);
        return;
      }

      if (inbound.kind === "audio_features") {
        const normalized = normalizeAudioFeatures(inbound.data);
        lastAudioFeatures = normalized;
        deps.audioOpsStateHub.setAudioFeatures(normalized);
        broadcastAudioFeatures(normalized);
        composeAndBroadcastProceduralState();
        composeAndBroadcastTextScene(false);
        return;
      }

      if (inbound.kind === "phone_audio_pool_state") {
        const pool = deps.phoneAudioPool.setGateState({
          gateArmed: booleanOrUndefined(inbound.data.gateArmed),
          gateCommitted: booleanOrUndefined(inbound.data.gateCommitted),
          quadRouteReady: booleanOrUndefined(inbound.data.quadRouteReady)
        });
        publishPhonePoolState(pool);
        return;
      }

      if (inbound.kind === "phone_audio_command") {
        const command = normalizePhoneAudioCommand(inbound.data);
        if (!deps.phoneAudioPool.canDispatchPhoneAudio()) {
          send(socket, {
            kind: "error",
            data: {
              message: "PHONE AUDIO NOGO: gate not committed or quad route not ready"
            },
            sentAt: Date.now()
          } satisfies WireEnvelope);
          return;
        }

        const dispatched = dispatchPhoneAudioCommand(command);
        if (!dispatched) {
          send(socket, {
            kind: "error",
            data: {
              message: "PHONE AUDIO NOGO: no eligible devices"
            },
            sentAt: Date.now()
          } satisfies WireEnvelope);
          return;
        }

        await deps.replayService.record({
          type: "device_uplink",
          timestamp: Date.now(),
          logicalTime: deps.show.snapshot().logicalTime,
          source: "harness",
          payload: {
            envelopeKind: "phone_audio_command",
            command: dispatched
          }
        });

        const pool = deps.phoneAudioPool.snapshot();
        publishPhonePoolState(pool);
        return;
      }

      if (inbound.kind === "keyboard_state") {
        const keyboardState = normalizeKeyboardStatePayload(inbound.data, latestKeyboardState);
        latestKeyboardState = keyboardState;
        const envelope = {
          kind: "keyboard_state",
          data: keyboardState,
          sentAt: Date.now()
        } satisfies WireEnvelope<KeyboardStatePayload>;
        broadcastToDevices(envelope);
        broadcastToHarness(envelope);
        return;
      }

      if (inbound.kind === "keyboard_patch_change") {
        const keyboardPatch = normalizeKeyboardPatchChangePayload(inbound.data, latestKeyboardState);
        const patchSnapshot: KeyboardStatePayload["patch"] = {
          patchId: keyboardPatch.patchId,
          patchName: keyboardPatch.patchName,
          bank: keyboardPatch.bank,
          program: keyboardPatch.program,
          returnBusStrategy: latestKeyboardState?.patch.returnBusStrategy,
          updatedAt: keyboardPatch.updatedAt
        };
        if (latestKeyboardState) {
          latestKeyboardState = {
            ...latestKeyboardState,
            patch: patchSnapshot,
            updatedAt: keyboardPatch.updatedAt
          };
        } else {
          latestKeyboardState = {
            profileId: "minilab3",
            profileName: "MiniLab 3",
            page: 0,
            pageName: "A",
            hostLink: "degraded",
            clockMaster: true,
            clockBpm: 120,
            transportRunning: false,
            patch: patchSnapshot,
            updatedAt: keyboardPatch.updatedAt
          };
        }
        const envelope = {
          kind: "keyboard_patch_change",
          data: keyboardPatch,
          sentAt: Date.now()
        } satisfies WireEnvelope<KeyboardPatchChangePayload>;
        broadcastToDevices(envelope);
        broadcastToHarness(envelope);
        return;
      }

      if (inbound.kind === "voice_publisher_announce") {
        const publisherId =
          typeof inbound.data.publisherId === "string" && inbound.data.publisherId.trim().length > 0
            ? inbound.data.publisherId.trim()
            : "harness";
        const sessionId =
          typeof inbound.data.sessionId === "string" && inbound.data.sessionId.trim().length > 0
            ? inbound.data.sessionId.trim()
            : `${deps.config.CONDUCTOR_MANAGED_SFU_SESSION_PREFIX}-sess-${Math.floor(Date.now() / 1_000)}`;
        const trackId =
          typeof inbound.data.trackId === "string" && inbound.data.trackId.trim().length > 0
            ? inbound.data.trackId.trim()
            : "main";
        const codec =
          inbound.data.codec === "aac" || inbound.data.codec === "pcm" || inbound.data.codec === "opus"
            ? inbound.data.codec
            : "opus";
        const active = inbound.data.active !== false;
        const announced = await mediasoupVoiceService.announcePublisher({
          publisherId,
          sessionId,
          trackId,
          codec,
          active,
          updatedAt:
            typeof inbound.data.updatedAt === "number" && Number.isFinite(inbound.data.updatedAt)
              ? inbound.data.updatedAt
              : Date.now()
        });
        broadcastToHarness({
          kind: "voice_publisher_announce",
          data: announced,
          sentAt: Date.now()
        } satisfies WireEnvelope<VoicePublisherAnnouncePayload>);
        return;
      }

      if (inbound.kind === "push_pad_labels") {
        const labels = normalizePushPadLabelsPayload(inbound.data);
        if (!labels) {
          return;
        }
        lastPushPadLabels = labels;
        broadcastToDevices({
          kind: "push_pad_labels",
          data: labels,
          sentAt: Date.now()
        } satisfies WireEnvelope<PushPadLabelsPayload>);
        return;
      }

      if (inbound.kind === "text_scene") {
        const current = deps.audioOpsStateHub.snapshot().textScene;
        const merged: TextScenePayload = {
          ...current,
          ...inbound.data,
          cueId: inbound.data.cueId ?? current.cueId
        };
        deps.audioOpsStateHub.setTextScene(merged);
        broadcastTextScene(merged);
        return;
      }

      if (inbound.kind === "text_runtime_update") {
        let didMutate = false;
        const strictCandidates = parseRuntimeScriptCandidates(inbound.data.strictCandidates);
        const looseCandidates = parseRuntimeScriptCandidates(inbound.data.looseCandidates);
        if (strictCandidates || looseCandidates) {
          deps.textSceneComposer.setRuntimeScriptBanks({
            strictCandidates: strictCandidates ?? undefined,
            looseCandidates: looseCandidates ?? undefined,
            sourceLabel: "harness-runtime"
          });
          didMutate = true;
        }

        if (typeof inbound.data.modelPayloadJSON === "string" && inbound.data.modelPayloadJSON.trim().length > 0) {
          try {
            const parsedModel = JSON.parse(inbound.data.modelPayloadJSON);
            const result = deps.textSceneComposer.setRuntimeModelPayload(parsedModel, "harness-runtime");
            if (!result.ok) {
              broadcastToHarness({
                kind: "error",
                data: {
                  message: `text runtime model rejected: ${result.reason}`
                },
                sentAt: Date.now()
              } satisfies WireEnvelope);
            } else {
              didMutate = true;
            }
          } catch (error) {
            const message = error instanceof Error ? error.message : "unknown parse error";
            broadcastToHarness({
              kind: "error",
              data: {
                message: `text runtime model JSON parse failed: ${message}`
              },
              sentAt: Date.now()
            } satisfies WireEnvelope);
          }
        }

        const nextSemanticMode =
          inbound.data.semanticMode === "off" || inbound.data.semanticMode === "openai"
            ? inbound.data.semanticMode
            : undefined;
        const nextSemanticApiKey =
          inbound.data.semanticApiKey === null
            ? null
            : typeof inbound.data.semanticApiKey === "string"
              ? inbound.data.semanticApiKey
              : undefined;
        const nextSemanticModel =
          typeof inbound.data.semanticModel === "string" ? inbound.data.semanticModel : undefined;
        if (
          nextSemanticMode !== undefined ||
          nextSemanticApiKey !== undefined ||
          nextSemanticModel !== undefined
        ) {
          deps.textSceneComposer.configureSemanticRuntime({
            mode: nextSemanticMode,
            openAiApiKey: nextSemanticApiKey,
            openAiModel: nextSemanticModel
          });
          didMutate = true;
        }

        if (inbound.data.reload) {
          deps.textSceneComposer.reloadScriptBanks(true);
          deps.textSceneComposer.reloadModelRuntime(true);
          didMutate = true;
        }

        if (didMutate) {
          composeAndBroadcastTextScene(true, latestCue?.cueId);
        }

        if (didMutate || inbound.data.requestStatus) {
          broadcastTextRuntimeStatus();
        }
        return;
      }

      if (inbound.kind === "telemetry") {
        await deps.replayService.record({
          type: "telemetry",
          timestamp: Date.now(),
          logicalTime: deps.show.snapshot().logicalTime,
          source: "harness",
          payload: inbound.data
        });
        if (inbound.data.type === "cue_activation_ack" && typeof inbound.data.cueId === "string") {
          recordCueActivationAck(
            "harness",
            inbound.data.cueId,
            inbound.data.activatedAtMs,
            inbound.data.activationDeltaMs,
            {
              cueVersion: inbound.data.cueVersion
            }
          );
        }
      }
    });
  });

  wsApp.get("/ws/device/:hashedId", { websocket: true }, async (socket, req) => {
    const hashedId = req.params.hashedId ?? "";

    if (!deps.identityService.validateHashedId(hashedId)) {
      socket.close(1008, "invalid hashed id");
      return;
    }

    const previousSocket = deviceSockets.get(hashedId);
    if (previousSocket && previousSocket !== socket) {
      try {
        previousSocket.close(4002, "superseded");
      } catch {
        // Ignore close errors for stale sockets; the new socket is authoritative.
      }
    }
    deviceSockets.set(hashedId, socket);
    promptOrchestrator.upsertDevice(hashedId);
    logger.info("ws socket opened", { role: "device", hashedId });

    const existing = await deps.sessions.get(hashedId);
    const profile =
      existing ?? deps.identityService.profileFromHashedId(hashedId);
    if (!existing) {
      await deps.sessions.upsert(profile);
    }

    const poolAfterConnect = deps.phoneAudioPool.markDevice(hashedId, {
      audio: profile.permissions.audio
    });
    choirAllocator.upsertDevice(hashedId, profile.permissions);
    if (profile.zone) {
      choirAllocator.updateZone(hashedId, profile.zone);
    }
    publishPhonePoolState(poolAfterConnect);

    const audienceOnConnect = audienceField.update(hashedId, {
      vector: {},
      influence: 0,
      compositorMode: "fallback"
    });
    broadcastAudienceVector(audienceOnConnect);

    pushInitialSnapshot(socket, "device");

    socket.on("close", (code, reason) => {
      const isCurrentSocket = deviceSockets.get(hashedId) === socket;
      logger.info("ws socket closed", {
        role: "device",
        hashedId,
        code,
        reason: decodeCloseReason(reason),
        current: isCurrentSocket
      });
      if (!isCurrentSocket) {
        return;
      }
      deviceSockets.delete(hashedId);
      promptOrchestrator.removeDevice(hashedId);
      promptInfluenceByDevice.delete(hashedId);
      syncHealthByDevice.delete(hashedId);
      const aggregate = audienceField.remove(hashedId);
      broadcastAudienceVector(aggregate);
      const lighting = deps.lightingField.remove(hashedId);
      broadcastLightingState(lighting);
      const pool = deps.phoneAudioPool.removeDevice(hashedId);
      choirAllocator.removeDevice(hashedId);
      clearVoiceStreamsForDevice(hashedId);
      mediasoupVoiceService.closeSubscriber(hashedId);
      clearPendingPushEventsForDevice(hashedId);
      publishPhonePoolState(pool);
    });

    socket.on("error", (error) => {
      const isCurrentSocket = deviceSockets.get(hashedId) === socket;
      logger.warn("ws socket error", {
        role: "device",
        hashedId,
        message: String(error),
        current: isCurrentSocket
      });
    });

    socket.on("message", async (raw: Buffer) => {
      if (deviceSockets.get(hashedId) !== socket) {
        return;
      }
      const inbound = parse<DeviceInbound>(raw.toString());
      if (!inbound) {
        return;
      }

      if (inbound.kind === "sync" && inbound.data.kind === "pong") {
        const stats = deps.sync.evaluatePong(inbound.data, Date.now());
        choirAllocator.updateSyncHealth(hashedId, stats.rtt, stats.driftEstimate, Date.now());
        syncHealthByDevice.set(hashedId, {
          rttMs: stats.rtt,
          driftMs: stats.driftEstimate,
          lastSeenAtMs: Date.now()
        });
        await deps.replayService.record({
          type: "sync",
          timestamp: Date.now(),
          logicalTime: deps.show.snapshot().logicalTime,
          source: "phone",
          payload: {
            hashedId,
            ...stats
          }
        });

        if (stats.shouldResync) {
          send(socket, {
            kind: "sync",
            data: {
              kind: "ping",
              serverTime: Date.now(),
              clientTime: inbound.data.clientTime,
              rtt: stats.rtt,
              driftEstimate: stats.driftEstimate
            },
            sentAt: Date.now()
          } satisfies WireEnvelope<SyncPacket>);
        }
        return;
      }

      if (inbound.kind === "permissions") {
        const current = await deps.sessions.get(hashedId);
        if (current) {
          await deps.sessions.upsert({
            ...current,
            permissions: {
              ...current.permissions,
              ...inbound.data
            }
          });
        }

        const pool = deps.phoneAudioPool.markDevice(hashedId, inbound.data);
        choirAllocator.upsertDevice(hashedId, inbound.data);
        publishPhonePoolState(pool);
        return;
      }

      if (inbound.kind === "zone_update") {
        await deps.sessions.patchZone(hashedId, inbound.data);
        choirAllocator.updateZone(hashedId, inbound.data, Date.now());
        return;
      }

      if (inbound.kind === "participant_vector") {
        const vector = normalizeVector(inbound.data.vector ?? {});
        const influence = clamp01Number(inbound.data.influence);
        const priorPrompt = promptInfluenceByDevice.get(hashedId);
        const promptInfluence =
          typeof inbound.data.promptInfluence === "number"
            ? clamp01Number(inbound.data.promptInfluence)
            : priorPrompt?.promptInfluence ?? 0;
        const directPickInfluence =
          typeof inbound.data.directPickInfluence === "number"
            ? clamp01Number(inbound.data.directPickInfluence)
            : priorPrompt?.directPickInfluence ?? 0;
        promptInfluenceByDevice.set(hashedId, {
          promptInfluence,
          directPickInfluence
        });
        const compositorMode = toCompositorMode(inbound.data.compositorMode);
        const aggregate = audienceField.update(hashedId, {
          vector,
          influence,
          promptInfluence,
          directPickInfluence,
          compositorMode
        });
        choirAllocator.updateVector(hashedId, vector, influence, Date.now());

        await deps.replayService.record({
          type: "telemetry",
          timestamp: Date.now(),
          logicalTime: deps.show.snapshot().logicalTime,
          source: "phone",
          payload: {
            hashedId,
            kind: "participant_vector",
            influence,
            promptInfluence,
            directPickInfluence,
            compositorMode,
            colorIntent: normalizeColorIntent(inbound.data.colorIntent),
            vector
          }
        });

        broadcastAudienceVector(aggregate);
        const sessionProfile = await deps.sessions.get(hashedId);
        const lightingState = deps.lightingField.update(hashedId, {
          intent: normalizeColorIntent(inbound.data.colorIntent),
          influence,
          updatedAt: Date.now(),
          zone: sessionProfile?.zone
            ? {
                x: sessionProfile.zone.x,
                y: sessionProfile.zone.y
              }
            : {
                x: vector.spatialX,
                y: vector.spatialY
            }
        });
        broadcastLightingState(lightingState);
        composeAndBroadcastProceduralState();
        composeAndBroadcastTextScene(false);
        return;
      }

      if (inbound.kind === "push_deck_event") {
        const normalized = normalizePushDeckEvent(inbound.data, hashedId);
        if (!normalized) {
          return;
        }

        if (normalized.controlKind === "ml_param" && normalized.mlParam) {
          const activeEchoCaps = resolveEchoCapsByScene(latestActiveScene);
          const normalizedEcho = applyEchoMLParam(
            normalized.mlParam.key,
            normalized.mlParam.value,
            activeEchoCaps,
            echoByStem
          );
          echoByStem.pads = normalizedEcho.pads;
          echoByStem.hotas = normalizedEcho.hotas;
          echoByStem.choir = normalizedEcho.choir;
          echoByStem.fx = normalizedEcho.fx;
          globalEchoProbability = normalizedEcho.global;
          composeAndBroadcastProceduralState();
        }

        if (
          normalized.controlKind === "macro" ||
          normalized.controlKind === "long_strip" ||
          normalized.controlKind === "ml_param"
        ) {
          forwardPushDeckEventWithCoalescing(normalized);
        } else {
          forwardPushDeckEvent(normalized);
        }

        await deps.replayService.record({
          type: "device_uplink",
          timestamp: Date.now(),
          logicalTime: deps.show.snapshot().logicalTime,
          source: "phone",
          payload: {
            hashedId,
            kind: "push_deck_event",
            eventId: normalized.eventId,
            controlKind: normalized.controlKind,
            modeContext: normalized.modeContext,
            timingMode: normalized.timingMode,
            longStripValue: normalized.longStrip?.value,
            mlParamKey: normalized.mlParam?.key,
            mlParamValue: normalized.mlParam?.value
          }
        });
        return;
      }

      if (inbound.kind === "crowd_pick_vote") {
        const vote: CrowdPickVotePayload = {
          windowId: typeof inbound.data.windowId === "string" ? inbound.data.windowId : "",
          optionId: typeof inbound.data.optionId === "string" ? inbound.data.optionId : "",
          votedAt: typeof inbound.data.votedAt === "number" ? inbound.data.votedAt : Date.now()
        };
        const accepted = deps.crowdPickPulse.vote(hashedId, vote);
        if (!accepted) {
          return;
        }
        await deps.replayService.record({
          type: "device_uplink",
          timestamp: Date.now(),
          logicalTime: deps.show.snapshot().logicalTime,
          source: "phone",
          payload: {
            hashedId,
            kind: "crowd_pick_vote",
            ...vote
          }
        });
        return;
      }

      if (inbound.kind === "prompt_response") {
        const response = normalizePromptResponse(inbound.data);
        const result = promptOrchestrator.consumeResponse(hashedId, response, Date.now());
        if (!result.accepted) {
          return;
        }

        const aggregate = audienceField.updatePromptInfluence(hashedId, {
          promptInfluence: result.promptInfluence,
          directPickInfluence: result.directPickInfluence,
          updatedAt: Date.now()
        });
        promptInfluenceByDevice.set(hashedId, {
          promptInfluence: result.promptInfluence,
          directPickInfluence: result.directPickInfluence
        });
        broadcastAudienceVector(aggregate);

        const selectedChoice = resolvePromptChoiceToken(response);
        const clipPromptAction =
          result.action === "direct_slot_a" ||
          result.action === "direct_slot_b" ||
          result.action === "direct_take_next" ||
          result.action === "clip_select" ||
          result.action === "clip_tension" ||
          result.action === "clip_release";

        if (clipPromptAction && baseProceduralState.dynamicBinManifest.length > 0) {
          const preferredIndex = baseProceduralState.dynamicBinManifest.findIndex((clip) => {
            const clipId = clip.id.toLowerCase();
            return clipId === selectedChoice;
          });
          if (preferredIndex >= 0) {
            baseProceduralState = normalizeProceduralState(
              {
                ...baseProceduralState,
                dynamicBinSelection:
                  baseProceduralState.dynamicBinManifest.length <= 1
                    ? 0
                    : preferredIndex / Math.max(1, baseProceduralState.dynamicBinManifest.length - 1),
                dynamicBinIndex: preferredIndex
              },
              baseProceduralState
            );
          }
        }

        if (result.action === "blend_select") {
          const selectedPreset = toPromptBlendPreset(selectedChoice, baseProceduralState.splitLayout);
          if (selectedPreset) {
            baseProceduralState = normalizeProceduralState(
              {
                ...baseProceduralState,
                compositorPreset: selectedPreset
              },
              baseProceduralState
            );
          }
        }

        if (result.action === "layout_pip" || result.action === "layout_split" || result.action === "layout_full") {
          const splitLayout =
            result.action === "layout_pip"
              ? "pip"
              : result.action === "layout_split"
                ? "split-2"
                : "none";
          baseProceduralState = normalizeProceduralState(
            {
              ...baseProceduralState,
              splitLayout
            },
            baseProceduralState
          );
        }

        if (result.action === "split_type") {
          const requestedSplit = toPromptSplitLayout(selectedChoice);
          if (requestedSplit) {
            baseProceduralState = normalizeProceduralState(
              {
                ...baseProceduralState,
                splitLayout: requestedSplit
              },
              baseProceduralState
            );
          }
        }

        if (result.action === "split_amount" && response.dragVector) {
          const nextSplitAmount = clamp01Number(0.5 + response.dragVector.x * 0.35);
          baseProceduralState = normalizeProceduralState(
            {
              ...baseProceduralState,
              splitAmount: nextSplitAmount
            },
            baseProceduralState
          );
        }

        if (result.action === "pip_position") {
          const pipPosition = toPromptPipPosition(selectedChoice);
          if (pipPosition) {
            baseProceduralState = normalizeProceduralState(
              {
                ...baseProceduralState,
                pipPosition
              },
              baseProceduralState
            );
          }
        }

        if (result.domain === "text") {
          composeAndBroadcastTextScene(true);
        }
        composeAndBroadcastProceduralState();

        await deps.replayService.record({
          type: "device_uplink",
          timestamp: Date.now(),
          logicalTime: deps.show.snapshot().logicalTime,
          source: "phone",
          payload: {
            hashedId,
            kind: "prompt_response",
            promptId: response.promptId,
            responseType: response.responseType,
            promptInfluence: result.promptInfluence,
            directPickInfluence: result.directPickInfluence,
            action: result.action,
            domain: result.domain
          }
        });
        return;
      }

      if (inbound.kind === "ack") {
        const cueId = typeof inbound.data.cueId === "string" ? inbound.data.cueId : "";
        const seenAt = parseFiniteNumber(inbound.data.seenAt) ?? Date.now();
        if (cueId.length > 0) {
          recordCueActivationAck(
            "device",
            cueId,
            inbound.data.activatedAtMs ?? seenAt,
            inbound.data.activationDeltaMs,
            {
              hashedId
            }
          );
        }
        await deps.replayService.record({
          type: "device_uplink",
          timestamp: Date.now(),
          logicalTime: deps.show.snapshot().logicalTime,
          source: "phone",
          payload: {
            hashedId,
            kind: "cue_activation_ack",
            cueId,
            seenAt,
            activatedAtMs:
              parseFiniteNumber(inbound.data.activatedAtMs) ??
              seenAt,
            activationDeltaMs: parseFiniteNumber(inbound.data.activationDeltaMs)
          }
        });
        return;
      }

      if (inbound.kind === "phone_audio_ack") {
        const ack: PhoneAudioAckPayload = {
          commandId: typeof inbound.data.commandId === "string" ? inbound.data.commandId : "",
          hashedId,
          ok: inbound.data.ok === true,
          detail: typeof inbound.data.detail === "string" ? inbound.data.detail : undefined,
          streamStatus: toStreamLifecycleStatus(inbound.data.streamStatus),
          streamReason: typeof inbound.data.streamReason === "string" ? inbound.data.streamReason : undefined,
          voiceId: typeof inbound.data.voiceId === "string" ? inbound.data.voiceId : undefined,
          trackId: typeof inbound.data.trackId === "string" ? inbound.data.trackId : undefined,
          receivedAt: typeof inbound.data.receivedAt === "number" ? inbound.data.receivedAt : Date.now()
        };

        await deps.replayService.record({
          type: "device_uplink",
          timestamp: Date.now(),
          logicalTime: deps.show.snapshot().logicalTime,
          source: "phone",
          payload: {
            kind: "phone_audio_ack",
            ...ack
          }
        });

        broadcastToHarness({
          kind: "phone_audio_ack",
          data: ack,
          sentAt: Date.now()
        } satisfies WireEnvelope<PhoneAudioAckPayload>);

        choirAllocator.observeAck(hashedId, ack.ok, ack.receivedAt);
        const pending = pendingVoiceAcks.get(ack.commandId);
        if (pending && pending.targetHashedId === hashedId) {
          clearTimeout(pending.timeout);
          pendingVoiceAcks.delete(ack.commandId);
          if (!ack.ok && pending.failoverAttempts < 1) {
            dispatchVoiceFailover(pending, `ack_fail:${hashedId}`);
          }
        }
        publishPhonePoolState(deps.phoneAudioPool.snapshot());
        return;
      }

      if (inbound.kind === "voice_stream_subscribe") {
        const requestType = inbound.data.requestType;
        if (
          requestType !== "init" &&
          requestType !== "connect" &&
          requestType !== "consume" &&
          requestType !== "resume"
        ) {
          send(socket, {
            kind: "error",
            data: {
              message: "voice_stream_subscribe rejected: invalid request type"
            },
            sentAt: Date.now()
          } satisfies WireEnvelope);
          return;
        }

        const payload: VoiceStreamSubscribePayload = {
          commandId:
            typeof inbound.data.commandId === "string" && inbound.data.commandId.trim().length > 0
              ? inbound.data.commandId
              : `voice-sub-${Date.now()}`,
          hashedId,
          voiceId:
            typeof inbound.data.voiceId === "string" && inbound.data.voiceId.trim().length > 0
              ? inbound.data.voiceId
              : "voice",
          trackId:
            typeof inbound.data.trackId === "string" && inbound.data.trackId.trim().length > 0
              ? inbound.data.trackId
              : "track",
          sessionId:
            typeof inbound.data.sessionId === "string" && inbound.data.sessionId.trim().length > 0
              ? inbound.data.sessionId
              : `${deps.config.CONDUCTOR_MANAGED_SFU_SESSION_PREFIX}-sess`,
          requestType,
          transportId:
            typeof inbound.data.transportId === "string" && inbound.data.transportId.trim().length > 0
              ? inbound.data.transportId
              : undefined,
          rtpCapabilities: asRecord(inbound.data.rtpCapabilities) ?? undefined,
          dtlsParameters: asRecord(inbound.data.dtlsParameters) ?? undefined,
          consumerId:
            typeof inbound.data.consumerId === "string" && inbound.data.consumerId.trim().length > 0
              ? inbound.data.consumerId
              : undefined,
          issuedAt:
            typeof inbound.data.issuedAt === "number" && Number.isFinite(inbound.data.issuedAt)
              ? inbound.data.issuedAt
              : Date.now()
        };

        const response = await mediasoupVoiceService.handleSubscribe(payload);
        if (!response) {
          send(socket, {
            kind: "error",
            data: {
              message: "voice_stream_subscribe rejected: unavailable"
            },
            sentAt: Date.now()
          } satisfies WireEnvelope);
          return;
        }

        send(socket, {
          kind: "voice_stream_subscribed",
          data: response,
          sentAt: Date.now()
        } satisfies WireEnvelope<VoiceStreamSubscribedPayload>);
        return;
      }

      if (inbound.kind === "voice_stream_unsubscribe") {
        mediasoupVoiceService.handleUnsubscribe({
          hashedId,
          voiceId:
            typeof inbound.data.voiceId === "string" && inbound.data.voiceId.trim().length > 0
              ? inbound.data.voiceId
              : undefined,
          trackId:
            typeof inbound.data.trackId === "string" && inbound.data.trackId.trim().length > 0
              ? inbound.data.trackId
              : undefined
        });
        return;
      }

      if (inbound.kind === "voice_stream_ice") {
        mediasoupVoiceService.handleIceCandidate({
          hashedId,
          transportId:
            typeof inbound.data.transportId === "string" && inbound.data.transportId.trim().length > 0
              ? inbound.data.transportId
              : undefined,
          candidate:
            typeof inbound.data.candidate === "string" && inbound.data.candidate.trim().length > 0
              ? inbound.data.candidate
              : undefined
        });
        return;
      }

      if (inbound.kind === "telemetry") {
        await deps.replayService.record({
          type: "telemetry",
          timestamp: Date.now(),
          logicalTime: deps.show.snapshot().logicalTime,
          source: "phone",
          payload: {
            hashedId,
            ...inbound.data
          }
        });
      }
    });
  });

  setInterval(() => {
    const ping = deps.sync.createPing(Date.now());
    broadcastToDevices({
      kind: "sync",
      data: ping,
      sentAt: Date.now()
    } satisfies WireEnvelope<SyncPacket>);
  }, 2000).unref();

  setInterval(() => {
    if (deviceSockets.size === 0 && harnessSockets.size === 0) {
      return;
    }
    broadcastShowSnapshot();
  }, 1000).unref();

  setInterval(() => {
    const activeParticipants = audienceField.snapshot().participantCount;
    const result = deps.crowdPickPulse.tick(activeParticipants, Date.now());
    if (!result.windowChanged && !result.resultChanged) {
      return;
    }

    const pulse = deps.crowdPickPulse.snapshot();
    deps.audioOpsStateHub.setPickWindow(pulse.window);
    deps.audioOpsStateHub.setPickResult(pulse.result);

    if (pulse.window) {
      const envelope = {
        kind: "crowd_pick_window",
        data: pulse.window,
        sentAt: Date.now()
      } satisfies WireEnvelope;
      broadcastToDevices(envelope);
      broadcastToHarness(envelope);
    }

    if (pulse.result) {
      const envelope = {
        kind: "crowd_pick_result",
        data: pulse.result,
        sentAt: Date.now()
      } satisfies WireEnvelope;
      broadcastToDevices(envelope);
      broadcastToHarness(envelope);

      if (pulse.result.applied) {
        composeAndBroadcastProceduralState();
        composeAndBroadcastTextScene(true);
      }
    }
  }, 1000).unref();

  setInterval(() => {
    const now = Date.now();
    const showSnapshot = deps.show.snapshot();
    const cuePayload = (latestCue.payload ?? {}) as Record<string, unknown>;
    const dispatches = promptOrchestrator.tick({
      now,
      cueVersion: latestCueVersion,
      showState: showSnapshot.state,
      activeScene: latestActiveScene,
      engineRunning: parseBoolean(cuePayload.engineRunning, showSnapshot.state !== "idle"),
      participantCount: audienceField.snapshot().participantCount,
      entropy: deps.lightingField.snapshot().entropy,
      audioFlux: lastAudioFeatures.flux,
      connectedHashedIds: [...deviceSockets.keys()],
      availableDynamicClipIds: baseProceduralState.dynamicBinManifest.map((clip) => clip.id),
      splitLayout: baseProceduralState.splitLayout
    });
    if (dispatches.length === 0) {
      return;
    }

    for (const dispatch of dispatches) {
      broadcastToSpecificDevices(
        [dispatch.hashedId],
        {
          kind: "prompt_offer",
          data: dispatch.offer,
          sentAt: now
        } satisfies WireEnvelope<PromptOfferPayload>
      );
      broadcastToHarness({
        kind: "telemetry",
        data: {
          kind: "prompt_offer",
          targetHashedId: dispatch.hashedId,
          promptId: dispatch.offer.promptId,
          scene: dispatch.offer.scene,
          domain: dispatch.offer.domain,
          action: dispatch.offer.action,
          affordance: dispatch.offer.affordance,
          expiresAt: dispatch.offer.expiresAt
        },
        sentAt: now
      } satisfies WireEnvelope);
    }
  }, 500).unref();

  deps.audioOpsStateHub.subscribe((snapshot) => {
    broadcastToHarness({
      kind: "telemetry",
      data: {
        kind: "audio_ops_state",
        updatedAt: snapshot.updatedAt
      },
      sentAt: Date.now()
    } satisfies WireEnvelope);
  });

  function composeAndBroadcastProceduralState(): void {
    const audience = audienceField.snapshot();
    const pulse = deps.crowdPickPulse.snapshot();
    const echoCaps = resolveEchoCapsByScene(latestActiveScene);
    for (const stem of Object.keys(echoByStem) as EchoStem[]) {
      const caps = echoCaps[stem];
      echoByStem[stem] = Math.max(caps.floor, Math.min(caps.cap, echoByStem[stem]));
    }
    globalEchoProbability = clamp01((echoByStem.pads + echoByStem.hotas + echoByStem.choir + echoByStem.fx) / 4);
    effectiveProceduralState = applyAudienceSteeringAndVariance(
      baseProceduralState,
      audience,
      lastAudioFeatures,
      pulse.result,
      {
        promptInfluence: clamp01(audience.promptInfluence ?? 0),
        directPickInfluence: clamp01(audience.directPickInfluence ?? 0),
        globalEchoProbability,
        echoByStem,
        echoCapsByStem: echoCaps
      }
    );
    deps.audioOpsStateHub.setProceduralState(effectiveProceduralState);
    broadcastProceduralState(effectiveProceduralState);
    if (latestActiveScene === "mainDynamic") {
      scheduleDynamicClipCommit(effectiveProceduralState.dynamicBinClipId);
    }
  }

  function composeAndBroadcastTextScene(force: boolean, cueIdOverride?: string): void {
    const now = Date.now();
    if (!force && now - lastTextComposeAt < 700) {
      return;
    }
    lastTextComposeAt = now;
    const showSnapshot = deps.show.snapshot();
    const pulse = deps.crowdPickPulse.snapshot();
    const scene = deps.textSceneComposer.compose({
      cueId: cueIdOverride ?? `${showSnapshot.state}:${Math.round(showSnapshot.logicalTime)}`,
      vector: showSnapshot.vector,
      audioFeatures: lastAudioFeatures,
      pickResult: pulse.result,
      pickEpoch: pulse.pickEpoch,
      textBlend: {
        probability: effectiveProceduralState.textProbability,
        strictRatio: effectiveProceduralState.strictLooseBlend
      }
    });
    deps.audioOpsStateHub.setTextScene(scene);
    broadcastTextScene(scene);
  }

  function buildTextRuntimeStatusPayload(): TextRuntimeStatusPayload {
    const runtime = deps.textSceneComposer.runtimeStatus();
    return {
      updatedAt: runtime.updatedAt,
      strictCount: runtime.strictCount,
      looseCount: runtime.looseCount,
      strictSource: runtime.strictSource,
      looseSource: runtime.looseSource,
      warnings: runtime.warnings,
      modelHealth: runtime.modelHealth,
      semantic: runtime.semantic
    };
  }

  function broadcastTextRuntimeStatus(): void {
    const envelope = {
      kind: "text_runtime_status",
      data: buildTextRuntimeStatusPayload(),
      sentAt: Date.now()
    } satisfies WireEnvelope<TextRuntimeStatusPayload>;
    broadcastToHarness(envelope);
  }

  function enrichPhoneAudioPoolState(pool: PhoneAudioPoolStatePayload): PhoneAudioPoolStatePayload {
    const telemetry = choirAllocator.telemetry(pool.activeVoices);
    return {
      ...pool,
      ...telemetry,
      updatedAt: Date.now()
    };
  }

  function publishPhonePoolState(pool: PhoneAudioPoolStatePayload): PhoneAudioPoolStatePayload {
    const enriched = enrichPhoneAudioPoolState(pool);
    deps.audioOpsStateHub.setPhoneAudioPool(enriched);
    broadcastPhoneAudioPoolState(enriched);
    return enriched;
  }

  function pushInitialSnapshot(socket: WebSocket, role: "harness" | "device"): void {
    send(socket, {
      kind: "show_snapshot",
      data: buildShowSnapshotPayload(),
      sentAt: Date.now()
    } satisfies WireEnvelope);

    if (latestKeyboardState) {
      send(socket, {
        kind: "keyboard_state",
        data: latestKeyboardState,
        sentAt: Date.now()
      } satisfies WireEnvelope<KeyboardStatePayload>);
    }

    // Always provide a cue envelope at connection time so clients have an
    // immediately renderable output mode/layer state.
    send(socket, {
      kind: "cue",
      data: enrichCuePayload(latestCue ?? buildSnapshotCue()),
      sentAt: Date.now()
    } satisfies WireEnvelope);

    const ops = deps.audioOpsStateHub.snapshot();
    send(socket, {
      kind: "phone_audio_pool_state",
      data: ops.phoneAudioPool,
      sentAt: Date.now()
    } satisfies WireEnvelope<PhoneAudioPoolStatePayload>);

    send(socket, {
      kind: "procedural_state",
      data: ops.proceduralState ?? effectiveProceduralState,
      sentAt: Date.now()
    } satisfies WireEnvelope<ProgramProceduralState>);

    if (role === "harness") {
      send(socket, {
        kind: "text_runtime_status",
        data: buildTextRuntimeStatusPayload(),
        sentAt: Date.now()
      } satisfies WireEnvelope<TextRuntimeStatusPayload>);
    }

    if (role === "device") {
      if (lastPushPadLabels) {
        send(socket, {
          kind: "push_pad_labels",
          data: lastPushPadLabels,
          sentAt: Date.now()
        } satisfies WireEnvelope<PushPadLabelsPayload>);
      }

      send(socket, {
        kind: "audience_vector",
        data: audienceField.snapshot(),
        sentAt: Date.now()
      } satisfies WireEnvelope<AudienceVectorPayload>);

      send(socket, {
        kind: "lighting_state",
        data: deps.lightingField.snapshot(),
        sentAt: Date.now()
      } satisfies WireEnvelope<LightingStatePayload>);

      send(socket, {
        kind: "audio_features",
        data: ops.audioFeatures,
        sentAt: Date.now()
      } satisfies WireEnvelope<AudioFeaturePayload>);

      if (ops.pickWindow) {
        send(socket, {
          kind: "crowd_pick_window",
          data: ops.pickWindow,
          sentAt: Date.now()
        } satisfies WireEnvelope);
      }
      if (ops.pickResult) {
        send(socket, {
          kind: "crowd_pick_result",
          data: ops.pickResult,
          sentAt: Date.now()
        } satisfies WireEnvelope);
      }
      send(socket, {
        kind: "text_scene",
        data: ops.textScene,
        sentAt: Date.now()
      } satisfies WireEnvelope<TextScenePayload>);
    }
  }

  function dispatchPhoneAudioCommand(command: PhoneAudioCommandPayload): PhoneAudioCommandPayload | null {
    const pool = deps.phoneAudioPool.snapshot();
    let targets = command.targetHashedIds.filter((id) => deviceSockets.has(id));
    let renderHintsByTarget: Record<string, NonNullable<PhoneAudioCommandPayload["renderHints"]>> = {};
    let streamByTarget: Record<string, VoiceStreamDescriptor> = {};
    let fallbackGroup: GroupStemDescriptor | undefined;
    const voiceStreamStarts: VoiceStreamStartPayload[] = [];
    const voiceStreamStops: VoiceStreamStopPayload[] = [];
    const groupStemStarts: GroupStemStartPayload[] = [];
    const groupStemStops: GroupStemStopPayload[] = [];

    switch (command.kind) {
      case "note_on": {
        const note = typeof command.note === "number" ? command.note : 60;
        const plan = choirAllocator.planNoteOn(note, pool.availableDevices, pool.activeVoices, targets);
        targets = deps.phoneAudioPool.allocateVoice(note, plan.targetHashedIds);
        renderHintsByTarget = targets.reduce<Record<string, NonNullable<PhoneAudioCommandPayload["renderHints"]>>>((acc, id) => {
          const hint = plan.renderHintsByTarget[id];
          if (hint) {
            acc[id] = hint;
          }
          return acc;
        }, {});

        const activeVoiceCount = [...activeVoiceStreamsByNote.values()].reduce((sum, map) => sum + map.size, 0);
        const availableVoiceSlots = Math.max(0, maxConcurrentVoiceStreams - activeVoiceCount);
        const voiceTargets = targets.slice(0, availableVoiceSlots);
        const overflowTargets = targets.slice(availableVoiceSlots);
        const noteStreamMap = activeVoiceStreamsByNote.get(note) ?? new Map<string, VoiceStreamDescriptor>();

        for (const targetHashedId of voiceTargets) {
          const rawDescriptor = managedSfuCoordinator.buildVoiceDescriptor({
            hashedId: targetHashedId,
            note,
            commandId: command.commandId
          });
          const baseDescriptor = normalizeVoiceDescriptorForTransport(rawDescriptor, note);
          const descriptor = mediasoupVoiceService.decorateVoiceDescriptor(baseDescriptor);
          noteStreamMap.set(targetHashedId, descriptor);
          streamByTarget[targetHashedId] = descriptor;
          voiceStreamStarts.push({
            commandId: command.commandId,
            hashedId: targetHashedId,
            note,
            velocity: command.velocity,
            renderHints: plan.renderHintsByTarget[targetHashedId],
            stream: descriptor,
            issuedAt: Date.now()
          });
        }
        activeVoiceStreamsByNote.set(note, noteStreamMap);

        if (overflowTargets.length > 0) {
          const baseGroup = managedSfuCoordinator.buildGroupDescriptor({
            groupId: "phone-choir-group",
            commandId: command.commandId
          });
          fallbackGroup = mediasoupVoiceService.decorateGroupDescriptor(baseGroup);
          for (const targetHashedId of overflowTargets) {
            activeGroupStemByTarget.set(targetHashedId, fallbackGroup);
          }
          groupStemStarts.push({
            commandId: command.commandId,
            hashedIds: overflowTargets,
            group: fallbackGroup,
            reason: "voice_cap",
            issuedAt: Date.now()
          });
        }
        break;
      }
      case "note_off": {
        const note = typeof command.note === "number" ? command.note : undefined;
        if (typeof note === "number") {
          const noteStreamMap = activeVoiceStreamsByNote.get(note);
          if (noteStreamMap) {
            for (const targetHashedId of targets) {
              const descriptor = noteStreamMap.get(targetHashedId);
              if (!descriptor) {
                continue;
              }
              noteStreamMap.delete(targetHashedId);
              voiceStreamStops.push({
                commandId: command.commandId,
                hashedId: targetHashedId,
                note,
                voiceId: descriptor.voiceId,
                trackId: descriptor.trackId,
                reason: "note_off",
                issuedAt: Date.now()
              });
            }
            if (noteStreamMap.size === 0) {
              activeVoiceStreamsByNote.delete(note);
            } else {
              activeVoiceStreamsByNote.set(note, noteStreamMap);
            }
          }
        }

        targets = deps.phoneAudioPool.releaseVoice(command.note, targets);
        if (typeof command.note === "number") {
          for (const [commandId, pending] of pendingVoiceAcks.entries()) {
            if (pending.note === command.note) {
              clearTimeout(pending.timeout);
              pendingVoiceAcks.delete(commandId);
            }
          }
        }

        for (const targetHashedId of targets) {
          const group = activeGroupStemByTarget.get(targetHashedId);
          if (!group) {
            continue;
          }
          activeGroupStemByTarget.delete(targetHashedId);
          groupStemStops.push({
            commandId: command.commandId,
            hashedIds: [targetHashedId],
            groupId: group.groupId,
            reason: "manual",
            issuedAt: Date.now()
          });
        }
        break;
      }
      case "stop_all": {
        const before = Object.keys(deps.phoneAudioPool.snapshot().activeVoices);
        deps.phoneAudioPool.releaseAll();
        for (const [, pending] of pendingVoiceAcks.entries()) {
          clearTimeout(pending.timeout);
        }
        pendingVoiceAcks.clear();
        targets = before;

        for (const [note, noteStreamMap] of activeVoiceStreamsByNote.entries()) {
          for (const [targetHashedId, descriptor] of noteStreamMap.entries()) {
            voiceStreamStops.push({
              commandId: command.commandId,
              hashedId: targetHashedId,
              note,
              voiceId: descriptor.voiceId,
              trackId: descriptor.trackId,
              reason: "stop_all",
              issuedAt: Date.now()
            });
          }
        }
        activeVoiceStreamsByNote.clear();

        for (const [targetHashedId, descriptor] of activeGroupStemByTarget.entries()) {
          groupStemStops.push({
            commandId: command.commandId,
            hashedIds: [targetHashedId],
            groupId: descriptor.groupId,
            reason: "show_stop",
            issuedAt: Date.now()
          });
        }
        activeGroupStemByTarget.clear();
        break;
      }
      case "sample_trigger": {
        const plan = choirAllocator.planTextureTargets(pool.availableDevices, pool.activeVoices, targets, "medium");
        targets = plan.targetHashedIds;
        renderHintsByTarget = plan.renderHintsByTarget;
        break;
      }
      case "ambient_noise": {
        const plan = choirAllocator.planTextureTargets(pool.availableDevices, pool.activeVoices, targets, "low");
        targets = plan.targetHashedIds;
        renderHintsByTarget = plan.renderHintsByTarget;
        break;
      }
      default:
        break;
    }

    if (targets.length === 0) {
      return null;
    }

    const dispatched: PhoneAudioCommandPayload = {
      ...command,
      targetHashedIds: targets,
      stream: streamByTarget[targets[0]] ?? command.stream,
      streamByTarget: Object.keys(streamByTarget).length > 0 ? streamByTarget : command.streamByTarget,
      fallbackGroup: fallbackGroup ?? command.fallbackGroup,
      renderHints: Object.values(renderHintsByTarget)[0] ?? command.renderHints,
      renderHintsByTarget: Object.keys(renderHintsByTarget).length > 0 ? renderHintsByTarget : command.renderHintsByTarget,
      issuedAt: Date.now()
    };

    dispatchPhoneCommandToTargets(dispatched);
    for (const payload of voiceStreamStarts) {
      dispatchVoiceStreamStart(payload);
    }
    for (const payload of groupStemStarts) {
      dispatchGroupStemStart(payload);
    }
    for (const payload of voiceStreamStops) {
      dispatchVoiceStreamStop(payload);
    }
    for (const payload of groupStemStops) {
      dispatchGroupStemStop(payload);
    }
    publishPhonePoolState(deps.phoneAudioPool.snapshot());

    if (dispatched.kind === "note_on" && typeof dispatched.note === "number" && dispatched.targetHashedIds.length > 0) {
      const targetHashedId = dispatched.targetHashedIds[0];
      const timeout = setTimeout(() => {
        const pending = pendingVoiceAcks.get(dispatched.commandId);
        if (!pending) {
          return;
        }
        pendingVoiceAcks.delete(dispatched.commandId);
        dispatchVoiceFailover(pending, `ack_timeout:${targetHashedId}`);
      }, 720);
      timeout.unref();
      pendingVoiceAcks.set(dispatched.commandId, {
        note: dispatched.note,
        targetHashedId,
        command: dispatched,
        timeout,
        failoverAttempts: 0
      });
    }

    return dispatched;
  }

  function dispatchPhoneCommandToTargets(dispatched: PhoneAudioCommandPayload): void {
    broadcastToSpecificDevices(dispatched.targetHashedIds, {
      kind: "phone_audio_command",
      data: dispatched,
      sentAt: Date.now()
    } satisfies WireEnvelope<PhoneAudioCommandPayload>);
    broadcastToHarness({
      kind: "phone_audio_command",
      data: dispatched,
      sentAt: Date.now()
    } satisfies WireEnvelope<PhoneAudioCommandPayload>);
  }

  function dispatchVoiceStreamStart(payload: VoiceStreamStartPayload): void {
    broadcastToSpecificDevices([payload.hashedId], {
      kind: "voice_stream_start",
      data: payload,
      sentAt: Date.now()
    } satisfies WireEnvelope<VoiceStreamStartPayload>);
    broadcastToHarness({
      kind: "voice_stream_start",
      data: payload,
      sentAt: Date.now()
    } satisfies WireEnvelope<VoiceStreamStartPayload>);
  }

  function dispatchVoiceStreamStop(payload: VoiceStreamStopPayload): void {
    broadcastToSpecificDevices([payload.hashedId], {
      kind: "voice_stream_stop",
      data: payload,
      sentAt: Date.now()
    } satisfies WireEnvelope<VoiceStreamStopPayload>);
    broadcastToHarness({
      kind: "voice_stream_stop",
      data: payload,
      sentAt: Date.now()
    } satisfies WireEnvelope<VoiceStreamStopPayload>);
  }

  function dispatchGroupStemStart(payload: GroupStemStartPayload): void {
    broadcastToSpecificDevices(payload.hashedIds, {
      kind: "group_stem_start",
      data: payload,
      sentAt: Date.now()
    } satisfies WireEnvelope<GroupStemStartPayload>);
    broadcastToHarness({
      kind: "group_stem_start",
      data: payload,
      sentAt: Date.now()
    } satisfies WireEnvelope<GroupStemStartPayload>);
  }

  function dispatchGroupStemStop(payload: GroupStemStopPayload): void {
    broadcastToSpecificDevices(payload.hashedIds, {
      kind: "group_stem_stop",
      data: payload,
      sentAt: Date.now()
    } satisfies WireEnvelope<GroupStemStopPayload>);
    broadcastToHarness({
      kind: "group_stem_stop",
      data: payload,
      sentAt: Date.now()
    } satisfies WireEnvelope<GroupStemStopPayload>);
  }

  function dispatchVoiceFailover(
    pending: {
      note: number;
      targetHashedId: string;
      command: PhoneAudioCommandPayload;
      failoverAttempts: number;
    },
    reason: string
  ): void {
    deps.phoneAudioPool.releaseVoice(pending.note, [pending.targetHashedId]);
    const priorStreamMap = activeVoiceStreamsByNote.get(pending.note);
    const priorDescriptor = priorStreamMap?.get(pending.targetHashedId);
    if (priorDescriptor) {
      priorStreamMap?.delete(pending.targetHashedId);
      dispatchVoiceStreamStop({
        commandId: pending.command.commandId,
        hashedId: pending.targetHashedId,
        note: pending.note,
        voiceId: priorDescriptor.voiceId,
        trackId: priorDescriptor.trackId,
        reason: "failover",
        issuedAt: Date.now()
      });
      if (priorStreamMap && priorStreamMap.size === 0) {
        activeVoiceStreamsByNote.delete(pending.note);
      }
    }
    const pool = deps.phoneAudioPool.snapshot();
    const plan = choirAllocator.planFailover(
      pending.targetHashedId,
      pending.note,
      pool.availableDevices,
      pool.activeVoices
    );
    if (plan.targetHashedIds.length === 0) {
      return;
    }

    const targetHashedIds = deps.phoneAudioPool.allocateVoice(pending.note, plan.targetHashedIds);
    if (targetHashedIds.length === 0) {
      return;
    }

    const command: PhoneAudioCommandPayload = {
      ...pending.command,
      commandId: `${pending.command.commandId}-fo-${Date.now()}`,
      targetHashedIds,
      stream: undefined,
      streamByTarget: undefined,
      renderHints: plan.renderHintsByTarget[targetHashedIds[0]],
      renderHintsByTarget: plan.renderHintsByTarget,
      issuedAt: Date.now()
    };

    if (targetHashedIds.length > 0) {
      const nextTarget = targetHashedIds[0];
      const rawDescriptor = managedSfuCoordinator.buildVoiceDescriptor({
        hashedId: nextTarget,
        note: pending.note,
        commandId: command.commandId
      });
      const baseDescriptor = normalizeVoiceDescriptorForTransport(rawDescriptor, pending.note);
      const descriptor = mediasoupVoiceService.decorateVoiceDescriptor(baseDescriptor);
      const map = activeVoiceStreamsByNote.get(pending.note) ?? new Map<string, VoiceStreamDescriptor>();
      map.set(nextTarget, descriptor);
      activeVoiceStreamsByNote.set(pending.note, map);
      command.stream = descriptor;
      command.streamByTarget = {
        [nextTarget]: descriptor
      };
      dispatchVoiceStreamStart({
        commandId: command.commandId,
        hashedId: nextTarget,
        note: pending.note,
        velocity: command.velocity,
        renderHints: command.renderHintsByTarget?.[nextTarget] ?? command.renderHints,
        stream: descriptor,
        issuedAt: Date.now()
      });
    }

    dispatchPhoneCommandToTargets(command);
    publishPhonePoolState(deps.phoneAudioPool.snapshot());
    broadcastToHarness({
      kind: "telemetry",
      data: {
        kind: "phone_audio_failover",
        reason,
        originalCommandId: pending.command.commandId,
        failoverCommandId: command.commandId,
        failedTarget: pending.targetHashedId,
        nextTarget: targetHashedIds[0]
      },
      sentAt: Date.now()
    } satisfies WireEnvelope);
  }

  function clearVoiceStreamsForDevice(hashedId: string): void {
    const commandId = `disconnect-${Date.now()}`;
    for (const [note, noteStreamMap] of activeVoiceStreamsByNote.entries()) {
      const descriptor = noteStreamMap.get(hashedId);
      if (!descriptor) {
        continue;
      }
      noteStreamMap.delete(hashedId);
      dispatchVoiceStreamStop({
        commandId,
        hashedId,
        note,
        voiceId: descriptor.voiceId,
        trackId: descriptor.trackId,
        reason: "expired",
        issuedAt: Date.now()
      });
      if (noteStreamMap.size === 0) {
        activeVoiceStreamsByNote.delete(note);
      }
    }

    const group = activeGroupStemByTarget.get(hashedId);
    if (group) {
      activeGroupStemByTarget.delete(hashedId);
      dispatchGroupStemStop({
        commandId,
        hashedIds: [hashedId],
        groupId: group.groupId,
        reason: "manual",
        issuedAt: Date.now()
      });
    }

    for (const [pendingCommandId, pending] of pendingVoiceAcks.entries()) {
      if (pending.targetHashedId !== hashedId) {
        continue;
      }
      clearTimeout(pending.timeout);
      pendingVoiceAcks.delete(pendingCommandId);
    }
  }

  function clearPendingPushEventsForDevice(hashedId: string): void {
    const prefix = `${hashedId}:`;
    for (const [key, pending] of pushPendingContinuousEvents.entries()) {
      if (!key.startsWith(prefix)) {
        continue;
      }
      clearTimeout(pending.timeout);
      pushPendingContinuousEvents.delete(key);
    }
    for (const key of pushLastForwardAt.keys()) {
      if (key.startsWith(prefix)) {
        pushLastForwardAt.delete(key);
      }
    }
  }

  function forwardPushDeckEvent(payload: PushDeckEventPayload): void {
    const harnessPayload =
      payload.controlKind === "ml_param" &&
      payload.mlParam &&
      payload.mlParam.key !== "phone_pad_echo_probability"
        ? {
            ...payload,
            mlParam: {
              key: "phone_pad_echo_probability" as const,
              value: Math.max(0, Math.min(0.2, globalEchoProbability * 0.2))
            }
          }
        : payload;
    broadcastToHarness({
      kind: "push_deck_event",
      data: harnessPayload,
      sentAt: Date.now()
    } satisfies WireEnvelope<PushDeckEventPayload>);
  }

  function forwardPushDeckEventWithCoalescing(payload: PushDeckEventPayload): void {
    let key: string;
    if (payload.controlKind === "macro") {
      key = `${payload.sourceId}:macro:${payload.macro?.lane ?? 0}`;
    } else if (payload.controlKind === "long_strip") {
      key = `${payload.sourceId}:long_strip`;
    } else {
      key = `${payload.sourceId}:ml:${payload.mlParam?.key ?? "unknown"}`;
    }
    const now = Date.now();
    const last = pushLastForwardAt.get(key) ?? 0;
    const elapsed = now - last;

    if (elapsed >= pushContinuousThrottleMs) {
      pushLastForwardAt.set(key, now);
      forwardPushDeckEvent(payload);
      return;
    }

    const existing = pushPendingContinuousEvents.get(key);
    if (existing) {
      existing.payload = payload;
      pushPendingContinuousEvents.set(key, existing);
      return;
    }

    const timeout = setTimeout(() => {
      const pending = pushPendingContinuousEvents.get(key);
      if (!pending) {
        return;
      }
      pushPendingContinuousEvents.delete(key);
      pushLastForwardAt.set(key, Date.now());
      forwardPushDeckEvent(pending.payload);
    }, Math.max(1, pushContinuousThrottleMs - elapsed));
    timeout.unref();

    pushPendingContinuousEvents.set(key, {
      payload,
      timeout
    });
  }

  function broadcastCue(cue: CueCommand): CueCommand {
    const enriched = enrichCuePayload(cue);
    latestCue = enriched;
    syncCueMediaState(enriched);
    updateMediaSchedulersAfterCue(enriched);
    const envelope = {
      kind: "cue",
      data: enriched,
      sentAt: Date.now()
    } satisfies WireEnvelope<CueCommand>;

    broadcastToDevices(envelope);
    broadcastToHarness(envelope);
    return enriched;
  }

  function broadcastShowSnapshot(): void {
    const envelope = {
      kind: "show_snapshot",
      data: buildShowSnapshotPayload(),
      sentAt: Date.now()
    } satisfies WireEnvelope<ShowSnapshotPayload>;
    broadcastToDevices(envelope);
    broadcastToHarness(envelope);
  }

  function broadcastAudienceVector(vector: AudienceVectorPayload): void {
    const envelope = {
      kind: "audience_vector",
      data: vector,
      sentAt: Date.now()
    } satisfies WireEnvelope<AudienceVectorPayload>;

    broadcastToDevices(envelope);
  }

  function broadcastLightingState(state: LightingStatePayload): void {
    const envelope = {
      kind: "lighting_state",
      data: state,
      sentAt: Date.now()
    } satisfies WireEnvelope<LightingStatePayload>;

    broadcastToDevices(envelope);
  }

  function broadcastAudioFeatures(features: AudioFeaturePayload): void {
    const envelope = {
      kind: "audio_features",
      data: features,
      sentAt: Date.now()
    } satisfies WireEnvelope<AudioFeaturePayload>;
    broadcastToDevices(envelope);
  }

  function broadcastTextScene(scene: TextScenePayload): void {
    const envelope = {
      kind: "text_scene",
      data: scene,
      sentAt: Date.now()
    } satisfies WireEnvelope<TextScenePayload>;
    broadcastToDevices(envelope);
  }

  function broadcastProceduralState(state: ProgramProceduralState): void {
    const envelope = {
      kind: "procedural_state",
      data: state,
      sentAt: Date.now()
    } satisfies WireEnvelope<ProgramProceduralState>;
    broadcastToDevices(envelope);
    broadcastToHarness(envelope);
  }

  function broadcastPhoneAudioPoolState(pool: PhoneAudioPoolStatePayload): void {
    const envelope = {
      kind: "phone_audio_pool_state",
      data: pool,
      sentAt: Date.now()
    } satisfies WireEnvelope<PhoneAudioPoolStatePayload>;
    broadcastToDevices(envelope);
    broadcastToHarness(envelope);
  }

  function broadcastToHarness(envelope: WireEnvelope): void {
    for (const harnessSocket of harnessSockets) {
      if (harnessSocket.readyState !== 1) {
        continue;
      }
      send(harnessSocket, envelope);
    }
  }

  function broadcastToDevices(envelope: WireEnvelope): void {
    for (const [id, socket] of deviceSockets.entries()) {
      if (socket.readyState !== 1) {
        logger.warn("Skipping closed device socket", { id });
        continue;
      }
      send(socket, envelope);
    }
  }

  function broadcastToSpecificDevices(targetIds: string[], envelope: WireEnvelope): void {
    for (const targetId of targetIds) {
      const socket = deviceSockets.get(targetId);
      if (!socket || socket.readyState !== 1) {
        continue;
      }
      send(socket, envelope);
    }
  }
};

const decodeCloseReason = (reason: Buffer): string => {
  if (!reason || reason.length === 0) {
    return "";
  }
  return reason.toString("utf8");
};

const parseRuntimeScriptCandidates = (
  value: unknown
): Array<{ id?: string; text: string; weight?: number }> | null => {
  if (!Array.isArray(value)) {
    return null;
  }
  const parsed: Array<{ id?: string; text: string; weight?: number }> = [];
  for (const entry of value) {
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      continue;
    }
    const record = entry as Record<string, unknown>;
    const text = typeof record.text === "string" ? record.text : null;
    if (!text || text.trim().length === 0) {
      continue;
    }
    const id = typeof record.id === "string" && record.id.trim().length > 0 ? record.id.trim() : undefined;
    const weight =
      typeof record.weight === "number" && Number.isFinite(record.weight)
        ? record.weight
        : typeof record.weight === "string" && Number.isFinite(Number(record.weight))
          ? Number(record.weight)
          : undefined;
    parsed.push({
      id,
      text,
      weight
    });
  }
  return parsed;
};

const toCompositorMode = (value: unknown): CompositorMode => {
  if (value === "html-in-canvas" || value === "fallback" || value === "unsupported") {
    return value;
  }
  return "unsupported";
};

const clamp01Number = (value: unknown): number => {
  if (typeof value !== "number" || Number.isNaN(value)) {
    return 0;
  }
  return Math.min(1, Math.max(0, value));
};

const booleanOrUndefined = (value: unknown): boolean | undefined =>
  typeof value === "boolean" ? value : undefined;

const normalizeColorIntent = (value: unknown): ColorIntentPayload => {
  const payload = (value && typeof value === "object" ? value : {}) as Partial<ColorIntentPayload>;
  const hueX = clampSigned(payload.hueX ?? 1);
  const hueY = clampSigned(payload.hueY ?? 0);
  const norm = Math.hypot(hueX, hueY);
  const normalizedX = norm < 0.001 ? 1 : hueX / norm;
  const normalizedY = norm < 0.001 ? 0 : hueY / norm;

  return {
    hueX: normalizedX,
    hueY: normalizedY,
    chroma: clamp01Number(typeof payload.chroma === "number" ? payload.chroma : 0.12),
    luminance: clamp01Number(typeof payload.luminance === "number" ? payload.luminance : 0.56),
    energy: clamp01Number(typeof payload.energy === "number" ? payload.energy : 0.42),
    updatedAt:
      typeof payload.updatedAt === "number" && Number.isFinite(payload.updatedAt)
        ? payload.updatedAt
        : Date.now()
  };
};

const normalizeAudioFeatures = (value: Partial<AudioFeaturePayload>): AudioFeaturePayload => ({
  rms: clamp01(value.rms ?? 0),
  spectralCentroid: clamp01(value.spectralCentroid ?? 0.5),
  flux: clamp01(value.flux ?? 0.5),
  transientDensity: clamp01(value.transientDensity ?? 0),
  updatedAt: typeof value.updatedAt === "number" ? value.updatedAt : Date.now()
});

const normalizeVoiceStreamCodec = (value: unknown): VoiceStreamDescriptor["codec"] => {
  if (value === "aac" || value === "pcm" || value === "opus") {
    return value;
  }
  return "opus";
};

const normalizeVoiceStreamDescriptor = (value: unknown): VoiceStreamDescriptor | undefined => {
  if (!value || typeof value !== "object") {
    return undefined;
  }
  const payload = value as Record<string, unknown>;
  const voiceId = typeof payload.voiceId === "string" && payload.voiceId.length > 0 ? payload.voiceId : "";
  const trackId = typeof payload.trackId === "string" && payload.trackId.length > 0 ? payload.trackId : "";
  const sessionId = typeof payload.sessionId === "string" && payload.sessionId.length > 0 ? payload.sessionId : "";
  if (!voiceId || !trackId || !sessionId) {
    return undefined;
  }
  return {
    voiceId,
    trackId,
    sessionId,
    token: typeof payload.token === "string" ? payload.token : "",
    codec: normalizeVoiceStreamCodec(payload.codec),
    expiresAt: typeof payload.expiresAt === "number" ? payload.expiresAt : Date.now() + 30_000,
    streamUrl: typeof payload.streamUrl === "string" ? payload.streamUrl : undefined,
    fallbackGroup: typeof payload.fallbackGroup === "string" ? payload.fallbackGroup : undefined
  };
};

const normalizeGroupStemDescriptor = (value: unknown): GroupStemDescriptor | undefined => {
  if (!value || typeof value !== "object") {
    return undefined;
  }
  const payload = value as Record<string, unknown>;
  const groupId = typeof payload.groupId === "string" && payload.groupId.length > 0 ? payload.groupId : "";
  const sessionId = typeof payload.sessionId === "string" && payload.sessionId.length > 0 ? payload.sessionId : "";
  if (!groupId || !sessionId) {
    return undefined;
  }
  return {
    groupId,
    sessionId,
    token: typeof payload.token === "string" ? payload.token : "",
    codec: normalizeVoiceStreamCodec(payload.codec),
    expiresAt: typeof payload.expiresAt === "number" ? payload.expiresAt : Date.now() + 30_000,
    streamUrl: typeof payload.streamUrl === "string" ? payload.streamUrl : undefined
  };
};

const normalizeVoiceStreamByTarget = (value: unknown): Record<string, VoiceStreamDescriptor> | undefined => {
  if (!value || typeof value !== "object") {
    return undefined;
  }
  const normalized = Object.entries(value as Record<string, unknown>).reduce<Record<string, VoiceStreamDescriptor>>(
    (acc, [hashedId, descriptor]) => {
      const parsed = normalizeVoiceStreamDescriptor(descriptor);
      if (parsed) {
        acc[hashedId] = parsed;
      }
      return acc;
    },
    {}
  );
  return Object.keys(normalized).length > 0 ? normalized : undefined;
};

const normalizePhoneAudioCommand = (value: Partial<PhoneAudioCommandPayload>): PhoneAudioCommandPayload => {
  const kind = toPhoneAudioCommandKind(value.kind);
  const hints = normalizeRenderHints(value.renderHints);
  const hintsByTarget = normalizeRenderHintsByTarget(value.renderHintsByTarget);
  return {
    commandId: typeof value.commandId === "string" && value.commandId.length > 0
      ? value.commandId
      : `cmd-${Date.now()}`,
    kind,
    targetHashedIds: Array.isArray(value.targetHashedIds)
      ? value.targetHashedIds.filter((id): id is string => typeof id === "string")
      : [],
    note: typeof value.note === "number" ? value.note : undefined,
    velocity: typeof value.velocity === "number" ? value.velocity : undefined,
    sampleId: typeof value.sampleId === "string" ? value.sampleId : undefined,
    gain: typeof value.gain === "number" ? value.gain : undefined,
    seed: typeof value.seed === "number" ? value.seed : undefined,
    stream: normalizeVoiceStreamDescriptor(value.stream),
    streamByTarget: normalizeVoiceStreamByTarget(value.streamByTarget),
    fallbackGroup: normalizeGroupStemDescriptor(value.fallbackGroup),
    renderHints: hints,
    renderHintsByTarget: hintsByTarget,
    issuedAt: typeof value.issuedAt === "number" ? value.issuedAt : Date.now()
  };
};

const normalizePushDeckEvent = (
  value: Partial<PushDeckEventPayload>,
  sourceId: string
): PushDeckEventPayload | null => {
  const controlKind = toPushDeckControlKind(value.controlKind);
  const modeContext = toPushDeckModeContext(value.modeContext);
  const timingMode = toPushDeckTimingMode(value.timingMode);
  const quantIntervalMs =
    typeof value.quantIntervalMs === "number" && Number.isFinite(value.quantIntervalMs)
      ? Math.max(20, Math.min(500, Math.round(value.quantIntervalMs)))
      : undefined;
  const pad = normalizePushDeckPadControl(value.pad);
  const macro = normalizePushDeckMacroControl(value.macro);
  const longStrip = normalizePushDeckLongStripControl(value.longStrip);
  const bank = normalizePushDeckBankControl(value.bank);
  const mlParam = normalizePushDeckMLParamControl(value.mlParam);

  if ((controlKind === "pad_down" || controlKind === "pad_up") && !pad) {
    return null;
  }
  if (controlKind === "macro" && !macro) {
    return null;
  }
  if (controlKind === "long_strip" && !longStrip) {
    return null;
  }
  if (controlKind === "bank_select" && !bank) {
    return null;
  }
  if (controlKind === "ml_param" && !mlParam) {
    return null;
  }

  return {
    eventId:
      typeof value.eventId === "string" && value.eventId.length > 0
        ? value.eventId
        : `push-${Date.now()}-${Math.floor(Math.random() * 1_000_000)}`,
    sourceId,
    controlKind,
    modeContext,
    timingMode,
    quantIntervalMs,
    pad,
    macro,
    longStrip,
    bank,
    mlParam,
    issuedAt: typeof value.issuedAt === "number" ? value.issuedAt : Date.now()
  };
};

const normalizePushDeckPadControl = (value: unknown): PushDeckEventPayload["pad"] => {
  if (!value || typeof value !== "object") {
    return undefined;
  }
  const payload = value as Record<string, unknown>;
  const row = typeof payload.row === "number" ? Math.max(0, Math.min(7, Math.round(payload.row))) : 0;
  const column = typeof payload.column === "number" ? Math.max(0, Math.min(7, Math.round(payload.column))) : 0;
  const slot = typeof payload.slot === "number" ? Math.max(0, Math.min(63, Math.round(payload.slot))) : row * 8 + column;
  const pressure = typeof payload.pressure === "number" ? clamp01(payload.pressure) : 0;
  const velocity = typeof payload.velocity === "number" ? clamp01(payload.velocity) : pressure;
  return {
    row,
    column,
    slot,
    pressure,
    velocity
  };
};

const normalizePushDeckMacroControl = (value: unknown): PushDeckEventPayload["macro"] => {
  if (!value || typeof value !== "object") {
    return undefined;
  }
  const payload = value as Record<string, unknown>;
  if (typeof payload.lane !== "number") {
    return undefined;
  }
  return {
    lane: Math.max(1, Math.min(8, Math.round(payload.lane))),
    value: typeof payload.value === "number" ? clamp01(payload.value) : 0
  };
};

const normalizePushDeckLongStripControl = (value: unknown): PushDeckEventPayload["longStrip"] => {
  if (!value || typeof value !== "object") {
    return undefined;
  }
  const payload = value as Record<string, unknown>;
  const raw = typeof payload.value === "number" ? payload.value : undefined;
  if (raw === undefined || Number.isNaN(raw)) {
    return undefined;
  }
  return {
    value: clamp01(raw)
  };
};

const normalizePushDeckBankControl = (value: unknown): PushDeckEventPayload["bank"] => {
  if (!value || typeof value !== "object") {
    return undefined;
  }
  const payload = value as Record<string, unknown>;
  const domain = toPushDeckBankDomain(payload.domain);
  if (!domain || typeof payload.bank !== "number") {
    return undefined;
  }
  return {
    domain,
    bank: Math.max(1, Math.min(3, Math.round(payload.bank)))
  };
};

const normalizePushDeckMLParamControl = (value: unknown): PushDeckEventPayload["mlParam"] => {
  if (!value || typeof value !== "object") {
    return undefined;
  }
  const payload = value as Record<string, unknown>;
  const key = toPushDeckMLParamKey(payload.key);
  if (!key) {
    return undefined;
  }
  const raw = typeof payload.value === "number" && Number.isFinite(payload.value) ? payload.value : 0;
  const max = key === "phone_pad_echo_probability" ? 0.2 : 1;
  return {
    key,
    value: Math.max(0, Math.min(max, raw))
  };
};

const normalizePushPadLabelsPayload = (value: unknown): PushPadLabelsPayload | null => {
  if (!value || typeof value !== "object") {
    return null;
  }
  const payload = value as Record<string, unknown>;
  const labelsRaw = Array.isArray(payload.padLabels)
    ? payload.padLabels
    : Array.isArray(payload.pad_labels)
      ? payload.pad_labels
      : null;
  if (!labelsRaw) {
    return null;
  }
  const labels = labelsRaw
    .map((item) => (typeof item === "string" ? item.trim() : ""))
    .slice(0, 64);
  if (labels.length === 0) {
    return null;
  }
  while (labels.length < 64) {
    labels.push("");
  }
  const bank =
    typeof payload.bank === "number" && Number.isFinite(payload.bank)
      ? Math.max(1, Math.min(3, Math.round(payload.bank)))
      : undefined;
  const updatedAt =
    typeof payload.updatedAt === "number" && Number.isFinite(payload.updatedAt)
      ? payload.updatedAt
      : Date.now();
  return {
    padLabels: labels,
    bank,
    updatedAt
  };
};

const toPushDeckControlKind = (value: unknown): PushDeckEventPayload["controlKind"] => {
  if (
    value === "pad_down" ||
    value === "pad_up" ||
    value === "macro" ||
    value === "long_strip" ||
    value === "bank_select" ||
    value === "ml_param"
  ) {
    return value;
  }
  return "pad_down";
};

const toPushDeckModeContext = (value: unknown): PushDeckEventPayload["modeContext"] => {
  if (value === "auto" || value === "dynamic" || value === "static" || value === "choir") {
    return value;
  }
  return "auto";
};

const toPushDeckTimingMode = (value: unknown): PushDeckEventPayload["timingMode"] => {
  if (value === "immediate" || value === "quantized") {
    return value;
  }
  return "immediate";
};

const toPushDeckBankDomain = (value: unknown): PushDeckBankDomain | null => {
  if (value === "main" || value === "choir") {
    return value;
  }
  return null;
};

const toPushDeckMLParamKey = (value: unknown): PushDeckMLParamKey | null => {
  if (
    value === "phone_pad_echo_probability" ||
    value === "pads_echo_probability" ||
    value === "global_echo_probability" ||
    value === "hotas_echo_probability" ||
    value === "choir_echo_probability" ||
    value === "fx_echo_probability"
  ) {
    return value;
  }
  return null;
};

const toPhoneAudioCommandKind = (value: unknown): PhoneAudioCommandPayload["kind"] => {
  if (
    value === "note_on" ||
    value === "note_off" ||
    value === "sample_trigger" ||
    value === "ambient_noise" ||
    value === "stop_all"
  ) {
    return value;
  }
  return "sample_trigger";
};

const toStreamLifecycleStatus = (value: unknown): PhoneAudioAckPayload["streamStatus"] => {
  if (
    value === "subscribed" ||
    value === "underrun" ||
    value === "track_lost" ||
    value === "fallback_group"
  ) {
    return value;
  }
  return undefined;
};

const normalizeRenderHints = (value: unknown): PhoneAudioCommandPayload["renderHints"] => {
  if (!value || typeof value !== "object") {
    return undefined;
  }
  const payload = value as Record<string, unknown>;
  const priority =
    payload.priority === "high" || payload.priority === "medium" || payload.priority === "low"
      ? payload.priority
      : undefined;
  return {
    zoneId: typeof payload.zoneId === "string" ? payload.zoneId : undefined,
    pan: typeof payload.pan === "number" ? Math.max(-1, Math.min(1, payload.pan)) : undefined,
    detuneCents:
      typeof payload.detuneCents === "number"
        ? Math.max(-1200, Math.min(1200, payload.detuneCents))
        : undefined,
    grainMix: typeof payload.grainMix === "number" ? clamp01(payload.grainMix) : undefined,
    motionEnergy: typeof payload.motionEnergy === "number" ? clamp01(payload.motionEnergy) : undefined,
    priority
  };
};

const normalizeRenderHintsByTarget = (
  value: unknown
): PhoneAudioCommandPayload["renderHintsByTarget"] => {
  if (!value || typeof value !== "object") {
    return undefined;
  }
  const entries = Object.entries(value as Record<string, unknown>)
    .map(([hashedId, hints]) => [hashedId, normalizeRenderHints(hints)] as const)
    .filter(([, hints]) => hints !== undefined);
  if (entries.length === 0) {
    return undefined;
  }
  return entries.reduce<NonNullable<PhoneAudioCommandPayload["renderHintsByTarget"]>>((acc, [hashedId, hints]) => {
    if (hints) {
      acc[hashedId] = hints;
    }
    return acc;
  }, {});
};

const toPromptResponseType = (value: unknown): PromptResponsePayload["responseType"] => {
  if (value === "tap" || value === "drag" || value === "hold" || value === "skip") {
    return value;
  }
  return "tap";
};

const normalizePromptResponse = (value: Partial<PromptResponsePayload>): PromptResponsePayload => {
  const drag = value.dragVector;
  const hasDrag = Boolean(
    drag &&
      typeof drag === "object" &&
      typeof drag.x === "number" &&
      typeof drag.y === "number"
  );
  const slotPick = value.slotPick;
  const hasSlotPick = Boolean(
    slotPick &&
      typeof slotPick === "object" &&
      typeof slotPick.slotId === "string" &&
      slotPick.slotId.length > 0
  );
  return {
    promptId: typeof value.promptId === "string" ? value.promptId : "",
    cueVersion: typeof value.cueVersion === "number" ? Math.max(0, Math.round(value.cueVersion)) : 0,
    responseType: toPromptResponseType(value.responseType),
    tapChoice: typeof value.tapChoice === "string" ? value.tapChoice : undefined,
    dragVector: hasDrag
      ? {
          x: Math.max(-1, Math.min(1, drag!.x)),
          y: Math.max(-1, Math.min(1, drag!.y))
        }
      : undefined,
    holdMs: typeof value.holdMs === "number" && Number.isFinite(value.holdMs)
      ? Math.max(0, Math.round(value.holdMs))
      : undefined,
    latencyMs: typeof value.latencyMs === "number" && Number.isFinite(value.latencyMs)
      ? Math.max(0, Math.round(value.latencyMs))
      : 0,
    slotPick: hasSlotPick
      ? {
          slotId: slotPick!.slotId,
          takeId: typeof slotPick!.takeId === "string" ? slotPick!.takeId : undefined
        }
      : undefined,
    respondedAt: typeof value.respondedAt === "number" && Number.isFinite(value.respondedAt)
      ? value.respondedAt
      : Date.now()
  };
};

const normalizePromptChoiceToken = (value: string): string =>
  value
    .trim()
    .toLowerCase()
    .replace(/\s+/g, "-")
    .replace(/_/g, "-");

const resolvePromptChoiceToken = (response: PromptResponsePayload): string => {
  const candidate =
    response.slotPick?.takeId ??
    response.slotPick?.slotId ??
    response.tapChoice ??
    "";
  return normalizePromptChoiceToken(candidate);
};

const toPromptBlendPreset = (choice: string, splitLayout: SplitLayout): CompositorPreset | null => {
  if (choice === "normal" || choice === "blend") {
    return "blend";
  }
  if (choice === "add" || choice === "lighter") {
    return splitLayout === "pip" ? "blend" : "add";
  }
  if (choice === "exclusion") {
    return "exclusion";
  }
  if (choice === "screen") {
    return "screen";
  }
  return null;
};

const toPromptPipPosition = (choice: string): ProgramProceduralState["pipPosition"] | null => {
  if (choice === "top-left" || choice === "top-right" || choice === "bottom-left" || choice === "bottom-right") {
    return choice;
  }
  return null;
};

const toPromptSplitLayout = (choice: string): SplitLayout | null => {
  if (choice === "split-2" || choice === "split2" || choice === "2-up") {
    return "split-2";
  }
  if (choice === "split-3" || choice === "split3" || choice === "3-up") {
    return "split-3";
  }
  if (choice === "split-4" || choice === "split4" || choice === "4-up" || choice === "grid") {
    return "split-4";
  }
  return null;
};

const normalizeKeyboardHostLink = (value: unknown): KeyboardStatePayload["hostLink"] => {
  if (value === "online" || value === "connecting" || value === "degraded" || value === "offline") {
    return value;
  }
  return "degraded";
};

const normalizeKeyboardPatchSnapshot = (
  value: unknown,
  fallback?: KeyboardStatePayload | null
): KeyboardStatePayload["patch"] => {
  const payload = (value && typeof value === "object" ? value : {}) as Record<string, unknown>;
  const patchId =
    typeof payload.patchId === "string" && payload.patchId.length > 0
      ? payload.patchId
      : fallback?.patch.patchId ?? "default";
  const patchName =
    typeof payload.patchName === "string" && payload.patchName.length > 0
      ? payload.patchName
      : fallback?.patch.patchName;
  const bankRaw = typeof payload.bank === "number" ? payload.bank : fallback?.patch.bank ?? 0;
  const programRaw = typeof payload.program === "number" ? payload.program : fallback?.patch.program ?? 0;
  const returnBusStrategy =
    typeof payload.returnBusStrategy === "string" && payload.returnBusStrategy.trim().length > 0
      ? payload.returnBusStrategy.trim()
      : fallback?.patch.returnBusStrategy;
  const updatedAtRaw = typeof payload.updatedAt === "number" ? payload.updatedAt : Date.now();

  return {
    patchId,
    patchName,
    bank: Math.max(0, Math.min(127, Math.round(bankRaw))),
    program: Math.max(0, Math.min(127, Math.round(programRaw))),
    returnBusStrategy,
    updatedAt: updatedAtRaw
  };
};

const normalizeKeyboardStatePayload = (
  value: Partial<KeyboardStatePayload>,
  fallback: KeyboardStatePayload | null
): KeyboardStatePayload => {
  const activeScene: KeyboardStatePayload["activeScene"] =
    value.activeScene === "interstitial" ||
    value.activeScene === "preshow" ||
    value.activeScene === "introduction" ||
    value.activeScene === "mainStatic" ||
    value.activeScene === "mainDynamic" ||
    value.activeScene === "ending"
      ? value.activeScene
      : undefined;
  return {
    profileId:
      typeof value.profileId === "string" && value.profileId.length > 0
        ? value.profileId
        : fallback?.profileId ?? "minilab3",
    profileName:
      typeof value.profileName === "string" && value.profileName.length > 0
        ? value.profileName
        : fallback?.profileName ?? "MiniLab 3",
    page:
      typeof value.page === "number" && Number.isFinite(value.page)
        ? Math.max(0, Math.round(value.page))
        : fallback?.page ?? 0,
    pageName:
      typeof value.pageName === "string" && value.pageName.length > 0
        ? value.pageName
        : fallback?.pageName ?? "A",
    hostLink:
      typeof value.hostLink === "string"
        ? normalizeKeyboardHostLink(value.hostLink)
        : fallback?.hostLink ?? "degraded",
    clockMaster: typeof value.clockMaster === "boolean" ? value.clockMaster : fallback?.clockMaster ?? true,
    clockBpm:
      typeof value.clockBpm === "number" && Number.isFinite(value.clockBpm)
        ? Math.max(20, Math.min(320, value.clockBpm))
        : fallback?.clockBpm ?? 120,
    transportRunning:
      typeof value.transportRunning === "boolean" ? value.transportRunning : fallback?.transportRunning ?? false,
    patch: normalizeKeyboardPatchSnapshot(value.patch, fallback),
    cueVersion:
      typeof value.cueVersion === "number" && Number.isFinite(value.cueVersion)
        ? Math.max(0, Math.round(value.cueVersion))
        : fallback?.cueVersion,
    activeScene: activeScene ?? fallback?.activeScene,
    updatedAt:
      typeof value.updatedAt === "number" && Number.isFinite(value.updatedAt)
        ? value.updatedAt
        : Date.now()
  };
};

const normalizeKeyboardPatchChangePayload = (
  value: Partial<KeyboardPatchChangePayload>,
  fallback: KeyboardStatePayload | null
): KeyboardPatchChangePayload => {
  const patch = normalizeKeyboardPatchSnapshot(
    {
      patchId: value.patchId,
      patchName: value.patchName,
      bank: value.bank,
      program: value.program,
      updatedAt: value.updatedAt
    },
    fallback
  );
  return {
    patchId: patch.patchId,
    patchName: patch.patchName,
    bank: patch.bank,
    program: patch.program,
    source: "operator",
    updatedAt: patch.updatedAt
  };
};

const applyEchoMLParam = (
  key: PushDeckMLParamKey,
  value: number,
  capsByStem: EchoCapsByStem,
  current: Record<EchoStem, number>
): { global: number; pads: number; hotas: number; choir: number; fx: number } => {
  const normalizeLegacy = key === "phone_pad_echo_probability" ? clamp01(value / 0.2) : clamp01(value);
  let next: Record<EchoStem, number> = {
    pads: current.pads,
    hotas: current.hotas,
    choir: current.choir,
    fx: current.fx
  };

  if (key === "global_echo_probability") {
    next = {
      pads: normalizeLegacy,
      hotas: normalizeLegacy,
      choir: normalizeLegacy,
      fx: normalizeLegacy
    };
  } else if (key === "hotas_echo_probability") {
    next.hotas = normalizeLegacy;
  } else if (key === "choir_echo_probability") {
    next.choir = normalizeLegacy;
  } else if (key === "fx_echo_probability") {
    next.fx = normalizeLegacy;
  } else if (key === "pads_echo_probability" || key === "phone_pad_echo_probability") {
    next.pads = normalizeLegacy;
  }

  for (const stem of Object.keys(next) as EchoStem[]) {
    const caps = capsByStem[stem];
    next[stem] = Math.max(caps.floor, Math.min(caps.cap, next[stem]));
  }

  return {
    global: clamp01((next.pads + next.hotas + next.choir + next.fx) / 4),
    pads: next.pads,
    hotas: next.hotas,
    choir: next.choir,
    fx: next.fx
  };
};

const clampSigned = (value: number): number => Math.min(1, Math.max(-1, value));

const createDefaultProceduralState = (performerVector: ParamVector): ProgramProceduralState => ({
  epoch: 0,
  seed: stableHashToSeed(`procedural:${Date.now()}`),
  updatedAt: Date.now(),
  dynamicBinSelection: 0.5,
  dynamicBinIndex: 0,
  dynamicBinClipId: null,
  dynamicBinManifest: [],
  cutCadence: 0.5,
  transitionMode: "cut",
  compositorPreset: "blend",
  splitLayout: "none",
  splitAmount: 0.5,
  pipPosition: "top-right",
  fade: 0,
  textProbability: 0.5,
  strictLooseBlend: 0.5,
  visualVariance: 0.5,
  crowdSteeringLevel: 0,
  promptInfluence: 0,
  directPickInfluence: 0,
  echoProbabilityGlobal: 0,
  echoProbabilityByStem: {
    pads: 0,
    hotas: 0,
    choir: 0,
    fx: 0
  },
  performerVector: normalizeVector(performerVector),
  audienceVector: normalizeVector({}),
  textBlend: {
    mode: "always-mixed",
    probability: 0.5,
    strictRatio: 0.5,
    looseRatio: 0.5
  }
});

const normalizeProceduralState = (
  input: Partial<ProgramProceduralState>,
  current: ProgramProceduralState
): ProgramProceduralState => {
  const nextManifest = Array.isArray(input.dynamicBinManifest)
    ? input.dynamicBinManifest
        .filter((candidate): candidate is ProgramProceduralState["dynamicBinManifest"][number] =>
          Boolean(candidate && typeof candidate.id === "string" && typeof candidate.mediaRef === "string")
        )
        .map((candidate) => ({
          id: candidate.id,
          mediaRef: candidate.mediaRef,
          tags: Array.isArray(candidate.tags) ? candidate.tags.filter((tag): tag is string => typeof tag === "string") : [],
          weight: typeof candidate.weight === "number" ? Math.max(0, candidate.weight) : 1,
          scopes: Array.isArray(candidate.scopes) ? candidate.scopes.filter((scope): scope is string => typeof scope === "string") : []
        }))
    : current.dynamicBinManifest;

  const dynamicBinSelection = clamp01Number(
    typeof input.dynamicBinSelection === "number" ? input.dynamicBinSelection : current.dynamicBinSelection
  );
  const maxIndex = Math.max(0, nextManifest.length - 1);
  const dynamicBinIndexCandidate = typeof input.dynamicBinIndex === "number" ? Math.round(input.dynamicBinIndex) : null;
  const dynamicBinIndex =
    dynamicBinIndexCandidate !== null
      ? Math.min(maxIndex, Math.max(0, dynamicBinIndexCandidate))
      : Math.min(maxIndex, Math.max(0, Math.round(dynamicBinSelection * maxIndex)));
  const dynamicBinClipId = nextManifest[dynamicBinIndex]?.id ?? null;

  const strictLooseBlend = clamp01Number(
    typeof input.strictLooseBlend === "number" ? input.strictLooseBlend : current.strictLooseBlend
  );
  const textProbability = clamp01Number(
    typeof input.textProbability === "number" ? input.textProbability : current.textProbability
  );
  const textBlend: TextBlendState = {
    mode: "always-mixed",
    probability: textProbability,
    strictRatio: strictLooseBlend,
    looseRatio: clamp01(1 - strictLooseBlend)
  };

  return {
    epoch: typeof input.epoch === "number" ? Math.max(0, Math.round(input.epoch)) : current.epoch,
    seed: typeof input.seed === "number" ? Math.round(input.seed) : current.seed,
    updatedAt: typeof input.updatedAt === "number" ? input.updatedAt : Date.now(),
    dynamicBinSelection,
    dynamicBinIndex,
    dynamicBinClipId: typeof input.dynamicBinClipId === "string" || input.dynamicBinClipId === null
      ? input.dynamicBinClipId
      : dynamicBinClipId,
    dynamicBinManifest: nextManifest,
    cutCadence: clamp01Number(typeof input.cutCadence === "number" ? input.cutCadence : current.cutCadence),
    transitionMode: toTransitionMode(input.transitionMode ?? current.transitionMode),
    compositorPreset: toCompositorPreset(input.compositorPreset ?? current.compositorPreset),
    splitLayout: toSplitLayout(input.splitLayout ?? current.splitLayout),
    splitAmount: clamp01Number(typeof input.splitAmount === "number" ? input.splitAmount : current.splitAmount ?? 0.5),
    pipPosition: toPipPosition(input.pipPosition ?? current.pipPosition),
    fade: clamp01Number(typeof input.fade === "number" ? input.fade : current.fade),
    textProbability,
    strictLooseBlend,
    visualVariance: clamp01Number(typeof input.visualVariance === "number" ? input.visualVariance : current.visualVariance),
    crowdSteeringLevel: clamp01Number(
      typeof input.crowdSteeringLevel === "number" ? input.crowdSteeringLevel : current.crowdSteeringLevel
    ),
    promptInfluence: clamp01Number(
      typeof input.promptInfluence === "number" ? input.promptInfluence : current.promptInfluence ?? 0
    ),
    directPickInfluence: clamp01Number(
      typeof input.directPickInfluence === "number"
        ? input.directPickInfluence
        : current.directPickInfluence ?? 0
    ),
    echoProbabilityGlobal: clamp01Number(
      typeof input.echoProbabilityGlobal === "number"
        ? input.echoProbabilityGlobal
        : current.echoProbabilityGlobal ?? 0
    ),
    echoProbabilityByStem:
      input.echoProbabilityByStem && typeof input.echoProbabilityByStem === "object"
        ? {
            pads: clamp01Number(input.echoProbabilityByStem.pads ?? current.echoProbabilityByStem?.pads ?? 0),
            hotas: clamp01Number(input.echoProbabilityByStem.hotas ?? current.echoProbabilityByStem?.hotas ?? 0),
            choir: clamp01Number(input.echoProbabilityByStem.choir ?? current.echoProbabilityByStem?.choir ?? 0),
            fx: clamp01Number(input.echoProbabilityByStem.fx ?? current.echoProbabilityByStem?.fx ?? 0)
          }
        : current.echoProbabilityByStem,
    performerVector: normalizeVector((input.performerVector ?? current.performerVector) as Partial<ParamVector>),
    audienceVector: normalizeVector((input.audienceVector ?? current.audienceVector) as Partial<ParamVector>),
    textBlend
  };
};

const applyAudienceSteeringAndVariance = (
  base: ProgramProceduralState,
  audience: AudienceVectorPayload,
  audioFeatures: AudioFeaturePayload,
  pickResult: CrowdPickResultPayload | null,
  interaction: {
    promptInfluence: number;
    directPickInfluence: number;
    globalEchoProbability: number;
    echoByStem: Record<EchoStem, number>;
    echoCapsByStem: EchoCapsByStem;
  }
): ProgramProceduralState => {
  const crowdWeight = clamp01((audience.participantCount - 1) / 20);
  const waveIntensity = clamp01(audience.wavefront?.intensity ?? 0);
  const wavePhase = clamp01(audience.wavefront?.phase ?? 0.5);
  const promptBoost = interaction.promptInfluence * 0.32 + interaction.directPickInfluence * 0.46;
  const steeringLevel = clamp01(crowdWeight * 0.35 + promptBoost * 0.6 + waveIntensity * 0.18);
  const centered = {
    text: audience.vector.textAmount - 0.5,
    comp: audience.vector.compositeBias - 0.5,
    gain: audience.vector.audioGain - 0.5
  };

  let next = normalizeProceduralState(
    {
      ...base,
      updatedAt: Date.now(),
      crowdSteeringLevel: steeringLevel,
      audienceVector: audience.vector,
      cutCadence: clamp01(base.cutCadence + centered.gain * steeringLevel * 1.45 + (audioFeatures.transientDensity - 0.5) * 0.08),
      fade: clamp01(base.fade + centered.comp * steeringLevel * 1.2),
      textProbability: clamp01(base.textProbability + centered.text * steeringLevel * 1.4),
      strictLooseBlend: clamp01(base.strictLooseBlend + centered.comp * -steeringLevel * 0.95),
      visualVariance: clamp01(
        base.visualVariance +
          centered.comp * steeringLevel * 1.1 +
          (audioFeatures.flux - 0.5) * 0.06 +
          interaction.directPickInfluence * 0.08 +
          waveIntensity * 0.12
      ),
      promptInfluence: interaction.promptInfluence,
      directPickInfluence: interaction.directPickInfluence,
      echoProbabilityGlobal: interaction.globalEchoProbability,
      echoProbabilityByStem: interaction.echoByStem
    },
    base
  );

  const variancePressure = next.visualVariance * (0.55 + steeringLevel);
  if (variancePressure > 0.22) {
    const seed = stableHashToSeed(
      `${next.seed}:${next.epoch}:${Math.round(audioFeatures.flux * 100)}:${pickResult?.winnerOptionId ?? "none"}`
    );

    const transitions: TransitionMode[] = ["cut", "crossfade", "fade", "stutter"];
    const compositors: CompositorPreset[] = ["blend", "add", "exclusion", "screen", "multiply", "mask", "pip", "stutter"];
    const splits: SplitLayout[] = ["none", "split-2", "split-3", "split-4", "pip"];

    next = normalizeProceduralState(
      {
        ...next,
        transitionMode: transitions[seed % transitions.length],
        compositorPreset: compositors[(seed >>> 2) % compositors.length],
        splitLayout: splits[(seed + Math.round(wavePhase * 10)) % splits.length]
      },
      next
    );
  }

  return next;
};

const toTransitionMode = (value: unknown): TransitionMode => {
  if (value === "cut" || value === "crossfade" || value === "stutter" || value === "fade") {
    return value;
  }
  return "cut";
};

const toCompositorPreset = (value: unknown): CompositorPreset => {
  if (
    value === "blend" ||
    value === "add" ||
    value === "exclusion" ||
    value === "multiply" ||
    value === "screen" ||
    value === "mask" ||
    value === "pip" ||
    value === "stutter"
  ) {
    return value;
  }
  return "blend";
};

const toSplitLayout = (value: unknown): SplitLayout => {
  if (value === "none" || value === "split-2" || value === "split-3" || value === "split-4" || value === "pip") {
    return value;
  }
  return "none";
};

const toPipPosition = (value: unknown): ProgramProceduralState["pipPosition"] => {
  if (value === "top-left" || value === "top-right" || value === "bottom-left" || value === "bottom-right") {
    return value;
  }
  return "top-right";
};
