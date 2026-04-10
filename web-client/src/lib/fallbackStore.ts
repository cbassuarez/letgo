import type { CueCommand, ParamVector } from "@conductor/protocol";

const KEY_PREFIX = "participant-fallback";

export interface FallbackSnapshot {
  cue?: CueCommand;
  vector?: ParamVector;
  savedAt: number;
}

export const saveFallbackSnapshot = (hashedId: string, snapshot: Omit<FallbackSnapshot, "savedAt">): void => {
  const payload: FallbackSnapshot = {
    ...snapshot,
    savedAt: Date.now()
  };
  localStorage.setItem(`${KEY_PREFIX}:${hashedId}`, JSON.stringify(payload));
};

export const readFallbackSnapshot = (hashedId: string): FallbackSnapshot | null => {
  const raw = localStorage.getItem(`${KEY_PREFIX}:${hashedId}`);
  if (!raw) {
    return null;
  }

  try {
    return JSON.parse(raw) as FallbackSnapshot;
  } catch {
    localStorage.removeItem(`${KEY_PREFIX}:${hashedId}`);
    return null;
  }
};
