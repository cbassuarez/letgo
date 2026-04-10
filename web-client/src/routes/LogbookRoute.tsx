import { motion } from "framer-motion";
import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { fetchLogbookFeed } from "../lib/api";
import type { PublicLogbookEntry } from "../types/api";

export const LogbookRoute = (): JSX.Element => {
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
        if (!active) {
          return;
        }
        setEntries(response.entries);
        setNextCursor(response.nextCursor);
      })
      .catch((reason) => {
        if (!active) {
          return;
        }
        setError(reason instanceof Error ? reason.message : "feed_unavailable");
      })
      .finally(() => {
        if (active) {
          setLoading(false);
        }
      });

    return () => {
      active = false;
    };
  }, []);

  const loadMore = async (): Promise<void> => {
    if (!nextCursor || loadingMore) {
      return;
    }
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

      <section className="mx-auto max-w-6xl">
        <p className="cyanotype-kicker">PUBLIC WALL</p>
        <h1 className="mt-4 text-5xl font-semibold leading-[0.95] sm:text-7xl">Digital Logbook</h1>
        <p className="mt-4 max-w-3xl text-cyanotype-100/80">
          Participant signatures collected during rehearsals and live nights. The wall is public; signing
          requires an active participant key.
        </p>
        <motion.p
          initial={{ opacity: 0.3 }}
          animate={{ opacity: [0.28, 0.85, 0.28], x: [0, 8, 0] }}
          transition={{ duration: 8, repeat: Infinity, ease: "easeInOut" }}
          className="font-display mt-8 text-2xl text-cyanotype-000/86 sm:text-4xl"
        >
          A public archive of private thresholds.
        </motion.p>
        <Link to="/" className="cyanotype-cta mt-8 inline-flex">
          Back to Piece Briefing
        </Link>
      </section>

      <section className="mx-auto mt-12 max-w-6xl">
        {loading ? <p className="text-cyanotype-100/60">Loading signatures…</p> : null}
        {error ? <p className="text-red-300">Feed unavailable: {error}</p> : null}
        {!loading && !error && entries.length === 0 ? (
          <p className="text-cyanotype-100/70">No signatures yet. The wall opens once participants begin signing.</p>
        ) : null}

        <div className="mt-4">
          {entries.map((entry, index) => (
            <motion.article
              key={`${entry.participantTag}:${entry.updatedAt}:${index}`}
              initial={{ opacity: 0, y: 14 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: Math.min(0.25, index * 0.02) }}
              className="logbook-line grid gap-4 py-7 md:grid-cols-[160px_1fr]"
            >
              <div>
                <p className="cyanotype-kicker">{entry.participantTag}</p>
                <p className="mt-2 text-xs uppercase tracking-[0.2em] text-cyanotype-100/52">
                  Updated {new Date(entry.updatedAt).toLocaleString()}
                </p>
              </div>
              <div>
                <h2 className="font-display text-3xl text-cyanotype-000/95 sm:text-4xl">{entry.signer}</h2>
                <p className="mt-4 whitespace-pre-wrap text-base leading-relaxed text-cyanotype-100/84">
                  {entry.message}
                </p>
              </div>
            </motion.article>
          ))}
        </div>

        {nextCursor ? (
          <button className="cyanotype-cta mt-8" onClick={() => void loadMore()} disabled={loadingMore}>
            {loadingMore ? "Loading…" : "Load More"}
          </button>
        ) : null}
      </section>
    </main>
  );
};
