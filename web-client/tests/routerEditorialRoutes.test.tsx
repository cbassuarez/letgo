import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { createMemoryRouter, RouterProvider } from "react-router-dom";

vi.mock("../src/routes/DeviceRoute", () => ({
  DeviceRoute: (): JSX.Element => <main>Mock Live Route</main>
}));

vi.mock("../src/routes/ParticipantLogbookRoute", () => ({
  ParticipantLogbookRoute: (): JSX.Element => <main>Mock Participant Logbook</main>
}));

vi.mock("../src/components/FixedVideoLayer", () => ({
  FixedVideoLayer: (): JSX.Element | null => null
}));

vi.mock("../src/lib/api", () => ({
  fetchLogbookFeed: () => Promise.resolve({ entries: [], nextCursor: null })
}));

vi.mock("../src/hooks/useConductorSession", () => ({
  useConductorSession: () => ({
    cue: null,
    vector: {
      textAmount: 0.4,
      compositeBias: 0.5,
      audioGain: 0.5,
      spatialX: 0.5,
      spatialY: 0.5,
      spatialZ: 0.5
    },
    driftMs: 0,
    connected: false,
    fallbackActive: false,
    fallbackAgeMs: 0,
    linkState: "connecting",
    retryInMs: null,
    logicalNow: 0,
    audienceVector: {
      vector: {
        textAmount: 0.4,
        compositeBias: 0.5,
        audioGain: 0.5,
        spatialX: 0.5,
        spatialY: 0.5,
        spatialZ: 0.5
      },
      participantCount: 0,
      updatedAt: 0,
      compositorModes: {}
    },
    lightingState: {
      targetColor: {
        oklch: { l: 0.56, c: 0.12, h: 220 },
        hex: "#2f5f8e"
      },
      confidence: 0,
      entropy: 0,
      stability: 1,
      trend: "hold",
      participantCount: 0,
      updatedAt: 0,
      zoneField: []
    },
    audioFeatures: { rms: 0, spectralCentroid: 0.5, flux: 0.5, transientDensity: 0, updatedAt: 0 },
    phoneAudioPoolState: {
      gateArmed: false,
      gateCommitted: false,
      quadRouteReady: false,
      availableDevices: [],
      activeVoices: {},
      updatedAt: 0
    },
    crowdPickWindow: null,
    crowdPickResult: null,
    proceduralState: {},
    textScene: {},
    phoneAudioCommand: null,
    promptOffer: null,
    sendPermissions: vi.fn(),
    sendZoneUpdate: vi.fn(),
    sendParticipantVector: vi.fn(),
    sendPhoneAudioAck: vi.fn(),
    sendCrowdPickVote: vi.fn(),
    sendPromptResponse: vi.fn()
  })
}));

import { appRoutes } from "../src/app/router";

const validHash = "0123456789abcdef0123456789abcdef";

const renderAt = (path: string) => {
  const router = createMemoryRouter(appRoutes, {
    initialEntries: [path]
  });

  render(<RouterProvider router={router} />);

  return router;
};

describe("participant editorial routing", () => {
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  });

  it("renders hashed HOME at /:hashedId", () => {
    renderAt(`/${validHash}`);

    expect(screen.getByRole("heading", { name: /I keep this film open/i })).toBeTruthy();
  });

  it("renders hashed ABOUT at /:hashedId/about", () => {
    renderAt(`/${validHash}/about`);

    expect(screen.getByText("Plot")).toBeTruthy();
    expect(screen.getByText("Participation Ethic")).toBeTruthy();
  });

  it("keeps hash context when navigating HOME and ABOUT", async () => {
    const router = renderAt(`/${validHash}`);

    fireEvent.click(screen.getByRole("link", { name: "ABOUT" }));
    await waitFor(() => expect(router.state.location.pathname).toBe(`/${validHash}/about`));

    fireEvent.click(screen.getByRole("link", { name: "HOME" }));
    await waitFor(() => expect(router.state.location.pathname).toBe(`/${validHash}`));
  });

  it("routes ENTER nav action to /:hashedId/live", async () => {
    const router = renderAt(`/${validHash}`);

    fireEvent.click(screen.getByRole("link", { name: "ENTER" }));

    await waitFor(() => expect(router.state.location.pathname).toBe(`/${validHash}/live`));
    expect(screen.getByText("Mock Live Route")).toBeTruthy();
  });

  it("renders keyless intro at /", () => {
    renderAt("/");

    expect(screen.getByText(/Tap your program to enter the participant field/i)).toBeTruthy();
  });

  it("ensures /about uses keyless intro and does not collide with hash route", () => {
    renderAt("/about");

    expect(screen.getByText(/Tap your program to enter the participant field/i)).toBeTruthy();
    expect(screen.queryByText("Participant Link Not Valid")).toBeNull();
  });

  it("shows lockout when hash is invalid", () => {
    renderAt("/not-a-valid-hash");

    expect(screen.getByText("Participant Link Not Valid")).toBeTruthy();
  });

  it("keeps public and participant logbook routes reachable", () => {
    renderAt("/logbook");
    expect(screen.getByRole("heading", { name: "Digital Logbook" })).toBeTruthy();

    renderAt(`/${validHash}/logbook`);
    expect(screen.getByText("Mock Participant Logbook")).toBeTruthy();
  });
});
