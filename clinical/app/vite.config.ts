import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

const here = fileURLToPath(new URL(".", import.meta.url));

// One page, served by the gateway (server/gateway.py), which is also the SMART launch URI.
export default defineConfig({
  base: "./",
  plugins: [react()],
  build: { rollupOptions: { input: { index: resolve(here, "index.html") } } },
});
