import {
  clamp01,
  type InteractionAuthorityMode,
  type PromptAction,
  type PromptAffordance,
  type PromptDomain,
  type PromptOfferPayload,
  type PromptPolicyPayload,
  type PromptResponsePayload,
  type SharedUniqueMixPayload,
  type ShowSceneKey,
  type ShowState,
  stableHashToSeed
} from "@conductor/protocol";

const DEFAULT_SCENE: ShowSceneKey = "interstitial";

interface PromptDeviceState {
  hashedId: string;
  cadenceBiasMs: number;
  cohort: number;
  lastPromptAt: number;
  lastResponseAt: number;
  pendingPromptId: string | null;
  pendingExpiresAt: number;
  misses: number;
}

interface ActivePromptRecord {
  hashedId: string;
  offer: PromptOfferPayload;
  deliveredAt: number;
}

interface PromptTickContext {
  now: number;
  cueVersion: number;
  showState: ShowState;
  activeScene: ShowSceneKey | null;
  engineRunning: boolean;
  participantCount: number;
  entropy: number;
  audioFlux: number;
  connectedHashedIds: string[];
}

export interface PromptDispatch {
  hashedId: string;
  offer: PromptOfferPayload;
}

export interface PromptResponseResult {
  accepted: boolean;
  promptInfluence: number;
  directPickInfluence: number;
  action?: PromptAction;
  domain?: PromptDomain;
  slotPick?: { slotId: string; takeId?: string };
}

const PROMPT_POLICY: PromptPolicyPayload = {
  scheduler: "state_score",
  cadenceModel: "rolling_cohorts",
  adaptiveWindowMinMs: 4_000,
  adaptiveWindowMaxMs: 7_000,
  directPickBurstMinRatio: 0.1,
  directPickBurstMaxRatio: 0.2,
  maxPromptsPerTick: 6
};

const SHARED_UNIQUE_MIX: SharedUniqueMixPayload = {
  shared: 0.7,
  unique: 0.3
};

const AUTHORITY_MODE: InteractionAuthorityMode = "operator_hard_override_weighted";

const sceneWeight = (state: ShowState, scene: ShowSceneKey): number => {
  if (state === "main") {
    return scene === "mainDynamic" ? 0.82 : 0.72;
  }
  if (state === "preshow" || state === "introduction") {
    return 0.56;
  }
  if (state === "ending") {
    return 0.62;
  }
  if (state === "hold" || state === "recovery") {
    return 0.44;
  }
  if (state === "idle") {
    return 0.28;
  }
  return 0.36;
};

const domainWeightsByScene = (scene: ShowSceneKey): Array<{ domain: PromptDomain; weight: number }> => {
  switch (scene) {
    case "mainDynamic":
      return [
        { domain: "video", weight: 0.42 },
        { domain: "text", weight: 0.22 },
        { domain: "sound", weight: 0.22 },
        { domain: "lighting", weight: 0.14 }
      ];
    case "mainStatic":
      return [
        { domain: "video", weight: 0.28 },
        { domain: "text", weight: 0.28 },
        { domain: "sound", weight: 0.2 },
        { domain: "lighting", weight: 0.24 }
      ];
    case "preshow":
    case "introduction":
      return [
        { domain: "lighting", weight: 0.4 },
        { domain: "text", weight: 0.36 },
        { domain: "sound", weight: 0.16 },
        { domain: "video", weight: 0.08 }
      ];
    case "ending":
      return [
        { domain: "text", weight: 0.44 },
        { domain: "lighting", weight: 0.24 },
        { domain: "sound", weight: 0.2 },
        { domain: "video", weight: 0.12 }
      ];
    case "interstitial":
    default:
      return [
        { domain: "video", weight: 0.28 },
        { domain: "text", weight: 0.28 },
        { domain: "lighting", weight: 0.22 },
        { domain: "sound", weight: 0.22 }
      ];
  }
};

const actionsByDomain: Record<PromptDomain, PromptAction[]> = {
  video: ["layout_full", "layout_pip", "layout_split", "clip_tension", "clip_release"],
  text: ["cut", "stretch", "echo", "withhold"],
  sound: ["echo_push", "echo_pull", "density_hold"],
  lighting: ["warm_shift", "cool_shift", "luma_raise", "luma_lower"]
};

const affordanceForAction = (action: PromptAction): PromptAffordance => {
  if (action === "layout_split" || action === "layout_pip" || action === "warm_shift" || action === "cool_shift") {
    return "drag";
  }
  if (action === "withhold" || action === "density_hold") {
    return "hold";
  }
  return "tap";
};

const weightedPick = <T>(seed: number, weighted: Array<{ value: T; weight: number }>): T => {
  const total = weighted.reduce((sum, entry) => sum + Math.max(0, entry.weight), 0);
  if (total <= 0) {
    return weighted[0].value;
  }
  const target = (seed % 10_000) / 10_000;
  let cursor = 0;
  for (const entry of weighted) {
    cursor += Math.max(0, entry.weight) / total;
    if (target <= cursor) {
      return entry.value;
    }
  }
  return weighted[weighted.length - 1].value;
};

export class PromptOrchestrator {
  private readonly devices = new Map<string, PromptDeviceState>();
  private readonly activePrompts = new Map<string, ActivePromptRecord>();

  private promptCounter = 0;
  private sceneToken = `${DEFAULT_SCENE}:0`;
  private cohortSalt = `seed:${DEFAULT_SCENE}:0`;

  policy(): PromptPolicyPayload {
    return PROMPT_POLICY;
  }

  authorityMode(): InteractionAuthorityMode {
    return AUTHORITY_MODE;
  }

  sharedUniqueMix(): SharedUniqueMixPayload {
    return SHARED_UNIQUE_MIX;
  }

  currentCohortSalt(): string {
    return this.cohortSalt;
  }

  upsertDevice(hashedId: string): void {
    const existing = this.devices.get(hashedId);
    if (existing) {
      return;
    }

    const seed = stableHashToSeed(`prompt:${hashedId}`);
    const next: PromptDeviceState = {
      hashedId,
      cadenceBiasMs: seed % 1_900,
      cohort: seed % 5,
      lastPromptAt: 0,
      lastResponseAt: 0,
      pendingPromptId: null,
      pendingExpiresAt: 0,
      misses: 0
    };
    this.devices.set(hashedId, next);
  }

  removeDevice(hashedId: string): void {
    this.devices.delete(hashedId);
    for (const [promptId, record] of this.activePrompts.entries()) {
      if (record.hashedId === hashedId) {
        this.activePrompts.delete(promptId);
      }
    }
  }

  tick(context: PromptTickContext): PromptDispatch[] {
    for (const hashedId of context.connectedHashedIds) {
      this.upsertDevice(hashedId);
    }

    const activeSet = new Set(context.connectedHashedIds);
    for (const hashedId of this.devices.keys()) {
      if (!activeSet.has(hashedId)) {
        this.removeDevice(hashedId);
      }
    }

    const activeScene = context.activeScene ?? DEFAULT_SCENE;
    const nextToken = `${activeScene}:${context.cueVersion}`;
    if (nextToken !== this.sceneToken) {
      this.sceneToken = nextToken;
      this.cohortSalt = `salt:${activeScene}:${context.cueVersion}`;
      for (const state of this.devices.values()) {
        state.cohort = stableHashToSeed(`${state.hashedId}:${this.cohortSalt}`) % 5;
        state.pendingPromptId = null;
        state.pendingExpiresAt = 0;
      }
      this.activePrompts.clear();
    }

    for (const state of this.devices.values()) {
      if (state.pendingPromptId && state.pendingExpiresAt > 0 && context.now > state.pendingExpiresAt) {
        this.activePrompts.delete(state.pendingPromptId);
        state.pendingPromptId = null;
        state.pendingExpiresAt = 0;
        state.misses = Math.min(8, state.misses + 1);
      }
    }

    if (!context.engineRunning || context.connectedHashedIds.length === 0) {
      return [];
    }

    const roomHeadroom = clamp01(1 - context.participantCount / 200);
    const demand = clamp01(
      sceneWeight(context.showState, activeScene) * 0.45 +
        clamp01(context.entropy) * 0.2 +
        roomHeadroom * 0.18 +
        clamp01(context.audioFlux) * 0.17
    );

    if (demand < 0.34) {
      return [];
    }

    const maxDispatches = Math.max(
      1,
      Math.min(
        PROMPT_POLICY.maxPromptsPerTick,
        Math.round(context.connectedHashedIds.length * (0.04 + demand * 0.08))
      )
    );

    const tickBucket = Math.floor(context.now / 350);
    const candidates: Array<{ state: PromptDeviceState; score: number }> = [];

    for (const state of this.devices.values()) {
      if (state.pendingPromptId && state.pendingExpiresAt > context.now) {
        continue;
      }

      const cadenceMs = Math.max(
        2_600,
        Math.round(4_400 + state.cadenceBiasMs + state.cohort * 260 + state.misses * 420 - demand * 2_200)
      );
      if (context.now - state.lastPromptAt < cadenceMs) {
        continue;
      }

      const gateSeed = stableHashToSeed(`${state.hashedId}:${this.cohortSalt}:${tickBucket}`);
      const gate = gateSeed % 100;
      const gateThreshold = Math.round(24 + demand * 48);
      if (gate > gateThreshold) {
        continue;
      }

      const staleResponse = clamp01((context.now - state.lastResponseAt) / 20_000);
      const score = demand + staleResponse * 0.25 + (gateSeed % 1_000) / 10_000;
      candidates.push({ state, score });
    }

    candidates.sort((lhs, rhs) => rhs.score - lhs.score);

    const dispatches: PromptDispatch[] = [];
    for (const candidate of candidates.slice(0, maxDispatches)) {
      const offer = this.buildOffer(candidate.state, context, demand, activeScene);
      dispatches.push({ hashedId: candidate.state.hashedId, offer });

      candidate.state.lastPromptAt = context.now;
      candidate.state.pendingPromptId = offer.promptId;
      candidate.state.pendingExpiresAt = offer.expiresAt;
      this.activePrompts.set(offer.promptId, {
        hashedId: candidate.state.hashedId,
        offer,
        deliveredAt: context.now
      });
    }

    return dispatches;
  }

  consumeResponse(hashedId: string, response: PromptResponsePayload, now = Date.now()): PromptResponseResult {
    const promptId = typeof response.promptId === "string" ? response.promptId : "";
    if (!promptId) {
      return { accepted: false, promptInfluence: 0, directPickInfluence: 0 };
    }

    const active = this.activePrompts.get(promptId);
    if (!active || active.hashedId !== hashedId) {
      return { accepted: false, promptInfluence: 0, directPickInfluence: 0 };
    }

    if (now > active.offer.expiresAt) {
      this.activePrompts.delete(promptId);
      const state = this.devices.get(hashedId);
      if (state?.pendingPromptId === promptId) {
        state.pendingPromptId = null;
        state.pendingExpiresAt = 0;
        state.misses = Math.min(8, state.misses + 1);
      }
      return { accepted: false, promptInfluence: 0, directPickInfluence: 0 };
    }

    this.activePrompts.delete(promptId);
    const state = this.devices.get(hashedId);
    if (state?.pendingPromptId === promptId) {
      state.pendingPromptId = null;
      state.pendingExpiresAt = 0;
      state.lastResponseAt = now;
      state.misses = Math.max(0, state.misses - 1);
    }

    const effectiveLatency =
      typeof response.latencyMs === "number" && Number.isFinite(response.latencyMs)
        ? Math.max(0, response.latencyMs)
        : Math.max(0, now - active.deliveredAt);
    const responseWindowMs = Math.max(1, active.offer.expiresAt - active.deliveredAt);
    const latencyScore = clamp01(1 - effectiveLatency / responseWindowMs);

    const responseScore =
      response.responseType === "drag" ? 0.92 : response.responseType === "hold" ? 0.88 : response.responseType === "tap" ? 0.82 : 0.5;

    const promptInfluence = clamp01(0.28 + latencyScore * 0.44 + responseScore * 0.28);
    const directPickActive =
      active.offer.action === "direct_slot_a" ||
      active.offer.action === "direct_slot_b" ||
      active.offer.action === "direct_take_next" ||
      Boolean(response.slotPick);
    const directPickInfluence = directPickActive ? clamp01(0.42 + latencyScore * 0.48) : 0;

    return {
      accepted: true,
      promptInfluence,
      directPickInfluence,
      action: active.offer.action,
      domain: active.offer.domain,
      slotPick: response.slotPick
    };
  }

  private buildOffer(
    state: PromptDeviceState,
    context: PromptTickContext,
    demand: number,
    activeScene: ShowSceneKey
  ): PromptOfferPayload {
    this.promptCounter += 1;

    const seed = stableHashToSeed(
      `${state.hashedId}:${context.cueVersion}:${activeScene}:${this.promptCounter}:${Math.floor(context.now / 1_000)}`
    );

    const directPickBurstRatio =
      PROMPT_POLICY.directPickBurstMinRatio +
      (PROMPT_POLICY.directPickBurstMaxRatio - PROMPT_POLICY.directPickBurstMinRatio) * demand;
    const directPickAllowed = activeScene === "mainDynamic" || activeScene === "mainStatic";
    const directPick = directPickAllowed && ((seed >>> 5) % 100) / 100 < directPickBurstRatio;

    let domain: PromptDomain;
    let action: PromptAction;

    if (directPick) {
      domain = "video";
      action = ["direct_slot_a", "direct_slot_b", "direct_take_next"][seed % 3] as PromptAction;
    } else {
      const domainWeights = domainWeightsByScene(activeScene).map((entry) => ({
        value: entry.domain,
        weight: entry.weight
      }));
      domain = weightedPick(seed, domainWeights);
      const actions = actionsByDomain[domain];
      action = actions[(seed >>> 3) % actions.length];
    }

    const affordance = affordanceForAction(action);
    const jitter = ((seed >>> 9) % 1000) / 1000;
    const windowMs = Math.round(
      PROMPT_POLICY.adaptiveWindowMinMs +
        (PROMPT_POLICY.adaptiveWindowMaxMs - PROMPT_POLICY.adaptiveWindowMinMs) * (0.2 + 0.8 * (1 - demand * 0.7 + jitter * 0.3))
    );

    const directPickTargets =
      directPick
        ? [
            { slotId: "slot-a", label: "Slot A" },
            { slotId: "slot-b", label: "Slot B" },
            { slotId: "slot-c", label: "Slot C" }
          ]
        : undefined;

    return {
      promptId: `prompt:${context.cueVersion}:${this.promptCounter}:${seed % 1_000_000}`,
      cueVersion: context.cueVersion,
      scene: activeScene,
      domain,
      action,
      affordance,
      expiresAt: context.now + Math.max(PROMPT_POLICY.adaptiveWindowMinMs, Math.min(PROMPT_POLICY.adaptiveWindowMaxMs, windowMs)),
      haptic: true,
      directPickTargets
    };
  }
}
