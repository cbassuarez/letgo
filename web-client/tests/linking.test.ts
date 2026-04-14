import { describe, expect, it } from "vitest";
import { computeReconnectDelayMs, linkStateFromSilence } from "../src/hooks/useConductorSession";
import { BACKEND_HOST, buildDeviceWsUrl } from "../src/lib/wsClient";

describe("web linking helpers", () => {
  it("builds fixed-host device websocket urls", () => {
    expect(BACKEND_HOST.length).toBeGreaterThan(0);
    expect(buildDeviceWsUrl("abc123")).toBe(`wss://${BACKEND_HOST}/ws/device/abc123`);
    expect(buildDeviceWsUrl("abc/123")).toBe(`wss://${BACKEND_HOST}/ws/device/abc%2F123`);
  });

  it("computes bounded reconnect delays", () => {
    expect(computeReconnectDelayMs(1, 0)).toBeGreaterThanOrEqual(1000);
    expect(computeReconnectDelayMs(1, 1)).toBeLessThanOrEqual(30000);
    expect(computeReconnectDelayMs(12, 0.5)).toBeLessThanOrEqual(30000);
  });

  it("derives degraded/offline from silence", () => {
    expect(linkStateFromSilence(5000)).toBe("online");
    expect(linkStateFromSilence(21_000)).toBe("degraded");
    expect(linkStateFromSilence(31_000)).toBe("offline");
  });
});
