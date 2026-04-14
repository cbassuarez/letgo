import type { CompositorMode, ProgramProceduralState } from "@conductor/protocol";

const supportsHtmlInCanvas = (): boolean => {
  if (typeof window === "undefined") {
    return false;
  }

  const canvas = document.createElement("canvas") as HTMLCanvasElement & {
    requestPaint?: () => void;
    layoutSubtree?: boolean;
  };
  let context: (CanvasRenderingContext2D & { drawElementImage?: (...args: unknown[]) => unknown }) | null =
    null;
  try {
    context = canvas.getContext("2d") as CanvasRenderingContext2D & {
      drawElementImage?: (...args: unknown[]) => unknown;
    } | null;
  } catch {
    return false;
  }

  return Boolean(
    context &&
      typeof context.drawElementImage === "function" &&
      typeof canvas.requestPaint === "function" &&
      "layoutSubtree" in canvas
  );
};

export const detectCompositorMode = (): CompositorMode =>
  supportsHtmlInCanvas() ? "html-in-canvas" : "fallback";

export const renderFallbackFrame = (
  canvas: HTMLCanvasElement,
  options: {
    text: string;
    intensity: number;
    influence: number;
    timestampMs: number;
    procedural: ProgramProceduralState;
  }
): void => {
  const context = canvas.getContext("2d");
  if (!context) {
    return;
  }

  const width = canvas.width;
  const height = canvas.height;
  const pulse = 0.5 + 0.5 * Math.sin(options.timestampMs / 1300);
  const stutterKick =
    options.procedural.transitionMode === "stutter"
      ? Math.sin(options.timestampMs / 42) * options.procedural.visualVariance * 18
      : 0;
  const alpha = (0.16 + options.intensity * 0.33) * (0.6 + options.procedural.fade * 0.6);

  context.clearRect(0, 0, width, height);
  context.save();
  if (stutterKick !== 0) {
    context.translate(stutterKick, 0);
  }

  const gradient = context.createLinearGradient(0, 0, width, height);
  gradient.addColorStop(0, `rgba(15, 40, 74, ${alpha})`);
  gradient.addColorStop(0.55, `rgba(15, 98, 141, ${0.15 + options.influence * 0.35})`);
  gradient.addColorStop(1, `rgba(207, 242, 255, ${0.08 + pulse * 0.14})`);
  context.fillStyle = gradient;
  context.fillRect(0, 0, width, height);

  context.strokeStyle = "rgba(216, 245, 255, 0.22)";
  context.lineWidth = 1;
  const gridSize = Math.max(18, Math.floor(width / 28));
  for (let x = 0; x < width; x += gridSize) {
    context.beginPath();
    context.moveTo(x, 0);
    context.lineTo(x, height);
    context.stroke();
  }

  if (options.procedural.splitLayout === "split-2") {
    context.strokeStyle = "rgba(230, 249, 255, 0.35)";
    context.beginPath();
    context.moveTo(width / 2, 0);
    context.lineTo(width / 2, height);
    context.stroke();
  } else if (options.procedural.splitLayout === "split-3") {
    context.strokeStyle = "rgba(230, 249, 255, 0.3)";
    context.beginPath();
    context.moveTo(width / 3, 0);
    context.lineTo(width / 3, height);
    context.moveTo((2 * width) / 3, 0);
    context.lineTo((2 * width) / 3, height);
    context.stroke();
  } else if (options.procedural.splitLayout === "split-4") {
    context.strokeStyle = "rgba(230, 249, 255, 0.28)";
    context.beginPath();
    context.moveTo(width / 2, 0);
    context.lineTo(width / 2, height);
    context.moveTo(0, height / 2);
    context.lineTo(width, height / 2);
    context.stroke();
  }

  if (options.procedural.compositorPreset === "mask") {
    const mask = context.createRadialGradient(width * 0.5, height * 0.5, width * 0.1, width * 0.5, height * 0.5, width * 0.6);
    mask.addColorStop(0, "rgba(0, 0, 0, 0)");
    mask.addColorStop(1, "rgba(0, 0, 0, 0.42)");
    context.fillStyle = mask;
    context.fillRect(0, 0, width, height);
  }

  if (options.procedural.compositorPreset === "pip") {
    const pipW = Math.floor(width * 0.26);
    const pipH = Math.floor(height * 0.22);
    context.fillStyle = "rgba(5, 13, 24, 0.55)";
    context.fillRect(width - pipW - 18, 18, pipW, pipH);
    context.strokeStyle = "rgba(230, 249, 255, 0.45)";
    context.strokeRect(width - pipW - 18, 18, pipW, pipH);
  }

  context.fillStyle = "rgba(230, 249, 255, 0.92)";
  context.font = "700 26px 'Fraunces'";
  context.textBaseline = "middle";
  context.fillText(options.text.slice(0, 98), 26, height * 0.7);
  context.restore();
};
