import { type GroupStemDescriptor, type VoiceStreamCodec, type VoiceStreamDescriptor } from "@conductor/protocol";

export interface ManagedSFUCoordinatorOptions {
  baseUrl?: string;
  groupStemBaseUrl?: string;
  voiceCodec?: VoiceStreamCodec;
  groupCodec?: VoiceStreamCodec;
  streamTtlMs?: number;
  sessionPrefix?: string;
  tokenSecret?: string;
}

interface VoiceDescriptorInput {
  hashedId: string;
  note?: number;
  commandId: string;
  nowMs?: number;
}

interface GroupDescriptorInput {
  groupId: string;
  commandId: string;
  nowMs?: number;
}

const normalizeBase = (value: string | undefined): string | null => {
  if (!value) {
    return null;
  }
  const trimmed = value.trim();
  if (trimmed.length === 0) {
    return null;
  }
  return trimmed.endsWith("/") ? trimmed.slice(0, -1) : trimmed;
};

const slug = (value: string): string =>
  value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "") || "x";

export class ManagedSFUCoordinator {
  private readonly baseUrl: string | null;
  private readonly groupStemBaseUrl: string | null;
  private readonly voiceCodec: VoiceStreamCodec;
  private readonly groupCodec: VoiceStreamCodec;
  private readonly streamTtlMs: number;
  private readonly sessionPrefix: string;
  private readonly tokenSecret: string;
  private sequence = 0;

  constructor(options: ManagedSFUCoordinatorOptions = {}) {
    this.baseUrl = normalizeBase(options.baseUrl);
    this.groupStemBaseUrl = normalizeBase(options.groupStemBaseUrl);
    this.voiceCodec = options.voiceCodec ?? "opus";
    this.groupCodec = options.groupCodec ?? "aac";
    this.streamTtlMs = Math.max(5_000, options.streamTtlMs ?? 30_000);
    this.sessionPrefix = options.sessionPrefix?.trim() || "letgo";
    this.tokenSecret = options.tokenSecret?.trim() || "managed-sfu-token";
  }

  buildVoiceDescriptor(input: VoiceDescriptorInput): VoiceStreamDescriptor {
    const nowMs = input.nowMs ?? Date.now();
    const expiresAt = nowMs + this.streamTtlMs;
    const seq = this.nextSequence();
    const noteSegment = typeof input.note === "number" ? `n${Math.max(0, Math.min(127, Math.round(input.note)))}` : "nxx";
    const deviceSegment = slug(input.hashedId).slice(0, 18);
    const voiceId = `${this.sessionPrefix}-v-${noteSegment}-${seq}`;
    const trackId = `${this.sessionPrefix}-trk-${deviceSegment}-${seq}`;
    const sessionId = `${this.sessionPrefix}-sess-${Math.floor(nowMs / 1_000)}`;
    const token = this.issueToken(`${sessionId}:${trackId}:${input.commandId}:${expiresAt}`);

    const streamUrl = this.baseUrl
      ? `${this.baseUrl}/voice/${encodeURIComponent(sessionId)}/${encodeURIComponent(trackId)}.m3u8`
      : undefined;

    return {
      voiceId,
      trackId,
      sessionId,
      token,
      codec: this.voiceCodec,
      transport: "hls",
      expiresAt,
      streamUrl,
      fallbackGroup: "phone-choir-group"
    };
  }

  buildGroupDescriptor(input: GroupDescriptorInput): GroupStemDescriptor {
    const nowMs = input.nowMs ?? Date.now();
    const expiresAt = nowMs + this.streamTtlMs;
    const sessionId = `${this.sessionPrefix}-group-${Math.floor(nowMs / 1_000)}`;
    const groupId = slug(input.groupId);
    const token = this.issueToken(`${sessionId}:${groupId}:${input.commandId}:${expiresAt}`);
    const streamUrl = this.groupStemBaseUrl
      ? `${this.groupStemBaseUrl}/${encodeURIComponent(groupId)}.m3u8`
      : undefined;

    return {
      groupId,
      sessionId,
      token,
      codec: this.groupCodec,
      transport: "hls",
      expiresAt,
      streamUrl
    };
  }

  private nextSequence(): string {
    this.sequence += 1;
    return `${Date.now().toString(36)}-${this.sequence.toString(36)}`;
  }

  private issueToken(payload: string): string {
    const signed = `${payload}:${this.tokenSecret}`;
    return Buffer.from(signed, "utf8").toString("base64url");
  }
}
