import { useEffect, useMemo, useState } from "react";
import { useParams } from "react-router-dom";
import { deterministicPick, stableHashToSeed, type ScriptCandidate } from "@conductor/protocol";
import { DynamicOverlay } from "../components/DynamicOverlay";
import { FixedVideoLayer } from "../components/FixedVideoLayer";
import { PermissionGate } from "../components/PermissionGate";
import { ZoneRefine } from "../components/ZoneRefine";
import { useConductorSession } from "../hooks/useConductorSession";
import { createSessionSocket, sendEnvelope } from "../lib/wsClient";

const scriptBank: ScriptCandidate[] = [
  {
    id: "line-1",
    arc: "arc1",
    tags: ["arrival", "fear"],
    text: "I was sure letting go meant disappearing. It did not.",
    weight: 0.8,
    cooldownMs: 15000,
    tone: "confessional"
  },
  {
    id: "line-2",
    arc: "arc2",
    tags: ["control", "breath"],
    text: "Control was never silence. It was listening in public.",
    weight: 0.6,
    cooldownMs: 12000,
    tone: "directive"
  },
  {
    id: "line-3",
    arc: "arc3",
    tags: ["release", "choir"],
    text: "When we released it together, the room learned our names.",
    weight: 0.9,
    cooldownMs: 20000,
    tone: "lyrical"
  }
];

const hashedPattern = /^[a-f0-9]{32}$/;

const boolFromPayload = (value: unknown, fallback = false): boolean => {
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

export const DeviceRoute = (): JSX.Element => {
  const { hashedId = "" } = useParams();
  const [permissionsDone, setPermissionsDone] = useState(false);
  const [permissions, setPermissions] = useState({
    audio: false,
    geolocation: false,
    motion: false
  });
  const [zoneDone, setZoneDone] = useState(false);

  const session = useConductorSession(hashedId);

  const seededLine = useMemo(() => {
    const seed = stableHashToSeed(hashedId);
    return deterministicPick(seed, scriptBank).text;
  }, [hashedId]);

  const cuePayload = (session.cue?.payload ?? {}) as Record<string, unknown>;
  const defaultDynamicEnabled = session.cue?.showState === "main";
  const engineRunning = boolFromPayload(cuePayload.engineRunning, false);
  const showFixed = engineRunning && boolFromPayload(cuePayload.showFixed, false);
  const showDynamic = engineRunning && boolFromPayload(cuePayload.showDynamic, defaultDynamicEnabled);
  const outputMode = typeof cuePayload.outputMode === "string" ? cuePayload.outputMode : "legacy";

  useEffect(() => {
    if (!permissionsDone || !hashedPattern.test(hashedId)) {
      return;
    }

    const socket = createSessionSocket(hashedId);
    const onOpen = () => {
      sendEnvelope(socket, "permissions", {
        audio: permissions.audio,
        geolocation: permissions.geolocation,
        motion: permissions.motion
      });
    };

    socket.addEventListener("open", onOpen);
    return () => {
      socket.removeEventListener("open", onOpen);
      socket.close();
    };
  }, [hashedId, permissions, permissionsDone]);

  if (!hashedPattern.test(hashedId)) {
    return (
      <main className="min-h-dvh px-6 py-12">
        <h1 className="font-display text-3xl">Invalid Participant Link</h1>
        <p className="mt-3 max-w-lg text-sm text-fog/80">
          This URL is not a valid production identity. Please scan your assigned NFC tag.
        </p>
      </main>
    );
  }

  return (
    <main className="relative min-h-dvh overflow-hidden bg-ink text-fog">
      <div className="absolute inset-0 bg-[radial-gradient(circle_at_20%_20%,rgba(217,95,53,0.22),transparent_45%),radial-gradient(circle_at_80%_80%,rgba(46,143,88,0.25),transparent_40%)]" />

      {!permissionsDone ? (
        <PermissionGate
          onDone={(granted) => {
            setPermissions(granted);
            setPermissionsDone(true);
          }}
        />
      ) : null}

      {permissionsDone && !zoneDone ? (
        <ZoneRefine
          onSubmit={(zone) => {
            const socket = createSessionSocket(hashedId);
            socket.addEventListener("open", () => {
              sendEnvelope(socket, "zone_update", zone);
              setZoneDone(true);
              socket.close();
            });
          }}
        />
      ) : null}

      {permissionsDone && zoneDone ? (
        <>
          <FixedVideoLayer cue={session.cue} logicalNow={session.logicalNow} enabled={showFixed} />
          <DynamicOverlay vector={session.vector} line={seededLine} enabled={showDynamic} />

          <aside className="absolute left-4 top-4 rounded-xl border border-fog/20 bg-ink/65 px-3 py-2 text-[11px] uppercase tracking-[0.16em] text-fog/80 backdrop-blur">
            <p>{session.connected ? "Live" : "Offline"}</p>
            <p>Link {session.linkState}</p>
            {session.retryInMs !== null ? <p>Retry {(session.retryInMs / 1000).toFixed(1)}s</p> : null}
            <p>Drift {session.driftMs.toFixed(1)}ms</p>
            <p>{session.fallbackActive ? "Fallback" : "Synced"}</p>
            {session.fallbackActive ? <p>FallbackAge {(session.fallbackAgeMs / 1000).toFixed(1)}s</p> : null}
            <p>Engine {engineRunning ? "ON" : "OFF"}</p>
            <p>Mode {outputMode}</p>
          </aside>
        </>
      ) : null}
    </main>
  );
};
