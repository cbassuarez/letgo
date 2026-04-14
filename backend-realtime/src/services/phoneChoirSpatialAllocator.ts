import {
  clamp01,
  type ParamVector,
  type PhoneAudioRenderHints
} from "@conductor/protocol";

interface DeviceHealthSample {
  rttMs: number;
  driftMs: number;
  ackOk: number;
  ackFail: number;
  lastAckAt: number;
}

interface DeviceSpatialSample {
  name: string;
  x: number;
  y: number;
  z: number;
}

interface DeviceCapabilitySample {
  audio: boolean;
  motion: boolean;
  geolocation: boolean;
}

interface DeviceEntry {
  hashedId: string;
  capabilities: DeviceCapabilitySample;
  zone: DeviceSpatialSample;
  influence: number;
  motionEnergy: number;
  vector: ParamVector;
  health: DeviceHealthSample;
  lastSeenAt: number;
}

export interface ChoirAllocatorTelemetry {
  zoneOccupancy: Record<string, number>;
  deviceHealth: Record<
    string,
    {
      rttMs: number;
      driftMs: number;
      ackReliability: number;
      lastSeenAt: number;
    }
  >;
  failoverCount: number;
}

export interface ChoirVoicePlan {
  targetHashedIds: string[];
  renderHintsByTarget: Record<string, PhoneAudioRenderHints>;
}

const DEFAULT_VECTOR: ParamVector = {
  textAmount: 0.5,
  compositeBias: 0.5,
  audioGain: 0.5,
  spatialX: 0.5,
  spatialY: 0.5,
  spatialZ: 0.5
};

export class PhoneChoirSpatialAllocator {
  private readonly devices = new Map<string, DeviceEntry>();
  private failoverCount = 0;

  upsertDevice(
    hashedId: string,
    capabilities: Partial<DeviceCapabilitySample>,
    nowMs: number = Date.now()
  ): void {
    const current = this.devices.get(hashedId);
    const entry: DeviceEntry = current ?? {
      hashedId,
      capabilities: {
        audio: false,
        motion: false,
        geolocation: false
      },
      zone: {
        name: "auto-field",
        x: 0.5,
        y: 0.5,
        z: 0.5
      },
      influence: 0.5,
      motionEnergy: 0,
      vector: DEFAULT_VECTOR,
      health: {
        rttMs: 200,
        driftMs: 0,
        ackOk: 0,
        ackFail: 0,
        lastAckAt: 0
      },
      lastSeenAt: nowMs
    };

    entry.capabilities = {
      audio: capabilities.audio ?? entry.capabilities.audio,
      motion: capabilities.motion ?? entry.capabilities.motion,
      geolocation: capabilities.geolocation ?? entry.capabilities.geolocation
    };
    entry.lastSeenAt = nowMs;
    this.devices.set(hashedId, entry);
  }

  removeDevice(hashedId: string): void {
    this.devices.delete(hashedId);
  }

  updateZone(
    hashedId: string,
    zone: { name: string; x: number; y: number; z?: number },
    nowMs: number = Date.now()
  ): void {
    const entry = this.devices.get(hashedId);
    if (!entry) {
      this.upsertDevice(hashedId, {}, nowMs);
    }
    const current = this.devices.get(hashedId);
    if (!current) {
      return;
    }
    current.zone = {
      name: zone.name || "auto-field",
      x: clamp01(zone.x),
      y: clamp01(zone.y),
      z: clamp01(zone.z ?? 0.5)
    };
    current.lastSeenAt = nowMs;
  }

  updateVector(
    hashedId: string,
    vector: ParamVector,
    influence: number,
    nowMs: number = Date.now()
  ): void {
    if (!this.devices.has(hashedId)) {
      this.upsertDevice(hashedId, {}, nowMs);
    }
    const entry = this.devices.get(hashedId);
    if (!entry) {
      return;
    }
    entry.vector = vector;
    entry.influence = clamp01(influence);
    entry.motionEnergy = clamp01((vector.spatialZ * 0.55) + (vector.audioGain * 0.45));
    entry.lastSeenAt = nowMs;
  }

  updateSyncHealth(hashedId: string, rttMs: number, driftMs: number, nowMs: number = Date.now()): void {
    if (!this.devices.has(hashedId)) {
      this.upsertDevice(hashedId, {}, nowMs);
    }
    const entry = this.devices.get(hashedId);
    if (!entry) {
      return;
    }
    entry.health.rttMs = Math.max(0, rttMs);
    entry.health.driftMs = Math.max(-2_000, Math.min(2_000, driftMs));
    entry.lastSeenAt = nowMs;
  }

  observeAck(hashedId: string, ok: boolean, nowMs: number = Date.now()): void {
    if (!this.devices.has(hashedId)) {
      this.upsertDevice(hashedId, {}, nowMs);
    }
    const entry = this.devices.get(hashedId);
    if (!entry) {
      return;
    }
    if (ok) {
      entry.health.ackOk += 1;
    } else {
      entry.health.ackFail += 1;
    }
    entry.health.lastAckAt = nowMs;
    entry.lastSeenAt = nowMs;
  }

  planNoteOn(
    note: number,
    availableDeviceIds: string[],
    activeVoices: Record<string, number>,
    requestedTargets: string[] = []
  ): ChoirVoicePlan {
    const eligible = this.eligibleDevices(availableDeviceIds, activeVoices, requestedTargets);
    if (eligible.length === 0) {
      return { targetHashedIds: [], renderHintsByTarget: {} };
    }

    const zoneCounts = this.zoneCounts(activeVoices);
    const maxPerZone = Math.max(1, Math.floor(availableDeviceIds.length / 3));
    const scored = eligible
      .map((entry) => ({
        entry,
        score: this.deviceScore(entry, zoneCounts)
      }))
      .sort((lhs, rhs) => rhs.score - lhs.score);

    let selected = scored.find(({ entry }) => (zoneCounts[this.zoneID(entry)] ?? 0) < maxPerZone)?.entry;
    if (!selected) {
      selected = scored[0]?.entry;
    }

    if (!selected) {
      return { targetHashedIds: [], renderHintsByTarget: {} };
    }

    return {
      targetHashedIds: [selected.hashedId],
      renderHintsByTarget: {
        [selected.hashedId]: this.renderHintsForEntry(selected, note, "high")
      }
    };
  }

  planTextureTargets(
    availableDeviceIds: string[],
    activeVoices: Record<string, number>,
    requestedTargets: string[],
    priority: "medium" | "low"
  ): ChoirVoicePlan {
    const eligible = this.eligibleDevices(availableDeviceIds, activeVoices, requestedTargets, true);
    if (eligible.length === 0) {
      return { targetHashedIds: [], renderHintsByTarget: {} };
    }

    const zoneCounts = this.zoneCounts(activeVoices);
    const scored = eligible
      .map((entry) => ({
        entry,
        score: this.deviceScore(entry, zoneCounts)
      }))
      .sort((lhs, rhs) => rhs.score - lhs.score);

    const targetCount = priority === "medium" ? Math.min(2, scored.length) : 1;
    const selected = scored.slice(0, targetCount).map((value) => value.entry);
    const renderHintsByTarget: Record<string, PhoneAudioRenderHints> = {};
    for (const entry of selected) {
      renderHintsByTarget[entry.hashedId] = this.renderHintsForEntry(entry, undefined, priority);
    }
    return {
      targetHashedIds: selected.map((entry) => entry.hashedId),
      renderHintsByTarget
    };
  }

  planFailover(
    failedHashedId: string,
    note: number,
    availableDeviceIds: string[],
    activeVoices: Record<string, number>
  ): ChoirVoicePlan {
    const candidates = this.eligibleDevices(
      availableDeviceIds.filter((id) => id !== failedHashedId),
      activeVoices,
      []
    );
    if (candidates.length === 0) {
      return { targetHashedIds: [], renderHintsByTarget: {} };
    }
    const zoneCounts = this.zoneCounts(activeVoices);
    const selected = candidates
      .map((entry) => ({ entry, score: this.deviceScore(entry, zoneCounts) }))
      .sort((lhs, rhs) => rhs.score - lhs.score)[0]?.entry;
    if (!selected) {
      return { targetHashedIds: [], renderHintsByTarget: {} };
    }

    this.failoverCount += 1;
    return {
      targetHashedIds: [selected.hashedId],
      renderHintsByTarget: {
        [selected.hashedId]: this.renderHintsForEntry(selected, note, "high")
      }
    };
  }

  telemetry(activeVoices: Record<string, number>): ChoirAllocatorTelemetry {
    const zoneOccupancy = this.zoneCounts(activeVoices);
    const deviceHealth: ChoirAllocatorTelemetry["deviceHealth"] = {};
    for (const [hashedId, entry] of this.devices.entries()) {
      const totalAcks = entry.health.ackOk + entry.health.ackFail;
      const ackReliability = totalAcks > 0 ? clamp01(entry.health.ackOk / totalAcks) : 1;
      deviceHealth[hashedId] = {
        rttMs: entry.health.rttMs,
        driftMs: entry.health.driftMs,
        ackReliability,
        lastSeenAt: entry.lastSeenAt
      };
    }
    return {
      zoneOccupancy,
      deviceHealth,
      failoverCount: this.failoverCount
    };
  }

  private eligibleDevices(
    availableDeviceIds: string[],
    activeVoices: Record<string, number>,
    requestedTargets: string[],
    allowBusy: boolean = false
  ): DeviceEntry[] {
    const requestedSet = new Set(requestedTargets);
    const availableSet = new Set(availableDeviceIds);
    const population = [...this.devices.values()].filter((entry) => {
      if (!availableSet.has(entry.hashedId)) {
        return false;
      }
      if (!entry.capabilities.audio) {
        return false;
      }
      if (!allowBusy && activeVoices[entry.hashedId] !== undefined) {
        return false;
      }
      return true;
    });

    if (requestedSet.size === 0) {
      return population;
    }
    const requested = population.filter((entry) => requestedSet.has(entry.hashedId));
    return requested.length > 0 ? requested : population;
  }

  private zoneID(entry: DeviceEntry): string {
    if (entry.capabilities.geolocation && entry.zone.name.length > 0) {
      return entry.zone.name;
    }
    const col = entry.zone.x < 0.5 ? "L" : "R";
    const row = entry.zone.y < 0.5 ? "U" : "D";
    return `auto-${row}${col}`;
  }

  private zoneCounts(activeVoices: Record<string, number>): Record<string, number> {
    const result: Record<string, number> = {};
    for (const hashedId of Object.keys(activeVoices)) {
      const entry = this.devices.get(hashedId);
      if (!entry) {
        continue;
      }
      const zoneID = this.zoneID(entry);
      result[zoneID] = (result[zoneID] ?? 0) + 1;
    }
    return result;
  }

  private deviceScore(entry: DeviceEntry, zoneCounts: Record<string, number>): number {
    const zoneLoad = zoneCounts[this.zoneID(entry)] ?? 0;
    const zoneBalance = 1 - clamp01(zoneLoad / 4);
    const rttPenalty = clamp01(entry.health.rttMs / 1_000);
    const driftPenalty = clamp01(Math.abs(entry.health.driftMs) / 1_200);
    const totalAcks = entry.health.ackOk + entry.health.ackFail;
    const ackReliability = totalAcks > 0 ? clamp01(entry.health.ackOk / totalAcks) : 1;
    const recency = clamp01(1 - ((Date.now() - entry.lastSeenAt) / 15_000));

    return (
      (entry.influence * 0.24) +
      (entry.motionEnergy * (entry.capabilities.motion ? 0.18 : 0.08)) +
      (zoneBalance * 0.2) +
      (ackReliability * 0.16) +
      ((1 - rttPenalty) * 0.12) +
      ((1 - driftPenalty) * 0.06) +
      (recency * 0.04)
    );
  }

  private renderHintsForEntry(
    entry: DeviceEntry,
    note: number | undefined,
    priority: "high" | "medium" | "low"
  ): PhoneAudioRenderHints {
    const pan = (entry.zone.x * 2) - 1;
    const detuneCents = note === undefined ? 0 : ((entry.zone.y - 0.5) * 26) + ((entry.motionEnergy - 0.5) * 18);
    return {
      zoneId: this.zoneID(entry),
      pan,
      detuneCents,
      grainMix: clamp01((entry.motionEnergy * 0.7) + (entry.influence * 0.3)),
      motionEnergy: entry.motionEnergy,
      priority
    };
  }
}
