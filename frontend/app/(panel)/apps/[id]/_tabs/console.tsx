"use client";

import { useEffect, useRef, useState } from "react";
import { toast } from "@/lib/toast";
import { Play, Trash2, Terminal } from "lucide-react";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { api, getToken, getWsBase } from "@/lib/api";
import { cn } from "@/lib/utils";

const WS_URL = getWsBase();

interface OutputLine {
  ts: string;
  stream: string;
  line: string;
}

export function ConsoleTab({ appId }: { appId: number }) {
  const [command, setCommand] = useState("");
  const [lines, setLines] = useState<OutputLine[]>([]);
  const [running, setRunning] = useState(false);
  const wsRef = useRef<WebSocket | null>(null);
  const endRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    endRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [lines]);

  // Tear down any open socket on unmount.
  useEffect(() => () => wsRef.current?.close(), []);

  const append = (l: OutputLine) =>
    setLines((prev) => [...prev, l].slice(-2000));

  async function run() {
    const token = getToken();
    const cmd = command.trim();
    if (!cmd || !token || running) return;

    setRunning(true);
    append({ ts: new Date().toISOString(), stream: "system", line: `$ ${cmd}` });

    let execId: string;
    try {
      const res = await api<{ execId: string }>(`/apps/${appId}/exec`, {
        method: "POST",
        body: JSON.stringify({ command: cmd }),
      });
      execId = res.execId;
    } catch (err: unknown) {
      append({
        ts: new Date().toISOString(),
        stream: "stderr",
        line: `[error] ${err instanceof Error ? err.message : "failed to queue command"}`,
      });
      setRunning(false);
      return;
    }

    setCommand("");

    // The worker streams a duplicate "$ cmd" system line on connect (from the
    // replayed history); that's fine — it confirms the run started.
    const ws = new WebSocket(`${WS_URL}/apps/${appId}/exec/${execId}`);
    wsRef.current = ws;

    ws.onopen = () => ws.send(JSON.stringify({ token, appId, execId }));

    ws.onmessage = (ev) => {
      try {
        const data = JSON.parse(ev.data);
        if (data.error) {
          append({
            ts: new Date().toISOString(),
            stream: "stderr",
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
        const line = parsed.line ?? raw;
        // Completion marker emitted by the exec worker.
        const exitMatch = /^__EXIT__:(-?\d+)$/.exec(line);
        if (exitMatch) {
          const code = Number(exitMatch[1]);
          append({
            ts: data.ts ?? new Date().toISOString(),
            stream: code === 0 ? "system" : "stderr",
            line:
              code === 0
                ? "✓ command finished (exit 0)"
                : `✗ command exited with code ${code}`,
          });
          setRunning(false);
          ws.close();
          return;
        }
        append({
          ts: data.ts ?? new Date().toISOString(),
          stream: parsed.stream ?? "stdout",
          line,
        });
      } catch {
        /* ignore malformed frames */
      }
    };

    ws.onclose = () => {
      setRunning(false);
    };
    ws.onerror = () => {
      ws.close();
    };
  }

  return (
    <Card>
      <CardContent className="space-y-3 p-5">
        <div className="flex items-center gap-2">
          <Terminal className="h-4 w-4 text-muted-foreground" />
          <p className="text-xs uppercase tracking-wider text-muted-foreground">
            Run a command as the app user
          </p>
          {running && (
            <span className="flex items-center gap-1.5 text-xs text-muted-foreground">
              <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-emerald-400" />
              running…
            </span>
          )}
        </div>

        <form
          onSubmit={(e) => {
            e.preventDefault();
            run();
          }}
          className="flex items-center gap-2"
        >
          <Input
            value={command}
            onChange={(e) => setCommand(e.target.value)}
            placeholder="e.g. python manage.py migrate · pip list · ls -la"
            className="font-mono text-xs"
            disabled={running}
          />
          <Button type="submit" size="sm" disabled={running || !command.trim()}>
            <Play className="h-4 w-4" /> Run
          </Button>
          <Button
            type="button"
            size="sm"
            variant="outline"
            onClick={() => setLines([])}
          >
            <Trash2 className="h-4 w-4" /> Clear
          </Button>
        </form>

        <p className="text-xs text-muted-foreground">
          Runs in the app&apos;s working directory. For Python apps the
          virtualenv is activated automatically, so <code>python</code>,{" "}
          <code>pip</code> and <code>manage.py</code> use the app interpreter.
        </p>

        <div className="scrollbar-thin h-[420px] overflow-y-auto rounded-md border border-border/60 bg-black/80 p-3 font-mono text-xs text-emerald-200">
          {lines.length === 0 && (
            <p className="text-muted-foreground">
              No output yet. Type a command above and hit Run.
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
