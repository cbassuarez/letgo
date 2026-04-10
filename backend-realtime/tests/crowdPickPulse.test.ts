import { describe, expect, it } from "vitest";
import { CrowdPickPulseService } from "../src/services/crowdPickPulse";

describe("CrowdPickPulseService", () => {
  it("opens windows and applies winner after quorum + hysteresis", () => {
    const pulse = new CrowdPickPulseService({
      cycleMs: 1200,
      votingOpenMs: 500,
      minimumVotes: 2,
      minimumVoteRatio: 0.1,
      minimumMargin: 0.1
    });

    pulse.tick(10, 1000);
    const firstWindow = pulse.snapshot().window;
    expect(firstWindow).not.toBeNull();
    if (!firstWindow) {
      return;
    }

    pulse.vote("a", { windowId: firstWindow.id, optionId: "focus", votedAt: 1100 });
    pulse.vote("b", { windowId: firstWindow.id, optionId: "focus", votedAt: 1101 });
    pulse.tick(10, firstWindow.closesAt + 1);
    const firstResult = pulse.snapshot().result;
    expect(firstResult?.applied).toBe(false);

    const secondWindow = pulse.snapshot().window;
    if (!secondWindow) {
      return;
    }
    pulse.vote("a", { windowId: secondWindow.id, optionId: "focus", votedAt: secondWindow.opensAt + 10 });
    pulse.vote("b", { windowId: secondWindow.id, optionId: "focus", votedAt: secondWindow.opensAt + 11 });
    pulse.tick(10, secondWindow.closesAt + 1);

    const secondResult = pulse.snapshot().result;
    expect(secondResult?.applied).toBe(true);
    expect(secondResult?.winnerOptionId).toBe("focus");
  });
});
