import type { CueTimingContract } from "@conductor/protocol";

export interface SyncHealthSample {
  rttMs: number;
  driftMs: number;
  lastSeenAtMs: number;
}

export interface CueTimingSchedule {
  leadMs: number;
  cohortSize: number;
  cohortP95RttMs: number;
  timing: Required<Pick<CueTimingContract, "activateAtMs" | "issuedAtMs" | "leadMs" | "timingPolicy" | "timingCohort">>;
}

export const VENUE_COHORT_MAX_AGE_MS = 8_000;
export const VENUE_COHORT_MAX_RTT_MS = 420;
export const VENUE_COHORT_MAX_DRIFT_MS = 220;
export const TAKE_MIN_LEAD_MS = 450;
export const TAKE_MAX_LEAD_MS = 900;
export const TAKE_LEAD_RTT_BUFFER_MS = 220;

const clamp = (value: number, min: number, max: number): number => Math.max(min, Math.min(max, value));

const quantile = (values: number[], q: number): number => {
  if (values.length === 0) {
    return 0;
  }
  const sorted = [...values].sort((lhs, rhs) => lhs - rhs);
  const position = Math.max(0, Math.min(sorted.length - 1, Math.ceil((sorted.length - 1) * q)));
  return sorted[position] ?? sorted[sorted.length - 1] ?? 0;
};

export const computeVenueCohortRTT = (
  healthByDevice: Record<string, SyncHealthSample>,
  connectedDeviceIds: string[],
  nowMs: number
): { cohortSize: number; cohortP95RttMs: number } => {
  const connected = new Set(connectedDeviceIds);
  const venueRtts = Object.entries(healthByDevice)
    .filter(([hashedId, sample]) => {
      if (!connected.has(hashedId)) {
        return false;
      }
      if (nowMs - sample.lastSeenAtMs > VENUE_COHORT_MAX_AGE_MS) {
        return false;
      }
      if (sample.rttMs > VENUE_COHORT_MAX_RTT_MS) {
        return false;
      }
      if (Math.abs(sample.driftMs) > VENUE_COHORT_MAX_DRIFT_MS) {
        return false;
      }
      return true;
    })
    .map(([, sample]) => Math.max(0, sample.rttMs));

  return {
    cohortSize: venueRtts.length,
    cohortP95RttMs: quantile(venueRtts, 0.95)
  };
};

export const buildCueTimingSchedule = (
  healthByDevice: Record<string, SyncHealthSample>,
  connectedDeviceIds: string[],
  nowMs: number = Date.now()
): CueTimingSchedule => {
  const { cohortSize, cohortP95RttMs } = computeVenueCohortRTT(healthByDevice, connectedDeviceIds, nowMs);
  const leadMs = Math.round(
    clamp(cohortP95RttMs + TAKE_LEAD_RTT_BUFFER_MS, TAKE_MIN_LEAD_MS, TAKE_MAX_LEAD_MS)
  );
  return {
    leadMs,
    cohortSize,
    cohortP95RttMs,
    timing: {
      activateAtMs: nowMs + leadMs,
      issuedAtMs: nowMs,
      leadMs,
      timingPolicy: "scheduled_window_v1",
      timingCohort: "venue"
    }
  };
};
