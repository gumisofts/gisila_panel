"use client";

import { useEffect, useRef, useState } from "react";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Pause, Play, Trash2 } from "lucide-react";
import { getToken } from "@/lib/api";

const WS_URL =
  (process.env.NEXT_PUBLIC_WS_URL ??
    process.env.NEXT_PUBLIC_API_URL?.replace(/^http/, "ws") ??
    "ws://localhost:8000") + "/ws";

interface LogLine {
  ts: string;
  stream: string;
  line: string;
}

export function LogsTab({ appId }: { appId: number }) {
  const [lines, setLines] = useState<LogLine[]>([]);
  const [paused, setPaused] = useState(false);
  const wsRef = useRef<WebSocket | null>(null);
  const endRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    const token = getToken();
    if (!token) return;
    const url = `${WS_URL}/apps/${appId}/logs`;
    const ws = new WebSocket(url);
    wsRef.current = ws;

    ws.onopen = () => {
      ws.send(JSON.stringify({ token, appId }));
      setLines((l) => [
        ...l,
        {
          ts: new Date().toISOString(),
          stream: "system",
          line: "[ws] connected",
        },
      ]);
    };
    ws.onmessage = (ev) => {
      if (paused) return;
      try {
        const data = JSON.parse(ev.data);
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
        setLines((l) =>
          [
            ...l,
            {
              ts: data.ts ?? new Date().toISOString(),
              stream: parsed.stream ?? "stdout",
              line: parsed.line ?? raw,
            },
          ].slice(-1000),
        );
      } catch {
        /* ignore */
      }
    };
    ws.onclose = () =>
      setLines((l) => [
        ...l,
        {
          ts: new Date().toISOString(),
          stream: "system",
          line: "[ws] closed",
        },
      ]);
    return () => ws.close();
  }, [appId, paused]);

  useEffect(() => {
    if (!paused) endRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [lines, paused]);

  return (
    <Card>
      <CardContent className="space-y-3 p-5">
        <div className="flex items-center justify-between">
          <p className="text-xs uppercase tracking-wider text-muted-foreground">
            Live runtime logs · journald
          </p>
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
