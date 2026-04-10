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

      <section className="mx-auto max-w-5xl">
        <p className="cyanotype-kicker">PUBLIC WALL</p>
        <h1 className="mt-4 font-display text-4xl sm:text-5xl">Digital Logbook</h1>
        <p className="mt-4 max-w-2xl text-cyanotype-100/80">
          Participant signatures collected during rehearsals and live nights. The wall is public; signing
          requires an active participant key.
        </p>
        <Link to="/" className="mt-6 inline-flex text-sm uppercase tracking-[0.2em] text-cyanotype-100/72">
          Back to Piece Briefing
        </Link>
      </section>

      <section className="mx-auto mt-8 max-w-5xl">
        {loading ? <p className="text-cyanotype-100/60">Loading signatures…</p> : null}
        {error ? <p className="text-red-300">Feed unavailable: {error}</p> : null}
        {!loading && !error && entries.length === 0 ? (
          <p className="text-cyanotype-100/70">No signatures yet. The wall opens once participants begin signing.</p>
        ) : null}

        <div className="grid gap-4 md:grid-cols-2">
          {entries.map((entry, index) => (
            <motion.article
              key={`${entry.participantTag}:${entry.updatedAt}:${index}`}
              initial={{ opacity: 0, y: 14 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: Math.min(0.25, index * 0.02) }}
              className="cyanotype-panel p-5"
            >
              <p className="cyanotype-kicker">{entry.participantTag}</p>
              <h2 className="mt-3 font-display text-2xl">{entry.signer}</h2>
              <p className="mt-3 whitespace-pre-wrap text-sm leading-relaxed text-cyanotype-100/80">
                {entry.message}
              </p>
              <p className="mt-4 text-xs uppercase tracking-[0.2em] text-cyanotype-100/48">
                Updated {new Date(entry.updatedAt).toLocaleString()}
              </p>
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
