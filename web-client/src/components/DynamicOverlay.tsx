import { motion } from "framer-motion";
import { useEffect, useMemo, useRef } from "react";
import type { ParamVector } from "@conductor/protocol";
import { enableHtmlInCanvasExperiment } from "../lib/htmlInCanvasExperiment";

interface DynamicOverlayProps {
  vector: ParamVector;
  line: string;
  enabled: boolean;
}

export const DynamicOverlay = ({ vector, line, enabled }: DynamicOverlayProps): JSX.Element | null => {
  if (!enabled) {
    return null;
  }

  const intensity = useMemo(
    () => (vector.textAmount + vector.compositeBias + vector.audioGain) / 3,
    [vector.audioGain, vector.compositeBias, vector.textAmount]
  );
  const canvasRef = useRef<HTMLCanvasElement | null>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) {
      return;
    }
    enableHtmlInCanvasExperiment(canvas, line, intensity);
  }, [line, intensity]);

  return (
    <div className="pointer-events-none absolute inset-0">
      <canvas ref={canvasRef} width={1080} height={1920} className="absolute inset-0 h-full w-full opacity-70 mix-blend-screen" />
      <motion.div
        initial={{ opacity: 0, y: 30 }}
        animate={{ opacity: 0.5 + intensity * 0.5, y: 0 }}
        transition={{ duration: 0.8 }}
        className="absolute bottom-8 left-0 right-0 mx-5 rounded-2xl border border-fog/30 bg-ink/60 p-4 text-sm leading-relaxed tracking-[0.02em] text-fog shadow-panel"
      >
        {line}
      </motion.div>
    </div>
  );
};
