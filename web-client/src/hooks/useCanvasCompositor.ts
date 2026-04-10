import type { CompositorMode } from "@conductor/protocol";
import { useEffect, useState } from "react";
import type { RefObject } from "react";
import { detectCompositorMode, renderFallbackFrame } from "../lib/compositor";

interface UseCanvasCompositorInput {
  enabled: boolean;
  canvasRef: RefObject<HTMLCanvasElement>;
  htmlSourceRef: RefObject<HTMLElement>;
  text: string;
  intensity: number;
  influence: number;
}

export const useCanvasCompositor = ({
  enabled,
  canvasRef,
  htmlSourceRef,
  text,
  intensity,
  influence
}: UseCanvasCompositorInput): CompositorMode => {
  const [mode, setMode] = useState<CompositorMode>("unsupported");

  useEffect(() => {
    if (!enabled) {
      return;
    }

    const canvas = canvasRef.current;
    if (!canvas) {
      return;
    }

    const resizeCanvas = (): void => {
      const rect = canvas.getBoundingClientRect();
      const dpr = window.devicePixelRatio || 1;
      canvas.width = Math.max(1, Math.floor(rect.width * dpr));
      canvas.height = Math.max(1, Math.floor(rect.height * dpr));
    };

    resizeCanvas();
    const resizeObserver = new ResizeObserver(resizeCanvas);
    resizeObserver.observe(canvas);

    const detectedMode = detectCompositorMode();
    setMode(detectedMode);
    let runHtmlInCanvas = detectedMode === "html-in-canvas";

    let frameHandle = 0;
    let paintListener: ((event: Event) => void) | null = null;

    if (runHtmlInCanvas) {
      const sourceElement = htmlSourceRef.current;
      const context = canvas.getContext("2d") as (CanvasRenderingContext2D & {
        drawElementImage?: (
          element: HTMLElement,
          dx: number,
          dy: number,
          dWidth: number,
          dHeight: number
        ) => unknown;
      }) | null;
      const paintableCanvas = canvas as HTMLCanvasElement & {
        layoutSubtree?: boolean;
        requestPaint?: () => void;
      };

      if (!sourceElement || !context || typeof context.drawElementImage !== "function") {
        runHtmlInCanvas = false;
        setMode("fallback");
      } else {
        paintableCanvas.layoutSubtree = true;

        paintListener = () => {
          context.clearRect(0, 0, canvas.width, canvas.height);
          context.fillStyle = "rgba(6, 19, 39, 0.18)";
          context.fillRect(0, 0, canvas.width, canvas.height);
          context.drawElementImage?.(sourceElement, 0, 0, canvas.width, canvas.height);
        };

        canvas.addEventListener("paint", paintListener as EventListener);
        const tick = (): void => {
          if (!enabled) {
            return;
          }
          paintableCanvas.requestPaint?.();
          frameHandle = window.requestAnimationFrame(tick);
        };
        tick();
      }
    }

    const runFallback = (): void => {
      renderFallbackFrame(canvas, {
        text,
        intensity,
        influence,
        timestampMs: Date.now()
      });
      frameHandle = window.requestAnimationFrame(runFallback);
    };

    if (!runHtmlInCanvas) {
      runFallback();
    }

    return () => {
      resizeObserver.disconnect();
      if (paintListener) {
        canvas.removeEventListener("paint", paintListener as EventListener);
      }
      if (frameHandle) {
        window.cancelAnimationFrame(frameHandle);
      }
    };
  }, [enabled, canvasRef, htmlSourceRef, intensity, influence, text]);

  return mode;
};
