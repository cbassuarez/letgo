import type { WireEnvelope } from "@conductor/protocol";

const DEFAULT_BACKEND_HOST = "letgo-backend.onrender.com";

const sanitizeHost = (value: string | undefined): string | null => {
  if (!value) {
    return null;
  }
  const trimmed = value.trim();
  if (!trimmed) {
    return null;
  }

  if (trimmed.startsWith("http://") || trimmed.startsWith("https://") || trimmed.startsWith("ws://") || trimmed.startsWith("wss://")) {
    try {
      const parsed = new URL(trimmed);
      return parsed.host || null;
    } catch {
      return null;
    }
  }

  return trimmed.replace(/\/+$/, "");
};

const envHost =
  sanitizeHost(import.meta.env.VITE_BACKEND_HOST) ??
  sanitizeHost(import.meta.env.VITE_BACKEND_HTTP_ORIGIN) ??
  sanitizeHost(import.meta.env.VITE_BACKEND_WS_URL);

export const BACKEND_HOST = envHost ?? DEFAULT_BACKEND_HOST;
export const BACKEND_HEALTH_URL = `https://${BACKEND_HOST}/health`;
export const HARNESS_WS_URL = `wss://${BACKEND_HOST}/ws/harness`;
export const DEVICE_WS_BASE_URL = `wss://${BACKEND_HOST}/ws/device`;

export const buildDeviceWsUrl = (hashedId: string): string =>
  `${DEVICE_WS_BASE_URL}/${encodeURIComponent(hashedId)}`;

export const createSessionSocket = (hashedId: string): WebSocket => {
  return new WebSocket(buildDeviceWsUrl(hashedId));
};

export const sendEnvelope = <T>(socket: WebSocket, kind: WireEnvelope<T>["kind"], data: T): void => {
  if (socket.readyState !== WebSocket.OPEN) {
    return;
  }

  socket.send(
    JSON.stringify({
      kind,
      data,
      sentAt: Date.now()
    } satisfies WireEnvelope<T>)
  );
};
