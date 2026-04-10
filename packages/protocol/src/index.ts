export const PROTOCOL_VERSION = 1 as const;

export type ShowState =
  | "idle"
  | "preshow"
  | "introduction"
  | "main"
  | "ending"
  | "hold"
  | "aborted"
  | "recovery";

export type CueAction = "start" | "hold" | "jump" | "abort" | "recover";

export type Role = "audience" | "performer" | "observer" | "muted";

export interface CueCommand {
  cueId: string;
  showState: ShowState;
  logicalTime: number;
  payload: Record<string, unknown>;
  version: number;
  action: CueAction;
}

export interface SyncPacket {
  kind: "ping" | "pong";
  serverTime: number;
  clientTime: number;
  rtt: number;
  driftEstimate: number;
}

export interface DevicePermissions {
  motion: boolean;
  geolocation: boolean;
  audio: boolean;
}

export interface DeviceZone {
  name: string;
  x: number;
  y: number;
  z?: number;
}

export interface DeviceProfile {
  hashedId: string;
  role: Role;
  permissions: DevicePermissions;
  zone?: DeviceZone;
  variantSeed: number;
}

export interface ParamVector {
  textAmount: number;
  compositeBias: number;
  audioGain: number;
  spatialX: number;
  spatialY: number;
  spatialZ: number;
}

export type CompositorMode = "html-in-canvas" | "fallback" | "unsupported";

export interface ColorIntentPayload {
  hueX: number;
  hueY: number;
  chroma: number;
  luminance: number;
  energy: number;
  updatedAt: number;
}

export interface ParticipantVectorPayload {
  vector: ParamVector;
  influence: number;
  compositorMode: CompositorMode;
  colorIntent?: ColorIntentPayload;
  updatedAt: number;
}

export interface AudienceVectorPayload {
  vector: ParamVector;
  participantCount: number;
  updatedAt: number;
  compositorModes: Record<string, number>;
}

export interface AudioFeaturePayload {
  rms: number;
  spectralCentroid: number;
  flux: number;
  transientDensity: number;
  updatedAt: number;
}

export type PhoneAudioCommandKind =
  | "note_on"
  | "note_off"
  | "sample_trigger"
  | "ambient_noise"
  | "stop_all";

export interface PhoneAudioCommandPayload {
  commandId: string;
  kind: PhoneAudioCommandKind;
  targetHashedIds: string[];
  note?: number;
  velocity?: number;
  sampleId?: string;
  gain?: number;
  seed?: number;
  issuedAt: number;
}

export interface PhoneAudioAckPayload {
  commandId: string;
  hashedId: string;
  ok: boolean;
  detail?: string;
  receivedAt: number;
}

export interface CrowdPickWindowPayload {
  id: string;
  title: string;
  options: Array<{ id: string; label: string }>;
  opensAt: number;
  closesAt: number;
  quorumTarget: number;
  active: boolean;
}

export interface CrowdPickVotePayload {
  windowId: string;
  optionId: string;
  votedAt: number;
}

export interface CrowdPickResultPayload {
  windowId: string;
  winnerOptionId: string | null;
  winnerLabel: string | null;
  totalVotes: number;
  quorumTarget: number;
  margin: number;
  applied: boolean;
  updatedAt: number;
}

export interface DeviceVarianceSpec {
  seed: number;
  sceneVersion: number;
  pickEpoch: number;
  offsetX: number;
  offsetY: number;
  alphaBias: number;
  weightBias: number;
  cadenceBiasMs: number;
  variantWordIndexes: number[];
}

export interface TextSceneLine {
  id: string;
  baseText: string;
  variants: string[];
}

export interface TextScenePayload {
  sceneVersion: number;
  pickEpoch: number;
  cueId: string;
  anchor: "center-center" | "center-left" | "center-right" | "upper-center" | "lower-center";
  lineCount: number;
  cutMode: "hold" | "stutter" | "crossfade";
  alpha: number;
  fontScale: number;
  weight: number;
  durationMs: number;
  lines: TextSceneLine[];
  guardrails: {
    maxOffsetX: number;
    maxOffsetY: number;
    minContrast: number;
    minDurationMs: number;
  };
}

export interface PhoneAudioPoolStatePayload {
  gateArmed: boolean;
  gateCommitted: boolean;
  quadRouteReady: boolean;
  availableDevices: string[];
  activeVoices: Record<string, number>;
  updatedAt: number;
}

export interface AudioOpsStatePayload {
  audioFeatures: AudioFeaturePayload;
  phoneAudioPool: PhoneAudioPoolStatePayload;
  pickWindow: CrowdPickWindowPayload | null;
  pickResult: CrowdPickResultPayload | null;
  textScene: TextScenePayload;
  updatedAt: number;
}

export type LightingDirective = "go" | "caution" | "hold";

export interface LightingTargetColor {
  oklch: {
    l: number;
    c: number;
    h: number;
  };
  hex: string;
}

export interface LightingZoneCell {
  id: string;
  x: number;
  y: number;
  participantDensity: number;
  confidence: number;
  entropy: number;
  targetColor: LightingTargetColor;
}

export interface LightingStatePayload {
  targetColor: LightingTargetColor;
  confidence: number;
  entropy: number;
  stability: number;
  trend: LightingDirective;
  participantCount: number;
  updatedAt: number;
  zoneField: LightingZoneCell[];
}

export interface ColorInteractionPolicy {
  enabled: boolean;
  roles?: Role[];
  showStates?: ShowState[];
}

export interface ScriptCandidate {
  id: string;
  arc: "arc1" | "arc2" | "arc3";
  tags: string[];
  text: string;
  weight: number;
  cooldownMs: number;
  tone: "confessional" | "directive" | "lyrical";
}

export interface SelectionDecision {
  selectedId: string | null;
  modelScore: number;
  rulePass: boolean;
  reason: string;
  cueId: string;
  deviceId?: string;
}

export type ReplayEventType =
  | "cue"
  | "sync"
  | "telemetry"
  | "selection"
  | "device_uplink"
  | "system";

export interface ReplayEvent {
  id: string;
  type: ReplayEventType;
  timestamp: number;
  logicalTime: number;
  cueId?: string;
  source: "harness" | "backend" | "phone";
  payload: Record<string, unknown>;
}

export interface WireEnvelope<T = unknown> {
  kind:
    | "cue"
    | "sync"
    | "device_profile"
    | "param_vector"
    | "selection"
    | "telemetry"
    | "replay"
    | "show_snapshot"
    | "error"
    | "permissions"
    | "zone_update"
    | "ack"
    | "participant_vector"
    | "audience_vector"
    | "lighting_state"
    | "audio_features"
    | "phone_audio_command"
    | "phone_audio_ack"
    | "crowd_pick_window"
    | "crowd_pick_vote"
    | "crowd_pick_result"
    | "text_scene"
    | "phone_audio_pool_state";
  data: T;
  sentAt: number;
}

export const clamp01 = (value: number): number => Math.min(1, Math.max(0, value));

export const normalizeVector = (vector: Partial<ParamVector>): ParamVector => ({
  textAmount: clamp01(vector.textAmount ?? 0),
  compositeBias: clamp01(vector.compositeBias ?? 0.5),
  audioGain: clamp01(vector.audioGain ?? 0.5),
  spatialX: clamp01(vector.spatialX ?? 0.5),
  spatialY: clamp01(vector.spatialY ?? 0.5),
  spatialZ: clamp01(vector.spatialZ ?? 0.5)
});

export const stableHashToSeed = (input: string): number => {
  let hash = 2166136261;
  for (let i = 0; i < input.length; i += 1) {
    hash ^= input.charCodeAt(i);
    hash +=
      (hash << 1) +
      (hash << 4) +
      (hash << 7) +
      (hash << 8) +
      (hash << 24);
  }
  return Math.abs(hash >>> 0);
};

export const deterministicPick = <T>(seed: number, values: T[]): T => {
  if (values.length === 0) {
    throw new Error("Cannot pick from an empty array");
  }
  const index = seed % values.length;
  return values[index];
};

export const isCueCommand = (value: unknown): value is CueCommand => {
  if (!value || typeof value !== "object") {
    return false;
  }
  const candidate = value as Partial<CueCommand>;
  return (
    typeof candidate.cueId === "string" &&
    typeof candidate.showState === "string" &&
    typeof candidate.logicalTime === "number" &&
    typeof candidate.payload === "object" &&
    typeof candidate.version === "number" &&
    typeof candidate.action === "string"
  );
};
