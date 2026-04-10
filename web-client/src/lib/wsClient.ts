import type { WireEnvelope } from "@conductor/protocol";

export const BACKEND_HOST = "letgo-backend.onrender.com";
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
