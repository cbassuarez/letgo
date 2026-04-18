import { motion, useReducedMotion } from "framer-motion";
import { useEffect, useMemo, useRef, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { ParticleMesh } from "../components/ParticleMesh";
import { useConductorSession } from "../hooks/useConductorSession";
import { fetchLogbookFeed } from "../lib/api";
import type { PublicLogbookEntry } from "../types/api";

const BASE_PHRASES = [
  "LET GO",
  "LETTING GO",
  "WITNESS",
  "PRESSURE HELD IN PUBLIC"
];

const OFF_PHRASES = [...BASE_PHRASES, "FIELD HELD"];
const ON_PHRASES = [...BASE_PHRASES, "THE FILM IS OPEN", "COME IN"];

const SPRITE_POSITIONS = [
  { top: "18%", left: "58%" },
  { top: "42%", left: "12%" },
  { top: "62%", left: "64%" },
  { top: "28%", left: "34%" },
  { top: "74%", left: "22%" }
];

export const HashedHomeRoute = (): JSX.Element => {
  const { hashedId = "" } = useParams();
  const reducedMotion = useReducedMotion() ?? false;
  const session = useConductorSession(hashedId);
  const [moreOpen, setMoreOpen] = useState(false);
  const [logbookEntries, setLogbookEntries] = useState<PublicLogbookEntry[]>([]);
  const moreRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    let active = true;
    fetchLogbookFeed()
      .then((response) => {
        if (active) setLogbookEntries(response.entries.slice(0, 5));
      })
      .catch(() => {});
    return () => { active = false; };
  }, []);

  useEffect(() => {
    let active = true;
    fetchLogbookFeed()
      .then((response) => {
        if (active) setLogbookEntries(response.entries.slice(0, 5));
      })
      .catch(() => {});
    return () => { active = false; };
  }, []);

  const cuePayload = (session.cue?.payload ?? {}) as Record<string, unknown>;
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

  const phrases = useMemo(
    () => (engineRunning ? ON_PHRASES : OFF_PHRASES),
    [engineRunning]
  );

  const pressure = engineRunning ? 0.78 : 0.42;
  const density = useMemo(() => {
    const audienceBoost = Math.min(1, audienceCount / 40) * 0.35;
    return 0.85 + audienceBoost;
  }, [audienceCount]);

  const statusLabel = engineRunning
    ? audienceCount === 0
      ? "Field Open"
      : `Field Open · ${audienceCount} ${audienceCount === 1 ? "witness" : "witnesses"}`
    : linkOnline
      ? "Field Held"
      : "Field Reconnecting";

  useEffect(() => {
    if (!moreOpen) return;
    const handlePointer = (event: MouseEvent): void => {
      if (moreRef.current && !moreRef.current.contains(event.target as Node)) {
        setMoreOpen(false);
      }
    };
    const handleKey = (event: KeyboardEvent): void => {
      if (event.key === "Escape") setMoreOpen(false);
    };
    window.addEventListener("mousedown", handlePointer);
    window.addEventListener("keydown", handleKey);
    return () => {
      window.removeEventListener("mousedown", handlePointer);
      window.removeEventListener("keydown", handleKey);
    };
  }, [moreOpen]);

  return (
    <section
      className="home-landing"
      data-testid="home-stage"
      data-engine-state={engineRunning ? "on" : "off"}
    >
      <ParticleMesh
        className="home-mesh"
        phrases={phrases}
        phraseDurationMs={3400}
        pressure={pressure}
        density={density}
        reducedMotion={reducedMotion}
      />

      {logbookEntries.length > 0 ? (
        <div className="home-sprites" aria-label="Recent reflections">
          {logbookEntries.map((entry, i) => {
            const pos = SPRITE_POSITIONS[i % SPRITE_POSITIONS.length];
            const msg = entry.message.length > 64
              ? entry.message.slice(0, 61).trimEnd() + "\u2026"
              : entry.message;
            return (
              <div
                key={`${entry.participantTag}-${entry.updatedAt}`}
                className={`home-sprite ${reducedMotion ? "is-still" : ""}`}
                style={{
                  top: pos.top,
                  left: pos.left,
                  animationDelay: `${i * 4.6}s`
                }}
              >
                <p className="home-sprite-message">&ldquo;{msg}&rdquo;</p>
                <p className="home-sprite-signer">&mdash; {entry.signer}</p>
              </div>
            );
          })}
        </div>
      ) : null}

      <div className="home-landing-frame">
        <motion.p
          initial={reducedMotion ? false : { opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          transition={reducedMotion ? { duration: 0 } : { duration: 0.82, ease: [0.22, 1, 0.36, 1] }}
          className="participant-kicker home-status"
          data-testid="home-status"
        >
          {statusLabel}
        </motion.p>

        <motion.div
          initial={reducedMotion ? false : { opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={reducedMotion ? { duration: 0 } : { duration: 0.9, delay: 0.12, ease: [0.22, 1, 0.36, 1] }}
          className="home-actions"
        >
          <Link
            to={`/${hashedId}/live`}
            className="participant-enter-link home-cta-primary"
            data-testid="home-enter-link"
          >
            Enter Film
          </Link>

          <div className="home-more" ref={moreRef}>
            <button
              type="button"
              className="home-cta-secondary"
              aria-haspopup="menu"
              aria-expanded={moreOpen}
              aria-controls="home-more-menu"
              onClick={() => setMoreOpen((current) => !current)}
              data-testid="home-more-button"
            >
              {moreOpen ? "Close" : "More"}
              <span aria-hidden="true" className="home-more-caret">
                {moreOpen ? "−" : "+"}
              </span>
            </button>
            {moreOpen ? (
              <motion.ul
                id="home-more-menu"
                role="menu"
                initial={reducedMotion ? false : { opacity: 0, y: 6 }}
                animate={{ opacity: 1, y: 0 }}
                transition={reducedMotion ? { duration: 0 } : { duration: 0.22 }}
                className="home-more-menu"
                data-testid="home-more-menu"
              >
                <li role="none">
                  <Link
                    to={`/${hashedId}/about`}
                    role="menuitem"
                    className="home-more-item"
                    onClick={() => setMoreOpen(false)}
                  >
                    About
                  </Link>
                </li>
                <li role="none">
                  <Link
                    to={`/${hashedId}/logbook`}
                    role="menuitem"
                    className="home-more-item"
                    onClick={() => setMoreOpen(false)}
                  >
                    Logbook
                  </Link>
                </li>
                <li role="none">
                  <Link
                    to={`/${hashedId}/accessibility`}
                    role="menuitem"
                    className="home-more-item"
                    onClick={() => setMoreOpen(false)}
                  >
                    Accessibility
                  </Link>
                </li>
              </motion.ul>
            ) : null}
          </div>
        </motion.div>
      </div>
    </section>
  );
};
