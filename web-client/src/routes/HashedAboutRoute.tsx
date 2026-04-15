import { motion, useReducedMotion } from "framer-motion";

const fadeConfig = (reducedMotion: boolean, delay = 0): Record<string, unknown> => {
  if (reducedMotion) {
    return {
      initial: false,
      animate: { opacity: 1 }
    };
  }

  return {
    initial: { opacity: 0, y: 16 },
    animate: { opacity: 1, y: 0 },
    transition: {
      delay,
      duration: 0.8,
      ease: [0.22, 1, 0.36, 1]
    }
  };
};

export const HashedAboutRoute = (): JSX.Element => {
  const reducedMotion = useReducedMotion() ?? false;

  return (
    <section className="mx-auto mt-10 w-full max-w-6xl pb-16 sm:mt-14 sm:pb-24">
      <motion.p {...fadeConfig(reducedMotion, 0.08)} className="participant-kicker">
        ABOUT · CONTEXT
      </motion.p>

      <motion.h1
        {...fadeConfig(reducedMotion, 0.14)}
        className="participant-headline mt-4 max-w-5xl text-[2.3rem] leading-[0.9] text-participant-cream sm:text-[4.2rem]"
      >
        I make this piece as a celebration of pressure held in public.
      </motion.h1>

      <motion.section {...fadeConfig(reducedMotion, 0.2)} className="participant-card mt-10">
        <p className="participant-kicker">Artistic Statement</p>
        <p className="mt-4 max-w-4xl text-lg leading-relaxed text-participant-smoke/88">
          I work with fixed image, unstable text, and distributed sound to keep the film porous. I want the room to
          feel the difference between a recorded statement and a live event that still risks collapse. The work does
          not ask for pity. It asks for attention, precision, and appetite.
        </p>
      </motion.section>

      <motion.section {...fadeConfig(reducedMotion, 0.27)} className="participant-card mt-8">
        <p className="participant-kicker">Participation Ethic</p>
        <p className="mt-4 max-w-4xl text-lg leading-relaxed text-participant-smoke/88">
          I treat participants as co-present operators, and viewers as witnesses with agency. Phones are used as field
          instruments, never as confession traps. Each role remains legible, and each person keeps their own boundary.
          The social contract is simple: clarity over spectacle, consent over coercion, and shared attention over noise.
        </p>
      </motion.section>

      <motion.section {...fadeConfig(reducedMotion, 0.34)} className="mt-10 grid gap-8 md:grid-cols-2">
        <article className="participant-card">
          <p className="participant-kicker">Credits</p>
          <ul className="mt-4 space-y-2 text-sm uppercase tracking-[0.15em] text-participant-smoke/78 sm:text-base">
            <li>Direction · [Name]</li>
            <li>Sound Design · [Name]</li>
            <li>Visual System · [Name]</li>
            <li>Realtime Engineering · [Name]</li>
          </ul>
        </article>

        <article className="participant-card">
          <p className="participant-kicker">Technical Method</p>
          <p className="mt-4 text-base leading-relaxed text-participant-smoke/86 sm:text-lg">
            The performance runs on a fixed cinematic spine with realtime overlays. Participant devices stream motion,
            timing, and interaction vectors into a shared bus; the projector composite responds in sync while preserving
            deterministic scene order.
          </p>
        </article>
      </motion.section>
    </section>
  );
};
