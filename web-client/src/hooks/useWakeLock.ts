import { useEffect, useRef } from "react";

export const useWakeLock = (enabled: boolean): void => {
  const lockRef = useRef<WakeLockSentinel | null>(null);

  useEffect(() => {
    if (!enabled || !("wakeLock" in navigator)) {
      return;
    }

    const acquire = async (): Promise<void> => {
      try {
        lockRef.current = await navigator.wakeLock.request("screen");
      } catch {
        /* browser denied or not supported */
      }
    };

    const onVisibilityChange = (): void => {
      if (document.visibilityState === "visible") {
        void acquire();
      }
    };

    void acquire();
    document.addEventListener("visibilitychange", onVisibilityChange);

    return () => {
      document.removeEventListener("visibilitychange", onVisibilityChange);
      lockRef.current?.release().catch(() => {});
      lockRef.current = null;
    };
  }, [enabled]);
};
