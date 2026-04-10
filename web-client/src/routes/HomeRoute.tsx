import { motion } from "framer-motion";
import { Link } from "react-router-dom";

export const HomeRoute = (): JSX.Element => {
  return (
    <main className="cyanotype-shell min-h-dvh px-5 py-10 text-cyanotype-050 sm:px-8">
      <div className="cyanotype-atmosphere absolute inset-0 -z-10" />

      <section className="mx-auto max-w-5xl">
        <motion.p
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          className="cyanotype-kicker"
        >
          LET GO · CONDUCTED CINEMA
        </motion.p>
        <motion.h1
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.05 }}
          className="mt-4 max-w-4xl font-display text-4xl leading-tight sm:text-6xl"
        >
          A cyanotype field performance where every phone becomes a live instrument.
        </motion.h1>
        <motion.p
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.1 }}
          className="mt-6 max-w-2xl text-base leading-relaxed text-cyanotype-100/80"
        >
          Let Go is part confessional film, part distributed score. The projector carries the fixed spine,
          while participant devices modulate sound, color density, and spatial drift in real time.
        </motion.p>

        <motion.div
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.16 }}
          className="mt-8 flex flex-wrap gap-3"
        >
          <Link to="/logbook" className="cyanotype-cta">
            View Digital Logbook
          </Link>
          <span className="rounded-full border border-cyanotype-300/25 px-4 py-2 text-xs uppercase tracking-[0.2em] text-cyanotype-100/60">
            Scan NFC card to enter live mode
          </span>
        </motion.div>
      </section>

      <section className="mx-auto mt-12 grid max-w-5xl gap-4 md:grid-cols-3">
        {[
          {
            title: "Learn",
            body: "Understand the show spine, audience role, and why identity is keyed per participant."
          },
          {
            title: "Sign",
            body: "Participants sign one evolving entry in the digital logbook; the public reads the wall."
          },
          {
            title: "Perform",
            body: "Your motion and touch become vectors shaping a shared composite signal."
          }
        ].map((card, index) => (
          <motion.article
            key={card.title}
            initial={{ opacity: 0, y: 14 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.2 + index * 0.06 }}
            className="cyanotype-panel p-5"
          >
            <h2 className="font-display text-2xl">{card.title}</h2>
            <p className="mt-3 text-sm leading-relaxed text-cyanotype-100/75">{card.body}</p>
          </motion.article>
        ))}
      </section>
    </main>
  );
};
