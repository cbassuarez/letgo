import { Link } from "react-router-dom";

export const NotFoundRoute = (): JSX.Element => {
  return (
    <main className="cyanotype-shell min-h-dvh px-6 py-16 text-cyanotype-050">
      <section className="cyanotype-panel mx-auto max-w-2xl p-10">
        <p className="cyanotype-kicker">404</p>
        <h1 className="mt-3 font-display text-4xl">Route Not In This Score</h1>
        <p className="mt-4 text-cyanotype-100/78">
          This URL is outside the current piece map. Return to the briefing page or your participant key route.
        </p>
        <Link to="/" className="cyanotype-cta mt-8 inline-flex">
          Return Home
        </Link>
      </section>
    </main>
  );
};
