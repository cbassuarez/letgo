import { afterEach, describe, expect, it } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { FixedVideoLayer } from "../src/components/FixedVideoLayer";

const baseCue = {
  cueId: "cue-test",
  showState: "preshow",
  issuedAt: 0,
  logicalTime: 0,
  payload: {}
} as any;

describe("FixedVideoLayer", () => {
  afterEach(() => {
    cleanup();
  });

  it("returns null when disabled", () => {
    const view = render(<FixedVideoLayer cue={baseCue} logicalNow={0} enabled={false} />);
    expect(view.container.firstChild).toBeNull();
  });

  it("shows fallback until video is ready", () => {
    render(<FixedVideoLayer cue={baseCue} logicalNow={0} enabled />);
    expect(screen.getByTestId("fixed-video-fallback")).toBeTruthy();
  });

  it("uses interstitial source when output mode is interstitial", () => {
    render(
      <FixedVideoLayer
        cue={{
          ...baseCue,
          showState: "main",
          payload: { outputMode: "interstitial_loop" }
        }}
        logicalNow={0}
        enabled
      />
    );

    const video = screen.getByTestId("fixed-video-layer").querySelector("video");
    expect(video?.getAttribute("src")).toContain("/media/interstitial-loop.mp4");
  });

  it("uses lane source when showFixedLaneId is present", () => {
    render(
      <FixedVideoLayer
        cue={{
          ...baseCue,
          showState: "main",
          payload: { showFixedLaneId: "lane-a" }
        }}
        logicalNow={0}
        enabled
      />
    );

    const video = screen.getByTestId("fixed-video-layer").querySelector("video");
    expect(video?.getAttribute("src")).toContain("/media/show-fixed/lane-a.mp4");
  });

  it("hides fallback when video can play", () => {
    render(<FixedVideoLayer cue={baseCue} logicalNow={0} enabled />);

    const video = screen.getByTestId("fixed-video-layer").querySelector("video");
    expect(video).toBeTruthy();
    fireEvent.canPlay(video as HTMLVideoElement);

    expect(screen.queryByTestId("fixed-video-fallback")).toBeNull();
  });

  it("keeps fallback visible on load error", () => {
    render(<FixedVideoLayer cue={baseCue} logicalNow={0} enabled />);

    const video = screen.getByTestId("fixed-video-layer").querySelector("video");
    expect(video).toBeTruthy();
    fireEvent.error(video as HTMLVideoElement);

    expect(screen.getByTestId("fixed-video-fallback")).toBeTruthy();
  });
});
