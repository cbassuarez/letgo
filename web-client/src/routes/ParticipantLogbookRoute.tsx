import { motion } from "framer-motion";
import { FormEvent, useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import {
  fetchLogbookFeed,
  fetchParticipantLogbookEntry,
  upsertParticipantLogbookEntry
} from "../lib/api";
import { isValidHashedId } from "../lib/identity";
import type { PublicLogbookEntry } from "../types/api";

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

export const ParticipantLogbookRoute = (): JSX.Element => {
  const { hashedId = "" } = useParams();
  const [loading, setLoading] = useState(true);
  const allowed = isValidHashedId(hashedId);
  const [firstName, setFirstName] = useState("");
  const [lastName, setLastName] = useState("");
  const [message, setMessage] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [savedAt, setSavedAt] = useState<number | null>(null);
  const [createdAt, setCreatedAt] = useState<number | null>(null);
  const [wallEntries, setWallEntries] = useState<PublicLogbookEntry[]>([]);
  const [wallLoading, setWallLoading] = useState(true);

  const locked = createdAt !== null && Date.now() - createdAt >= 3_600_000;

  useEffect(() => {
    if (!allowed) {
      setLoading(false);
      return;
    }

    let active = true;
    setLoading(true);
    setError(null);

    fetchParticipantLogbookEntry(hashedId)
      .then((entry) => {
        if (!active || !entry) return;
        const parts = entry.signer.trim().split(/\s+/);
        setFirstName(parts[0] ?? "");
        setLastName(parts.slice(1).join(" "));
        setMessage(entry.message);
        setSavedAt(entry.updatedAt);
        setCreatedAt(entry.createdAt);
      })
      .catch(() => {})
      .finally(() => {
        if (active) setLoading(false);
      });

    return () => { active = false; };
  }, [allowed, hashedId]);

  useEffect(() => {
    let active = true;
    setWallLoading(true);
    fetchLogbookFeed()
      .then((response) => {
        if (active) setWallEntries(response.entries);
      })
      .catch(() => {})
      .finally(() => {
        if (active) setWallLoading(false);
      });
    return () => { active = false; };
  }, []);

  const submitEntry = async (event: FormEvent<HTMLFormElement>): Promise<void> => {
    event.preventDefault();
    if (!allowed || saving || locked) return;
    const signer = `${firstName.trim()} ${lastName.trim()}`;
    if (signer.trim().split(/\s+/).length < 2) {
      setError("First and last name required.");
      return;
    }
    setSaving(true);
    setError(null);
    try {
      const entry = await upsertParticipantLogbookEntry(hashedId, { signer, message });
      setSavedAt(entry.updatedAt);
      if (createdAt === null) setCreatedAt(entry.createdAt);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "save_failed");
    } finally {
      setSaving(false);
    }
  };

  if (!isValidHashedId(hashedId)) {
    return <LockoutCard title="Invalid Link" detail="This route requires a valid participant key." hashedId={hashedId} />;
  }

  if (loading) {
    return (
      <main className="cyanotype-shell min-h-dvh px-6 py-16">
        <section className="mx-auto max-w-3xl border-t border-cyanotype-200/30 py-10">
          <p className="text-cyanotype-100/72">Checking participant key…</p>
        </section>
      </main>
    );
  }

  return (
    <main className="cyanotype-shell min-h-dvh px-5 py-10 text-cyanotype-050 sm:px-8">
      <div className="cyanotype-atmosphere absolute inset-0 -z-10" />

      <header className="mx-auto max-w-6xl">
        <Link to={`/${hashedId}`} className="participant-return-link" aria-label="Return to home">
          <span aria-hidden="true">←</span>
          <span>Home</span>
        </Link>
        <p className="cyanotype-kicker mt-4">FIELD REFLECTIONS</p>
        <h1 className="mt-3 text-4xl font-semibold leading-[0.95] sm:text-6xl">
          What Did You Witness?
        </h1>
        <p className="mt-3 max-w-2xl text-sm leading-relaxed text-cyanotype-100/76 sm:text-base">
          Describe what held you. One entry per key — you can revise over time.
        </p>
      </header>

      <div className="logbook-split mx-auto mt-10 max-w-6xl">
        <section className="logbook-split-wall" aria-label="Participant reflections">
          {wallLoading ? (
            <p className="text-cyanotype-100/52 text-sm">Loading reflections…</p>
          ) : wallEntries.length === 0 ? (
            <p className="text-cyanotype-100/52 text-sm">No reflections yet. Be the first.</p>
          ) : (
            <ul className="logbook-wall">
              {wallEntries.map((entry, index) => (
                <motion.li
                  key={`${entry.participantTag}:${entry.updatedAt}:${index}`}
                  initial={{ opacity: 0, y: 12 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ delay: Math.min(0.4, 0.06 + index * 0.03), duration: 0.6 }}
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
          )}
        </section>

        <aside className="logbook-split-form">
          <p className="cyanotype-kicker">Your Reflection</p>

          {locked ? (
            <div className="mt-4 grid gap-3">
              <p className="text-xs uppercase tracking-[0.22em] text-cyanotype-100/62">
                This entry is committed and can no longer be edited.
              </p>
              {savedAt ? (
                <p className="text-xs uppercase tracking-[0.2em] text-cyanotype-100/42">
                  Saved {new Date(savedAt).toLocaleString()}
                </p>
              ) : null}
              <Link to={`/${hashedId}`} className="cyanotype-cta mt-2">
                Back To Home
              </Link>
            </div>
          ) : (
            <form
              onSubmit={(event) => void submitEntry(event)}
              className="mt-4 grid gap-5"
            >
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs uppercase tracking-[0.22em] text-cyanotype-100/65">
                    First Name
                  </label>
                  <input
                    className="cyanotype-input mt-2"
                    value={firstName}
                    onChange={(event) => setFirstName(event.target.value)}
                    maxLength={30}
                    placeholder="First"
                    required
                  />
                </div>
                <div>
                  <label className="block text-xs uppercase tracking-[0.22em] text-cyanotype-100/65">
                    Last Name
                  </label>
                  <input
                    className="cyanotype-input mt-2"
                    value={lastName}
                    onChange={(event) => setLastName(event.target.value)}
                    maxLength={30}
                    placeholder="Last"
                    required
                  />
                </div>
              </div>

              <div>
                <label className="block text-xs uppercase tracking-[0.22em] text-cyanotype-100/65">
                  Message
                </label>
                <textarea
                  className="cyanotype-input mt-2 min-h-36"
                  value={message}
                  onChange={(event) => setMessage(event.target.value)}
                  maxLength={900}
                  placeholder="The moment that held was..."
                  required
                />
              </div>

              <p className="text-[0.62rem] uppercase tracking-[0.2em] text-cyanotype-100/46">
                Displayed as Firstname L. · Editable for one hour after first save.
              </p>

              <div className="flex flex-wrap items-center gap-4">
                <button className="cyanotype-cta" type="submit" disabled={saving}>
                  {saving ? "Saving…" : savedAt ? "Update Entry" : "Save Entry"}
                </button>
                <Link to={`/${hashedId}`} className="cyanotype-cta">
                  Back To Home
                </Link>
              </div>

              {savedAt ? (
                <p className="text-xs uppercase tracking-[0.2em] text-cyanotype-100/52">
                  Last saved {new Date(savedAt).toLocaleString()}
                </p>
              ) : null}
              {error ? <p className="text-sm text-red-300/80">{error}</p> : null}
            </form>
          )}
        </aside>
      </div>
    </main>
  );
};

const LockoutCard = ({ title, detail, hashedId }: { title: string; detail: string; hashedId: string }): JSX.Element => (
  <main className="cyanotype-shell min-h-dvh px-6 py-16">
    <section className="mx-auto max-w-3xl border-t border-cyanotype-200/30 py-10">
      <p className="cyanotype-kicker">LOCKOUT</p>
      <h1 className="mt-3 text-5xl font-semibold leading-[0.95]">{title}</h1>
      <p className="mt-4 text-cyanotype-100/78">{detail}</p>
      <Link to="/logbook" className="cyanotype-cta mt-8 inline-flex">
        View Public Wall
      </Link>
    </section>
  </main>
);
