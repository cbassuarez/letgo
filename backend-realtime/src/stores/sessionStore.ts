import type { DeviceProfile, DeviceZone } from "@conductor/protocol";
import Redis from "ioredis";

export interface SessionStore {
  upsert(profile: DeviceProfile): Promise<void>;
  patchZone(hashedId: string, zone: DeviceZone): Promise<DeviceProfile | null>;
  get(hashedId: string): Promise<DeviceProfile | null>;
  list(): Promise<DeviceProfile[]>;
}

export class MemorySessionStore implements SessionStore {
  private readonly data = new Map<string, DeviceProfile>();

  async upsert(profile: DeviceProfile): Promise<void> {
    this.data.set(profile.hashedId, profile);
  }

  async patchZone(hashedId: string, zone: DeviceZone): Promise<DeviceProfile | null> {
    const current = this.data.get(hashedId);
    if (!current) {
      return null;
    }
    const updated = { ...current, zone };
    this.data.set(hashedId, updated);
    return updated;
  }

  async get(hashedId: string): Promise<DeviceProfile | null> {
    return this.data.get(hashedId) ?? null;
  }

  async list(): Promise<DeviceProfile[]> {
    return [...this.data.values()];
  }
}

export class RedisSessionStore implements SessionStore {
  constructor(private readonly redis: Redis) {}

  private key(id: string): string {
    return `device:${id}`;
  }

  async upsert(profile: DeviceProfile): Promise<void> {
    await this.redis.set(this.key(profile.hashedId), JSON.stringify(profile));
  }

  async patchZone(hashedId: string, zone: DeviceZone): Promise<DeviceProfile | null> {
    const current = await this.get(hashedId);
    if (!current) {
      return null;
    }
    const updated = { ...current, zone };
    await this.upsert(updated);
    return updated;
  }

  async get(hashedId: string): Promise<DeviceProfile | null> {
    const raw = await this.redis.get(this.key(hashedId));
    return raw ? (JSON.parse(raw) as DeviceProfile) : null;
  }

  async list(): Promise<DeviceProfile[]> {
    const keys = await this.redis.keys("device:*");
    if (keys.length === 0) {
      return [];
    }
    const values = await this.redis.mget(keys);
    return values
      .filter((value): value is string => Boolean(value))
      .map((value) => JSON.parse(value) as DeviceProfile);
  }
}
