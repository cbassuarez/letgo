export {};

declare global {
  interface HTMLCanvasElement {
    layoutSubtree?: boolean;
    requestPaint?: () => void;
  }

  interface CanvasRenderingContext2D {
    drawElementImage?: (
      element: Element,
      dx: number,
      dy: number,
      dWidth?: number,
      dHeight?: number
    ) => DOMMatrix;
  }
}
