import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { useEffect } from "react";
import { createMemoryRouter, RouterProvider } from "react-router-dom";
import { DeviceRoute } from "../src/routes/DeviceRoute";

const validHash = "0123456789abcdef0123456789abcdef";

let sessionState: any;
let permissionState: any;
let fixedLayerShouldError = false;

vi.mock("../src/components/FixedVideoLayer", () => ({
  FixedVideoLayer: ({
    enabled,
    forcedSource,
    onPlaybackErrorChange,
    onPlaybackReadyChange
  }: {
    enabled: boolean;
    forcedSource?: string | null;
    onPlaybackErrorChange?: (hasError: boolean) => void;
    onPlaybackReadyChange?: (isReady: boolean) => void;
  }): JSX.Element | null => {
    useEffect(() => {
      onPlaybackErrorChange?.(enabled && fixedLayerShouldError);
      onPlaybackReadyChange?.(enabled && !fixedLayerShouldError);
    }, [enabled, onPlaybackErrorChange, onPlaybackReadyChange]);

    return enabled ? <div data-testid="fixed-layer" data-force-source={forcedSource ?? ""} /> : null;
  }
}));

vi.mock("../src/components/DynamicOverlay", () => ({
  DynamicOverlay: ({ enabled }: { enabled: boolean }): JSX.Element | null => (
    enabled ? <div data-testid="dynamic-overlay" /> : null
  )
}));

vi.mock("../src/hooks/useConductorSession", () => ({
  useConductorSession: () => sessionState
}));

vi.mock("../src/hooks/useParticipantVector", () => ({
  useParticipantVector: () => ({
    vector: {
      textAmount: 0.42,
      compositeBias: 0.45,
      audioGain: 0.48,
      spatialX: 0.52,
      spatialY: 0.49,
      spatialZ: 0.51
    },
    influence: 0.66,
    recommendedIntervalMs: 140
  })
}));

vi.mock("../src/hooks/useColorBiasField", () => ({
  useColorBiasField: () => ({
    intent: {
      hueX: 1,
      hueY: 0,
      chroma: 0.2,
      luminance: 0.6,
      energy: 0.5,
      updatedAt: Date.now()
    },
    pointer: { x: 0.5, y: 0.5 },
    interacting: false,
    onPointerDown: () => undefined,
    onPointerMove: () => undefined,
    onPointerUp: () => undefined,
    onPointerLeave: () => undefined
  })
}));

vi.mock("../src/hooks/useDeviceTextVariance", () => ({
  useDeviceTextVariance: () => ({
    lines: ["Test Line"],
    spec: {
      offsetX: 0,
      offsetY: 0,
      alphaBias: 0,
      weightBias: 0
    }
  })
}));

vi.mock("../src/hooks/usePhoneVoiceEngine", () => ({
  usePhoneVoiceEngine: () => ({
    handleCommand: () => undefined
  })
}));

vi.mock("../src/hooks/usePermissionFlow", () => ({
  usePermissionFlow: () => permissionState
}));

const baseSession = (): any => ({
  cue: {
    showState: "main",
    cueId: "cue-main",
    logicalTime: 12_000,
    issuedAt: 0,
    payload: {
      engineRunning: true,
      outputMode: "dynamic",
      showDynamic: true,
      showFixed: false,
      showStreamInterstitial: "https://stream.example.com/interstitial.m3u8",
      colorPolicy: {
        enabled: true,
        roles: ["audience"],
        showStates: ["main"]
      }
    }
  },
  vector: {
    textAmount: 0.4,
    compositeBias: 0.5,
    audioGain: 0.5,
    spatialX: 0.5,
    spatialY: 0.5,
    spatialZ: 0.5
  },
  driftMs: 32,
  connected: true,
  fallbackActive: false,
  fallbackAgeMs: 0,
  linkState: "online",
  retryInMs: null,
  logicalNow: 12_000,
  audienceVector: {
    vector: {
      textAmount: 0.4,
      compositeBias: 0.5,
      audioGain: 0.5,
      spatialX: 0.5,
      spatialY: 0.5,
      spatialZ: 0.5
    },
    participantCount: 12,
    updatedAt: 0,
    compositorModes: {}
  },
  lightingState: {
    targetColor: {
      oklch: { l: 0.55, c: 0.12, h: 220 },
      hex: "#336699"
    },
    confidence: 0.74,
    entropy: 0.22,
    stability: 0.8,
    trend: "go",
    participantCount: 12,
    updatedAt: 0,
    zoneField: []
  },
  audioFeatures: {
    rms: 0.25,
    spectralCentroid: 0.5,
    flux: 0.4,
    transientDensity: 0.2,
    updatedAt: 0
  },
  phoneAudioPoolState: {
    gateArmed: true,
    gateCommitted: true,
    quadRouteReady: true,
    availableDevices: ["device-1"],
    activeVoices: {},
    updatedAt: 0
  },
  crowdPickWindow: null,
  crowdPickResult: null,
  proceduralState: {
    epoch: 1,
    seed: 1,
    updatedAt: 0,
    dynamicBinSelection: 0.5,
    dynamicBinIndex: 0,
    dynamicBinClipId: null,
    dynamicBinManifest: [],
    cutCadence: 0.5,
    transitionMode: "cut",
    compositorPreset: "blend",
    splitLayout: "none",
    fade: 0,
    textProbability: 0.5,
    strictLooseBlend: 0.5,
    visualVariance: 0.5,
    crowdSteeringLevel: 0.5,
    performerVector: {
      textAmount: 0.4,
      compositeBias: 0.5,
      audioGain: 0.5,
      spatialX: 0.5,
      spatialY: 0.5,
      spatialZ: 0.5
    },
    audienceVector: {
      textAmount: 0.4,
      compositeBias: 0.5,
      audioGain: 0.5,
      spatialX: 0.5,
      spatialY: 0.5,
      spatialZ: 0.5
    },
    textBlend: {
      mode: "always-mixed",
      probability: 0.5,
      strictRatio: 0.5,
      looseRatio: 0.5
    }
  },
  textScene: {
    sceneVersion: 1,
    pickEpoch: 2,
    cueId: "cue-main",
    anchor: "center-center",
    lineCount: 1,
    cutMode: "hold",
    alpha: 0.85,
    fontScale: 1,
    weight: 0.6,
    durationMs: 4200,
    lines: ["Test Line"],
    guardrails: {
      maxOffsetX: 0.08,
      maxOffsetY: 0.06,
      minContrast: 4.5,
      minDurationMs: 2400
    }
  },
  phoneAudioCommand: null,
  promptOffer: null,
  sendPermissions: vi.fn(),
  sendZoneUpdate: vi.fn(),
  sendParticipantVector: vi.fn(),
  sendPhoneAudioAck: vi.fn(),
  sendCrowdPickVote: vi.fn(),
  sendPromptResponse: vi.fn()
});

const renderLive = () => {
  const router = createMemoryRouter(
    [
      {
        path: "/:hashedId/live",
        element: <DeviceRoute />
      }
    ],
    {
      initialEntries: [`/${validHash}/live`]
    }
  );

  render(<RouterProvider router={router} />);
};

const continueIntoLive = () => {
  fireEvent.click(screen.getByRole("button", { name: "Continue" }));
};

describe("DeviceRoute minimal live UI", () => {
  beforeEach(() => {
    sessionState = baseSession();
    fixedLayerShouldError = false;
    permissionState = {
      permissions: {
        audio: true,
        motion: true,
        geolocation: true
      },
      completed: true,
      enableAudio: vi.fn(),
      enableMotion: vi.fn(),
      enableGeo: vi.fn()
    };

    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true }));
    vi.stubGlobal("WebSocket", class MockSocket {} as unknown as typeof WebSocket);
    vi.stubGlobal("DeviceMotionEvent", class MockDeviceMotionEvent {} as any);
    vi.stubGlobal("DeviceOrientationEvent", class MockDeviceOrientationEvent {} as any);
  });

  afterEach(() => {
    cleanup();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("renders black live stage, removes standby hero, and removes live links", () => {
    renderLive();

    expect(screen.getByTestId("live-stage").className).toContain("live-stage-shell");
    expect(screen.queryByText(/This phone is armed and ready/i)).toBeNull();
    expect(screen.queryByRole("link", { name: /Open Lighting Endpoint/i })).toBeNull();
    expect(screen.queryByRole("link", { name: /Open Audio Endpoint/i })).toBeNull();
    expect(screen.queryByRole("link", { name: /Sign Digital Logbook/i })).toBeNull();
  });

  it("shows controls ribbon collapsed by default and expands panel on tap", async () => {
    renderLive();

    fireEvent.click(screen.getByRole("button", { name: "Continue" }));

    await waitFor(() => {
      expect(screen.getByTestId("live-controls-ribbon")).toBeTruthy();
    });
    expect(screen.queryByTestId("live-controls-panel")).toBeNull();

    fireEvent.click(screen.getByRole("button", { name: "Lighting" }));

    expect(screen.getByTestId("live-controls-panel")).toBeTruthy();
  });

  it("fades utility UI after idle and restores on interaction", async () => {
    vi.useFakeTimers();
    try {
      renderLive();
      fireEvent.click(screen.getByRole("button", { name: "Continue" }));
      expect(screen.getByTestId("live-controls-ribbon")).toBeTruthy();

      act(() => {
        vi.advanceTimersByTime(3_400);
      });
      expect(screen.getByTestId("live-stage").className).toContain("live-ui-faded");

      fireEvent.pointerMove(document.body);
      act(() => {
        vi.advanceTimersByTime(20);
      });
      expect(screen.getByTestId("live-stage").className).not.toContain("live-ui-faded");
    } finally {
      vi.useRealTimers();
    }
  });

  it("renders prompt card and sends prompt responses", async () => {
    sessionState.promptOffer = {
      promptId: "prompt-1",
      cueVersion: 11,
      scene: "mainDynamic",
      domain: "text",
      action: "cut",
      affordance: "tap",
      expiresAt: Date.now() + 5_000,
      haptic: false
    };

    renderLive();
    fireEvent.click(screen.getByRole("button", { name: "Continue" }));
    await waitFor(() => {
      expect(screen.getByTestId("live-prompt-card")).toBeTruthy();
    });

    fireEvent.click(screen.getByRole("button", { name: "Primary" }));
    expect(sessionState.sendPromptResponse).toHaveBeenCalledWith(
      expect.objectContaining({
        promptId: "prompt-1",
        responseType: "tap"
      })
    );
  });

  it("shows diagnostics ribbon and toggles diagnostics drawer", async () => {
    renderLive();

    fireEvent.click(screen.getByRole("button", { name: "Continue" }));

    await waitFor(() => {
      expect(screen.getByTestId("live-diagnostics-ribbon")).toBeTruthy();
    });
    expect(screen.queryByTestId("live-diagnostics-panel")).toBeNull();

    fireEvent.click(screen.getByRole("button", { name: "Diagnostics" }));

    expect(screen.getByTestId("live-diagnostics-panel")).toBeTruthy();
  });

  it("shows mission-control offline card when engine is off", async () => {
    sessionState.cue.payload.engineRunning = false;

    renderLive();
    continueIntoLive();

    await waitFor(() => {
      expect(screen.getByTestId("live-offline-card").textContent).toContain("ENGINE OFFLINE");
    });
    expect(screen.queryByTestId("fixed-layer")).toBeNull();
    expect(screen.queryByTestId("dynamic-overlay")).toBeNull();
    expect(screen.queryByTestId("live-controls-ribbon")).toBeNull();
  });

  it("shows mission-control offline card when link is down", async () => {
    sessionState.connected = false;
    sessionState.linkState = "offline";

    renderLive();
    continueIntoLive();

    await waitFor(() => {
      expect(screen.getByTestId("live-offline-card").textContent).toContain("LINK RECONNECTING");
    });
    expect(screen.queryByTestId("live-controls-ribbon")).toBeNull();
  });

  it("falls back to fixed output when no cue has arrived yet", async () => {
    sessionState.cue = null;

    renderLive();
    continueIntoLive();

    await waitFor(() => {
      expect(screen.getByTestId("fixed-layer")).toBeTruthy();
    });
    expect(screen.queryByTestId("dynamic-overlay")).toBeNull();
  });

  it("infers dynamic output for main state when output mode is missing", async () => {
    sessionState.cue.showState = "main";
    sessionState.cue.payload = {
      engineRunning: true,
      showStreamInterstitial: "https://stream.example.com/interstitial.m3u8"
    };

    renderLive();
    continueIntoLive();

    await waitFor(() => {
      expect(screen.queryByTestId("fixed-layer")).toBeNull();
    });
    expect(screen.getByTestId("dynamic-overlay")).toBeTruthy();
  });

  it("renders main dynamic mode on dynamic layer only", async () => {
    sessionState.cue.showState = "main";
    sessionState.cue.payload.outputMode = "dynamic";
    sessionState.cue.payload.showFixed = false;
    sessionState.cue.payload.showDynamic = true;

    renderLive();
    continueIntoLive();

    await waitFor(() => {
      expect(screen.queryByTestId("fixed-layer")).toBeNull();
    });
    expect(screen.getByTestId("dynamic-overlay")).toBeTruthy();
  });

  it("renders main static mode on fixed layer only", async () => {
    sessionState.cue.showState = "main";
    sessionState.cue.payload.outputMode = "program";
    sessionState.cue.payload.showFixed = true;
    sessionState.cue.payload.showDynamic = false;

    renderLive();
    continueIntoLive();

    await waitFor(() => {
      expect(screen.getByTestId("fixed-layer")).toBeTruthy();
    });
    expect(screen.queryByTestId("dynamic-overlay")).toBeNull();
  });

  it("switches to interstitial recovery after stream dropout grace", async () => {
    vi.useFakeTimers();
    try {
      sessionState.cue.showState = "ending";
      sessionState.cue.payload.outputMode = "program";
      sessionState.cue.payload.showFixed = true;
      sessionState.cue.payload.showDynamic = false;
      fixedLayerShouldError = true;

      renderLive();
      continueIntoLive();

      expect(screen.getByTestId("live-status-toast").textContent).toContain("stream hold");

      act(() => {
        vi.advanceTimersByTime(3_100);
        fixedLayerShouldError = false;
        vi.advanceTimersByTime(300);
      });

      const layer = screen.getByTestId("fixed-layer");
      expect(layer.getAttribute("data-force-source")).toContain("interstitial.m3u8");
      expect(screen.queryByTestId("live-offline-card")).toBeNull();
    } finally {
      vi.useRealTimers();
    }
  });

  it("shows stream-hold offline card if interstitial recovery is unavailable", async () => {
    vi.useFakeTimers();
    try {
      sessionState.cue.payload.outputMode = "program";
      sessionState.cue.payload.showFixed = true;
      sessionState.cue.payload.showDynamic = false;
      sessionState.cue.payload.showStreamInterstitial = "";
      fixedLayerShouldError = true;

      renderLive();
      continueIntoLive();

      act(() => {
        vi.advanceTimersByTime(8_600);
      });

      expect(screen.getByTestId("live-offline-card").textContent).toContain("STREAM HOLD");
      expect(screen.queryByTestId("live-controls-ribbon")).toBeNull();
    } finally {
      vi.useRealTimers();
    }
  });

  it("runs a 3-second countdown before returning from offline to live", async () => {
    vi.useFakeTimers();
    try {
      sessionState.cue.payload.engineRunning = false;
      sessionState.cue.payload.showFixed = false;
      sessionState.cue.payload.showDynamic = true;
      sessionState.cue.payload.outputMode = "dynamic";

      renderLive();
      continueIntoLive();
      expect(screen.getByTestId("live-offline-card").textContent).toContain("ENGINE OFFLINE");

      act(() => {
        sessionState.cue.payload.engineRunning = true;
        vi.advanceTimersByTime(300);
      });

      expect(screen.getByTestId("live-reveal-countdown").textContent).toContain("3");

      act(() => {
        vi.advanceTimersByTime(1_100);
      });
      act(() => {
        vi.advanceTimersByTime(1_100);
      });
      act(() => {
        vi.advanceTimersByTime(1_100);
      });

      expect(screen.queryByTestId("live-reveal-countdown")).toBeNull();
      expect(screen.getByTestId("live-controls-ribbon")).toBeTruthy();
    } finally {
      vi.useRealTimers();
    }
  });

  it("shows blocking permission modal until onDone completes", async () => {
    renderLive();

    expect(screen.getByTestId("live-permission-overlay")).toBeTruthy();
    expect(screen.queryByTestId("live-controls-ribbon")).toBeNull();

    fireEvent.click(screen.getByRole("button", { name: "Continue" }));

    await waitFor(() => {
      expect(screen.queryByTestId("live-permission-overlay")).toBeNull();
    });
    expect(screen.getByTestId("live-controls-ribbon")).toBeTruthy();
  });
});
