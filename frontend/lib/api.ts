const API_BASE = import.meta.env.VITE_API_URL ?? "";

// ── WebSocket base URL ────────────────────────────────────────────────────────
// In dev VITE_WS_URL=ws://localhost:8000 is set in .env.
// In production (panel served from the same Dart origin) it is derived
// automatically from the current page location.
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
  return s.replace(/_([a-z0-9])/g, (_, c) => c.toUpperCase());
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
