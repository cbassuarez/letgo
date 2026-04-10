import { useState } from "react";

export interface PermissionState {
  audio: boolean;
  motion: boolean;
  geolocation: boolean;
}

const initialState: PermissionState = {
  audio: false,
  motion: false,
  geolocation: false
};

export const usePermissionFlow = () => {
  const [state, setState] = useState<PermissionState>(initialState);

  const enableAudio = async (): Promise<void> => {
    const context = new AudioContext();
    await context.resume();
    setState((current) => ({ ...current, audio: context.state === "running" }));
  };

  const enableMotion = async (): Promise<void> => {
    const motionEvent = DeviceMotionEvent as typeof DeviceMotionEvent & {
      requestPermission?: () => Promise<"granted" | "denied">;
    };

    if (typeof motionEvent.requestPermission === "function") {
      const result = await motionEvent.requestPermission();
      setState((current) => ({ ...current, motion: result === "granted" }));
      return;
    }

    setState((current) => ({ ...current, motion: true }));
  };

  const enableGeo = async (): Promise<void> => {
    await new Promise<void>((resolve, reject) => {
      navigator.geolocation.getCurrentPosition(
        () => resolve(),
        (error) => reject(error),
        {
          enableHighAccuracy: true,
          timeout: 5000
        }
      );
    });
    setState((current) => ({ ...current, geolocation: true }));
  };

  return {
    permissions: state,
    completed: state.audio && state.motion && state.geolocation,
    enableAudio,
    enableMotion,
    enableGeo
  };
};
