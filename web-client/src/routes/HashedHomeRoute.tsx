import { motion, useReducedMotion } from "framer-motion";
import { type CSSProperties, useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { FixedVideoLayer } from "../components/FixedVideoLayer";
import { useConductorSession } from "../hooks/useConductorSession";
import { fetchLogbookFeed } from "../lib/api";
import type { PublicLogbookEntry } from "../types/api";

const fadeConfig = (reducedMotion: boolean, delay = 0): Record<string, unknown> => {
  if (reducedMotion) {
    return {
      initial: false,
      animate: { opacity: 1 }
    };
  }

  return {
    initial: { opacity: 0, y: 18 },
    animate: { opacity: 1, y: 0 },
    transition: {
      delay,
      duration: 0.82,
      ease: [0.22, 1, 0.36, 1]
    }
  };
};

const normalizeStreamRef = (value: unknown): string | null => {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
};

const parseMapRecord = (value: unknown): Record<string, unknown> | null => {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  if (typeof value === "string") {
    try {
      return parseMapRecord(JSON.parse(value));
    } catch {
      return null;
    }
  }
  return null;
};

const resolveInterstitialSource = (payload: Record<string, unknown>): string | null => {
  const direct = normalizeStreamRef(payload.showStreamInterstitial);
  if (direct) {
    return direct;
  }
  const map = parseMapRecord(payload.showStreamMap);
  if (!map) {
    return null;
  }
  return normalizeStreamRef(map.interstitial);
};

const formatRelativeTime = (timestamp: number, now: number): string => {
  const deltaMs = Math.max(0, now - timestamp);
  const minutes = Math.floor(deltaMs / 60_000);
  if (minutes < 1) {
    return "Just now";
  }
  if (minutes < 60) {
    return `${minutes} min ago`;
  }
  const hours = Math.floor(minutes / 60);
  if (hours < 24) {
    return `${hours} hr ago`;
  }
  const days = Math.floor(hours / 24);
  return `${days} day${days === 1 ? "" : "s"} ago`;
};

export const HashedHomeRoute = (): JSX.Element => {
  const { hashedId = "" } = useParams();
  const reducedMotion = useReducedMotion() ?? false;
  const session = useConductorSession(hashedId);
  const [entries, setEntries] = useState<PublicLogbookEntry[]>([]);
  const [fetchedAt, setFetchedAt] = useState<number>(() => Date.now());

  useEffect(() => {
    let active = true;
    fetchLogbookFeed()
      .then((response) => {
        if (!active) {
          return;
        }
        setEntries(response.entries.slice(0, 4));
        setFetchedAt(Date.now());
      })
      .catch(() => {
        // Quietly skip the ambient strip when the feed is unavailable.
      });
    return () => {
      active = false;
    };
  }, []);

  const cuePayload = (session.cue?.payload ?? {}) as Record<string, unknown>;
  const interstitialSource = resolveInterstitialSource(cuePayload);

  const inferredEngineFromAudioPath =
    session.phoneAudioPoolState.quadRouteReady ||
    session.phoneAudioPoolState.gateArmed ||
    session.phoneAudioPoolState.gateCommitted;
  const explicitEngineRunning =
    cuePayload.engineRunning === true || cuePayload.engineRunning === "true";
  const showStateRunning =
    session.cue !== null && session.cue.showState !== "idle";
  const engineRunning =
    explicitEngineRunning || inferredEngineFromAudioPath || showStateRunning;
  const linkOnline = session.connected && session.linkState === "online";

  const audienceCount = session.audienceVector.participantCount;
  const hueHex = session.lightingState.targetColor.hex || "#2f5f8e";

  const headline = engineRunning
    ? "The film is open right now. Come in."
    : "I keep this film open. Right now it is held.";
  const flourish = engineRunning
    ? "Stay and watch the pressure hold."
    : "Waiting for pressure.";
  const statusLabel = engineRunning
    ? `Field Open · ${audienceCount} ${audienceCount === 1 ? "witness" : "witnesses"}`
    : linkOnline
      ? "Field Held"
      : "Field Reconnecting";

  return (
    <section
      className="home-stage relative mx-auto mt-6 w-full max-w-6xl pb-16 sm:mt-10 sm:pb-24"
      data-testid="home-stage"
      data-engine-state={engineRunning ? "on" : "off"}
    >
      {interstitialSource ? (
        <div className="home-plate" aria-hidden="true">
          <FixedVideoLayer
            cue={session.cue}
            logicalNow={session.logicalNow}
            enabled
            forcedScene="interstitial"
            forcedSource={interstitialSource}
          />
        </div>
      ) : null}

      <div
        className={`home-hue-wash ${reducedMotion ? "is-still" : ""}`}
        aria-hidden="true"
        style={{ "--home-hue": hueHex } as CSSProperties}
      />

      <div className="home-stage-content">
        <motion.p
          {...fadeConfig(reducedMotion, 0.08)}
          className="participant-kicker home-status"
          data-testid="home-status"
        >
          {statusLabel}
        </motion.p>

        <motion.h1
          {...fadeConfig(reducedMotion, 0.16)}
          className="participant-headline home-invocation mt-5 max-w-5xl text-[2.4rem] leading-[0.9] text-participant-cream sm:text-[4.4rem]"
          data-testid="home-invocation"
        >
          {headline}
        </motion.h1>

        <motion.p
          initial={reducedMotion ? false : { opacity: 0.36 }}
          animate={
            reducedMotion
              ? { opacity: 1 }
              : {
                  opacity: [0.38, 1, 0.38],
                  x: [0, 12, 0]
                }
          }
          transition={
            reducedMotion
              ? { duration: 0 }
              : {
                  duration: 9.6,
                  repeat: Infinity,
                  ease: "easeInOut"
                }
          }
          className="participant-script home-flourish mt-8 max-w-4xl text-[2.1rem] leading-[1.05] text-participant-blush sm:text-[3.4rem]"
        >
          {flourish}
        </motion.p>

        <motion.div
          {...fadeConfig(reducedMotion, 0.28)}
          className="home-gesture mt-10 flex flex-wrap items-center gap-5 border-t border-participant-smoke/25 pt-6"
        >
          <Link
            to={`/${hashedId}/live`}
            className="participant-enter-link"
            data-testid="home-enter-link"
          >
            Enter Film
          </Link>
          <div className="home-gesture-secondary">
            <Link to={`/${hashedId}/about`} className="home-secondary-link">
              About
            </Link>
            <span className="home-secondary-divider" aria-hidden="true">
              ·
            </span>
            <Link to={`/${hashedId}/logbook`} className="home-secondary-link">
              Logbook
            </Link>
          </div>
        </motion.div>
      </div>

      {entries.length > 0 ? (
        <section
          className="home-ambient-logbook mt-20 border-t border-participant-smoke/20 pt-8 sm:mt-28"
          aria-label="Recent witness entries"
          data-testid="home-ambient-logbook"
        >
          <motion.p
            {...fadeConfig(reducedMotion, 0.36)}
            className="participant-kicker"
          >
            Witnesses · Recently
          </motion.p>
          <ul className="home-logbook-list mt-6 grid gap-8">
            {entries.map((entry, index) => (
              <motion.li
                key={`${entry.participantTag}-${entry.updatedAt}`}
                {...fadeConfig(reducedMotion, 0.42 + index * 0.06)}
                className="home-logbook-quote"
              >
                <Link to="/logbook" className="home-logbook-quote-link">
                  <p className="home-logbook-message">{entry.message}</p>
                  <p className="home-logbook-attribution">
                    <span className="home-logbook-signer">{entry.signer}</span>
                    <span className="home-logbook-meta">
                      {entry.participantTag} · {formatRelativeTime(entry.updatedAt, fetchedAt)}
                    </span>
                  </p>
                </Link>
              </motion.li>
            ))}
          </ul>
        </section>
      ) : null}
    </section>
  );
};
