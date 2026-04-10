import {
  type CueCommand,
  isCueCommand,
  type ParamVector,
  type SyncPacket,
  type WireEnvelope
} from "@conductor/protocol";
import type { FastifyInstance } from "fastify";
import type { WebSocket } from "ws";
import type { AppConfig } from "../config";
import { IdentityService } from "../services/identityService";
import { ReplayService } from "../services/replayService";
import { ShowOrchestrator } from "../services/showOrchestrator";
import { SyncService } from "../services/syncService";
import type { SessionStore } from "../stores/sessionStore";
import { logger } from "../utils/logger";

interface WsDependencies {
  config: AppConfig;
  identityService: IdentityService;
  replayService: ReplayService;
  show: ShowOrchestrator;
  sync: SyncService;
  sessions: SessionStore;
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
  | { kind: "replay"; data: { action: "latest" | "freeze"; centerTimestamp?: number } };

type DeviceInbound =
  | { kind: "sync"; data: SyncPacket }
  | { kind: "telemetry"; data: Record<string, unknown> }
  | { kind: "zone_update"; data: { name: string; x: number; y: number; z?: number } }
  | { kind: "permissions"; data: { audio?: boolean; geolocation?: boolean; motion?: boolean } }
  | { kind: "ack"; data: { cueId: string; seenAt: number } };

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
  const wsApp = app as unknown as {
    get: (
      path: string,
      opts: { websocket: true },
      handler: (socket: WebSocket, req: { params: { hashedId?: string } }) => void | Promise<void>
    ) => void;
  };

  wsApp.get("/ws/harness", { websocket: true }, (socket) => {
    harnessSockets.add(socket);

    send(socket, {
      kind: "show_snapshot",
      data: deps.show.snapshot(),
      sentAt: Date.now()
    } satisfies WireEnvelope);

    socket.on("close", () => {
      harnessSockets.delete(socket);
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

      const existing = await deps.sessions.get(hashedId);
      if (!existing) {
        await deps.sessions.upsert(deps.identityService.profileFromHashedId(hashedId));
      }

      send(socket, {
        kind: "show_snapshot",
        data: deps.show.snapshot(),
        sentAt: Date.now()
      } satisfies WireEnvelope);

      socket.on("close", () => {
        deviceSockets.delete(hashedId);
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
          const profile = await deps.sessions.get(hashedId);
          if (profile) {
            await deps.sessions.upsert({
              ...profile,
              permissions: {
                ...profile.permissions,
                ...inbound.data
              }
            });
          }
          return;
        }

        if (inbound.kind === "zone_update") {
          await deps.sessions.patchZone(hashedId, inbound.data);
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

  function broadcastCue(cue: CueCommand): void {
    const envelope = {
      kind: "cue",
      data: cue,
      sentAt: Date.now()
    } satisfies WireEnvelope<CueCommand>;

    broadcastToDevices(envelope);
    for (const harnessSocket of harnessSockets) {
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
};
