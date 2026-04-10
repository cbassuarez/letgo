import { motion } from "framer-motion";
import { Link } from "react-router-dom";

export const HomeRoute = (): JSX.Element => {
  return (
    <main className="cyanotype-shell min-h-dvh px-5 py-10 text-cyanotype-050 sm:px-8">
      <div className="cyanotype-atmosphere absolute inset-0 -z-10" />

      <section className="mx-auto max-w-6xl">
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
          className="mt-4 max-w-5xl text-5xl font-semibold leading-[0.95] sm:text-7xl"
        >
          Every phone becomes a keyed vector inside a live cyanotype score.
        </motion.h1>
        <motion.p
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.1 }}
          className="mt-6 max-w-3xl text-base leading-relaxed text-cyanotype-100/82 sm:text-lg"
        >
          Let Go is confessional cinema and distributed instrument at once. A fixed visual spine holds
          the room while participant devices continuously bend sound, text pressure, and composite light.
        </motion.p>
        <motion.p
          initial={{ opacity: 0 }}
          animate={{ opacity: [0.35, 0.92, 0.35], x: [0, 10, 0] }}
          transition={{ duration: 7.2, repeat: Infinity, ease: "easeInOut" }}
          className="font-display mt-8 max-w-4xl text-2xl text-cyanotype-000/86 sm:text-4xl"
        >
          The audience is not watching the field. The audience is writing it.
        </motion.p>

        <motion.div
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.16 }}
          className="mt-10 flex flex-wrap gap-8 border-t border-cyanotype-200/30 pt-5"
        >
          <Link to="/logbook" className="cyanotype-cta">
            View Digital Logbook
          </Link>
          <span className="text-xs uppercase tracking-[0.2em] text-cyanotype-100/60">
            Scan NFC card to enter live mode
          </span>
        </motion.div>
      </section>

      <section className="mx-auto mt-16 max-w-6xl">
        {[
          {
            title: "Learn",
            body: "Read the score logic, cue language, and why each participant key remains unique."
          },
          {
            title: "Sign",
            body: "Write one evolving signature per key while the public wall remains openly readable."
          },
          {
            title: "Perform",
            body: "Motion and touch stream as live vectors that steer the room-scale composite field."
          }
        ].map((card, index) => (
          <motion.article
            key={card.title}
            initial={{ opacity: 0, y: 14 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.2 + index * 0.06 }}
            className="logbook-line grid gap-4 py-6 md:grid-cols-[120px_1fr]"
          >
            <h2 className="text-sm uppercase tracking-[0.2em] text-cyanotype-100/62">{card.title}</h2>
            <p className="font-display text-2xl leading-tight text-cyanotype-000/92 sm:text-[2rem]">
              {card.body}
            </p>
          </motion.article>
        ))}
      </section>
    </main>
  );
};
