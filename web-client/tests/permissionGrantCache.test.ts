import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  PERMISSION_CACHE_TTL_MS,
  clearPermissionGrantCache,
  readPermissionGrantCache,
  writePermissionGrantCache
} from "../src/lib/permissionGrantCache";

const hashedId = "0123456789abcdef0123456789abcdef";

describe("permissionGrantCache", () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("persists grants and returns valid cache entries", () => {
    const nowMs = 1_000_000;
    const entry = writePermissionGrantCache(
      hashedId,
      {
        audio: true,
        motion: true,
        geolocation: false
      },
      nowMs
    );
    expect(entry).not.toBeNull();

    const cached = readPermissionGrantCache(hashedId, nowMs + 5_000);
    expect(cached?.grantedPermissions.audio).toBe(true);
    expect(cached?.grantedPermissions.motion).toBe(true);
    expect(cached?.grantedPermissions.geolocation).toBe(false);
    expect(cached?.expiresAt).toBe(nowMs + PERMISSION_CACHE_TTL_MS);
  });

  it("invalidates expired entries", () => {
    const nowMs = 2_000_000;
    writePermissionGrantCache(
      hashedId,
      {
        audio: true,
        motion: true,
        geolocation: true
      },
      nowMs
    );
    const expired = readPermissionGrantCache(hashedId, nowMs + PERMISSION_CACHE_TTL_MS + 1);
    expect(expired).toBeNull();
  });

  it("clears cached grants", () => {
    writePermissionGrantCache(
      hashedId,
      {
        audio: true,
        motion: true,
        geolocation: true
      },
      3_000_000
    );
    clearPermissionGrantCache(hashedId);
    expect(readPermissionGrantCache(hashedId, 3_000_500)).toBeNull();
  });
});
