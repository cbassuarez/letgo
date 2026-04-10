import type { CompositorMode, ParamVector } from "@conductor/protocol";
import { motion } from "framer-motion";
import { useEffect, useMemo, useRef } from "react";
import { useCanvasCompositor } from "../hooks/useCanvasCompositor";

interface DynamicOverlayProps {
  vector: ParamVector;
  line: string;
  enabled: boolean;
  influence: number;
  onCompositorModeChange?: (mode: CompositorMode) => void;
}

export const DynamicOverlay = ({
  vector,
  line,
  enabled,
  influence,
  onCompositorModeChange
}: DynamicOverlayProps): JSX.Element | null => {
  if (!enabled) {
    return null;
  }

  const intensity = useMemo(
    () => (vector.textAmount + vector.compositeBias + vector.audioGain) / 3,
    [vector.audioGain, vector.compositeBias, vector.textAmount]
  );
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const sourceRef = useRef<HTMLDivElement | null>(null);
  const compositorMode = useCanvasCompositor({
    enabled,
    canvasRef,
    htmlSourceRef: sourceRef,
    text: line,
    intensity,
    influence
  });

  useEffect(() => {
    onCompositorModeChange?.(compositorMode);
  }, [compositorMode, onCompositorModeChange]);

  return (
    <div className="pointer-events-none absolute inset-0">
      <canvas
        ref={canvasRef}
        className="absolute inset-0 h-full w-full opacity-80 mix-blend-screen"
      >
        <div ref={sourceRef} className="hic-source">
          <div className="hic-source-frame">
            <p className="hic-source-kicker">LIVE COMPOSITE SIGNAL</p>
            <p className="hic-source-line">{line}</p>
          </div>
        </div>
      </canvas>

      {compositorMode !== "html-in-canvas" ? (
        <motion.div
          initial={{ opacity: 0, y: 24 }}
          animate={{ opacity: 0.48 + intensity * 0.45, y: 0 }}
          transition={{ duration: 0.8 }}
          className="absolute bottom-8 left-0 right-0 mx-5 rounded-2xl border border-cyanotype-200/35 bg-cyanotype-950/65 p-4 text-sm leading-relaxed tracking-[0.02em] text-cyanotype-050 shadow-panel"
        >
          {line}
        </motion.div>
      ) : null}
    </div>
  );
};
