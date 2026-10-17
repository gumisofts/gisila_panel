/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_API_URL?: string;
  readonly VITE_WS_URL?: string;
}

// Injected by vite.config.ts `define`.
declare const __GISILA_UI_VERSION__: string;
declare const __GISILA_UI_COMMIT__: string;
declare const __GISILA_UI_BUILT_AT__: string;

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
