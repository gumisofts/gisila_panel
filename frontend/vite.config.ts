import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { execSync } from "child_process";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

/// Build stamp for the UI bundle, matching infra/build-defines.sh for the
/// Dart binaries. The UI is often deployed from the prebuilt backend/web/, so
/// it can lag the backend — the About panel compares the two.
function git(args: string): string {
  try {
    return execSync(`git ${args}`, { cwd: __dirname, stdio: ["ignore", "pipe", "ignore"] })
      .toString()
      .trim();
  } catch {
    return "";
  }
}
const UI_VERSION =
  process.env.VERSION || git("describe --tags --always --dirty") || "dev";
const UI_COMMIT = process.env.COMMIT || git("rev-parse --short=12 HEAD");

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
  "notifications",
  "audit",
  "system",
];

export default defineConfig({
  plugins: [react()],
  define: {
    __GISILA_UI_VERSION__: JSON.stringify(UI_VERSION),
    __GISILA_UI_COMMIT__: JSON.stringify(UI_COMMIT),
    __GISILA_UI_BUILT_AT__: JSON.stringify(new Date().toISOString()),
  },
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
          {
            target: "http://localhost:8000",
            changeOrigin: true,
            // These prefixes are both API endpoints and client-side routes:
            // /apps is an endpoint, /apps/new is a page. Proxying on prefix
            // alone sends the page request to the backend and the browser gets
            // nothing back. A navigation asks for a document and belongs to the
            // SPA; the app's own fetches never do.
            bypass(req: { headers: Record<string, string | undefined> }) {
              if (req.headers.accept?.includes("text/html")) return "/index.html";
            },
          },
        ]),
      ),
    },
  },
});
