import {
  type AudioFeaturePayload,
  type AudioOpsStatePayload,
  type AudienceVectorPayload,
  clamp01,
  type ColorIntentPayload,
  type CompositorMode,
  type CrowdPickVotePayload,
  type CrowdPickResultPayload,
  type CueCommand,
  isCueCommand,
  type LightingStatePayload,
  normalizeVector,
  type ParamVector,
  type ParticipantVectorPayload,
  type PhoneAudioAckPayload,
  type PhoneAudioCommandPayload,
  type PhoneAudioPoolStatePayload,
  type PushDeckEventPayload,
  type PushDeckBankDomain,
  type ProgramProceduralState,
  stableHashToSeed,
  type TextBlendState,
  type SyncPacket,
  type TextScenePayload,
  type TransitionMode,
  type CompositorPreset,
  type SplitLayout,
  type WireEnvelope
} from "@conductor/protocol";
import type { FastifyInstance } from "fastify";
import type { WebSocket } from "ws";
import type { AppConfig } from "../config";
import { AudienceVectorField } from "../services/audienceVectorField";
import type { AudioOpsStateHub } from "../services/audioOpsStateHub";
import type { CrowdPickPulseService } from "../services/crowdPickPulse";
import { CrowdLightingField } from "../services/crowdLightingField";
import { IdentityService } from "../services/identityService";
import { PhoneChoirSpatialAllocator } from "../services/phoneChoirSpatialAllocator";
import type { PhoneAudioPoolService } from "../services/phoneAudioPool";
import { ReplayService } from "../services/replayService";
import { ShowOrchestrator } from "../services/showOrchestrator";
import { SyncService } from "../services/syncService";
import type { TextSceneComposerService } from "../services/textSceneComposer";
import type { SessionStore } from "../stores/sessionStore";
import { logger } from "../utils/logger";

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
  | { kind: "text_scene"; data: Partial<TextScenePayload> & { cueId?: string } }
  | { kind: "procedural_state"; data: Partial<ProgramProceduralState> };

type DeviceInbound =
  | { kind: "sync"; data: SyncPacket }
  | { kind: "telemetry"; data: Record<string, unknown> }
  | { kind: "participant_vector"; data: Partial<ParticipantVectorPayload> & { vector?: Partial<ParamVector> } }
  | { kind: "zone_update"; data: { name: string; x: number; y: number; z?: number } }
  | { kind: "permissions"; data: { audio?: boolean; geolocation?: boolean; motion?: boolean } }
  | { kind: "ack"; data: { cueId: string; seenAt: number } }
  | { kind: "phone_audio_ack"; data: Partial<PhoneAudioAckPayload> }
  | { kind: "push_deck_event"; data: Partial<PushDeckEventPayload> }
  | { kind: "crowd_pick_vote"; data: Partial<CrowdPickVotePayload> };

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
  const pushContinuousThrottleMs = 24;
  const pushLastForwardAt = new Map<string, number>();
  const pushPendingContinuousEvents = new Map<
    string,
    {
      payload: PushDeckEventPayload;
      timeout: NodeJS.Timeout;
    }
  >();
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
  let baseProceduralState = createDefaultProceduralState(deps.show.snapshot().vector);
  let effectiveProceduralState = baseProceduralState;

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
        await deps.replayService.record({
          type: "cue",
          timestamp: Date.now(),
          logicalTime: inbound.data.logicalTime,
          cueId: inbound.data.cueId,
          source: "harness",
          payload: inbound.data.payload
        });
        broadcastCue(inbound.data);
        composeAndBroadcastTextScene(true, inbound.data.cueId);
        return;
      }

      if (inbound.kind === "command") {
        try {
          const cue = deps.show.applyAction(
            inbound.data.action,
            Date.now(),
            inbound.data.targetState,
            inbound.data.payload ?? {}
          );

          await deps.replayService.record({
            type: "cue",
            timestamp: Date.now(),
            logicalTime: cue.logicalTime,
            cueId: cue.cueId,
            source: "harness",
            payload: cue.payload
          });

          broadcastCue(cue);
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

      if (inbound.kind === "text_scene") {
        const current = deps.audioOpsStateHub.snapshot().textScene;
        const merged: TextScenePayload = {
          ...current,
          ...inbound.data,
          cueId: inbound.data.cueId ?? current.cueId
        };
        deps.audioOpsStateHub.setTextScene(merged);
        broadcastTextScene(merged);
      }
    });
  });

  wsApp.get("/ws/device/:hashedId", { websocket: true }, async (socket, req) => {
    const hashedId = req.params.hashedId ?? "";

    if (!deps.identityService.validateHashedId(hashedId)) {
      socket.close(1008, "invalid hashed id");
      return;
    }

    deviceSockets.set(hashedId, socket);
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

    pushInitialSnapshot(socket, "device");

    socket.on("close", (code, reason) => {
      logger.info("ws socket closed", {
        role: "device",
        hashedId,
        code,
        reason: decodeCloseReason(reason)
      });
      deviceSockets.delete(hashedId);
      const aggregate = audienceField.remove(hashedId);
      broadcastAudienceVector(aggregate);
      const lighting = deps.lightingField.remove(hashedId);
      broadcastLightingState(lighting);
      const pool = deps.phoneAudioPool.removeDevice(hashedId);
      choirAllocator.removeDevice(hashedId);
      clearPendingPushEventsForDevice(hashedId);
      publishPhonePoolState(pool);
    });

    socket.on("error", (error) => {
      logger.warn("ws socket error", {
        role: "device",
        hashedId,
        message: String(error)
      });
    });

    socket.on("message", async (raw: Buffer) => {
      const inbound = parse<DeviceInbound>(raw.toString());
      if (!inbound) {
        return;
      }

      if (inbound.kind === "sync" && inbound.data.kind === "pong") {
        const stats = deps.sync.evaluatePong(inbound.data, Date.now());
        choirAllocator.updateSyncHealth(hashedId, stats.rtt, stats.driftEstimate, Date.now());
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
        const compositorMode = toCompositorMode(inbound.data.compositorMode);
        const aggregate = audienceField.update(hashedId, {
          vector,
          influence,
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

        if (normalized.controlKind === "macro" || normalized.controlKind === "ml_param") {
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

      if (inbound.kind === "phone_audio_ack") {
        const ack: PhoneAudioAckPayload = {
          commandId: typeof inbound.data.commandId === "string" ? inbound.data.commandId : "",
          hashedId,
          ok: inbound.data.ok === true,
          detail: typeof inbound.data.detail === "string" ? inbound.data.detail : undefined,
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

      if (inbound.kind === "telemetry" || inbound.kind === "ack") {
        await deps.replayService.record({
          type: inbound.kind === "ack" ? "device_uplink" : "telemetry",
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
    effectiveProceduralState = applyAudienceSteeringAndVariance(
      baseProceduralState,
      audience,
      lastAudioFeatures,
      pulse.result
    );
    deps.audioOpsStateHub.setProceduralState(effectiveProceduralState);
    broadcastProceduralState(effectiveProceduralState);
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
      data: deps.show.snapshot(),
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

    if (role === "device") {
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
        break;
      }
      case "note_off": {
        targets = deps.phoneAudioPool.releaseVoice(command.note, targets);
        if (typeof command.note === "number") {
          for (const [commandId, pending] of pendingVoiceAcks.entries()) {
            if (pending.note === command.note) {
              clearTimeout(pending.timeout);
              pendingVoiceAcks.delete(commandId);
            }
          }
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
      renderHints: Object.values(renderHintsByTarget)[0] ?? command.renderHints,
      renderHintsByTarget: Object.keys(renderHintsByTarget).length > 0 ? renderHintsByTarget : command.renderHintsByTarget,
      issuedAt: Date.now()
    };

    dispatchPhoneCommandToTargets(dispatched);
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
      renderHints: plan.renderHintsByTarget[targetHashedIds[0]],
      renderHintsByTarget: plan.renderHintsByTarget,
      issuedAt: Date.now()
    };
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
    broadcastToHarness({
      kind: "push_deck_event",
      data: payload,
      sentAt: Date.now()
    } satisfies WireEnvelope<PushDeckEventPayload>);
  }

  function forwardPushDeckEventWithCoalescing(payload: PushDeckEventPayload): void {
    const key =
      payload.controlKind === "macro"
        ? `${payload.sourceId}:macro:${payload.macro?.lane ?? 0}`
        : `${payload.sourceId}:ml:${payload.mlParam?.key ?? "unknown"}`;
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

  function broadcastCue(cue: CueCommand): void {
    const envelope = {
      kind: "cue",
      data: cue,
      sentAt: Date.now()
    } satisfies WireEnvelope<CueCommand>;

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
  const bank = normalizePushDeckBankControl(value.bank);
  const mlParam = normalizePushDeckMLParamControl(value.mlParam);

  if ((controlKind === "pad_down" || controlKind === "pad_up") && !pad) {
    return null;
  }
  if (controlKind === "macro" && !macro) {
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
  if (payload.key !== "phone_pad_echo_probability") {
    return undefined;
  }
  const raw = typeof payload.value === "number" && Number.isFinite(payload.value) ? payload.value : 0;
  return {
    key: "phone_pad_echo_probability",
    value: Math.max(0, Math.min(0.2, raw))
  };
};

const toPushDeckControlKind = (value: unknown): PushDeckEventPayload["controlKind"] => {
  if (
    value === "pad_down" ||
    value === "pad_up" ||
    value === "macro" ||
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
  fade: 0,
  textProbability: 0.5,
  strictLooseBlend: 0.5,
  visualVariance: 0.5,
  crowdSteeringLevel: 0,
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
    fade: clamp01Number(typeof input.fade === "number" ? input.fade : current.fade),
    textProbability,
    strictLooseBlend,
    visualVariance: clamp01Number(typeof input.visualVariance === "number" ? input.visualVariance : current.visualVariance),
    crowdSteeringLevel: clamp01Number(
      typeof input.crowdSteeringLevel === "number" ? input.crowdSteeringLevel : current.crowdSteeringLevel
    ),
    performerVector: normalizeVector((input.performerVector ?? current.performerVector) as Partial<ParamVector>),
    audienceVector: normalizeVector((input.audienceVector ?? current.audienceVector) as Partial<ParamVector>),
    textBlend
  };
};

const applyAudienceSteeringAndVariance = (
  base: ProgramProceduralState,
  audience: AudienceVectorPayload,
  audioFeatures: AudioFeaturePayload,
  pickResult: CrowdPickResultPayload | null
): ProgramProceduralState => {
  const crowdWeight = clamp01((audience.participantCount - 1) / 20);
  const steeringLevel = crowdWeight * 0.35;
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
      visualVariance: clamp01(base.visualVariance + centered.comp * steeringLevel * 1.1 + (audioFeatures.flux - 0.5) * 0.06)
    },
    base
  );

  const variancePressure = next.visualVariance * (0.55 + steeringLevel);
  if (variancePressure > 0.22) {
    const seed = stableHashToSeed(
      `${next.seed}:${next.epoch}:${Math.round(audioFeatures.flux * 100)}:${pickResult?.winnerOptionId ?? "none"}`
    );

    const transitions: TransitionMode[] = ["cut", "crossfade", "fade", "stutter"];
    const compositors: CompositorPreset[] = ["blend", "screen", "multiply", "mask", "pip", "stutter"];
    const splits: SplitLayout[] = ["none", "split-2", "split-3", "split-4", "pip"];

    next = normalizeProceduralState(
      {
        ...next,
        transitionMode: transitions[seed % transitions.length],
        compositorPreset: compositors[(seed >>> 2) % compositors.length],
        splitLayout: splits[(seed >>> 4) % splits.length]
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
