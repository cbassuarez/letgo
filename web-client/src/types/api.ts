import type { DeviceProfile } from "@conductor/protocol";

export interface ParticipantIdentityResponse {
  profile: DeviceProfile;
}

export interface LogbookEntry {
  signer: string;
  message: string;
  createdAt: number;
  updatedAt: number;
}

export interface PublicLogbookEntry extends LogbookEntry {
  participantTag: string;
}

export interface LogbookFeedResponse {
  entries: PublicLogbookEntry[];
  nextCursor: string | null;
}
