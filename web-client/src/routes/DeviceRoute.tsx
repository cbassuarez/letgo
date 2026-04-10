import {
  deterministicPick,
  stableHashToSeed,
  type CompositorMode,
  type ScriptCandidate
} from "@conductor/protocol";
import { motion } from "framer-motion";
import { useEffect, useMemo, useRef, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { DynamicOverlay } from "../components/DynamicOverlay";
import { FixedVideoLayer } from "../components/FixedVideoLayer";
import { PermissionGate } from "../components/PermissionGate";
import { useConductorSession } from "../hooks/useConductorSession";
import { useParticipantVector } from "../hooks/useParticipantVector";
import { isValidHashedId } from "../lib/identity";

const scriptBank: ScriptCandidate[] = [
  {
    id: "line-1",
    arc: "arc1",
    tags: ["arrival", "fear"],
    text: "The cyan night opened and each phone became a tuning fork.",
    weight: 0.85,
    cooldownMs: 15000,
    tone: "confessional"
  },
  {
    id: "line-2",
    arc: "arc2",
    tags: ["control", "breath"],
    text: "Every tilt reshaped the choir of screens into one shared breath.",
    weight: 0.72,
    cooldownMs: 12000,
    tone: "directive"
  },
  {
    id: "line-3",
    arc: "arc3",
    tags: ["release", "chorus"],
    text: "You are not watching the piece. You are one of its vectors.",
    weight: 0.9,
    cooldownMs: 20000,
    tone: "lyrical"
  }
];

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

const buildAutoZone = (hashedId: string): { name: string; x: number; y: number; z: number } => {
  const seed = stableHashToSeed(hashedId);
  const x = ((seed % 1000) + 1) / 1001;
  const y = (((seed >>> 10) % 1000) + 1) / 1001;
  return {
    name: "auto-field",
    x,
    y,
    z: 0.5
  };
};

export const DeviceRoute = (): JSX.Element => {
  const { hashedId = "" } = useParams();
  const capabilitiesSupported =
    typeof window !== "undefined" &&
    "WebSocket" in window &&
    "DeviceMotionEvent" in window &&
    "DeviceOrientationEvent" in window;
  const [permissionsDone, setPermissionsDone] = useState(false);
  const [permissions, setPermissions] = useState({
    audio: false,
    geolocation: false,
    motion: false
  });
  const [compositorMode, setCompositorMode] = useState<CompositorMode>("unsupported");
  const permissionsSentRef = useRef(false);
  const zoneSentRef = useRef(false);

  const session = useConductorSession(hashedId);
  const {
    sendPermissions,
    sendZoneUpdate,
    sendParticipantVector
  } = session;
  const participantVector = useParticipantVector(permissionsDone);
  const autoZone = useMemo(() => buildAutoZone(hashedId), [hashedId]);

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
    if (!permissionsDone || !session.connected || permissionsSentRef.current) {
      return;
    }
    sendPermissions(permissions);
    permissionsSentRef.current = true;
  }, [permissions, permissionsDone, sendPermissions, session.connected]);

  useEffect(() => {
    if (!permissionsDone || !session.connected || zoneSentRef.current) {
      return;
    }
    sendZoneUpdate(autoZone);
    zoneSentRef.current = true;
  }, [autoZone, permissionsDone, sendZoneUpdate, session.connected]);

  useEffect(() => {
    if (!permissionsDone || !engineRunning) {
      return;
    }

    let timer: number | null = null;
    const pushVector = (): void => {
      sendParticipantVector({
        vector: participantVector.vector,
        influence: participantVector.influence,
        compositorMode,
        updatedAt: Date.now()
      });
      timer = window.setTimeout(pushVector, participantVector.recommendedIntervalMs);
    };
    pushVector();

    return () => {
      if (timer !== null) {
        window.clearTimeout(timer);
      }
    };
  }, [
    compositorMode,
    engineRunning,
    participantVector.influence,
    participantVector.recommendedIntervalMs,
    participantVector.vector,
    permissionsDone,
    sendParticipantVector
  ]);

  if (!isValidHashedId(hashedId)) {
    return (
      <main className="cyanotype-shell min-h-dvh px-6 py-16">
        <section className="cyanotype-panel mx-auto max-w-2xl p-10">
          <p className="cyanotype-kicker">LOCKOUT</p>
          <h1 className="mt-4 font-display text-4xl">Participant Link Not Valid</h1>
          <p className="mt-4 text-cyanotype-100/78">
            This entrance key is not in the performance field. Scan your assigned NFC card to join.
          </p>
          <Link to="/" className="cyanotype-cta mt-8 inline-flex">
            Return To Briefing
          </Link>
        </section>
      </main>
    );
  }

  if (!capabilitiesSupported) {
    return (
      <main className="cyanotype-shell min-h-dvh px-6 py-16">
        <section className="cyanotype-panel mx-auto max-w-2xl p-10">
          <p className="cyanotype-kicker">LOCKOUT</p>
          <h1 className="mt-4 font-display text-4xl">Device Capabilities Not Supported</h1>
          <p className="mt-4 text-cyanotype-100/78">
            This browser cannot provide the motion/real-time APIs required for live participation.
            Open the same participant link in a modern mobile Chromium browser.
          </p>
          <Link to="/" className="cyanotype-cta mt-8 inline-flex">
            Return To Briefing
          </Link>
        </section>
      </main>
    );
  }

  return (
    <main className="cyanotype-shell relative min-h-dvh overflow-hidden text-cyanotype-050">
      <div className="cyanotype-atmosphere absolute inset-0" />

      {!permissionsDone ? (
        <PermissionGate
          onDone={(granted) => {
            permissionsSentRef.current = false;
            zoneSentRef.current = false;
            setPermissions(granted);
            setPermissionsDone(true);
          }}
        />
      ) : null}

      {permissionsDone ? (
        <>
          <FixedVideoLayer cue={session.cue} logicalNow={session.logicalNow} enabled={showFixed} />
          <DynamicOverlay
            vector={session.vector}
            line={seededLine}
            enabled={showDynamic}
            influence={participantVector.influence}
            onCompositorModeChange={setCompositorMode}
          />
          {!engineRunning || !session.connected ? (
            <motion.section
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              className="cyanotype-standby absolute bottom-8 left-1/2 w-[min(94vw,760px)] -translate-x-1/2 rounded-3xl p-6 sm:p-8"
            >
              <p className="cyanotype-kicker">{session.connected ? "STANDBY" : "RECONNECTING"}</p>
              <h2 className="mt-3 font-display text-3xl sm:text-4xl">
                {session.connected
                  ? "This phone is armed and ready."
                  : "The field link is recovering."}
              </h2>
              <p className="mt-3 max-w-2xl text-sm leading-relaxed text-cyanotype-100/80 sm:text-base">
                {session.connected
                  ? "Hold your device naturally. Participation is now automatic; no manual position tuning is required."
                  : "Stay on this screen. Your participant key and logbook access remain active while the link retries."}
              </p>
            </motion.section>
          ) : null}

          <motion.aside
            initial={{ opacity: 0, y: -12 }}
            animate={{ opacity: 1, y: 0 }}
            className="cyanotype-panel absolute left-4 top-4 w-[min(90vw,340px)] px-4 py-3 text-[11px] uppercase tracking-[0.16em] text-cyanotype-100/82"
          >
            <p>{session.connected ? "Live Link" : "Field Reconnect"}</p>
            <p>Link {session.linkState}</p>
            {session.retryInMs !== null ? <p>Retry {(session.retryInMs / 1000).toFixed(1)}s</p> : null}
            <p>Compositor {compositorMode}</p>
            <p>Influence {(participantVector.influence * 100).toFixed(0)}%</p>
            <p>Audience {session.audienceVector.participantCount}</p>
            <p>Drift {session.driftMs.toFixed(1)}ms</p>
            <p>{session.fallbackActive ? "Fallback" : "Synced"}</p>
            {session.fallbackActive ? <p>FallbackAge {(session.fallbackAgeMs / 1000).toFixed(1)}s</p> : null}
            <p>Engine {engineRunning ? "ON" : "OFF"}</p>
            <p>Mode {outputMode}</p>
            <Link to={`/${hashedId}/logbook`} className="mt-3 inline-flex text-cyanotype-000 underline">
              Sign Digital Logbook
            </Link>
          </motion.aside>
        </>
      ) : null}
    </main>
  );
};
