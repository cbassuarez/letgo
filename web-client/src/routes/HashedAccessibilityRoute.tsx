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
    initial: { opacity: 0, y: 16 },
    animate: { opacity: 1, y: 0 },
    transition: {
      delay,
      duration: 0.8,
      ease: [0.22, 1, 0.36, 1]
    }
  };
};

export const HashedAccessibilityRoute = (): JSX.Element => {
  const reducedMotion = useReducedMotion() ?? false;
  const { hashedId = "" } = useParams();

  return (
    <section className="mx-auto mt-10 w-full max-w-6xl pb-16 sm:mt-14 sm:pb-24">
      <motion.div {...fadeConfig(reducedMotion, 0.04)}>
        <Link to={`/${hashedId}`} className="participant-return-link" aria-label="Return to home">
          <span aria-hidden="true">&larr;</span>
          <span>Home</span>
        </Link>
      </motion.div>

      <motion.p {...fadeConfig(reducedMotion, 0.08)} className="participant-kicker mt-4">
        ACCESSIBILITY
      </motion.p>

      <motion.h1
        {...fadeConfig(reducedMotion, 0.14)}
        className="participant-headline mt-4 max-w-5xl text-[2.3rem] leading-[0.9] text-participant-cream sm:text-[4.2rem]"
      >
        Sensory &amp; Access Information
      </motion.h1>

      <motion.section {...fadeConfig(reducedMotion, 0.2)} className="participant-card mt-10">
        <p className="participant-kicker">Environment</p>
        <ul className="mt-4 max-w-4xl space-y-3 text-lg leading-relaxed text-participant-smoke/88">
          <li>This performance takes place in a darkened room with a projected screen and live audio through a PA system.</li>
          <li>Duration is variable and determined live. Expect approximately 45&ndash;75 minutes.</li>
          <li>You may leave and return at any time without disruption. Your participant link remains active.</li>
        </ul>
      </motion.section>

      <motion.section {...fadeConfig(reducedMotion, 0.27)} className="participant-card mt-8">
        <p className="participant-kicker">Visual</p>
        <ul className="mt-4 max-w-4xl space-y-3 text-lg leading-relaxed text-participant-smoke/88">
          <li>The film includes rapid text overlay transitions and dynamic compositing that may produce brief flicker-like effects.</li>
          <li>Screens (projected and phone) are the primary light source in an otherwise dark space.</li>
          <li>If your device is set to <em>Reduce Motion</em>, the web interface will respect that preference and disable animations.</li>
          <li>You can lower your phone brightness at any time without affecting your participation.</li>
        </ul>
      </motion.section>

      <motion.section {...fadeConfig(reducedMotion, 0.34)} className="participant-card mt-8">
        <p className="participant-kicker">Audio</p>
        <ul className="mt-4 max-w-4xl space-y-3 text-lg leading-relaxed text-participant-smoke/88">
          <li>Live audio may reach high volumes at points during the performance.</li>
          <li>Earplugs are welcome and will not diminish the experience.</li>
          <li>Your phone may produce audio as part of the distributed soundscape. You can mute your phone at any time.</li>
        </ul>
      </motion.section>

      <motion.section {...fadeConfig(reducedMotion, 0.41)} className="participant-card mt-8">
        <p className="participant-kicker">Interaction &amp; Physical</p>
        <ul className="mt-4 max-w-4xl space-y-3 text-lg leading-relaxed text-participant-smoke/88">
          <li>Participation requires holding a phone. The system uses touch, tilt, and device motion sensors.</li>
          <li>Interactive prompts appear on your phone during the performance. These are invitations, not obligations&mdash;the piece continues regardless of whether you respond.</li>
          <li>Your phone&rsquo;s haptic motor may be used for tactile cues. You can disable haptics through your device settings.</li>
          <li>Seated participation is fully supported.</li>
        </ul>
      </motion.section>

      <motion.section {...fadeConfig(reducedMotion, 0.48)} className="participant-card mt-8">
        <p className="participant-kicker">Accommodations</p>
        <p className="mt-4 max-w-4xl text-lg leading-relaxed text-participant-smoke/88">
          If you have specific access needs not addressed here, contact{" "}
          <a
            href="mailto:ssuarezsolis@calarts.edu"
            className="text-participant-cream underline underline-offset-4"
          >
            ssuarezsolis@calarts.edu
          </a>{" "}
          before the performance.
        </p>
      </motion.section>
    </section>
  );
};
