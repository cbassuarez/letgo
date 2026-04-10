import {
  normalizeVector,
  type CueCommand,
  type ParamVector,
  type SyncPacket,
  type WireEnvelope
} from "@conductor/protocol";
import { useEffect, useMemo, useRef, useState } from "react";
import { readFallbackSnapshot, saveFallbackSnapshot } from "../lib/fallbackStore";
import { SyncClock } from "../lib/syncClock";
import { createSessionSocket, sendEnvelope } from "../lib/wsClient";

interface SessionState {
  cue: CueCommand | null;
  vector: ParamVector;
  driftMs: number;
  connected: boolean;
  fallbackActive: boolean;
  logicalNow: number;
}

const defaultVector = normalizeVector({});

export const useConductorSession = (hashedId: string): SessionState => {
  const fallback = useMemo(() => readFallbackSnapshot(hashedId), [hashedId]);

  const [cue, setCue] = useState<CueCommand | null>(fallback?.cue ?? null);
  const [vector, setVector] = useState<ParamVector>(fallback?.vector ?? defaultVector);
  const [connected, setConnected] = useState(false);
  const [fallbackActive, setFallbackActive] = useState(Boolean(fallback));
  const [logicalNow, setLogicalNow] = useState(cue?.logicalTime ?? 0);
  const clockRef = useRef(new SyncClock());
  const cueRef = useRef<CueCommand | null>(fallback?.cue ?? null);
  const vectorRef = useRef<ParamVector>(fallback?.vector ?? defaultVector);
  const cueReceivedAtRef = useRef<number>(Date.now());

  useEffect(() => {
    const socket = createSessionSocket(hashedId);

    const logicalTimer = window.setInterval(() => {
      if (cueRef.current) {
        const elapsed = Date.now() - cueReceivedAtRef.current;
        setLogicalNow(Math.max(cueRef.current.logicalTime, cueRef.current.logicalTime + elapsed));
      }
    }, 200);

    socket.addEventListener("open", () => {
      setConnected(true);
      setFallbackActive(false);
    });

    socket.addEventListener("close", () => {
      setConnected(false);
      setFallbackActive(true);
      if (cueRef.current) {
        saveFallbackSnapshot(hashedId, { cue: cueRef.current, vector: vectorRef.current });
      }
    });

    socket.addEventListener("message", (event) => {
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

    return () => {
      window.clearInterval(logicalTimer);
      socket.close();
    };
  }, [hashedId]);

  return {
    cue,
    vector,
    driftMs: clockRef.current.getDrift(),
    connected,
    fallbackActive,
    logicalNow
  };
};
