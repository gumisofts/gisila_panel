import { toast } from "@/lib/toast";

const API_BASE = import.meta.env.VITE_API_URL ?? "";

// ── WebSocket base URL ────────────────────────────────────────────────────────
// Derived from the current page location, since the panel is always served
// from the same origin as the Dart API. Only set VITE_WS_URL when running the
// UI on a different origin than the API — never for a build whose output lands
// in the git-tracked backend/web/, as that value is baked into the bundle.
export function getWsBase(): string {
  const configured = import.meta.env.VITE_WS_URL;
  if (configured) return `${configured}/ws`;
  const proto = window.location.protocol === "https:" ? "wss:" : "ws:";
  return `${proto}//${window.location.host}/ws`;
}

// ── Case conversion ──────────────────────────────────────────────────────────
// The Dart backend serialises all model fields in snake_case. The TypeScript
// types use camelCase throughout. This helper recursively converts every
// object key so the two sides agree without touching any string values.

function snakeToCamel(s: string): string {
  // Preserve any leading underscores (e.g. the injected `_def` key) so they are
  // not folded into the next letter — `_def` must stay `_def`, not become `Def`.
  const lead = s.match(/^_+/)?.[0] ?? "";
  return (
    lead +
    s.slice(lead.length).replace(/_([a-z0-9])/g, (_, c) => c.toUpperCase())
  );
}

function deepCamelCase(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(deepCamelCase);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>).map(([k, v]) => [
        snakeToCamel(k),
        deepCamelCase(v),
      ])
    );
  }
  return value;
}

export const TOKEN_KEY = "gisila.token";

export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY);
}

export function setToken(token: string | null) {
  if (token == null) localStorage.removeItem(TOKEN_KEY);
  else localStorage.setItem(TOKEN_KEY, token);
}

export class ApiError extends Error {
  constructor(
    public status: number,
    public code: string | undefined,
    message: string,
    public details?: unknown,
  ) {
    super(message);
  }
}

// ── Session expiry handling ──────────────────────────────────────────────────
// The backend only issues short-lived access tokens (no refresh-token flow
// exists yet), so once a token expires every authenticated request starts
// coming back 401. Without a global handler for that, the stale token stays
// in localStorage forever, `PanelLayout`'s login guard keeps thinking the user
// is signed in (it only checks *presence* of a token, not validity), and the
// whole panel is left stuck making calls that will never succeed again. Any
// 401 returned for a request that *carried* a token means that token is no
// longer valid — clear it and bounce to /login so the user can sign in again.
// A 401 on a request made *without* a token (e.g. a bad login/register
// attempt) is a normal auth failure and must be left for the caller to handle.
let loggedOut = false;

function handleUnauthorized() {
  if (loggedOut) return;
  loggedOut = true;
  setToken(null);
  if (typeof window !== "undefined" && !window.location.pathname.startsWith("/login")) {
    toast.error("Your session has expired. Please sign in again.");
    window.location.assign("/login");
  }
}

export async function api<T>(
  path: string,
  init: RequestInit = {},
): Promise<T> {
  const headers = new Headers(init.headers ?? {});
  headers.set("Content-Type", "application/json");
  const token = getToken();
  if (token) headers.set("Authorization", `Bearer ${token}`);

  const res = await fetch(`${API_BASE}${path}`, { ...init, headers });
  const text = await res.text();
  const raw = text ? JSON.parse(text) : null;
  const data = deepCamelCase(raw) as typeof raw;
  if (!res.ok) {
    if (res.status === 401 && token) handleUnauthorized();
    const err = data?.error ?? {};
    throw new ApiError(
      res.status,
      err.code,
      err.message ?? res.statusText,
      err.details,
    );
  }
  return data as T;
}

export const fetcher = <T>(path: string) => api<T>(path);

// ── Binary file helpers ───────────────────────────────────────────────────────
// `api()` always sends/expects JSON, so file download/upload need their own
// fetch wrappers that carry the bearer token (a plain <a download> can't).

export async function downloadFile(
  path: string,
  fallbackName: string,
): Promise<void> {
  const headers = new Headers();
  const token = getToken();
  if (token) headers.set("Authorization", `Bearer ${token}`);

  const res = await fetch(`${API_BASE}${path}`, { headers });
  if (!res.ok) {
    if (res.status === 401 && token) handleUnauthorized();
    const text = await res.text();
    throw new ApiError(res.status, undefined, text || res.statusText);
  }

  // Prefer the server-provided filename from Content-Disposition.
  let name = fallbackName;
  const cd = res.headers.get("content-disposition");
  const m = cd && /filename="?([^"]+)"?/.exec(cd);
  if (m) name = m[1];

  const blob = await res.blob();
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = name;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

export async function uploadFile(path: string, file: File): Promise<void> {
  const headers = new Headers();
  const token = getToken();
  if (token) headers.set("Authorization", `Bearer ${token}`);
  headers.set("Content-Type", "application/octet-stream");
  headers.set("X-Filename", file.name);

  const res = await fetch(`${API_BASE}${path}`, {
    method: "POST",
    headers,
    body: file,
  });
  if (!res.ok) {
    if (res.status === 401 && token) handleUnauthorized();
    const text = await res.text();
    let msg = res.statusText;
    try {
      msg = JSON.parse(text)?.error?.message ?? msg;
    } catch {
      /* non-JSON error body */
    }
    throw new ApiError(res.status, undefined, msg);
  }
}
