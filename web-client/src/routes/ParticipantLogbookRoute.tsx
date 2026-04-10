import { motion } from "framer-motion";
import { FormEvent, useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import {
  fetchIdentity,
  fetchParticipantLogbookEntry,
  upsertParticipantLogbookEntry
} from "../lib/api";
import { isValidHashedId } from "../lib/identity";

export const ParticipantLogbookRoute = (): JSX.Element => {
  const { hashedId = "" } = useParams();
  const [loading, setLoading] = useState(true);
  const [allowed, setAllowed] = useState(false);
  const [signer, setSigner] = useState("");
  const [message, setMessage] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [savedAt, setSavedAt] = useState<number | null>(null);

  useEffect(() => {
    if (!isValidHashedId(hashedId)) {
      setLoading(false);
      setAllowed(false);
      return;
    }

    let active = true;
    setLoading(true);
    setError(null);

    Promise.all([fetchIdentity(hashedId), fetchParticipantLogbookEntry(hashedId)])
      .then(([, entry]) => {
        if (!active) {
          return;
        }
        setAllowed(true);
        if (entry) {
          setSigner(entry.signer);
          setMessage(entry.message);
          setSavedAt(entry.updatedAt);
        }
      })
      .catch(() => {
        if (!active) {
          return;
        }
        setAllowed(false);
      })
      .finally(() => {
        if (active) {
          setLoading(false);
        }
      });

    return () => {
      active = false;
    };
  }, [hashedId]);

  const submitEntry = async (event: FormEvent<HTMLFormElement>): Promise<void> => {
    event.preventDefault();
    if (!allowed || saving) {
      return;
    }
    setSaving(true);
    setError(null);
    try {
      const entry = await upsertParticipantLogbookEntry(hashedId, {
        signer,
        message
      });
      setSavedAt(entry.updatedAt);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "save_failed");
    } finally {
      setSaving(false);
    }
  };

  if (!isValidHashedId(hashedId)) {
    return <LockoutCard title="Invalid Link" detail="This route requires a valid participant key." />;
  }

  if (loading) {
    return (
      <main className="cyanotype-shell min-h-dvh px-6 py-16">
        <section className="cyanotype-panel mx-auto max-w-2xl p-10">
          <p className="text-cyanotype-100/72">Checking participant key…</p>
        </section>
      </main>
    );
  }

  if (!allowed) {
    return (
      <LockoutCard
        title="Participant Access Required"
        detail="Logbook signing is reserved for active participant keys from tonight’s field."
      />
    );
  }

  return (
    <main className="cyanotype-shell min-h-dvh px-5 py-10 text-cyanotype-050 sm:px-8">
      <div className="cyanotype-atmosphere absolute inset-0 -z-10" />

      <section className="mx-auto max-w-3xl">
        <p className="cyanotype-kicker">PARTICIPANT ENTRY</p>
        <h1 className="mt-3 font-display text-4xl">Sign The Digital Logbook</h1>
        <p className="mt-4 text-cyanotype-100/80">
          One entry per participant key. You can refine your words over time; each save updates the public wall.
        </p>
      </section>

      <motion.form
        initial={{ opacity: 0, y: 14 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.4 }}
        onSubmit={(event) => void submitEntry(event)}
        className="cyanotype-panel mx-auto mt-8 max-w-3xl p-6"
      >
        <label className="block text-xs uppercase tracking-[0.2em] text-cyanotype-100/65">Signer</label>
        <input
          className="cyanotype-input mt-2"
          value={signer}
          onChange={(event) => setSigner(event.target.value)}
          maxLength={60}
          required
        />

        <label className="mt-5 block text-xs uppercase tracking-[0.2em] text-cyanotype-100/65">Message</label>
        <textarea
          className="cyanotype-input mt-2 min-h-44"
          value={message}
          onChange={(event) => setMessage(event.target.value)}
          maxLength={900}
          required
        />

        <div className="mt-5 flex flex-wrap items-center gap-3">
          <button className="cyanotype-cta" type="submit" disabled={saving}>
            {saving ? "Saving…" : "Save Entry"}
          </button>
          <Link to={`/${hashedId}`} className="text-sm uppercase tracking-[0.2em] text-cyanotype-100/70">
            Back To Live Mode
          </Link>
        </div>

        {savedAt ? (
          <p className="mt-4 text-xs uppercase tracking-[0.2em] text-cyanotype-100/62">
            Last saved {new Date(savedAt).toLocaleString()}
          </p>
        ) : null}
        {error ? <p className="mt-3 text-red-300">{error}</p> : null}
      </motion.form>
    </main>
  );
};

const LockoutCard = ({ title, detail }: { title: string; detail: string }): JSX.Element => (
  <main className="cyanotype-shell min-h-dvh px-6 py-16">
    <section className="cyanotype-panel mx-auto max-w-2xl p-10">
      <p className="cyanotype-kicker">LOCKOUT</p>
      <h1 className="mt-3 font-display text-4xl">{title}</h1>
      <p className="mt-4 text-cyanotype-100/78">{detail}</p>
      <Link to="/logbook" className="cyanotype-cta mt-8 inline-flex">
        View Public Wall
      </Link>
    </section>
  </main>
);
