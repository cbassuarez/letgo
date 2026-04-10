import { useState } from "react";

interface ZoneRefineProps {
  onSubmit: (zone: { name: string; x: number; y: number; z: number }) => void;
}

export const ZoneRefine = ({ onSubmit }: ZoneRefineProps): JSX.Element => {
  const [name, setName] = useState("floor-a");
  const [x, setX] = useState(0.5);
  const [y, setY] = useState(0.5);
  const [z, setZ] = useState(0.5);

  return (
    <section className="mx-auto mt-4 w-full max-w-xl rounded-3xl border border-fog/20 bg-ink/70 p-6 shadow-panel backdrop-blur">
      <h3 className="font-display text-xl">Refine Your Position</h3>
      <p className="mt-2 text-xs text-fog/75">Indoor location drifts. Tune your zone manually for stable spatial choreography.</p>

      <label className="mt-4 block text-xs uppercase tracking-[0.18em] text-fog/70">Zone Name</label>
      <input
        className="mt-1 w-full rounded-lg border border-fog/25 bg-transparent px-3 py-2 text-sm"
        value={name}
        onChange={(event) => setName(event.target.value)}
      />

      {[
        ["X", x, setX],
        ["Y", y, setY],
        ["Z", z, setZ]
      ].map(([label, value, setter]) => (
        <label className="mt-4 block" key={label as string}>
          <span className="text-xs uppercase tracking-[0.18em] text-fog/70">{label as string}</span>
          <input
            className="mt-2 w-full"
            type="range"
            min={0}
            max={1}
            step={0.01}
            value={value as number}
            onChange={(event) => (setter as (value: number) => void)(Number(event.target.value))}
          />
        </label>
      ))}

      <button
        className="mt-6 w-full rounded-xl border border-fog/40 px-4 py-3 text-sm font-semibold"
        onClick={() => onSubmit({ name, x, y, z })}
      >
        Save Spatial Position
      </button>
    </section>
  );
};
