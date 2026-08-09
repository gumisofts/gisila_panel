"use client";

import { useEffect, useRef, useState } from "react";
import { Button, Stack, TextInput } from "@carbon/react";
import { PlayFilled, Terminal, TrashCan } from "@carbon/icons-react";
import { api, getToken, getWsBase } from "@/lib/api";
import { scrollLogPaneToBottom } from "@/lib/utils";
import "../_app-detail.scss";

const WS_URL = getWsBase();

interface OutputLine {
  ts: string;
  stream: string;
  line: string;
}

function lineClass(stream: string): string {
  if (stream === "stderr") return "gisila-term__line gisila-term__line--stderr";
  if (stream === "system") return "gisila-term__line gisila-term__line--system";
  return "gisila-term__line";
}

export function ConsoleTab({ appId }: { appId: number }) {
  const [command, setCommand] = useState("");
  const [lines, setLines] = useState<OutputLine[]>([]);
  const [running, setRunning] = useState(false);
  const wsRef = useRef<WebSocket | null>(null);
  const endRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    scrollLogPaneToBottom(endRef.current);
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
    <Stack gap={5}>
      <div className="gisila-app__inline">
        <Terminal size={16} />
        <span className="gisila-app__label">
          Run a command as the app user
        </span>
        {running && (
          <span className="gisila-app__inline gisila-app__label">
            <span className="gisila-app__pulse gisila-app__pulse--live" />
            running…
          </span>
        )}
      </div>

      <form
        onSubmit={(e) => {
          e.preventDefault();
          run();
        }}
        className="gisila-app__form-row"
      >
        <div className="gisila-app__form-field">
          <TextInput
            id="console-command"
            labelText="Command"
            hideLabel
            value={command}
            onChange={(e) => setCommand(e.target.value)}
            placeholder="e.g. dart run bin/migrate.dart up · python manage.py migrate"
            disabled={running}
          />
        </div>
        <Button
          type="submit"
          renderIcon={PlayFilled}
          disabled={running || !command.trim()}
        >
          Run
        </Button>
        <Button
          type="button"
          kind="tertiary"
          renderIcon={TrashCan}
          onClick={() => setLines([])}
        >
          Clear
        </Button>
      </form>

      <p className="gisila-app__hint">
        Runs in the app&apos;s working directory. For Python apps the virtualenv
        is activated automatically, so <code>python</code>, <code>pip</code> and{" "}
        <code>manage.py</code> use the app interpreter. For Dart apps the source
        tree and SDK are on PATH, e.g.{" "}
        <code>dart run bin/migrate.dart up</code>.
      </p>

      <div className="gisila-term">
        <div className="gisila-term__body">
          {lines.length === 0 && (
            <p className="gisila-term__placeholder">
              No output yet. Type a command above and hit Run.
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
