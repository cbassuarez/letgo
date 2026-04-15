import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

const normalizeBase = (value: string | undefined): string => {
  if (!value || value.trim() === "") {
    return "/";
  }

  const trimmed = value.trim();
  if (trimmed === "/") {
    return "/";
  }

  return trimmed.endsWith("/") ? trimmed : `${trimmed}/`;
};

export default defineConfig({
  base: normalizeBase(process.env.VITE_APP_BASE),
  plugins: [react()],
  server: {
    port: 5173,
    host: true
  }
});
