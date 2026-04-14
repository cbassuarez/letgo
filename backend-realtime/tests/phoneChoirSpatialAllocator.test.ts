import { describe, expect, it } from "vitest";
import { PhoneChoirSpatialAllocator } from "../src/services/phoneChoirSpatialAllocator";

describe("PhoneChoirSpatialAllocator", () => {
  it("prefers healthy zone-balanced targets for note_on", () => {
    const allocator = new PhoneChoirSpatialAllocator();
    allocator.upsertDevice("d1", { audio: true, geolocation: true, motion: true });
    allocator.upsertDevice("d2", { audio: true, geolocation: true, motion: true });
    allocator.upsertDevice("d3", { audio: true, geolocation: true, motion: true });

    allocator.updateZone("d1", { name: "zone-a", x: 0.2, y: 0.3 });
    allocator.updateZone("d2", { name: "zone-a", x: 0.25, y: 0.35 });
    allocator.updateZone("d3", { name: "zone-b", x: 0.8, y: 0.7 });

    allocator.updateVector("d1", {
      textAmount: 0.5,
      compositeBias: 0.5,
      audioGain: 0.6,
      spatialX: 0.2,
      spatialY: 0.3,
      spatialZ: 0.4
    }, 0.6);
    allocator.updateVector("d2", {
      textAmount: 0.5,
      compositeBias: 0.5,
      audioGain: 0.5,
      spatialX: 0.25,
      spatialY: 0.35,
      spatialZ: 0.45
    }, 0.5);
    allocator.updateVector("d3", {
      textAmount: 0.6,
      compositeBias: 0.6,
      audioGain: 0.8,
      spatialX: 0.8,
      spatialY: 0.7,
      spatialZ: 0.9
    }, 0.9);

    allocator.updateSyncHealth("d1", 120, 12);
    allocator.updateSyncHealth("d2", 180, 10);
    allocator.updateSyncHealth("d3", 80, 8);

    const activeVoices = { d1: 60 };
    const plan = allocator.planNoteOn(64, ["d1", "d2", "d3"], activeVoices);
    expect(plan.targetHashedIds.length).toBe(1);
    expect(plan.targetHashedIds[0]).toBe("d3");
    expect(plan.renderHintsByTarget.d3?.priority).toBe("high");
  });

  it("produces failover target and increments failover telemetry", () => {
    const allocator = new PhoneChoirSpatialAllocator();
    allocator.upsertDevice("a", { audio: true, motion: true, geolocation: true });
    allocator.upsertDevice("b", { audio: true, motion: true, geolocation: true });
    allocator.updateZone("a", { name: "zone-a", x: 0.2, y: 0.3 });
    allocator.updateZone("b", { name: "zone-b", x: 0.8, y: 0.7 });
    allocator.observeAck("a", false);

    const failover = allocator.planFailover("a", 67, ["a", "b"], { a: 67 });
    expect(failover.targetHashedIds).toEqual(["b"]);

    const telemetry = allocator.telemetry({ b: 67 });
    expect(telemetry.failoverCount).toBeGreaterThanOrEqual(1);
    expect(Object.keys(telemetry.deviceHealth)).toContain("a");
    expect(Object.keys(telemetry.zoneOccupancy)).toContain("zone-b");
  });
});
