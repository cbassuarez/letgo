import { describe, expect, it } from "vitest";
import {
  TAKE_MAX_LEAD_MS,
  TAKE_MIN_LEAD_MS,
  buildCueTimingSchedule,
  computeVenueCohortRTT
} from "../src/services/cueTimingScheduler";

describe("cueTimingScheduler", () => {
  it("filters remote/outlier sync samples from venue cohort", () => {
    const nowMs = 10_000;
    const cohort = computeVenueCohortRTT(
      {
        venueA: { rttMs: 32, driftMs: 14, lastSeenAtMs: 9_950 },
        venueB: { rttMs: 58, driftMs: -20, lastSeenAtMs: 9_980 },
        remoteOutlier: { rttMs: 980, driftMs: 12, lastSeenAtMs: 9_990 },
        driftOutlier: { rttMs: 55, driftMs: 780, lastSeenAtMs: 9_995 },
        stale: { rttMs: 30, driftMs: 10, lastSeenAtMs: 1_000 }
      },
      ["venueA", "venueB", "remoteOutlier", "driftOutlier", "stale"],
      nowMs
    );

    expect(cohort.cohortSize).toBe(2);
    expect(cohort.cohortP95RttMs).toBe(58);
  });

  it("clamps lead to configured min/max window", () => {
    const nowMs = 25_000;

    const minLead = buildCueTimingSchedule(
      {
        local: { rttMs: 20, driftMs: 0, lastSeenAtMs: nowMs }
      },
      ["local"],
      nowMs
    );
    expect(minLead.leadMs).toBe(TAKE_MIN_LEAD_MS);
    expect(minLead.timing.activateAtMs).toBe(nowMs + TAKE_MIN_LEAD_MS);

    const maxLead = buildCueTimingSchedule(
      {
        localA: { rttMs: 900, driftMs: 0, lastSeenAtMs: nowMs }
      },
      ["localA"],
      nowMs
    );
    expect(maxLead.leadMs).toBe(TAKE_MIN_LEAD_MS);

    const maxLeadInCohort = buildCueTimingSchedule(
      {
        localA: { rttMs: 410, driftMs: 0, lastSeenAtMs: nowMs },
        localB: { rttMs: 415, driftMs: 0, lastSeenAtMs: nowMs }
      },
      ["localA", "localB"],
      nowMs
    );
    expect(maxLeadInCohort.leadMs).toBe(635);
    expect(maxLeadInCohort.leadMs).toBeLessThanOrEqual(TAKE_MAX_LEAD_MS);
    expect(maxLeadInCohort.timing.activateAtMs).toBe(nowMs + 635);
  });
});
