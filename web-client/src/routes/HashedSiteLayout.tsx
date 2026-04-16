import { motion, useReducedMotion } from "framer-motion";
import { NavLink, Outlet, useParams } from "react-router-dom";
import { isValidHashedId } from "../lib/identity";

const fadeConfig = (reducedMotion: boolean, delay = 0): Record<string, unknown> => {
  if (reducedMotion) {
    return {
      initial: false,
      animate: { opacity: 1 }
    };
  }

  return {
    initial: { opacity: 0, y: 12 },
    animate: { opacity: 1, y: 0 },
    transition: {
      delay,
      duration: 0.72,
      ease: [0.22, 1, 0.36, 1]
    }
  };
};

export const HashedSiteLayout = (): JSX.Element => {
  const { hashedId = "" } = useParams();
  const reducedMotion = useReducedMotion() ?? false;

  if (!isValidHashedId(hashedId)) {
    return (
      <main className="participant-root participant-root-keyless min-h-dvh px-6 py-16">
        <div className="participant-atmosphere" aria-hidden="true" />
        <section className="participant-frame mx-auto max-w-4xl py-10">
          <p className="participant-kicker">LOCKOUT</p>
          <h1 className="mt-4 text-4xl leading-[0.95] text-participant-cream sm:text-6xl">
            Participant Link Not Valid
          </h1>
          <p className="participant-script mt-6 text-3xl text-participant-blush sm:text-5xl">
            This key is outside tonight&apos;s active field.
          </p>
          <p className="mt-5 max-w-2xl text-participant-smoke/85">
            Tap the NFC marker on the printed program to receive your active participant address.
          </p>
        </section>
      </main>
    );
  }

  return (
    <main className="participant-root min-h-dvh px-5 pb-14 pt-6 text-participant-cream sm:px-8 sm:pt-8">
      <div className="participant-atmosphere" aria-hidden="true" />

      <header className="participant-nav-wrap sticky top-3 z-20 mx-auto flex w-full max-w-6xl items-center justify-between gap-4 px-3 py-3 sm:top-4 sm:px-5">
        <motion.div {...fadeConfig(reducedMotion, 0.03)}>
          <p className="participant-kicker">LET GO · PARTICIPANT EDITION</p>
          <p className="mt-1 text-xs uppercase tracking-[0.24em] text-participant-smoke/70">{hashedId.slice(0, 8)}</p>
        </motion.div>

        <motion.nav
          {...fadeConfig(reducedMotion, 0.08)}
          className="flex items-center gap-3 text-[0.72rem] uppercase tracking-[0.2em] sm:text-[0.78rem]"
          aria-label="Participant navigation"
        >
          <NavLink to={`/${hashedId}`} end className="participant-nav-link">
            HOME
          </NavLink>
          <NavLink to={`/${hashedId}/about`} className="participant-nav-link">
            ABOUT
          </NavLink>
          <NavLink to={`/${hashedId}/live`} className="participant-enter-link">
            ENTER
          </NavLink>
          <NavLink to={`/${hashedId}/logbook`} className="participant-nav-link participant-nav-link-secondary">
            LOGBOOK
          </NavLink>
        </motion.nav>
      </header>

      <Outlet />
    </main>
  );
};
