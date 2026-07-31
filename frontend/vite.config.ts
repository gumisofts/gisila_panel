import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Top-level API prefixes served by the Dart backend. Listed explicitly rather
// than proxying "/" so the dev server keeps serving its own routes (/@vite,
// /src, /node_modules) and the SPA fallback for client-side navigation.
const API_PREFIXES = [
  "auth",
  "me",
  "apps",
  "projects",
  "teams",
  "applications",
  "services",
  "databases",
  "mongo",
  "storage",
  "mail",
];

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "."),
    },
  },
  css: {
    preprocessorOptions: {
      scss: {
        api: "modern-compiler",
        // Carbon's Sass is resolved from node_modules by bare specifier.
        loadPaths: ["node_modules"],
        // Carbon still uses a number of deprecated Sass features internally;
        // without this every build prints thousands of lines of warnings we
        // cannot act on.
        quietDeps: true,
        silenceDeprecations: ["global-builtin", "import"],
      },
    },
  },
  build: {
    outDir: "../backend/web",
    emptyOutDir: true,
  },
  server: {
    proxy: {
      "/ws": {
        target: "ws://localhost:8000",
        ws: true,
      },
      // Dev-only. Unlike VITE_API_URL, a dev-server proxy is never baked into
      // the bundle, so the production build keeps using origin-relative URLs.
      ...Object.fromEntries(
        API_PREFIXES.map((prefix) => [
          `/${prefix}`,
          { target: "http://localhost:8000", changeOrigin: true },
        ]),
      ),
    },
  },
});
