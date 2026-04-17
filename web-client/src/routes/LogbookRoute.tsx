import { motion, useReducedMotion } from "framer-motion";
import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { fetchLogbookFeed } from "../lib/api";
import type { PublicLogbookEntry } from "../types/api";

const fadeConfig = (reducedMotion: boolean, delay = 0): Record<string, unknown> => {
  if (reducedMotion) {
    return { initial: false, animate: { opacity: 1 } };
  }
  return {
    initial: { opacity: 0, y: 14 },
    animate: { opacity: 1, y: 0 },
    transition: { delay, duration: 0.72, ease: [0.22, 1, 0.36, 1] }
  };
};

const formatRelativeTime = (timestamp: number): string => {
  const delta = Math.max(0, Date.now() - timestamp);
  const minutes = Math.floor(delta / 60_000);
  if (minutes < 1) return "Just now";
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
};

export const LogbookRoute = (): JSX.Element => {
  const reducedMotion = useReducedMotion() ?? false;
  const [entries, setEntries] = useState<PublicLogbookEntry[]>([]);
  const [nextCursor, setNextCursor] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    setLoading(true);
    setError(null);
    fetchLogbookFeed()
      .then((response) => {
        if (!active) return;
        setEntries(response.entries);
        setNextCursor(response.nextCursor);
      })
      .catch((reason) => {
        if (!active) return;
        setError(reason instanceof Error ? reason.message : "feed_unavailable");
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => { active = false; };
  }, []);

  const loadMore = async (): Promise<void> => {
    if (!nextCursor || loadingMore) return;
    setLoadingMore(true);
    setError(null);
    try {
      const response = await fetchLogbookFeed(nextCursor);
      setEntries((current) => [...current, ...response.entries]);
      setNextCursor(response.nextCursor);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "feed_unavailable");
    } finally {
      setLoadingMore(false);
    }
  };

  return (
    <main className="cyanotype-shell min-h-dvh px-5 py-10 text-cyanotype-050 sm:px-8">
      <div className="cyanotype-atmosphere absolute inset-0 -z-10" />

      <header className="mx-auto max-w-4xl">
        <motion.div {...fadeConfig(reducedMotion, 0.04)}>
          <Link to="/" className="logbook-back-link" aria-label="Return to briefing">
            <span aria-hidden="true">←</span>
            <span>Briefing</span>
          </Link>
        </motion.div>
        <motion.p {...fadeConfig(reducedMotion, 0.08)} className="cyanotype-kicker mt-5">
          Public Wall
        </motion.p>
        <motion.h1
          {...fadeConfig(reducedMotion, 0.14)}
          className="mt-3 text-4xl font-semibold leading-[0.95] text-cyanotype-050 sm:text-6xl"
        >
          Digital Logbook
        </motion.h1>
        <motion.p {...fadeConfig(reducedMotion, 0.2)} className="mt-4 max-w-2xl text-sm leading-relaxed text-cyanotype-100/76 sm:text-base">
          Collected reflections from participants across rehearsals and live nights.
        </motion.p>
      </header>

      <section className="mx-auto mt-14 max-w-4xl" aria-label="Logbook entries">
        {loading ? <p className="text-cyanotype-100/52 text-sm">Loading reflections…</p> : null}
        {error ? <p className="text-sm text-red-300/80">{error}</p> : null}
        {!loading && !error && entries.length === 0 ? (
          <p className="text-cyanotype-100/60 text-sm">The wall is empty. Reflections appear once participants begin writing.</p>
        ) : null}

        <ul className="logbook-wall">
          {entries.map((entry, index) => (
            <motion.li
              key={`${entry.participantTag}:${entry.updatedAt}:${index}`}
              {...fadeConfig(reducedMotion, Math.min(0.4, 0.08 + index * 0.03))}
              className="logbook-entry"
            >
              <blockquote className="logbook-entry-message">
                {entry.message}
              </blockquote>
              <footer className="logbook-entry-footer">
                <cite className="logbook-entry-signer">{entry.signer}</cite>
                <span className="logbook-entry-meta">
                  {entry.participantTag} · {formatRelativeTime(entry.updatedAt)}
                </span>
              </footer>
            </motion.li>
          ))}
        </ul>

        {nextCursor ? (
          <motion.div {...fadeConfig(reducedMotion, 0.3)} className="mt-10">
            <button className="cyanotype-cta" onClick={() => void loadMore()} disabled={loadingMore}>
              {loadingMore ? "Loading…" : "Load More Reflections"}
            </button>
          </motion.div>
        ) : null}
      </section>
    </main>
  );
};
