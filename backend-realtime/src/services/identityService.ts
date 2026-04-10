import { stableHashToSeed, type DevicePermissions, type DeviceProfile, type Role } from "@conductor/protocol";
import { createHash } from "node:crypto";

export interface IdentityInput {
  rawToken: string;
  role?: Role;
  permissions?: Partial<DevicePermissions>;
}

export class IdentityService {
  constructor(private readonly salt: string) {}

  getOrCreateProfile(input: IdentityInput): DeviceProfile {
    const hashedId = this.hash(input.rawToken);
    return {
      hashedId,
      role: input.role ?? "audience",
      permissions: {
        audio: input.permissions?.audio ?? false,
        geolocation: input.permissions?.geolocation ?? false,
        motion: input.permissions?.motion ?? false
      },
      variantSeed: stableHashToSeed(hashedId)
    };
  }

  profileFromHashedId(hashedId: string, role: Role = "audience"): DeviceProfile {
    return {
      hashedId,
      role,
      permissions: {
        audio: false,
        geolocation: false,
        motion: false
      },
      variantSeed: stableHashToSeed(hashedId)
    };
  }

  validateHashedId(candidate: string): boolean {
    return /^[a-f0-9]{32}$/.test(candidate);
  }

  private hash(rawToken: string): string {
    return createHash("sha256")
      .update(`${this.salt}:${rawToken}`)
      .digest("hex")
      .slice(0, 32);
  }
}
