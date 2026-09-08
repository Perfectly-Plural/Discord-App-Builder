import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import packageMetadata from "./package.json" with { type: "json" };

export default defineConfig({
  plugins: [react()],
  define: {
    __APP_VERSION__: JSON.stringify(packageMetadata.version)
  },
  base: "./",
  build: {
    outDir: "dist-renderer",
    emptyOutDir: true
  }
});
