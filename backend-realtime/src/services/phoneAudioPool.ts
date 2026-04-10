import type { DeviceProfile, PhoneAudioPoolStatePayload } from "@conductor/protocol";

interface PhoneAudioPoolSample {
  audioEnabled: boolean;
  lastSeenAt: number;
}

type Listener = (payload: PhoneAudioPoolStatePayload) => void;

export class PhoneAudioPoolService {
  private readonly devices = new Map<string, PhoneAudioPoolSample>();
  private readonly activeVoices = new Map<string, number>();
  private readonly listeners = new Set<Listener>();

  private gateArmed = false;
  private gateCommitted = false;
  private quadRouteReady = false;
  private roundRobinCursor = 0;

  subscribe(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  snapshot(): PhoneAudioPoolStatePayload {
    const availableDevices = this.availableDeviceIds();
    const activeVoices: Record<string, number> = {};
    for (const [hashedId, note] of this.activeVoices.entries()) {
      activeVoices[hashedId] = note;
    }

    return {
      gateArmed: this.gateArmed,
      gateCommitted: this.gateCommitted,
      quadRouteReady: this.quadRouteReady,
      availableDevices,
      activeVoices,
      updatedAt: Date.now()
    };
  }

  syncProfiles(profiles: DeviceProfile[]): PhoneAudioPoolStatePayload {
    const now = Date.now();
    for (const profile of profiles) {
      this.devices.set(profile.hashedId, {
        audioEnabled: profile.permissions.audio,
        lastSeenAt: now
      });
    }
    this.pruneDeadVoices();
    return this.emit();
  }

  markDevice(hashedId: string, permissions: { audio?: boolean }): PhoneAudioPoolStatePayload {
    const current = this.devices.get(hashedId);
    this.devices.set(hashedId, {
      audioEnabled: permissions.audio ?? current?.audioEnabled ?? false,
      lastSeenAt: Date.now()
    });
    if (!this.devices.get(hashedId)?.audioEnabled) {
      this.activeVoices.delete(hashedId);
    }
    return this.emit();
  }

  removeDevice(hashedId: string): PhoneAudioPoolStatePayload {
    this.devices.delete(hashedId);
    this.activeVoices.delete(hashedId);
    return this.emit();
  }

  setGateState(next: {
    gateArmed?: boolean;
    gateCommitted?: boolean;
    quadRouteReady?: boolean;
  }): PhoneAudioPoolStatePayload {
    if (typeof next.gateArmed === "boolean") {
      this.gateArmed = next.gateArmed;
    }
    if (typeof next.gateCommitted === "boolean") {
      this.gateCommitted = next.gateCommitted;
    }
    if (typeof next.quadRouteReady === "boolean") {
      this.quadRouteReady = next.quadRouteReady;
    }

    if (!this.gateCommitted || !this.quadRouteReady) {
      this.activeVoices.clear();
    }
    return this.emit();
  }

  canDispatchPhoneAudio(): boolean {
    return this.gateCommitted && this.quadRouteReady;
  }

  allocateVoice(note: number, requestedTargets: string[] = []): string[] {
    const requested = requestedTargets
      .filter((id) => this.isDeviceAvailable(id))
      .filter((id) => !this.activeVoices.has(id));

    if (requested.length > 0) {
      for (const hashedId of requested) {
        this.activeVoices.set(hashedId, note);
      }
      this.emit();
      return requested;
    }

    const available = this.availableDeviceIds().filter((id) => !this.activeVoices.has(id));
    if (available.length === 0) {
      return [];
    }

    const index = this.roundRobinCursor % available.length;
    const selected = available[index];
    this.roundRobinCursor = (this.roundRobinCursor + 1) % Math.max(1, available.length);
    this.activeVoices.set(selected, note);
    this.emit();
    return [selected];
  }

  releaseVoice(note?: number, targets: string[] = []): string[] {
    const released: string[] = [];

    if (targets.length > 0) {
      for (const target of targets) {
        const current = this.activeVoices.get(target);
        if (current === undefined) {
          continue;
        }
        if (typeof note === "number" && current !== note) {
          continue;
        }
        this.activeVoices.delete(target);
        released.push(target);
      }
      if (released.length > 0) {
        this.emit();
      }
      return released;
    }

    for (const [hashedId, assignedNote] of this.activeVoices.entries()) {
      if (typeof note === "number" && assignedNote !== note) {
        continue;
      }
      this.activeVoices.delete(hashedId);
      released.push(hashedId);
    }

    if (released.length > 0) {
      this.emit();
    }
    return released;
  }

  releaseAll(): PhoneAudioPoolStatePayload {
    this.activeVoices.clear();
    return this.emit();
  }

  private emit(): PhoneAudioPoolStatePayload {
    const snapshot = this.snapshot();
    for (const listener of this.listeners) {
      listener(snapshot);
    }
    return snapshot;
  }

  private availableDeviceIds(): string[] {
    return [...this.devices.entries()]
      .filter(([, sample]) => sample.audioEnabled)
      .map(([hashedId]) => hashedId)
      .sort();
  }

  private isDeviceAvailable(hashedId: string): boolean {
    return this.devices.get(hashedId)?.audioEnabled === true;
  }

  private pruneDeadVoices(): void {
    for (const [hashedId] of this.activeVoices.entries()) {
      if (!this.isDeviceAvailable(hashedId)) {
        this.activeVoices.delete(hashedId);
      }
    }
  }
}
