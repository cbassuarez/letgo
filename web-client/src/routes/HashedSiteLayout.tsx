import { Outlet, useParams } from "react-router-dom";
import { isValidHashedId } from "../lib/identity";

export const HashedSiteLayout = (): JSX.Element => {
  const { hashedId = "" } = useParams();

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
    <main className="participant-root min-h-dvh px-5 pb-14 pt-6 sm:px-8 sm:pt-8">
      <div className="participant-atmosphere" aria-hidden="true" />
      <Outlet />
    </main>
  );
};
