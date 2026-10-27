import { useEffect, useRef, useState } from "react";
import { Button, Stack } from "@carbon/react";
import { PauseFilled, PlayFilled, TrashCan } from "@carbon/icons-react";
import { openLogSocket, type LogSocketState } from "@/lib/log-socket";
import { scrollLogPaneToBottom } from "@/lib/utils";
import "../_app-detail.scss";
import { renderAnsi } from "@/lib/ansi";

interface LogLine {
  ts: string;
  stream: string;
  line: string;
}

const MAX_LINES = 1000;

function lineClass(stream: string): string {
  if (stream === "stderr") return "gisila-term__line gisila-term__line--stderr";
  if (stream === "system") return "gisila-term__line gisila-term__line--system";
  return "gisila-term__line";
}

export function LogsTab({ appId }: { appId: number }) {
  const [lines, setLines] = useState<LogLine[]>([]);
  const [paused, setPaused] = useState(false);
  const [conn, setConn] = useState<LogSocketState>("connecting");
  const [connError, setConnError] = useState<string | undefined>();
  const pausedRef = useRef(false);
  // Lines that arrived while paused, shown on resume.
  const heldRef = useRef<LogLine[]>([]);
  const endRef = useRef<HTMLDivElement | null>(null);

  // Keep a ref in sync so pausing doesn't tear down / recreate the socket.
  useEffect(() => {
    pausedRef.current = paused;
    if (!paused && heldRef.current.length > 0) {
      const held = heldRef.current;
      heldRef.current = [];
      setLines((prev) => [...prev, ...held].slice(-MAX_LINES));
    }
  }, [paused]);

  useEffect(() => {
    const append = (l: LogLine) => {
      if (pausedRef.current) {
        heldRef.current = [...heldRef.current, l].slice(-MAX_LINES);
        return;
      }
      setLines((prev) => [...prev, l].slice(-MAX_LINES));
    };

    return openLogSocket({
      path: `/apps/${appId}/logs`,
      auth: { appId },
      onLine: ({ ts, stream, line }) => append({ ts, stream, line }),
      onState: (state, error) => {
        setConn(state);
        setConnError(error);
        if (error) {
          append({
            ts: new Date().toISOString(),
            stream: "system",
            line: `[error] ${error}`,
          });
        }
      },
    });
  }, [appId]);

  useEffect(() => {
    if (!paused) scrollLogPaneToBottom(endRef.current);
  }, [lines, paused]);

  const statusMeta = {
    connecting: { label: "Connecting…", tone: "waiting" },
    live: { label: paused ? "Paused" : "Live", tone: "live" },
    reconnecting: { label: "Reconnecting…", tone: "waiting" },
    stopped: { label: connError ? "Stopped" : "Disconnected", tone: "waiting" },
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
              {renderAnsi(l.line)}
            </div>
          ))}
          <div ref={endRef} />
        </div>
      </div>
    </Stack>
  );
}
