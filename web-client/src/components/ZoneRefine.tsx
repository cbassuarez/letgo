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
    <section className="mx-auto mt-8 w-full max-w-3xl border-t border-cyanotype-200/30 py-6">
      <p className="cyanotype-kicker">SPATIAL CALIBRATION</p>
      <h3 className="mt-3 text-4xl font-semibold leading-[0.95]">Refine Your Position</h3>
      <p className="mt-2 text-xs text-cyanotype-100/72">
        Indoor location drifts. Tune your zone manually for stable spatial choreography.
      </p>

      <label className="mt-4 block text-xs uppercase tracking-[0.18em] text-cyanotype-100/62">Zone Name</label>
      <input
        className="cyanotype-input mt-1"
        value={name}
        onChange={(event) => setName(event.target.value)}
      />

      {[
        ["X", x, setX],
        ["Y", y, setY],
        ["Z", z, setZ]
      ].map(([label, value, setter]) => (
        <label className="mt-4 block" key={label as string}>
          <span className="text-xs uppercase tracking-[0.18em] text-cyanotype-100/62">{label as string}</span>
          <input
            className="cyanotype-slider mt-2 w-full"
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
        className="cyanotype-cta mt-6 w-full justify-center"
        onClick={() => onSubmit({ name, x, y, z })}
      >
        Save Spatial Position
      </button>
    </section>
  );
};
