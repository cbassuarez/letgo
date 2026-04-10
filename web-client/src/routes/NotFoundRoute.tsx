export const NotFoundRoute = (): JSX.Element => {
  return (
    <main className="min-h-dvh bg-ink px-6 py-12 text-fog">
      <h1 className="font-display text-3xl">Participant Link Not Found</h1>
      <p className="mt-4 max-w-md text-sm text-fog/80">
        Open the page using your NFC tag URL so this phone can join the conducted film.
      </p>
    </main>
  );
};
