import { describe, expect, it } from "vitest";
import { PhoneAudioPoolService } from "../src/services/phoneAudioPool";

describe("PhoneAudioPoolService", () => {
  it("allocates mono voices in round-robin order", () => {
    const service = new PhoneAudioPoolService();
    service.markDevice("a", { audio: true });
    service.markDevice("b", { audio: true });
    service.markDevice("c", { audio: true });
    service.setGateState({ gateArmed: true, gateCommitted: true, quadRouteReady: true });

    const first = service.allocateVoice(60);
    const second = service.allocateVoice(62);
    const third = service.allocateVoice(64);
    const none = service.allocateVoice(65);

    expect(first.length).toBe(1);
    expect(second.length).toBe(1);
    expect(third.length).toBe(1);
    expect(new Set([...first, ...second, ...third]).size).toBe(3);
    expect(none).toEqual([]);
  });

  it("drops voices when gate is no longer committed", () => {
    const service = new PhoneAudioPoolService();
    service.markDevice("a", { audio: true });
    service.setGateState({ gateArmed: true, gateCommitted: true, quadRouteReady: true });
    service.allocateVoice(60);
    expect(Object.keys(service.snapshot().activeVoices)).toEqual(["a"]);

    service.setGateState({ gateCommitted: false });
    expect(Object.keys(service.snapshot().activeVoices)).toEqual([]);
  });
});
