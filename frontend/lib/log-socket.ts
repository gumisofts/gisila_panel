import { getToken, getWsBase, handleUnauthorized } from "@/lib/api";

// Live-log WebSockets (backend/lib/endpoints/logs.dart). The client sends one
// auth frame with the token and ids; the server answers `{ready: true}`, then
// `{message, ts, replay?}` frames, or `{error}` and closes.

export type LogSocketState = "connecting" | "live" | "reconnecting" | "stopped";

export interface LogFrame {
  ts: string;
  stream: string;
  line: string;
  /** Replayed from history rather than live. */
  replay: boolean;
}

/** Error frames meaning the session itself is no longer valid. */
const AUTH_ERRORS = new Set(["auth_required", "invalid_token"]);

/** Parses a `{message, ts}` frame into a log line. */
export function parseLogFrame(data: {
  message?: unknown;
  ts?: string;
  replay?: boolean;
}): LogFrame {
  const raw =
    typeof data.message === "string" ? data.message : JSON.stringify(data.message);
  let parsed: { stream?: string; line?: string } = {};
  try {
    parsed = JSON.parse(raw);
  } catch {
    parsed = { line: raw };
  }
  return {
    ts: data.ts ?? new Date().toISOString(),
    stream: parsed.stream ?? "stdout",
    line: parsed.line ?? raw,
    replay: data.replay === true,
  };
}

/**
 * Handles an `{error}` frame. Returns true when it was an auth failure, in
 * which case the user has been sent back to sign in.
 */
export function handleSocketError(error: string): boolean {
  if (!AUTH_ERRORS.has(error)) return false;
  handleUnauthorized();
  return true;
}

/**
 * Opens a log socket at `path` (under /ws) and keeps it open, reconnecting
 * with backoff when the connection drops. An error frame stops it for good:
 * reconnecting cannot fix a bad token or a missing app. Returns a function
 * that closes it.
 */
export function openLogSocket(opts: {
  path: string;
  /** Ids sent with the token in the auth frame. */
  auth: Record<string, unknown>;
  onLine: (line: LogFrame) => void;
  onState?: (state: LogSocketState, error?: string) => void;
  /** Called on each (re)connect before the server replays history. */
  onConnect?: () => void;
  reconnect?: boolean;
}): () => void {
  const { reconnect = true } = opts;
  let ws: WebSocket | null = null;
  let timer: ReturnType<typeof setTimeout> | null = null;
  let attempt = 0;
  let stopped = false;

  const setState = (state: LogSocketState, error?: string) =>
    opts.onState?.(state, error);

  const stop = (error?: string) => {
    stopped = true;
    if (timer) clearTimeout(timer);
    ws?.close();
    setState("stopped", error);
  };

  function connect() {
    const token = getToken();
    if (!token) {
      stop("auth_required");
      handleUnauthorized();
      return;
    }
    setState(attempt === 0 ? "connecting" : "reconnecting");
    const socket = new WebSocket(`${getWsBase()}${opts.path}`);
    ws = socket;

    socket.onopen = () => {
      opts.onConnect?.();
      socket.send(JSON.stringify({ token, ...opts.auth }));
    };

    socket.onmessage = (ev) => {
      let data: { error?: string; ready?: boolean; message?: unknown; ts?: string; replay?: boolean };
      try {
        data = JSON.parse(ev.data);
      } catch {
        return; // malformed frame
      }
      if (typeof data.error === "string") {
        handleSocketError(data.error);
        stop(data.error);
        return;
      }
      attempt = 0;
      setState("live");
      if (data.ready) return;
      opts.onLine(parseLogFrame(data));
    };

    socket.onclose = () => {
      if (stopped || ws !== socket) return;
      if (!reconnect) {
        stop();
        return;
      }
      setState("reconnecting");
      const delay = Math.min(1000 * 2 ** attempt, 10000);
      attempt += 1;
      timer = setTimeout(connect, delay);
    };

    // onclose follows and decides whether to reconnect.
    socket.onerror = () => socket.close();
  }

  connect();
  return () => {
    stopped = true;
    if (timer) clearTimeout(timer);
    ws?.close();
  };
}
