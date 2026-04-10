import { afterEach, describe, expect, it, vi } from "vitest";
import { detectCompositorMode } from "../src/lib/compositor";

describe("compositor detection", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("falls back when html-in-canvas primitives are unavailable", () => {
    vi.spyOn(HTMLCanvasElement.prototype, "getContext").mockReturnValue(null);
    expect(detectCompositorMode()).toBe("fallback");
  });

  it("detects html-in-canvas when experimental primitives exist", () => {
    const originalCreateElement = document.createElement.bind(document);
    vi.spyOn(document, "createElement").mockImplementation(((tagName: string) => {
      const element = originalCreateElement(tagName) as HTMLCanvasElement & {
        requestPaint?: () => void;
        layoutSubtree?: boolean;
      };
      if (tagName === "canvas") {
        element.requestPaint = () => undefined;
        element.layoutSubtree = false;
        element.getContext = (() =>
          ({
            drawElementImage: () => new DOMMatrix()
          }) as unknown as ReturnType<HTMLCanvasElement["getContext"]>) as HTMLCanvasElement["getContext"];
      }
      return element;
    }) as Document["createElement"]);

    expect(detectCompositorMode()).toBe("html-in-canvas");
  });
});
