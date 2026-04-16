import { motion, useReducedMotion } from "framer-motion";
import { Link } from "react-router-dom";

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

export const KeylessIntroRoute = (): JSX.Element => {
  const reducedMotion = useReducedMotion() ?? false;

  return (
    <main className="participant-root participant-root-keyless min-h-dvh px-6 py-16 sm:px-8">
      <div className="participant-atmosphere" aria-hidden="true" />

      <section className="participant-frame mx-auto max-w-5xl py-8 sm:py-12">
        <motion.p {...fadeConfig(reducedMotion, 0.05)} className="participant-kicker">
          ACCESS REQUIRED
        </motion.p>

        <motion.h1
          {...fadeConfig(reducedMotion, 0.11)}
          className="participant-headline mt-4 max-w-4xl text-[2.3rem] leading-[0.9] text-participant-cream sm:text-[4.4rem]"
        >
          Tap your program to enter the participant field.
        </motion.h1>

        <motion.p
          {...fadeConfig(reducedMotion, 0.18)}
          className="mt-7 max-w-3xl text-base leading-relaxed text-participant-smoke/86 sm:text-lg"
        >
          This site only opens live routes from assigned participant links. Use the NFC marker on the concert program
          to receive your unique address, then continue to HOME, ABOUT, and ENTER.
        </motion.p>

        <motion.p
          {...fadeConfig(reducedMotion, 0.24)}
          className="participant-script mt-10 max-w-4xl text-[2rem] leading-[1.06] text-participant-blush sm:text-[3.6rem]"
        >
          let go letting go let go letting go let go letting go
        </motion.p>

        <motion.div
          {...fadeConfig(reducedMotion, 0.29)}
          className="mt-10 flex flex-wrap items-center gap-6 border-t border-participant-smoke/25 pt-5"
        >
          <Link to="/logbook" className="participant-nav-link participant-nav-link-secondary">
            VIEW THE PUBLIC LOGBOOK
          </Link>
          <span className="text-xs uppercase tracking-[0.22em] text-participant-smoke/62">
            let go letting go · cybernetic cinema (2021-2026)
          </span>
        </motion.div>
      </section>
    </main>
  );
};
