import type {
  GroupStemDescriptor,
  SFUIceServerConfig,
  VoicePublisherAnnouncePayload,
  VoiceStreamDescriptor,
  VoiceStreamSubscribePayload,
  VoiceStreamSubscribedPayload
} from "@conductor/protocol";
import * as mediasoup from "mediasoup";
import type { types as MediasoupTypes } from "mediasoup";
import { logger } from "../utils/logger";

export interface MediasoupVoiceServiceOptions {
  enabled: boolean;
  roomId: string;
  listenIp: string;
  announcedIp?: string;
  rtcMinPort?: number;
  rtcMaxPort?: number;
  maxSubscribers: number;
  iceServers: SFUIceServerConfig[];
}

interface PublisherRuntime {
  key: string;
  publisherId: string;
  sessionId: string;
  trackId: string;
  codec: "opus";
  plainTransport: MediasoupTypes.PlainTransport;
  producer: MediasoupTypes.Producer;
  payloadType: number;
  ssrc: number;
  updatedAt: number;
}

interface SubscriberRuntime {
  hashedId: string;
  transport?: MediasoupTypes.WebRtcTransport;
  consumersByVoiceId: Map<string, MediasoupTypes.Consumer>;
  consumersById: Map<string, MediasoupTypes.Consumer>;
}

const toCandidateArray = (value: unknown): Array<Record<string, unknown>> => {
  if (!Array.isArray(value)) {
    return [];
  }
  return value.filter((item): item is Record<string, unknown> => Boolean(item) && typeof item === "object");
};

const toRecord = (value: unknown): Record<string, unknown> | null => {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }
  return value as Record<string, unknown>;
};

const encodeIceServer = (server: SFUIceServerConfig): SFUIceServerConfig => ({
  urls: server.urls,
  username: server.username,
  credential: server.credential
});

export class MediasoupVoiceService {
  private readonly options: MediasoupVoiceServiceOptions;
  private worker: MediasoupTypes.Worker | null = null;
  private router: MediasoupTypes.Router | null = null;
  private readonly publishersByKey = new Map<string, PublisherRuntime>();
  private readonly subscribersByHashedId = new Map<string, SubscriberRuntime>();

  constructor(options: MediasoupVoiceServiceOptions) {
    this.options = options;
  }

  isEnabled(): boolean {
    return this.options.enabled;
  }

  async start(): Promise<void> {
    if (!this.options.enabled) {
      return;
    }
    if (this.worker && this.router) {
      return;
    }

    const worker = await mediasoup.createWorker({
      rtcMinPort: this.options.rtcMinPort,
      rtcMaxPort: this.options.rtcMaxPort,
      logLevel: "warn"
    });

    worker.on("died", () => {
      logger.error("mediasoup worker died");
      this.worker = null;
      this.router = null;
      this.publishersByKey.clear();
      for (const subscriber of this.subscribersByHashedId.values()) {
        subscriber.transport?.close();
      }
      this.subscribersByHashedId.clear();
    });

    const mediaCodecs: MediasoupTypes.RtpCodecCapability[] = [
      {
        kind: "audio",
        mimeType: "audio/opus",
        preferredPayloadType: 111,
        clockRate: 48_000,
        channels: 2,
        parameters: {
          useinbandfec: 1,
          minptime: 10
        }
      }
    ];

    const router = await worker.createRouter({ mediaCodecs });
    this.worker = worker;
    this.router = router;

    logger.info("mediasoup voice service online", {
      roomId: this.options.roomId,
      rtcMinPort: this.options.rtcMinPort,
      rtcMaxPort: this.options.rtcMaxPort,
      maxSubscribers: this.options.maxSubscribers
    });
  }

  decorateVoiceDescriptor(descriptor: VoiceStreamDescriptor): VoiceStreamDescriptor {
    if (!this.options.enabled) {
      return {
        ...descriptor,
        transport: descriptor.transport ?? "hls"
      };
    }

    const key = this.publisherKey(descriptor.sessionId, descriptor.trackId);
    const publisher = this.publishersByKey.get(key);

    return {
      ...descriptor,
      transport: "webrtc",
      streamUrl: undefined,
      codec: "opus",
      webrtc: {
        roomId: this.options.roomId,
        streamId: descriptor.trackId,
        publisherId: publisher?.publisherId,
        iceServers: this.options.iceServers.map(encodeIceServer)
      }
    };
  }

  decorateGroupDescriptor(descriptor: GroupStemDescriptor): GroupStemDescriptor {
    if (!this.options.enabled) {
      return {
        ...descriptor,
        transport: descriptor.transport ?? "hls"
      };
    }

    return {
      ...descriptor,
      transport: "hls"
    };
  }

  async announcePublisher(payload: VoicePublisherAnnouncePayload): Promise<VoicePublisherAnnouncePayload> {
    if (!this.options.enabled) {
      return {
        ...payload,
        error: "mediasoup_disabled",
        updatedAt: Date.now()
      };
    }

    const router = this.router;
    if (!router) {
      return {
        ...payload,
        error: "router_unavailable",
        updatedAt: Date.now()
      };
    }

    const key = this.publisherKey(payload.sessionId, payload.trackId);

    if (!payload.active) {
      const existing = this.publishersByKey.get(key);
      if (existing) {
        existing.producer.close();
        existing.plainTransport.close();
        this.publishersByKey.delete(key);
      }
      return {
        ...payload,
        updatedAt: Date.now()
      };
    }

    const existing = this.publishersByKey.get(key);
    if (existing) {
      existing.updatedAt = Date.now();
      return {
        ...payload,
        codec: existing.codec,
        ingest: {
          ip: existing.plainTransport.tuple.localAddress,
          port: existing.plainTransport.tuple.localPort,
          rtcpPort: existing.plainTransport.rtcpTuple?.localPort,
          payloadType: existing.payloadType,
          ssrc: existing.ssrc,
          mimeType: "audio/opus",
          clockRate: 48_000,
          channels: 2
        },
        updatedAt: existing.updatedAt
      };
    }

    const plainTransport = await router.createPlainTransport({
      listenIp: {
        ip: this.options.listenIp,
        announcedIp: this.options.announcedIp
      },
      rtcpMux: true,
      comedia: true
    });

    const payloadType = 111;
    const ssrc = this.nextSSRC();
    const producer = await plainTransport.produce({
      kind: "audio",
      rtpParameters: {
        codecs: [
          {
            mimeType: "audio/opus",
            payloadType,
            clockRate: 48_000,
            channels: 2,
            parameters: {
              useinbandfec: 1,
              minptime: 10
            },
            rtcpFeedback: []
          }
        ],
        encodings: [{ ssrc }],
        rtcp: {
          cname: `${payload.publisherId}:${payload.trackId}`.slice(0, 64),
          reducedSize: true
        }
      }
    });

    const runtime: PublisherRuntime = {
      key,
      publisherId: payload.publisherId,
      sessionId: payload.sessionId,
      trackId: payload.trackId,
      codec: "opus",
      plainTransport,
      producer,
      payloadType,
      ssrc,
      updatedAt: Date.now()
    };

    producer.on("transportclose", () => {
      if (this.publishersByKey.get(key)?.producer.id === producer.id) {
        this.publishersByKey.delete(key);
      }
    });

    this.publishersByKey.set(key, runtime);

    return {
      ...payload,
      codec: "opus",
      ingest: {
        ip: plainTransport.tuple.localAddress,
        port: plainTransport.tuple.localPort,
        rtcpPort: plainTransport.rtcpTuple?.localPort,
        payloadType,
        ssrc,
        mimeType: "audio/opus",
        clockRate: 48_000,
        channels: 2
      },
      updatedAt: runtime.updatedAt
    };
  }

  async handleSubscribe(payload: VoiceStreamSubscribePayload): Promise<VoiceStreamSubscribedPayload | null> {
    if (!this.options.enabled || !this.router) {
      return null;
    }

    const subscriber = await this.ensureSubscriber(payload.hashedId);
    if (!subscriber) {
      return null;
    }

    switch (payload.requestType) {
      case "init": {
        const transport = subscriber.transport;
        if (!transport) {
          return null;
        }

        return {
          commandId: payload.commandId,
          hashedId: payload.hashedId,
          voiceId: payload.voiceId,
          trackId: payload.trackId,
          sessionId: payload.sessionId,
          requestType: "init",
          transportId: transport.id,
          routerRtpCapabilities: this.router.rtpCapabilities as unknown as Record<string, unknown>,
          transportOptions: {
            id: transport.id,
            iceParameters: transport.iceParameters as unknown as Record<string, unknown>,
            iceCandidates: transport.iceCandidates as unknown as Array<Record<string, unknown>>,
            dtlsParameters: transport.dtlsParameters as unknown as Record<string, unknown>
          },
          issuedAt: Date.now()
        };
      }

      case "connect": {
        const transport = subscriber.transport;
        if (!transport || !payload.transportId || transport.id !== payload.transportId) {
          return null;
        }
        await transport.connect({
          dtlsParameters: (toRecord(payload.dtlsParameters) ?? {}) as MediasoupTypes.DtlsParameters
        });
        return {
          commandId: payload.commandId,
          hashedId: payload.hashedId,
          voiceId: payload.voiceId,
          trackId: payload.trackId,
          sessionId: payload.sessionId,
          requestType: "connect",
          transportId: transport.id,
          issuedAt: Date.now()
        };
      }

      case "consume": {
        const transport = subscriber.transport;
        if (!transport || !payload.transportId || transport.id !== payload.transportId) {
          return null;
        }

        const publisher = this.publishersByKey.get(this.publisherKey(payload.sessionId, payload.trackId));
        if (!publisher || publisher.producer.closed) {
          return null;
        }

        const rtpCapabilities = toRecord(payload.rtpCapabilities);
        if (!rtpCapabilities || !this.router.canConsume({ producerId: publisher.producer.id, rtpCapabilities: rtpCapabilities as MediasoupTypes.RtpCapabilities })) {
          return null;
        }

        const consumer = await transport.consume({
          producerId: publisher.producer.id,
          rtpCapabilities: rtpCapabilities as MediasoupTypes.RtpCapabilities,
          paused: true,
          appData: {
            hashedId: payload.hashedId,
            voiceId: payload.voiceId,
            trackId: payload.trackId
          }
        });

        subscriber.consumersById.set(consumer.id, consumer);
        subscriber.consumersByVoiceId.set(payload.voiceId, consumer);

        consumer.on("transportclose", () => {
          subscriber.consumersById.delete(consumer.id);
          subscriber.consumersByVoiceId.delete(payload.voiceId);
        });
        consumer.on("producerclose", () => {
          subscriber.consumersById.delete(consumer.id);
          subscriber.consumersByVoiceId.delete(payload.voiceId);
          consumer.close();
        });

        return {
          commandId: payload.commandId,
          hashedId: payload.hashedId,
          voiceId: payload.voiceId,
          trackId: payload.trackId,
          sessionId: payload.sessionId,
          requestType: "consume",
          transportId: transport.id,
          consumerId: consumer.id,
          consumerOptions: {
            id: consumer.id,
            producerId: publisher.producer.id,
            kind: consumer.kind,
            rtpParameters: consumer.rtpParameters as unknown as Record<string, unknown>,
            type: consumer.type
          },
          issuedAt: Date.now()
        };
      }

      case "resume": {
        const transport = subscriber.transport;
        if (!transport || !payload.consumerId) {
          return null;
        }
        const consumer = subscriber.consumersById.get(payload.consumerId);
        if (!consumer) {
          return null;
        }
        await consumer.resume();
        return {
          commandId: payload.commandId,
          hashedId: payload.hashedId,
          voiceId: payload.voiceId,
          trackId: payload.trackId,
          sessionId: payload.sessionId,
          requestType: "resume",
          transportId: transport.id,
          consumerId: consumer.id,
          issuedAt: Date.now()
        };
      }
    }
  }

  handleUnsubscribe(payload: {
    hashedId: string;
    voiceId?: string;
    trackId?: string;
  }): void {
    const subscriber = this.subscribersByHashedId.get(payload.hashedId);
    if (!subscriber) {
      return;
    }

    if (payload.voiceId) {
      const consumer = subscriber.consumersByVoiceId.get(payload.voiceId);
      if (consumer) {
        subscriber.consumersByVoiceId.delete(payload.voiceId);
        subscriber.consumersById.delete(consumer.id);
        consumer.close();
      }
    }

    if (payload.trackId) {
      for (const [voiceId, consumer] of subscriber.consumersByVoiceId.entries()) {
        const appData = (consumer.appData ?? {}) as Record<string, unknown>;
        if (appData.trackId === payload.trackId) {
          subscriber.consumersByVoiceId.delete(voiceId);
          subscriber.consumersById.delete(consumer.id);
          consumer.close();
        }
      }
    }
  }

  handleIceCandidate(_payload: {
    hashedId: string;
    transportId?: string;
    candidate?: string;
  }): void {
    // mediasoup WebRtcTransport currently uses static ICE candidates from the
    // transport options, so we intentionally no-op trickle candidates here.
  }

  closeSubscriber(hashedId: string): void {
    const runtime = this.subscribersByHashedId.get(hashedId);
    if (!runtime) {
      return;
    }
    for (const consumer of runtime.consumersById.values()) {
      consumer.close();
    }
    runtime.transport?.close();
    this.subscribersByHashedId.delete(hashedId);
  }

  close(): void {
    for (const runtime of this.publishersByKey.values()) {
      runtime.producer.close();
      runtime.plainTransport.close();
    }
    this.publishersByKey.clear();

    for (const runtime of this.subscribersByHashedId.values()) {
      for (const consumer of runtime.consumersById.values()) {
        consumer.close();
      }
      runtime.transport?.close();
    }
    this.subscribersByHashedId.clear();

    this.router?.close();
    this.router = null;

    this.worker?.close();
    this.worker = null;
  }

  private async ensureSubscriber(hashedId: string): Promise<SubscriberRuntime | null> {
    let runtime = this.subscribersByHashedId.get(hashedId);
    if (runtime?.transport && !runtime.transport.closed) {
      return runtime;
    }

    if (!runtime && this.subscribersByHashedId.size >= this.options.maxSubscribers) {
      return null;
    }

    const router = this.router;
    if (!router) {
      return null;
    }

    const transport = await router.createWebRtcTransport({
      listenIps: [
        {
          ip: this.options.listenIp,
          announcedIp: this.options.announcedIp
        }
      ],
      enableUdp: true,
      enableTcp: true,
      preferUdp: true
    });

    runtime = {
      hashedId,
      transport,
      consumersByVoiceId: new Map(),
      consumersById: new Map()
    };

    transport.on("routerclose", () => {
      this.subscribersByHashedId.delete(hashedId);
    });

    this.subscribersByHashedId.set(hashedId, runtime);
    return runtime;
  }

  private publisherKey(sessionId: string, trackId: string): string {
    return `${sessionId}::${trackId}`;
  }

  private nextSSRC(): number {
    const min = 10_000;
    const max = 0x7fff_ffff;
    return Math.floor(Math.random() * (max - min)) + min;
  }
}
