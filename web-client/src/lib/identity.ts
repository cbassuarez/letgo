import { isChecksumValid } from "@conductor/protocol";

export const hashedPattern = /^[a-f0-9]{32}$/;

export const isValidHashedId = (value: string): boolean => isChecksumValid(value);
