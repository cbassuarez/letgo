import type {
  CrowdPickResultPayload,
  CrowdPickVotePayload,
  CrowdPickWindowPayload
} from "@conductor/protocol";

interface CrowdPickOption {
  id: string;
  label: string;
}

interface CrowdPickPulseConfig {
  cycleMs: number;
  votingOpenMs: number;
  minimumVotes: number;
  minimumVoteRatio: number;
  minimumMargin: number;
}

type PulseListener = (event: {
  window: CrowdPickWindowPayload | null;
  result: CrowdPickResultPayload | null;
  pickEpoch: number;
}) => void;

const defaultOptions: CrowdPickOption[] = [
  { id: "focus", label: "Focus" },
  { id: "scatter", label: "Scatter" },
  { id: "echo", label: "Echo" },
  { id: "chorus", label: "Chorus" }
];

const defaults: CrowdPickPulseConfig = {
  cycleMs: 12_000,
  votingOpenMs: 5_000,
  minimumVotes: 8,
  minimumVoteRatio: 0.2,
  minimumMargin: 0.1
};

export class CrowdPickPulseService {
  private readonly listeners = new Set<PulseListener>();
  private readonly config: CrowdPickPulseConfig;
  private readonly votes = new Map<string, string>();

  private options: CrowdPickOption[] = defaultOptions;
  private window: CrowdPickWindowPayload | null = null;
  private lastResult: CrowdPickResultPayload | null = null;
  private pickEpoch = 0;
  private pendingWinner: string | null = null;
  private pendingWinnerCount = 0;
  private appliedWinner: string | null = null;

  constructor(config?: Partial<CrowdPickPulseConfig>) {
    this.config = { ...defaults, ...config };
  }

  subscribe(listener: PulseListener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  snapshot(): {
    window: CrowdPickWindowPayload | null;
    result: CrowdPickResultPayload | null;
    pickEpoch: number;
  } {
    return {
      window: this.window,
      result: this.lastResult,
      pickEpoch: this.pickEpoch
    };
  }

  setOptions(options: CrowdPickOption[]): void {
    if (options.length === 0) {
      return;
    }
    this.options = options;
  }

  tick(activeParticipants: number, now: number = Date.now()): {
    windowChanged: boolean;
    resultChanged: boolean;
  } {
    if (!this.window) {
      this.window = this.makeWindow(activeParticipants, now);
      this.emit();
      return { windowChanged: true, resultChanged: false };
    }

    if (now < this.window.closesAt) {
      return { windowChanged: false, resultChanged: false };
    }

    this.lastResult = this.resolveWindow(activeParticipants, now);
    this.window = this.makeWindow(activeParticipants, now + (this.config.cycleMs - this.config.votingOpenMs));
    this.votes.clear();
    this.emit();
    return { windowChanged: true, resultChanged: true };
  }

  vote(hashedId: string, vote: CrowdPickVotePayload): boolean {
    if (!this.window || !this.window.active) {
      return false;
    }
    const now = Number.isFinite(vote.votedAt) ? vote.votedAt : Date.now();
    if (now < this.window.opensAt || now > this.window.closesAt) {
      return false;
    }
    if (vote.windowId !== this.window.id) {
      return false;
    }
    if (!this.options.some((option) => option.id === vote.optionId)) {
      return false;
    }

    this.votes.set(hashedId, vote.optionId);
    return true;
  }

  private makeWindow(activeParticipants: number, opensAt: number): CrowdPickWindowPayload {
    const quorumTarget = Math.max(
      this.config.minimumVotes,
      Math.ceil(activeParticipants * this.config.minimumVoteRatio)
    );

    return {
      id: `pick-${opensAt}`,
      title: "Crowd Pick Window",
      options: this.options.map((option) => ({ id: option.id, label: option.label })),
      opensAt,
      closesAt: opensAt + this.config.votingOpenMs,
      quorumTarget,
      active: true
    };
  }

  private resolveWindow(activeParticipants: number, now: number): CrowdPickResultPayload {
    const tally = new Map<string, number>();
    for (const vote of this.votes.values()) {
      tally.set(vote, (tally.get(vote) ?? 0) + 1);
    }

    const ranked = [...tally.entries()].sort((lhs, rhs) => rhs[1] - lhs[1]);
    const top = ranked[0];
    const second = ranked[1];
    const totalVotes = this.votes.size;
    const quorumTarget = Math.max(
      this.config.minimumVotes,
      Math.ceil(activeParticipants * this.config.minimumVoteRatio)
    );
    const margin = top ? (top[1] - (second?.[1] ?? 0)) / Math.max(1, totalVotes) : 0;

    let applied = false;
    let winnerOptionId: string | null = null;
    let winnerLabel: string | null = null;

    if (top && totalVotes >= quorumTarget && margin >= this.config.minimumMargin) {
      const candidate = top[0];
      if (this.pendingWinner === candidate) {
        this.pendingWinnerCount += 1;
      } else {
        this.pendingWinner = candidate;
        this.pendingWinnerCount = 1;
      }

      if (this.appliedWinner === candidate || this.pendingWinnerCount >= 2) {
        applied = true;
        this.appliedWinner = candidate;
        this.pickEpoch += 1;
        winnerOptionId = candidate;
        winnerLabel = this.options.find((option) => option.id === candidate)?.label ?? candidate;
      }
    } else {
      this.pendingWinner = null;
      this.pendingWinnerCount = 0;
    }

    return {
      windowId: this.window?.id ?? `pick-${now}`,
      winnerOptionId,
      winnerLabel,
      totalVotes,
      quorumTarget,
      margin,
      applied,
      updatedAt: now
    };
  }

  private emit(): void {
    const snapshot = this.snapshot();
    for (const listener of this.listeners) {
      listener(snapshot);
    }
  }
}
