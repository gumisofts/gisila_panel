"use client";

import { useEffect, useRef, useState } from "react";
import { Button, Stack } from "@carbon/react";
import { PauseFilled, PlayFilled, TrashCan } from "@carbon/icons-react";
import { getToken, getWsBase } from "@/lib/api";
import { scrollLogPaneToBottom } from "@/lib/utils";
import "../_app-detail.scss";

const WS_URL = getWsBase();

interface LogLine {
  ts: string;
  stream: string;
  line: string;
}

type ConnState = "connecting" | "connected" | "reconnecting";

function lineClass(stream: string): string {
  if (stream === "stderr") return "gisila-term__line gisila-term__line--stderr";
  if (stream === "system") return "gisila-term__line gisila-term__line--system";
  return "gisila-term__line";
}

export function LogsTab({ appId }: { appId: number }) {
  const [lines, setLines] = useState<LogLine[]>([]);
  const [paused, setPaused] = useState(false);
  const [conn, setConn] = useState<ConnState>("connecting");
  const pausedRef = useRef(false);
  const endRef = useRef<HTMLDivElement | null>(null);

  // Keep a ref in sync so pausing doesn't tear down / recreate the socket.
  useEffect(() => {
    pausedRef.current = paused;
  }, [paused]);

  useEffect(() => {
    const token = getToken();
    if (!token) return;

    let ws: WebSocket | null = null;
    let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
    let attempt = 0;
    let closed = false; // set on unmount to stop reconnecting

    const append = (l: LogLine) =>
      setLines((prev) => [...prev, l].slice(-1000));

    function connect() {
      setConn(attempt === 0 ? "connecting" : "reconnecting");
      ws = new WebSocket(`${WS_URL}/apps/${appId}/logs`);

      ws.onopen = () => {
        attempt = 0;
        setConn("connected");
        ws?.send(JSON.stringify({ token, appId }));
      };

      ws.onmessage = (ev) => {
        if (pausedRef.current) return;
        try {
          const data = JSON.parse(ev.data);
          if (data.error) {
            append({
              ts: new Date().toISOString(),
              stream: "system",
              line: `[error] ${data.error}`,
            });
            return;
          }
          const raw =
            typeof data.message === "string"
              ? data.message
              : JSON.stringify(data.message);
          let parsed: { stream?: string; line?: string } = {};
          try {
            parsed = JSON.parse(raw);
          } catch {
            parsed = { line: raw };
          }
          append({
            ts: data.ts ?? new Date().toISOString(),
            stream: parsed.stream ?? "stdout",
            line: parsed.line ?? raw,
          });
        } catch {
          /* ignore malformed frames */
        }
      };

      ws.onclose = () => {
        if (closed) return;
        setConn("reconnecting");
        // Exponential backoff capped at 10s.
        const delay = Math.min(1000 * 2 ** attempt, 10000);
        attempt += 1;
        reconnectTimer = setTimeout(connect, delay);
      };

      ws.onerror = () => {
        // onclose will follow and trigger the reconnect.
        ws?.close();
      };
    }

    connect();

    return () => {
      closed = true;
      if (reconnectTimer) clearTimeout(reconnectTimer);
      ws?.close();
    };
  }, [appId]);

  useEffect(() => {
    if (!paused) scrollLogPaneToBottom(endRef.current);
  }, [lines, paused]);

  const statusMeta = {
    connecting: { label: "Connecting…", tone: "waiting" },
    connected: { label: "Live", tone: "live" },
    reconnecting: { label: "Reconnecting…", tone: "waiting" },
  }[conn];

  return (
    <Stack gap={5}>
      <div className="gisila-app__toolbar">
        <div className="gisila-app__inline">
          <span className="gisila-app__label">
            Live runtime logs · journald
          </span>
          <span className="gisila-app__inline gisila-app__label">
            <span className={`gisila-app__pulse gisila-app__pulse--${statusMeta.tone}`} />
            {statusMeta.label}
          </span>
        </div>
        <div className="gisila-app__row-actions">
          <Button
            size="sm"
            kind="tertiary"
            renderIcon={paused ? PlayFilled : PauseFilled}
            onClick={() => setPaused((p) => !p)}
          >
            {paused ? "Resume" : "Pause"}
          </Button>
          <Button
            size="sm"
            kind="tertiary"
            renderIcon={TrashCan}
            onClick={() => setLines([])}
          >
            Clear
          </Button>
        </div>
      </div>

      <div className="gisila-term">
        <div className="gisila-term__body gisila-term__body--tall">
          {lines.length === 0 && (
            <p className="gisila-term__placeholder">
              Waiting for output… deploy or restart the app to populate this
              stream.
            </p>
          )}
          {lines.map((l, i) => (
            <div key={i} className={lineClass(l.stream)}>
              <span className="gisila-term__ts">{l.ts.slice(11, 19)}</span>
              {l.line}
            </div>
          ))}
          <div ref={endRef} />
        </div>
      </div>
    </Stack>
  );
}
