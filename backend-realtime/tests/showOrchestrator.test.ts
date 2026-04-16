import { describe, expect, it } from "vitest";
import { ShowOrchestrator } from "../src/services/showOrchestrator";

describe("ShowOrchestrator", () => {
  it("builds deterministic cue IDs when given deterministic times", () => {
    const show = new ShowOrchestrator();

    const cueA = show.applyAction("start", 1000);
    const cueB = show.applyAction("jump", 5000, "introduction");

    expect(cueA.cueId).toBe("preshow:0");
    expect(cueB.cueId).toBe("introduction:4000");
  });

  it("enables fixed + dynamic layers in main", () => {
    const show = new ShowOrchestrator();
    show.applyAction("start", 1000);
    show.applyAction("jump", 2000, "introduction");
    const mainCue = show.applyAction("jump", 3000, "main");

    expect(mainCue.payload.layers).toEqual({ showFixed: true, showDynamic: true });
  });

  it("treats repeated start in preshow as idempotent", () => {
    const show = new ShowOrchestrator();
    const first = show.applyAction("start", 1000);
    const second = show.applyAction("start", 3000);

    expect(first.showState).toBe("preshow");
    expect(second.showState).toBe("preshow");
    expect(second.cueId).toBe("preshow:2000");
  });

  it("includes always-on color interaction policy hooks in cue payload", () => {
    const show = new ShowOrchestrator();
    const cue = show.applyAction("start", 1000);
    const colorPolicy = cue.payload.colorPolicy as {
      enabled: boolean;
      roles: string[];
      showStates: string[];
    };

    expect(colorPolicy.enabled).toBe(true);
    expect(colorPolicy.roles).toContain("audience");
    expect(colorPolicy.roles).toContain("performer");
    expect(colorPolicy.showStates).toContain("main");
  });

  it("increments cue version monotonically across transitions", () => {
    const show = new ShowOrchestrator();
    const first = show.applyAction("start", 1000);
    const second = show.applyAction("jump", 2000, "introduction");
    const third = show.applyAction("jump", 3000, "ending");

    expect(second.version).toBeGreaterThan(first.version);
    expect(third.version).toBeGreaterThan(second.version);
    expect(show.snapshot(3000).version).toBe(third.version);
  });
});
