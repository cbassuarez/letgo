import type { LogbookEntry, LogbookFeedResponse, ParticipantIdentityResponse } from "../types/api";
import { BACKEND_HOST } from "./wsClient";

export const BACKEND_HTTP_ORIGIN = `https://${BACKEND_HOST}`;

const readJson = async <T>(response: Response): Promise<T> => {
  const json = (await response.json()) as T & { error?: string; message?: string };
  if (!response.ok) {
    const errorMessage =
      typeof json.message === "string"
        ? json.message
        : typeof json.error === "string"
          ? json.error
          : "request_failed";
    throw new Error(errorMessage);
  }
  return json;
};

export const fetchIdentity = async (hashedId: string): Promise<ParticipantIdentityResponse> => {
  const response = await fetch(`${BACKEND_HTTP_ORIGIN}/identity/${encodeURIComponent(hashedId)}`, {
    method: "GET"
  });
  return readJson<ParticipantIdentityResponse>(response);
};

export const fetchParticipantLogbookEntry = async (hashedId: string): Promise<LogbookEntry | null> => {
  const response = await fetch(`${BACKEND_HTTP_ORIGIN}/logbook/${encodeURIComponent(hashedId)}`, {
    method: "GET"
  });

  if (response.status === 404) {
    return null;
  }

  const json = await readJson<{ entry: LogbookEntry }>(response);
  return json.entry;
};

export const upsertParticipantLogbookEntry = async (
  hashedId: string,
  payload: { signer: string; message: string }
): Promise<LogbookEntry> => {
  const response = await fetch(`${BACKEND_HTTP_ORIGIN}/logbook/${encodeURIComponent(hashedId)}`, {
    method: "PUT",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify(payload)
  });
  const json = await readJson<{ entry: LogbookEntry }>(response);
  return json.entry;
};

export const fetchLogbookFeed = async (cursor?: string): Promise<LogbookFeedResponse> => {
  const params = new URLSearchParams();
  params.set("limit", "24");
  if (cursor) {
    params.set("cursor", cursor);
  }

  const response = await fetch(`${BACKEND_HTTP_ORIGIN}/logbook?${params.toString()}`, {
    method: "GET"
  });
  return readJson<LogbookFeedResponse>(response);
};
