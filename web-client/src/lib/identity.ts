export const hashedPattern = /^[a-f0-9]{32}$/;

export const isValidHashedId = (value: string): boolean => hashedPattern.test(value);
