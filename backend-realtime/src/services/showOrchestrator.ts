import {
  type ColorInteractionPolicy,
  type CueAction,
  type CueCommand,
  type ParamVector,
  type Role,
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

const allShowStates: ShowState[] = [
  "idle",
  "preshow",
  "introduction",
  "main",
  "ending",
  "hold",
  "aborted",
  "recovery"
];

const allInteractiveRoles: Role[] = ["audience", "performer", "observer"];

const defaultColorPolicy: ColorInteractionPolicy = {
  enabled: true,
  roles: allInteractiveRoles,
  showStates: allShowStates
};

export interface ShowSnapshot {
  state: ShowState;
  logicalTime: number;
  version: number;
  vector: ParamVector;
}

export class ShowOrchestrator {
  private state: ShowState = "idle";
  private cueVersion = 0;
  private startedAtMs: number | null = null;
  private pausedAtMs: number | null = null;
  private pauseOffsetMs = 0;
  private vector: ParamVector = normalizeVector({});

  snapshot(now = Date.now()): ShowSnapshot {
    return {
      state: this.state,
      logicalTime: this.logicalTime(now),
      version: this.cueVersion,
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

    const colorPolicy = this.normalizeColorPolicy(payload.colorPolicy);

    this.state = nextState;
    const logicalTime = this.logicalTime(now);
    this.cueVersion += 1;
    const version = this.cueVersion;

    return {
      cueId: `${nextState}:${logicalTime}`,
      showState: nextState,
      logicalTime,
      payload: {
        ...payload,
        colorPolicy,
        vector: this.vector,
        layers:
          nextState === "main"
            ? {
                showFixed: true,
                showDynamic: true
              }
            : undefined
      },
      version,
      action
    };
  }

  private normalizeColorPolicy(value: unknown): ColorInteractionPolicy {
    const raw = (value && typeof value === "object" ? value : {}) as Partial<ColorInteractionPolicy>;
    const roles = Array.isArray(raw.roles)
      ? raw.roles.filter(
          (role): role is Role =>
            role === "audience" || role === "performer" || role === "observer" || role === "muted"
        )
      : undefined;
    const showStates = Array.isArray(raw.showStates)
      ? raw.showStates.filter((state): state is ShowState => allShowStates.includes(state))
      : undefined;

    return {
      enabled: typeof raw.enabled === "boolean" ? raw.enabled : defaultColorPolicy.enabled,
      roles: roles && roles.length > 0 ? roles : defaultColorPolicy.roles,
      showStates: showStates && showStates.length > 0 ? showStates : defaultColorPolicy.showStates
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
