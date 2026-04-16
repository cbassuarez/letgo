import { describe, expect, it } from "vitest";
import { PromptOrchestrator } from "../src/services/promptOrchestrator";

const runUntilPrompt = (orchestrator: PromptOrchestrator) => {
  let now = 100_000;
  for (let index = 0; index < 80; index += 1) {
    const dispatches = orchestrator.tick({
      now,
      cueVersion: 12,
      showState: "main",
      activeScene: "mainDynamic",
      engineRunning: true,
      participantCount: 24,
      entropy: 0.48,
      audioFlux: 0.66,
      connectedHashedIds: ["0123456789abcdef0123456789abcdef"]
    });
    if (dispatches.length > 0) {
      return dispatches[0];
    }
    now += 700;
  }
  return null;
};

describe("PromptOrchestrator", () => {
  it("emits adaptive prompt offers for connected devices", () => {
    const orchestrator = new PromptOrchestrator();
    const dispatch = runUntilPrompt(orchestrator);
    expect(dispatch).not.toBeNull();

    expect(dispatch?.offer.cueVersion).toBe(12);
    expect(dispatch?.offer.scene).toBe("mainDynamic");
    expect(dispatch?.offer.expiresAt).toBeGreaterThan(100_000);
    expect(dispatch?.offer.affordance).toMatch(/tap|drag|hold/);
  });

  it("rotates cohort salt when scene/cue changes", () => {
    const orchestrator = new PromptOrchestrator();
    orchestrator.tick({
      now: 5_000,
      cueVersion: 1,
      showState: "preshow",
      activeScene: "preshow",
      engineRunning: true,
      participantCount: 5,
      entropy: 0.2,
      audioFlux: 0.2,
      connectedHashedIds: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]
    });
    const firstSalt = orchestrator.currentCohortSalt();

    orchestrator.tick({
      now: 9_000,
      cueVersion: 2,
      showState: "main",
      activeScene: "mainDynamic",
      engineRunning: true,
      participantCount: 12,
      entropy: 0.4,
      audioFlux: 0.5,
      connectedHashedIds: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]
    });
    const secondSalt = orchestrator.currentCohortSalt();

    expect(secondSalt).not.toBe(firstSalt);
  });

  it("accepts prompt responses and computes influence scores", () => {
    const orchestrator = new PromptOrchestrator();
    const dispatch = runUntilPrompt(orchestrator);
    expect(dispatch).not.toBeNull();

    const response = orchestrator.consumeResponse(
      "0123456789abcdef0123456789abcdef",
      {
        promptId: dispatch!.offer.promptId,
        cueVersion: dispatch!.offer.cueVersion,
        responseType: "tap",
        tapChoice: "Primary",
        slotPick: {
          slotId: "slot-a"
        },
        latencyMs: 450,
        respondedAt: dispatch!.offer.expiresAt - 400
      },
      dispatch!.offer.expiresAt - 300
    );

    expect(response.accepted).toBe(true);
    expect(response.promptInfluence).toBeGreaterThan(0.3);
    expect(response.directPickInfluence).toBeGreaterThan(0.2);
  });
});
