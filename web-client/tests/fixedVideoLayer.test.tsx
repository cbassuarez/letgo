import { afterEach, describe, expect, it, vi } from "vitest";
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

  it("renders the video surface without a fallback overlay", () => {
    render(<FixedVideoLayer cue={baseCue} logicalNow={0} enabled />);
    expect(screen.getByTestId("fixed-video-layer")).toBeTruthy();
    expect(screen.queryByTestId("fixed-video-fallback")).toBeNull();
  });

  it("uses stream-map interstitial source when output mode is interstitial", () => {
    render(
      <FixedVideoLayer
        cue={{
          ...baseCue,
          showState: "main",
          payload: {
            outputMode: "interstitial_loop",
            showStreamInterstitial: "https://stream.example.com/interstitial.m3u8"
          }
        }}
        logicalNow={0}
        enabled
      />
    );

    const layer = screen.getByTestId("fixed-video-layer");
    expect(layer.getAttribute("data-active-source")).toBe(
      "https://stream.example.com/interstitial.m3u8"
    );
  });

  it("prioritizes scene playlist for ending even when output mode is interstitial", () => {
    render(
      <FixedVideoLayer
        cue={{
          ...baseCue,
          showState: "ending",
          payload: {
            outputMode: "interstitial_loop",
            showStreamInterstitial: "https://stream.example.com/interstitial.m3u8",
            showStreamEnding: "https://stream.example.com/ending.m3u8"
          }
        }}
        logicalNow={0}
        enabled
      />
    );

    const layer = screen.getByTestId("fixed-video-layer");
    expect(layer.getAttribute("data-active-source")).toBe(
      "https://stream.example.com/ending.m3u8"
    );
  });

  it("prefers explicit media ref over interstitial fallback when both are present", () => {
    render(
      <FixedVideoLayer
        cue={{
          ...baseCue,
          showState: "main",
          payload: {
            outputMode: "interstitial_loop",
            showFixedMediaRef: "https://stream.example.com/interstitial.m3u8"
          }
        }}
        logicalNow={0}
        enabled
      />
    );

    const layer = screen.getByTestId("fixed-video-layer");
    expect(layer.getAttribute("data-active-source")).toBe("https://stream.example.com/interstitial.m3u8");
  });

  it("uses explicit shared media ref when provided", () => {
    render(
      <FixedVideoLayer
        cue={{
          ...baseCue,
          showState: "main",
          payload: { showFixedMediaRef: "media/show-fixed/main-01.mp4" }
        }}
        logicalNow={0}
        enabled
      />
    );

    const layer = screen.getByTestId("fixed-video-layer");
    expect(layer.getAttribute("data-active-source")).toContain("/media/show-fixed/main-01.mp4");
  });

  it("treats m3u8 refs as stream output and disables looping", () => {
    render(
      <FixedVideoLayer
        cue={{
          ...baseCue,
          showState: "main",
          payload: { showFixedMediaRef: "https://stream.example.com/main.m3u8" }
        }}
        logicalNow={0}
        enabled
      />
    );

    const layer = screen.getByTestId("fixed-video-layer");
    expect(layer.getAttribute("data-active-source")).toBe("https://stream.example.com/main.m3u8");
    const video = layer.querySelector("video");
    expect(video?.loop).toBe(false);
  });

  it("hides fallback when video can play", () => {
    render(
      <FixedVideoLayer
        cue={{
          ...baseCue,
          payload: { showFixedMediaRef: "https://stream.example.com/preshow.m3u8" }
        }}
        logicalNow={0}
        enabled
      />
    );

    const video = screen.getByTestId("fixed-video-layer").querySelector("video");
    expect(video).toBeTruthy();
    fireEvent.canPlay(video as HTMLVideoElement);

    expect(screen.queryByTestId("fixed-video-fallback")).toBeNull();
  });

  it("keeps frame visible on load error without fallback overlay takeover", () => {
    render(
      <FixedVideoLayer
        cue={{
          ...baseCue,
          payload: { showFixedMediaRef: "https://stream.example.com/preshow.m3u8" }
        }}
        logicalNow={0}
        enabled
      />
    );

    const video = screen.getByTestId("fixed-video-layer").querySelector("video");
    expect(video).toBeTruthy();
    fireEvent.error(video as HTMLVideoElement);

    expect(screen.queryByTestId("fixed-video-fallback")).toBeNull();
  });

  it("uses no source by default without stream refs when local fallback is disabled", () => {
    render(<FixedVideoLayer cue={baseCue} logicalNow={0} enabled />);

    const layer = screen.getByTestId("fixed-video-layer");
    expect(layer.getAttribute("data-active-source")).toBe("none");
  });

  it("uses forced source override for recovery playback", () => {
    render(
      <FixedVideoLayer
        cue={baseCue}
        logicalNow={0}
        enabled
        forcedScene="interstitial"
        forcedSource="https://stream.example.com/interstitial.m3u8"
      />
    );

    const layer = screen.getByTestId("fixed-video-layer");
    expect(layer.getAttribute("data-active-source")).toBe("https://stream.example.com/interstitial.m3u8");
    expect(layer.getAttribute("data-active-scene")).toBe("interstitial");
  });

  it("reports playback readiness transitions", () => {
    const onPlaybackReadyChange = vi.fn();
    render(
      <FixedVideoLayer
        cue={{
          ...baseCue,
          payload: { showFixedMediaRef: "https://stream.example.com/preshow.m3u8" }
        }}
        logicalNow={0}
        enabled
        onPlaybackReadyChange={onPlaybackReadyChange}
      />
    );

    const video = screen.getByTestId("fixed-video-layer").querySelector("video");
    expect(video).toBeTruthy();
    fireEvent.canPlay(video as HTMLVideoElement);
    fireEvent.error(video as HTMLVideoElement);

    expect(onPlaybackReadyChange).toHaveBeenCalledWith(true);
    expect(onPlaybackReadyChange).toHaveBeenCalledWith(false);
  });
});
