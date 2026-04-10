import type { Config } from "tailwindcss";

export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        ink: "#131311",
        ember: "#d95f35",
        leaf: "#2e8f58",
        fog: "#f2ede6"
      },
      boxShadow: {
        panel: "0 20px 60px rgba(0, 0, 0, 0.24)"
      }
    }
  },
  plugins: []
} satisfies Config;
