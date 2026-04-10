import { Link } from "react-router-dom";

export const NotFoundRoute = (): JSX.Element => {
  return (
    <main className="cyanotype-shell min-h-dvh px-6 py-16 text-cyanotype-050">
      <section className="mx-auto max-w-4xl border-t border-cyanotype-200/30 py-10">
        <p className="cyanotype-kicker">404</p>
        <h1 className="mt-3 text-5xl font-semibold leading-[0.95] sm:text-7xl">Route Not In This Score</h1>
        <p className="font-display mt-6 text-2xl text-cyanotype-000/84 sm:text-4xl">
          This address is outside the active field map.
        </p>
        <p className="mt-4 max-w-3xl text-cyanotype-100/78">
          This URL is outside the current piece map. Return to the briefing page or your participant key route.
        </p>
        <Link to="/" className="cyanotype-cta mt-8 inline-flex">
          Return Home
        </Link>
      </section>
    </main>
  );
};
