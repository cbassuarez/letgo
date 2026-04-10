import type { Config } from "tailwindcss";

export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        cyanotype: {
          "0": "#e4f7ff",
          50: "#c9ecff",
          100: "#96c6df",
          200: "#60a9cb",
          300: "#2b7ca7",
          500: "#0c4a73",
          700: "#0a2f4f",
          900: "#061b30",
          950: "#040e1c"
        },
        ink: "#040e1c",
        fog: "#c9ecff"
      },
      boxShadow: {
        panel: "0 22px 60px rgba(0, 0, 0, 0.35)"
      }
    }
  },
  plugins: []
} satisfies Config;
