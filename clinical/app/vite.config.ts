import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

const here = fileURLToPath(new URL(".", import.meta.url));

// Two pages: launch.html (the SMART launch URI) and index.html (the redirect URI and the app).
export default defineConfig({
  base: "./",
  plugins: [react()],
  build: {
    rollupOptions: { input: { index: resolve(here, "index.html"), launch: resolve(here, "launch.html") } },
  },
});
