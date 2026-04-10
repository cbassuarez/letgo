import {
  type AudioFeaturePayload,
  type AudioOpsStatePayload,
  type AudienceVectorPayload,
  clamp01,
  type ColorIntentPayload,
  type CompositorMode,
  type CrowdPickVotePayload,
  type CueCommand,
  isCueCommand,
  type LightingStatePayload,
  normalizeVector,
  type ParamVector,
  type ParticipantVectorPayload,
  type PhoneAudioAckPayload,
  type PhoneAudioCommandPayload,
  type PhoneAudioPoolStatePayload,
  type SyncPacket,
  type TextScenePayload,
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
  | { kind: "text_scene"; data: Partial<TextScenePayload> & { cueId?: string } };

type DeviceInbound =
  | { kind: "sync"; data: SyncPacket }
  | { kind: "telemetry"; data: Record<string, unknown> }
  | { kind: "participant_vector"; data: Partial<ParticipantVectorPayload> & { vector?: Partial<ParamVector> } }
  | { kind: "zone_update"; data: { name: string; x: number; y: number; z?: number } }
  | { kind: "permissions"; data: { audio?: boolean; geolocation?: boolean; motion?: boolean } }
  | { kind: "ack"; data: { cueId: string; seenAt: number } }
  | { kind: "phone_audio_ack"; data: Partial<PhoneAudioAckPayload> }
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

  deps.crowdPickPulse.tick(0, Date.now());
  const initialPulse = deps.crowdPickPulse.snapshot();
  deps.audioOpsStateHub.setPickWindow(initialPulse.window);
  deps.audioOpsStateHub.setPickResult(initialPulse.result);

  const initialScene = deps.textSceneComposer.compose({
    cueId: "idle:0",
    vector: deps.show.snapshot().vector,
    audioFeatures: lastAudioFeatures,
    pickResult: initialPulse.result,
    pickEpoch: initialPulse.pickEpoch
  });
  deps.audioOpsStateHub.setTextScene(initialScene);

  wsApp.get("/ws/harness", { websocket: true }, (socket) => {
    harnessSockets.add(socket);
    logger.info("ws socket opened", { role: "harness" });
    pushInitialSnapshot(socket);

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
        composeAndBroadcastTextScene(false);
        return;
      }

      if (inbound.kind === "phone_audio_pool_state") {
        const pool = deps.phoneAudioPool.setGateState({
          gateArmed: booleanOrUndefined(inbound.data.gateArmed),
          gateCommitted: booleanOrUndefined(inbound.data.gateCommitted),
          quadRouteReady: booleanOrUndefined(inbound.data.quadRouteReady)
        });
        deps.audioOpsStateHub.setPhoneAudioPool(pool);
        broadcastPhoneAudioPoolState(pool);
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
        deps.audioOpsStateHub.setPhoneAudioPool(pool);
        broadcastPhoneAudioPoolState(pool);
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
    deps.audioOpsStateHub.setPhoneAudioPool(poolAfterConnect);
    broadcastPhoneAudioPoolState(poolAfterConnect);

    pushInitialSnapshot(socket);

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
      deps.audioOpsStateHub.setPhoneAudioPool(pool);
      broadcastPhoneAudioPoolState(pool);
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
        deps.audioOpsStateHub.setPhoneAudioPool(pool);
        broadcastPhoneAudioPoolState(pool);
        return;
      }

      if (inbound.kind === "zone_update") {
        await deps.sessions.patchZone(hashedId, inbound.data);
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
        composeAndBroadcastTextScene(false);
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
      pickEpoch: pulse.pickEpoch
    });
    deps.audioOpsStateHub.setTextScene(scene);
    broadcastTextScene(scene);
  }

  function pushInitialSnapshot(socket: WebSocket): void {
    send(socket, {
      kind: "show_snapshot",
      data: deps.show.snapshot(),
      sentAt: Date.now()
    } satisfies WireEnvelope);

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

    const ops = deps.audioOpsStateHub.snapshot();
    send(socket, {
      kind: "audio_features",
      data: ops.audioFeatures,
      sentAt: Date.now()
    } satisfies WireEnvelope<AudioFeaturePayload>);
    send(socket, {
      kind: "phone_audio_pool_state",
      data: ops.phoneAudioPool,
      sentAt: Date.now()
    } satisfies WireEnvelope<PhoneAudioPoolStatePayload>);
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

  function dispatchPhoneAudioCommand(command: PhoneAudioCommandPayload): PhoneAudioCommandPayload | null {
    let targets = command.targetHashedIds.filter((id) => deviceSockets.has(id));

    switch (command.kind) {
      case "note_on": {
        const note = typeof command.note === "number" ? command.note : 60;
        targets = deps.phoneAudioPool.allocateVoice(note, targets);
        break;
      }
      case "note_off": {
        targets = deps.phoneAudioPool.releaseVoice(command.note, targets);
        break;
      }
      case "stop_all": {
        const before = Object.keys(deps.phoneAudioPool.snapshot().activeVoices);
        deps.phoneAudioPool.releaseAll();
        targets = before;
        break;
      }
      case "sample_trigger":
      case "ambient_noise": {
        if (targets.length === 0) {
          targets = deps.phoneAudioPool.snapshot().availableDevices.slice(0, 1);
        }
        break;
      }
      default:
        break;
    }

    const dispatched: PhoneAudioCommandPayload = {
      ...command,
      targetHashedIds: targets,
      issuedAt: Date.now()
    };

    if (targets.length === 0) {
      return null;
    }

    broadcastToSpecificDevices(targets, {
      kind: "phone_audio_command",
      data: dispatched,
      sentAt: Date.now()
    } satisfies WireEnvelope<PhoneAudioCommandPayload>);
    broadcastToHarness({
      kind: "phone_audio_command",
      data: dispatched,
      sentAt: Date.now()
    } satisfies WireEnvelope<PhoneAudioCommandPayload>);

    return dispatched;
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
    broadcastToHarness(envelope);
  }

  function broadcastLightingState(state: LightingStatePayload): void {
    const envelope = {
      kind: "lighting_state",
      data: state,
      sentAt: Date.now()
    } satisfies WireEnvelope<LightingStatePayload>;

    broadcastToDevices(envelope);
    broadcastToHarness(envelope);
  }

  function broadcastAudioFeatures(features: AudioFeaturePayload): void {
    const envelope = {
      kind: "audio_features",
      data: features,
      sentAt: Date.now()
    } satisfies WireEnvelope<AudioFeaturePayload>;
    broadcastToDevices(envelope);
    broadcastToHarness(envelope);
  }

  function broadcastTextScene(scene: TextScenePayload): void {
    const envelope = {
      kind: "text_scene",
      data: scene,
      sentAt: Date.now()
    } satisfies WireEnvelope<TextScenePayload>;
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
    issuedAt: typeof value.issuedAt === "number" ? value.issuedAt : Date.now()
  };
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

const clampSigned = (value: number): number => Math.min(1, Math.max(-1, value));
