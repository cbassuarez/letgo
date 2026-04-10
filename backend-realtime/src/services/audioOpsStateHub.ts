import type {
  AudioFeaturePayload,
  AudioOpsStatePayload,
  CrowdPickResultPayload,
  CrowdPickWindowPayload,
  PhoneAudioPoolStatePayload,
  TextScenePayload
} from "@conductor/protocol";

type Listener = (payload: AudioOpsStatePayload) => void;

export class AudioOpsStateHub {
  private readonly listeners = new Set<Listener>();

  private audioFeatures: AudioFeaturePayload = {
    rms: 0,
    spectralCentroid: 0.5,
    flux: 0.5,
    transientDensity: 0,
    updatedAt: 0
  };

  private phoneAudioPool: PhoneAudioPoolStatePayload = {
    gateArmed: false,
    gateCommitted: false,
    quadRouteReady: false,
    availableDevices: [],
    activeVoices: {},
    updatedAt: 0
  };

  private pickWindow: CrowdPickWindowPayload | null = null;
  private pickResult: CrowdPickResultPayload | null = null;
  private textScene: TextScenePayload = {
    sceneVersion: 0,
    pickEpoch: 0,
    cueId: "idle:0",
    anchor: "center-center",
    lineCount: 1,
    cutMode: "hold",
    alpha: 0.85,
    fontScale: 1,
    weight: 0.6,
    durationMs: 4200,
    lines: [],
    guardrails: {
      maxOffsetX: 0.08,
      maxOffsetY: 0.06,
      minContrast: 4.5,
      minDurationMs: 2400
    }
  };

  subscribe(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  snapshot(): AudioOpsStatePayload {
    return {
      audioFeatures: this.audioFeatures,
      phoneAudioPool: this.phoneAudioPool,
      pickWindow: this.pickWindow,
      pickResult: this.pickResult,
      textScene: this.textScene,
      updatedAt: Date.now()
    };
  }

  setAudioFeatures(features: AudioFeaturePayload): AudioOpsStatePayload {
    this.audioFeatures = features;
    return this.emit();
  }

  setPhoneAudioPool(pool: PhoneAudioPoolStatePayload): AudioOpsStatePayload {
    this.phoneAudioPool = pool;
    return this.emit();
  }

  setPickWindow(window: CrowdPickWindowPayload | null): AudioOpsStatePayload {
    this.pickWindow = window;
    return this.emit();
  }

  setPickResult(result: CrowdPickResultPayload | null): AudioOpsStatePayload {
    this.pickResult = result;
    return this.emit();
  }

  setTextScene(textScene: TextScenePayload): AudioOpsStatePayload {
    this.textScene = textScene;
    return this.emit();
  }

  private emit(): AudioOpsStatePayload {
    const snapshot = this.snapshot();
    for (const listener of this.listeners) {
      listener(snapshot);
    }
    return snapshot;
  }
}
