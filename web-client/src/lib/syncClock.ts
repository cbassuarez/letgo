export interface ClockSample {
  serverTime: number;
  clientTime: number;
  receivedAt: number;
}

export class SyncClock {
  private driftMs = 0;
  private readonly maxSamples = 10;
  private readonly samples: number[] = [];

  observe(sample: ClockSample): number {
    const oneWay = Math.max(0, sample.receivedAt - sample.serverTime) / 2;
    const estimatedClientAtSend = sample.serverTime + oneWay;
    const drift = sample.clientTime - estimatedClientAtSend;

    this.samples.push(drift);
    if (this.samples.length > this.maxSamples) {
      this.samples.shift();
    }

    const total = this.samples.reduce((acc, value) => acc + value, 0);
    this.driftMs = total / this.samples.length;
    return this.driftMs;
  }

  estimateLogicalNow(serverLogicalMs: number): number {
    return Math.max(0, serverLogicalMs + this.driftMs);
  }

  getDrift(): number {
    return this.driftMs;
  }
}
