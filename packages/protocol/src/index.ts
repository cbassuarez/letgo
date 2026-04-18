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

export type TakeTimingPolicy = "scheduled_window_v1";
export type TakeTimingCohort = "venue";

export interface CueTimingContract {
  activateAtMs?: number;
  issuedAtMs?: number;
  leadMs?: number;
  timingPolicy?: TakeTimingPolicy;
  timingCohort?: TakeTimingCohort;
}

export interface CueCommand {
  cueId: string;
  showState: ShowState;
  logicalTime: number;
  payload: Record<string, unknown>;
  version: number;
  action: CueAction;
  activateAtMs?: number;
  issuedAtMs?: number;
  leadMs?: number;
  timingPolicy?: TakeTimingPolicy;
  timingCohort?: TakeTimingCohort;
}

export type ShowSceneKey =
  | "interstitial"
  | "preshow"
  | "introduction"
  | "mainStatic"
  | "mainDynamic"
  | "ending";

export type ShowStreamMap = Partial<Record<ShowSceneKey, string>>;

export type InteractionAuthorityMode = "operator_hard_override_weighted";

export interface PromptPolicyPayload {
  scheduler: "state_score";
  cadenceModel: "rolling_cohorts";
  adaptiveWindowMinMs: number;
  adaptiveWindowMaxMs: number;
  directPickBurstMinRatio: number;
  directPickBurstMaxRatio: number;
  maxPromptsPerTick: number;
}

export interface SharedUniqueMixPayload {
  shared: number;
  unique: number;
}

export type EchoStem = "pads" | "hotas" | "choir" | "fx";

export interface EchoStemCap {
  floor: number;
  cap: number;
}

export type EchoCapsByStem = Record<EchoStem, EchoStemCap>;

export interface ShowSnapshotPayload {
  state: ShowState;
  logicalTime: number;
  version: number;
  vector: ParamVector;
  cueId?: string;
  cueVersion?: number;
  activeScene?: ShowSceneKey;
  streamMap?: ShowStreamMap;
  cuePayload?: Record<string, unknown>;
  authorityMode?: InteractionAuthorityMode;
  promptPolicy?: PromptPolicyPayload;
  cohortSalt?: string;
  sharedUniqueMix?: SharedUniqueMixPayload;
  echoCapsByStem?: EchoCapsByStem;
  activateAtMs?: number;
  issuedAtMs?: number;
  leadMs?: number;
  timingPolicy?: TakeTimingPolicy;
  timingCohort?: TakeTimingCohort;
}

export interface CueActivationAckPayload {
  cueId: string;
  seenAt: number;
  activatedAtMs?: number;
  activationDeltaMs?: number;
  source?: "device" | "harness";
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

export type TransitionMode = "cut" | "crossfade" | "stutter" | "fade";
export type CompositorPreset =
  | "blend"
  | "multiply"
  | "screen"
  | "mask"
  | "pip"
  | "stutter";
export type SplitLayout = "none" | "split-2" | "split-3" | "split-4" | "pip";

export type PushDeckControlKind =
  | "pad_down"
  | "pad_up"
  | "macro"
  | "long_strip"
  | "bank_select"
  | "ml_param";
export type PushDeckModeContext = "auto" | "dynamic" | "static" | "choir";
export type PushDeckTimingMode = "immediate" | "quantized";
export type PushDeckBankDomain = "main" | "choir";
export type PushDeckMLParamKey =
  | "phone_pad_echo_probability"
  | "pads_echo_probability"
  | "global_echo_probability"
  | "hotas_echo_probability"
  | "choir_echo_probability"
  | "fx_echo_probability";

export interface PushDeckPadControl {
  row: number;
  column: number;
  slot: number;
  pressure: number;
  velocity: number;
}

export interface PushDeckMacroControl {
  lane: number;
  value: number;
}

export interface PushDeckLongStripControl {
  value: number;
}

export interface PushDeckBankControl {
  domain: PushDeckBankDomain;
  bank: number;
}

export interface PushDeckMLParamControl {
  key: PushDeckMLParamKey;
  value: number;
}

export interface PushPadLabelsPayload {
  padLabels: string[];
  bank?: number;
  updatedAt?: number;
}

export interface PushDeckEventPayload {
  eventId: string;
  sourceId: string;
  controlKind: PushDeckControlKind;
  modeContext: PushDeckModeContext;
  timingMode: PushDeckTimingMode;
  quantIntervalMs?: number;
  pad?: PushDeckPadControl;
  macro?: PushDeckMacroControl;
  longStrip?: PushDeckLongStripControl;
  bank?: PushDeckBankControl;
  mlParam?: PushDeckMLParamControl;
  issuedAt: number;
}

export interface DynamicBinClip {
  id: string;
  mediaRef: string;
  tags: string[];
  weight: number;
  scopes?: string[];
}

export interface TextBlendState {
  mode: "always-mixed";
  probability: number;
  strictRatio: number;
  looseRatio: number;
}

export interface ProgramProceduralState {
  epoch: number;
  seed: number;
  updatedAt: number;
  dynamicBinSelection: number;
  dynamicBinIndex: number;
  dynamicBinClipId: string | null;
  dynamicBinManifest: DynamicBinClip[];
  cutCadence: number;
  transitionMode: TransitionMode;
  compositorPreset: CompositorPreset;
  splitLayout: SplitLayout;
  fade: number;
  textProbability: number;
  strictLooseBlend: number;
  visualVariance: number;
  crowdSteeringLevel: number;
  performerVector: ParamVector;
  audienceVector: ParamVector;
  textBlend: TextBlendState;
  promptInfluence?: number;
  directPickInfluence?: number;
  echoProbabilityGlobal?: number;
  echoProbabilityByStem?: Partial<Record<EchoStem, number>>;
}

export type ProposalLane = "audio" | "visual_text";
export type AudioProposalKind = "texture_nudge" | "structured_latch";
export type MLProposalDecision = "accepted" | "expired" | "rejected" | "blocked";
export type AudioStemID = "master" | "main_samples" | "synth_ambient" | "choir" | "ipad_in";

export interface StateDevelopmentMetrics {
  repeatability: number;
  intensityTrend: number;
  noveltySaturation: number;
  headroom: number;
  safetyContext: number;
  stateDevelopmentIndex: number;
  interventionNeedScore: number;
  updatedAt: number;
}

export interface MLProposalPayloadAudio {
  kind: AudioProposalKind;
  suggestedBank?: number;
  suggestedSampleID?: string;
  chainAIntensityTarget?: number;
  chainBIntensityTarget?: number;
  densityTarget?: number;
  latchSuggested: boolean;
}

export interface MLProposalPayloadVisualText {
  dynamicBinSelection?: number;
  transitionMode?: TransitionMode;
  compositorPreset?: CompositorPreset;
  splitLayout?: SplitLayout;
  fade?: number;
  textProbability?: number;
  strictLooseBlend?: number;
}

export interface MLProposal {
  id: string;
  lane: ProposalLane;
  confidence: number;
  rationale: string;
  expectedEffect: string;
  timeoutMs: number;
  createdAt: number;
  audio?: MLProposalPayloadAudio;
  visualText?: MLProposalPayloadVisualText;
}

export interface AudioStemFeatureFrame {
  stem: AudioStemID;
  rms: number;
  spectralCentroid: number;
  flux: number;
  transientDensity: number;
}

export interface ProgramAudioState {
  epoch: number;
  updatedAt: number;
  activeSampleBank: number;
  activeChoirSampleBank: number;
  choirContextActive: boolean;
  phoneGateCommitted: boolean;
  estimatedDensity: number;
  effects: {
    chainAActive: boolean;
    chainAIntensity: number;
    chainBActive: boolean;
    chainBIntensity: number;
  };
  master: AudioFeaturePayload;
  stems: AudioStemFeatureFrame[];
  activeProposalID: string | null;
  structuredLatchActive: boolean;
  staticMacros: {
    sampleMorph: number;
    articulation: number;
    timbre: number;
    textureSend: number;
  };
  choirField: {
    spread: number;
    depth: number;
    detune: number;
  };
  staticVisualOverrideHeld: boolean;
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
  promptInfluence?: number;
  directPickInfluence?: number;
  colorIntent?: ColorIntentPayload;
  updatedAt: number;
}

export interface AudienceVectorPayload {
  vector: ParamVector;
  participantCount: number;
  updatedAt: number;
  compositorModes: Record<string, number>;
  promptInfluence?: number;
  directPickInfluence?: number;
  wavefront?: {
    intensity: number;
    phase: number;
    decay: number;
  };
}

export type PromptDomain = "video" | "text" | "sound" | "lighting";
export type PromptAffordance = "tap" | "drag" | "hold";
export type PromptResponseType = "tap" | "drag" | "hold" | "skip";

export type PromptAction =
  | "layout_full"
  | "layout_pip"
  | "layout_split"
  | "clip_tension"
  | "clip_release"
  | "direct_slot_a"
  | "direct_slot_b"
  | "direct_take_next"
  | "cut"
  | "stretch"
  | "echo"
  | "withhold"
  | "warm_shift"
  | "cool_shift"
  | "luma_raise"
  | "luma_lower"
  | "echo_push"
  | "echo_pull"
  | "density_hold";

export interface PromptDirectPickTarget {
  slotId: string;
  takeId?: string;
  label?: string;
}

export interface PromptOfferPayload {
  promptId: string;
  cueVersion: number;
  scene: ShowSceneKey;
  domain: PromptDomain;
  action: PromptAction;
  affordance: PromptAffordance;
  expiresAt: number;
  haptic: boolean;
  directPickTargets?: PromptDirectPickTarget[];
}

export interface PromptResponsePayload {
  promptId: string;
  cueVersion: number;
  responseType: PromptResponseType;
  tapChoice?: string;
  dragVector?: { x: number; y: number };
  holdMs?: number;
  latencyMs: number;
  slotPick?: { slotId: string; takeId?: string };
  respondedAt?: number;
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

export type PhoneAudioPriority = "high" | "medium" | "low";
export type VoiceStreamCodec = "opus" | "aac" | "pcm";
export type VoiceStreamTransport = "hls" | "webrtc";
export type StreamLifecycleStatus =
  | "subscribed"
  | "unsubscribed"
  | "underrun"
  | "track_lost"
  | "fallback_group";

export interface SFUIceServerConfig {
  urls: string | string[];
  username?: string;
  credential?: string;
}

export interface VoiceStreamWebRTCDescriptor {
  roomId: string;
  streamId: string;
  publisherId?: string;
  iceServers?: SFUIceServerConfig[];
}

export interface PhoneAudioRenderHints {
  zoneId?: string;
  pan?: number;
  detuneCents?: number;
  grainMix?: number;
  motionEnergy?: number;
  priority?: PhoneAudioPriority;
}

export interface VoiceStreamDescriptor {
  voiceId: string;
  trackId: string;
  sessionId: string;
  token?: string;
  codec: VoiceStreamCodec;
  transport?: VoiceStreamTransport;
  expiresAt: number;
  streamUrl?: string;
  fallbackGroup?: string;
  webrtc?: VoiceStreamWebRTCDescriptor;
}

export interface GroupStemDescriptor {
  groupId: string;
  sessionId: string;
  token?: string;
  codec: VoiceStreamCodec;
  transport?: VoiceStreamTransport;
  expiresAt: number;
  streamUrl?: string;
  webrtc?: VoiceStreamWebRTCDescriptor;
}

export interface PhoneAudioCommandPayload {
  commandId: string;
  kind: PhoneAudioCommandKind;
  targetHashedIds: string[];
  note?: number;
  velocity?: number;
  sampleId?: string;
  gain?: number;
  seed?: number;
  renderHints?: PhoneAudioRenderHints;
  renderHintsByTarget?: Record<string, PhoneAudioRenderHints>;
  stream?: VoiceStreamDescriptor;
  streamByTarget?: Record<string, VoiceStreamDescriptor>;
  fallbackGroup?: GroupStemDescriptor;
  issuedAt: number;
}

export interface PhoneAudioAckPayload {
  commandId: string;
  hashedId: string;
  ok: boolean;
  detail?: string;
  streamStatus?: StreamLifecycleStatus;
  streamReason?: string;
  voiceId?: string;
  trackId?: string;
  receivedAt: number;
}

export type KeyboardHostLinkState = "offline" | "connecting" | "online" | "degraded";

export interface KeyboardPatchSnapshot {
  patchId: string;
  patchName?: string;
  bank: number;
  program: number;
  updatedAt: number;
}

export interface KeyboardStatePayload {
  profileId: string;
  profileName: string;
  page: number;
  pageName: string;
  hostLink: KeyboardHostLinkState;
  clockMaster: boolean;
  clockBpm: number;
  transportRunning: boolean;
  patch: KeyboardPatchSnapshot;
  cueVersion?: number;
  activeScene?: ShowSceneKey;
  updatedAt: number;
}

export interface KeyboardPatchChangePayload {
  patchId: string;
  patchName?: string;
  bank: number;
  program: number;
  source: "operator";
  updatedAt: number;
}

export interface VoiceStreamStartPayload {
  commandId: string;
  hashedId: string;
  note?: number;
  velocity?: number;
  renderHints?: PhoneAudioRenderHints;
  stream: VoiceStreamDescriptor;
  issuedAt: number;
}

export interface VoiceStreamStopPayload {
  commandId: string;
  hashedId: string;
  voiceId: string;
  trackId: string;
  note?: number;
  reason?: "note_off" | "stop_all" | "failover" | "expired";
  issuedAt: number;
}

export interface GroupStemStartPayload {
  commandId: string;
  hashedIds: string[];
  group: GroupStemDescriptor;
  reason?: "voice_cap" | "stream_unstable" | "manual_recovery";
  issuedAt: number;
}

export interface GroupStemStopPayload {
  commandId: string;
  hashedIds: string[];
  groupId: string;
  reason?: "voice_capacity_recovered" | "manual" | "show_stop";
  issuedAt: number;
}

export interface VoiceStreamSubscribePayload {
  commandId: string;
  hashedId: string;
  voiceId: string;
  trackId: string;
  sessionId: string;
  requestType: "init" | "connect" | "consume" | "resume";
  transportId?: string;
  rtpCapabilities?: Record<string, unknown>;
  dtlsParameters?: Record<string, unknown>;
  consumerId?: string;
  issuedAt: number;
}

export interface VoiceStreamSubscribedPayload {
  commandId: string;
  hashedId: string;
  voiceId: string;
  trackId: string;
  sessionId: string;
  requestType: VoiceStreamSubscribePayload["requestType"];
  transportId?: string;
  routerRtpCapabilities?: Record<string, unknown>;
  transportOptions?: {
    id: string;
    iceParameters: Record<string, unknown>;
    iceCandidates: Array<Record<string, unknown>>;
    dtlsParameters: Record<string, unknown>;
  };
  consumerOptions?: {
    id: string;
    producerId: string;
    kind: "audio" | "video";
    rtpParameters: Record<string, unknown>;
    type: string;
  };
  consumerId?: string;
  issuedAt: number;
}

export interface VoiceStreamUnsubscribePayload {
  commandId: string;
  hashedId: string;
  voiceId: string;
  trackId: string;
  sessionId: string;
  reason?: "manual" | "note_off" | "expired" | "failover";
  issuedAt: number;
}

export interface VoiceStreamIceCandidatePayload {
  commandId: string;
  hashedId: string;
  voiceId: string;
  trackId: string;
  sessionId: string;
  transportId?: string;
  candidate: string;
  sdpMid?: string;
  sdpMLineIndex?: number;
  issuedAt: number;
}

export interface VoicePublisherAnnouncePayload {
  publisherId: string;
  sessionId: string;
  trackId: string;
  codec: VoiceStreamCodec;
  active: boolean;
  ingest?: {
    ip: string;
    port: number;
    rtcpPort?: number;
    payloadType: number;
    ssrc: number;
    mimeType: string;
    clockRate: number;
    channels: number;
  };
  error?: string;
  updatedAt: number;
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

export type TextSemanticMode = "off" | "openai";

export interface RuntimeScriptCandidate {
  id?: string;
  text: string;
  weight?: number;
}

export interface TextModelHealthPayload {
  active: boolean;
  summary: string;
  modelPath: string | null;
  source: "none" | "path" | "inline";
  sourceLabel?: string | null;
  version?: string | null;
  lastLoadedAt: number | null;
  runtimeFailures: number;
}

export interface TextRuntimeStatusPayload {
  updatedAt: number;
  strictCount: number;
  looseCount: number;
  strictSource: string;
  looseSource: string;
  warnings: string[];
  modelHealth: TextModelHealthPayload | null;
  semantic: {
    mode: TextSemanticMode;
    enabled: boolean;
    provider: "openai" | "none";
    model: string | null;
    apiKeyConfigured?: boolean;
    refreshMs: number;
    ttlMs: number;
    timeoutMs: number;
    cacheEntries: number;
    inFlight: number;
    lastSuccessAt: number | null;
    lastError: string | null;
  } | null;
}

export interface TextRuntimeUpdatePayload {
  requestStatus?: boolean;
  reload?: boolean;
  strictCandidates?: RuntimeScriptCandidate[];
  looseCandidates?: RuntimeScriptCandidate[];
  modelPayloadJSON?: string;
  semanticMode?: TextSemanticMode;
  semanticApiKey?: string | null;
  semanticModel?: string;
}

export interface PhoneAudioPoolStatePayload {
  gateArmed: boolean;
  gateCommitted: boolean;
  quadRouteReady: boolean;
  availableDevices: string[];
  activeVoices: Record<string, number>;
  zoneOccupancy?: Record<string, number>;
  deviceHealth?: Record<
    string,
    {
      rttMs: number;
      driftMs: number;
      ackReliability: number;
      lastSeenAt: number;
    }
  >;
  failoverCount?: number;
  updatedAt: number;
}

export interface AudioOpsStatePayload {
  audioFeatures: AudioFeaturePayload;
  phoneAudioPool: PhoneAudioPoolStatePayload;
  pickWindow: CrowdPickWindowPayload | null;
  pickResult: CrowdPickResultPayload | null;
  textScene: TextScenePayload;
  proceduralState?: ProgramProceduralState;
  programAudioState?: ProgramAudioState;
  stateDevelopmentMetrics?: StateDevelopmentMetrics;
  activeProposal?: MLProposal | null;
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
    | "keyboard_state"
    | "keyboard_patch_change"
    | "voice_stream_start"
    | "voice_stream_stop"
    | "group_stem_start"
    | "group_stem_stop"
    | "voice_stream_subscribe"
    | "voice_stream_subscribed"
    | "voice_stream_unsubscribe"
    | "voice_stream_ice"
    | "voice_publisher_announce"
    | "crowd_pick_window"
    | "crowd_pick_vote"
    | "crowd_pick_result"
    | "text_scene"
    | "text_runtime_status"
    | "text_runtime_update"
    | "phone_audio_pool_state"
    | "push_deck_event"
    | "push_pad_labels"
    | "procedural_state"
    | "prompt_offer"
    | "prompt_response";
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
