import type { SyncPacket } from "@conductor/protocol";

export interface DriftStats {
  driftEstimate: number;
  rtt: number;
  shouldResync: boolean;
}

export class SyncService {
  constructor(private readonly maxDriftMs: number) {}

  createPing(serverTime: number): SyncPacket {
    return {
      kind: "ping",
      serverTime,
      clientTime: 0,
      rtt: 0,
      driftEstimate: 0
    };
  }

  evaluatePong(packet: SyncPacket, serverReceiveTime: number): DriftStats {
    const rtt = Math.max(0, serverReceiveTime - packet.serverTime);
    const estimatedOneWay = rtt / 2;
    const expectedClientTime = packet.serverTime + estimatedOneWay;
    const driftEstimate = packet.clientTime - expectedClientTime;
    return {
      driftEstimate,
      rtt,
      shouldResync: Math.abs(driftEstimate) > this.maxDriftMs
    };
  }
}
