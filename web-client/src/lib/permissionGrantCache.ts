import type { DevicePermissions } from "@conductor/protocol";

export interface PermissionGrantCacheEntry {
  grantedPermissions: DevicePermissions;
  grantedAt: number;
  expiresAt: number;
}

export const PERMISSION_CACHE_TTL_MS = 30 * 24 * 60 * 60 * 1000;

const cacheKey = (hashedId: string): string => `conductor.permission-grant.v1:${hashedId}`;

const parseEntry = (raw: string | null): PermissionGrantCacheEntry | null => {
  if (!raw) {
    return null;
  }
  try {
    const parsed = JSON.parse(raw) as Partial<PermissionGrantCacheEntry>;
    if (!parsed || typeof parsed !== "object") {
      return null;
    }
    if (
      !parsed.grantedPermissions ||
      typeof parsed.grantedPermissions.audio !== "boolean" ||
      typeof parsed.grantedPermissions.motion !== "boolean" ||
      typeof parsed.grantedPermissions.geolocation !== "boolean"
    ) {
      return null;
    }
    if (typeof parsed.grantedAt !== "number" || !Number.isFinite(parsed.grantedAt)) {
      return null;
    }
    if (typeof parsed.expiresAt !== "number" || !Number.isFinite(parsed.expiresAt)) {
      return null;
    }
    return {
      grantedPermissions: parsed.grantedPermissions,
      grantedAt: parsed.grantedAt,
      expiresAt: parsed.expiresAt
    };
  } catch {
    return null;
  }
};

export const readPermissionGrantCache = (hashedId: string, nowMs: number = Date.now()): PermissionGrantCacheEntry | null => {
  if (typeof window === "undefined" || !window.localStorage) {
    return null;
  }
  const parsed = parseEntry(window.localStorage.getItem(cacheKey(hashedId)));
  if (!parsed) {
    return null;
  }
  if (parsed.expiresAt <= nowMs) {
    window.localStorage.removeItem(cacheKey(hashedId));
    return null;
  }
  return parsed;
};

export const writePermissionGrantCache = (
  hashedId: string,
  grantedPermissions: DevicePermissions,
  nowMs: number = Date.now()
): PermissionGrantCacheEntry | null => {
  if (typeof window === "undefined" || !window.localStorage) {
    return null;
  }
  const entry: PermissionGrantCacheEntry = {
    grantedPermissions,
    grantedAt: nowMs,
    expiresAt: nowMs + PERMISSION_CACHE_TTL_MS
  };
  window.localStorage.setItem(cacheKey(hashedId), JSON.stringify(entry));
  return entry;
};

export const clearPermissionGrantCache = (hashedId: string): void => {
  if (typeof window === "undefined" || !window.localStorage) {
    return;
  }
  window.localStorage.removeItem(cacheKey(hashedId));
};
