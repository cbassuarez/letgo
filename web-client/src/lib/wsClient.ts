import type { WireEnvelope } from "@conductor/protocol";

export const createSessionSocket = (hashedId: string): WebSocket => {
  const explicit = import.meta.env.VITE_BACKEND_WS_URL as string | undefined;
  if (explicit) {
    return new WebSocket(`${explicit.replace(/\/$/, "")}/ws/device/${hashedId}`);
  }

  const protocol = window.location.protocol === "https:" ? "wss" : "ws";
  return new WebSocket(`${protocol}://${window.location.host}/ws/device/${hashedId}`);
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
