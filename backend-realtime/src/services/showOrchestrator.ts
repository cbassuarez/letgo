import {
  PROTOCOL_VERSION,
  type CueAction,
  type CueCommand,
  type ParamVector,
  type ShowState,
  normalizeVector
} from "@conductor/protocol";

const transitions: Record<ShowState, ShowState[]> = {
  idle: ["preshow", "introduction", "main", "ending"],
  preshow: ["idle", "introduction", "main", "ending", "hold", "aborted"],
  introduction: ["idle", "preshow", "main", "ending", "hold", "aborted"],
  main: ["idle", "preshow", "introduction", "ending", "hold", "aborted"],
  ending: ["idle", "preshow", "introduction", "main", "hold", "aborted"],
  hold: ["idle", "preshow", "introduction", "main", "ending", "recovery", "aborted"],
  aborted: ["recovery", "idle"],
  recovery: ["idle", "preshow", "introduction", "main", "ending", "hold", "aborted"]
};

export interface ShowSnapshot {
  state: ShowState;
  logicalTime: number;
  version: number;
  vector: ParamVector;
}

export class ShowOrchestrator {
  private state: ShowState = "idle";
  private version = PROTOCOL_VERSION;
  private startedAtMs: number | null = null;
  private pausedAtMs: number | null = null;
  private pauseOffsetMs = 0;
  private vector: ParamVector = normalizeVector({});

  snapshot(now = Date.now()): ShowSnapshot {
    return {
      state: this.state,
      logicalTime: this.logicalTime(now),
      version: this.version,
      vector: this.vector
    };
  }

  applyAction(action: CueAction, now = Date.now(), targetState?: ShowState, payload: Record<string, unknown> = {}): CueCommand {
    switch (action) {
      case "start":
        return this.transitionTo(targetState ?? "preshow", action, now, payload);
      case "hold":
        if (this.state !== "hold") {
          this.pausedAtMs = now;
        }
        return this.transitionTo("hold", action, now, payload);
      case "jump":
        if (!targetState) {
          throw new Error("Jump requires a targetState");
        }
        return this.transitionTo(targetState, action, now, payload);
      case "abort":
        return this.transitionTo("aborted", action, now, payload);
      case "recover":
        return this.transitionTo(targetState ?? "recovery", action, now, payload);
      default:
        throw new Error(`Unsupported action ${action}`);
    }
  }

  updateVector(vector: Partial<ParamVector>): ParamVector {
    this.vector = normalizeVector({ ...this.vector, ...vector });
    return this.vector;
  }

  private transitionTo(nextState: ShowState, action: CueAction, now: number, payload: Record<string, unknown>): CueCommand {
    if (nextState !== this.state && !transitions[this.state].includes(nextState)) {
      throw new Error(`Invalid transition: ${this.state} -> ${nextState}`);
    }

    if (nextState === "preshow" && this.startedAtMs === null) {
      this.startedAtMs = now;
      this.pauseOffsetMs = 0;
      this.pausedAtMs = null;
    }

    if (this.state === "hold" && this.pausedAtMs !== null && nextState !== "hold") {
      this.pauseOffsetMs += now - this.pausedAtMs;
      this.pausedAtMs = null;
    }

    if (nextState === "idle") {
      this.startedAtMs = null;
      this.pauseOffsetMs = 0;
      this.pausedAtMs = null;
    }

    this.state = nextState;
    const logicalTime = this.logicalTime(now);

    return {
      cueId: `${nextState}:${logicalTime}`,
      showState: nextState,
      logicalTime,
      payload: {
        ...payload,
        vector: this.vector,
        layers:
          nextState === "main"
            ? {
                showFixed: true,
                showDynamic: true
              }
            : undefined
      },
      version: this.version,
      action
    };
  }

  private logicalTime(now: number): number {
    if (this.startedAtMs === null) {
      return 0;
    }
    const pausedDelta = this.pausedAtMs ? now - this.pausedAtMs : 0;
    return Math.max(0, now - this.startedAtMs - this.pauseOffsetMs - pausedDelta);
  }
}
