export const logger = {
  info: (message: string, data?: unknown): void => {
    console.log(JSON.stringify({ level: "info", message, data, ts: Date.now() }));
  },
  warn: (message: string, data?: unknown): void => {
    console.warn(JSON.stringify({ level: "warn", message, data, ts: Date.now() }));
  },
  error: (message: string, data?: unknown): void => {
    console.error(JSON.stringify({ level: "error", message, data, ts: Date.now() }));
  }
};
