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
        <p className="participant-kicker">Plot</p>
        <p className="mt-4 max-w-4xl text-lg leading-relaxed text-participant-smoke/88">
          a reflection on the rejection of letting go as a formalized concept; this variable length work
        </p>
      </motion.section>

      <motion.section {...fadeConfig(reducedMotion, 0.27)} className="participant-card mt-8">
        <p className="participant-kicker">Participation Ethic</p>
        <p className="mt-4 max-w-4xl text-lg leading-relaxed text-participant-smoke/88">
          In this film, audience participation is somewhere between cast, crew, observer, operator, and director. I see this made manifest through two constucts: 1. the system itself, which, as a cybernetic system, provides a wide array of interactive surfaces between its nodes (you, me, the machines and servers, the film, etc.) and 2. that of "the final cut" which this film rejects, instead opting for an immanent, Deleuzian realization of film. The latter treats the film as a constant process of becoming rather than a finished state, which connected audience-members shape live.
        </p>
      </motion.section>

      <motion.section {...fadeConfig(reducedMotion, 0.34)} className="mt-10 grid gap-8 md:grid-cols-2">
        <article className="participant-card">
          <p className="participant-kicker">Credits</p>
          <ul className="mt-4 space-y-2 text-sm uppercase tracking-[0.15em] text-participant-smoke/78 sm:text-base">
            <li>Direction · SEB SUAREZ</li>
            <li>Sound Design · [Name]</li>
            <li>Visual System · [Name]</li>
            <li>FACES</li>
            <li>Violet Hannasenna</li>
            <li>Rocco Lc Williams</li>
            <li>Sofi Belen Jacquez</li>
            <li>Bojun Zhang</li>
            <li>Autumn Hartley</li>
            <li>Paul Yorke</li>
          </ul>
        </article>

        <article className="participant-card">
          <p className="participant-kicker">Technical Method</p>
          <p className="mt-4 text-base leading-relaxed text-participant-smoke/86 sm:text-lg">
            This work is created as a cybernetic system, specifically a second-order cybernetic system, where humans interactivity with a system crosses the threshold from subject to operant, e.g. a system that you affect as well as one you are affected by. A film is often an end, a superposition of scenes baked into a print; through this cybernetic method, this film is procedural, dynamic rather than fixed. Performers and audience-members alike compose the film in realtime.
          </p>
          <p>
          To serve unique, hashed video over the internet (with variance and slew across users), body-in-space awareness and choreography, and interaction hooks to the audience, I set up a HTTP Live Streaming (HLS) server, a WebSocket endpoint for events and hooks, and calculate body-in-space awareness. Each hashed ID (given to you through an NFC in the program) is unique, allowing for: a unique timeline state (unique video), unique interaction prompts, and choreagraphed participation. This is the protocol layer of this work.
          </p>
          <p>
          Another layer of this work lies in software development, as this system required specific, custom software to handle the ins and outs of the performance, including a beat pad performer app surface, a website, a backend and database, and a centralized harness mac app which handles transport, ML training and performance, sample banks, timeline, and communication and interoperability between every other software and hardware layer.
          </p>
          <p>
          There is a cybernetic brain at the center of this work in machine learning picks and output transforms. The trained ML layer picks direct lines from my script/writing and serves them as a text overlay depending on what it hears, as well as driving subtle audio processing.
          </p>
          <p>
          A hands on throttle and stick (HOTAS) control affords me deep and expressive control of every layer in this system, and an AR monocle provides me with a birds-eye view of the film state and controls.
          </p>
        </article>
      </motion.section>
    </section>
  );
};
