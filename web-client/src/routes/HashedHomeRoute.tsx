import { motion, useReducedMotion } from "framer-motion";
import { Link, useParams } from "react-router-dom";

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

export const HashedHomeRoute = (): JSX.Element => {
  const { hashedId = "" } = useParams();
  const reducedMotion = useReducedMotion() ?? false;

  return (
    <section className="mx-auto mt-10 w-full max-w-6xl pb-16 sm:mt-14 sm:pb-24">
      <motion.p {...fadeConfig(reducedMotion, 0.1)} className="participant-kicker">
        HOME · FIELD BRIEFING
      </motion.p>

      <motion.h1
        {...fadeConfig(reducedMotion, 0.16)}
        className="participant-headline mt-4 max-w-5xl text-[2.4rem] leading-[0.9] text-participant-cream sm:text-[4.4rem]"
      >
        I keep this film open so you can witness it changing in real time.
      </motion.h1>

      <motion.p
        {...fadeConfig(reducedMotion, 0.24)}
        className="mt-7 max-w-3xl text-base leading-relaxed text-participant-smoke/88 sm:text-lg"
      >
        I built the frame, but I refuse to seal it shut. What you see is not a static object; it is a live score
        that bends under pressure, timing, and proximity. You are not cast as my subject. You are the witness who
        confirms that the image still has blood in it.
      </motion.p>

      <motion.p
        initial={reducedMotion ? false : { opacity: 0.3 }}
        animate={
          reducedMotion
            ? { opacity: 1 }
            : {
                opacity: [0.34, 1, 0.34],
                x: [0, 14, 0]
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
        className="participant-script mt-10 max-w-4xl text-[2.1rem] leading-[1.05] text-participant-blush sm:text-[3.8rem]"
      >
        I am not asking for sympathy. I am asking you to stay and watch the pressure hold.
      </motion.p>

      <motion.div
        {...fadeConfig(reducedMotion, 0.28)}
        className="mt-10 flex flex-wrap items-center gap-5 border-t border-participant-smoke/25 pt-5"
      >
        <Link to={`/${hashedId}/live`} className="participant-enter-link">
          ENTER FILM
        </Link>
        <span className="text-xs uppercase tracking-[0.22em] text-participant-smoke/62">
          Live route opens on your participant key only
        </span>
      </motion.div>

      <section className="mt-16 grid gap-8 sm:mt-20 md:grid-cols-3">
        {[
          {
            label: "Tempo",
            body: "I compose against a fixed spine and let the live layer bruise it in plain sight."
          },
          {
            label: "Witness",
            body: "You are placed at the edge of impact, close enough to observe without becoming an instrument."
          },
          {
            label: "Record",
            body: "Each pass leaves a residue: timing drift, altered text weight, and a sharper communal pulse."
          }
        ].map((entry, index) => (
          <motion.article
            key={entry.label}
            {...fadeConfig(reducedMotion, 0.34 + index * 0.08)}
            className="participant-card"
          >
            <p className="participant-kicker">{entry.label}</p>
            <p className="mt-4 text-lg leading-snug text-participant-cream/92 sm:text-xl">{entry.body}</p>
          </motion.article>
        ))}
      </section>
    </section>
  );
};
