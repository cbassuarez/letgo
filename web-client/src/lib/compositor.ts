import type { CompositorMode } from "@conductor/protocol";

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
  }
): void => {
  const context = canvas.getContext("2d");
  if (!context) {
    return;
  }

  const width = canvas.width;
  const height = canvas.height;
  const pulse = 0.5 + 0.5 * Math.sin(options.timestampMs / 1300);
  const alpha = 0.2 + options.intensity * 0.35;

  context.clearRect(0, 0, width, height);
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

  context.fillStyle = "rgba(230, 249, 255, 0.92)";
  context.font = "700 26px 'Fraunces'";
  context.textBaseline = "middle";
  context.fillText(options.text.slice(0, 98), 26, height * 0.7);
};
