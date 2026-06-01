"use client";

import { useEffect, useRef, useState } from "react";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Pause, Play, Trash2 } from "lucide-react";
import { getToken, getWsBase } from "@/lib/api";
import { cn } from "@/lib/utils";

const WS_URL = getWsBase();

interface LogLine {
  ts: string;
  stream: string;
  line: string;
}

type ConnState = "connecting" | "connected" | "reconnecting";

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
    if (!paused) endRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [lines, paused]);

  const statusMeta = {
    connecting: { label: "Connecting…", dot: "bg-amber-400" },
    connected: { label: "Live", dot: "bg-emerald-400 animate-pulse" },
    reconnecting: { label: "Reconnecting…", dot: "bg-amber-400 animate-pulse" },
  }[conn];

  return (
    <Card>
      <CardContent className="space-y-3 p-5">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <p className="text-xs uppercase tracking-wider text-muted-foreground">
              Live runtime logs · journald
            </p>
            <span className="flex items-center gap-1.5 text-xs text-muted-foreground">
              <span className={cn("h-1.5 w-1.5 rounded-full", statusMeta.dot)} />
              {statusMeta.label}
            </span>
          </div>
          <div className="flex items-center gap-2">
            <Button
              size="sm"
              variant="outline"
              onClick={() => setPaused((p) => !p)}
            >
              {paused ? <Play className="h-4 w-4" /> : <Pause className="h-4 w-4" />}
              {paused ? "Resume" : "Pause"}
            </Button>
            <Button size="sm" variant="outline" onClick={() => setLines([])}>
              <Trash2 className="h-4 w-4" /> Clear
            </Button>
          </div>
        </div>
        <div className="scrollbar-thin h-[480px] overflow-y-auto rounded-md border border-border/60 bg-black/80 p-3 font-mono text-xs text-emerald-200">
          {lines.length === 0 && (
            <p className="text-muted-foreground">
              Waiting for output… deploy or restart the app to populate this
              stream.
            </p>
          )}
          {lines.map((l, i) => (
            <div
              key={i}
              className={
                l.stream === "stderr"
                  ? "text-red-300"
                  : l.stream === "system"
                    ? "text-fuchsia-300"
                    : ""
              }
            >
              <span className="mr-2 text-muted-foreground">
                {l.ts.slice(11, 19)}
              </span>
              {l.line}
            </div>
          ))}
          <div ref={endRef} />
        </div>
      </CardContent>
    </Card>
  );
}
