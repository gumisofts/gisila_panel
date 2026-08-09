"use client";

import { useEffect, useRef, useState } from "react";
import useSWR from "swr";
import {
  Button,
  InlineNotification,
  ProgressIndicator,
  ProgressStep,
  RadioTile,
  SkeletonText,
  Stack,
  Tag,
  Tile,
  TileGroup,
} from "@carbon/react";
import { Branch, Renew, Time } from "@carbon/icons-react";
import { toast } from "@/lib/toast";
import { api, fetcher, getToken, getWsBase } from "@/lib/api";
import { formatRelative, scrollLogPaneToBottom } from "@/lib/utils";
import type { BuildLog, Deployment, ListResponse } from "@/lib/types";
import "../_app-detail.scss";

// ── Stage detection ────────────────────────────────────────────────────────────
const STAGES = [
  {
    id: "provision",
    label: "Provision",
    match: /provision/i,
  },
  {
    id: "build",
    label: "Fetch & Build",
    match: /^\[?agent.*\bbuild\b|git clone|pip install|dart compile|go build|cargo build/i,
  },
  {
    id: "apply-unit",
    label: "Configure",
    match: /apply-unit|apply.vhost/i,
  },
  {
    id: "restart",
    label: "Start",
    match: /^\[?agent.*\brestart\b|^\[?agent.*\bstart\b/i,
  },
  {
    id: "done",
    label: "Done",
    match: /deployment succeeded/i,
  },
] as const;

type StageId = (typeof STAGES)[number]["id"];

function detectStage(logs: BuildLog[]): StageId {
  for (let i = logs.length - 1; i >= 0; i--) {
    const line = logs[i].line;
    for (let s = STAGES.length - 1; s >= 0; s--) {
      if (STAGES[s].match.test(line)) return STAGES[s].id;
    }
  }
  return "provision";
}

const WS_BASE = getWsBase();

type TagType = "green" | "blue" | "cyan" | "red" | "gray";

function statusTagType(status: string): TagType {
  switch (status) {
    case "running":
    case "succeeded":
      return "green";
    case "building":
    case "deploying":
      return "blue";
    case "queued":
      return "cyan";
    case "failed":
    case "crashed":
    case "deleting":
      return "red";
    default:
      return "gray";
  }
}

function lineClass(stream: BuildLog["stream"]): string {
  if (stream === "stderr") return "gisila-term__line gisila-term__line--stderr";
  if (stream === "system") return "gisila-term__line gisila-term__line--system";
  return "gisila-term__line";
}

// ── Stepper ───────────────────────────────────────────────────────────────────
function Stepper({
  current,
  deploymentStatus,
}: {
  current: StageId;
  deploymentStatus: string;
}) {
  const failed = deploymentStatus === "failed";
  const currentIdx = STAGES.findIndex((s) => s.id === current);
  // Past the last stage every step reads as complete; ProgressIndicator marks
  // the step at currentIndex as in-progress rather than done.
  const displayIdx = current === "done" ? STAGES.length : currentIdx;

  return (
    <ProgressIndicator currentIndex={displayIdx} spaceEqually>
      {STAGES.map((stage, idx) => (
        <ProgressStep
          key={stage.id}
          label={stage.label}
          invalid={failed && idx === currentIdx}
        />
      ))}
    </ProgressIndicator>
  );
}

// ── Log panel ─────────────────────────────────────────────────────────────────
function LogPanel({
  appId,
  deployment,
}: {
  appId: number;
  deployment: Deployment;
}) {
  const [lines, setLines] = useState<BuildLog[]>([]);
  const [loading, setLoading] = useState(true);
  const endRef = useRef<HTMLDivElement>(null);
  const wsRef = useRef<WebSocket | null>(null);
  const active = ["queued", "building", "deploying"].includes(deployment.status);
  const currentStage = detectStage(lines);

  // Load stored logs
  useEffect(() => {
    setLines([]);
    setLoading(true);
    api<{ results: BuildLog[] }>(
      `/apps/${appId}/deployments/${deployment.id}/logs`
    )
      .then((d) => setLines(d.results))
      .catch(() => {})
      .finally(() => setLoading(false));
  }, [appId, deployment.id]);

  // Live stream for active deployments
  useEffect(() => {
    if (!active) return;
    const token = getToken();
    if (!token) return;

    const ws = new WebSocket(
      `${WS_BASE}/apps/${appId}/build-logs/${deployment.id}`
    );
    wsRef.current = ws;

    ws.onopen = () => {
      ws.send(JSON.stringify({ token, appId, deploymentId: deployment.id }));
    };
    ws.onmessage = (ev) => {
      try {
        const data = JSON.parse(ev.data);
        const raw =
          typeof data.message === "string"
            ? data.message
            : JSON.stringify(data.message);
        let parsed: { stream?: string; line?: string } = {};
        try { parsed = JSON.parse(raw); } catch { parsed = { line: raw }; }
        const line: BuildLog = {
          id: Date.now(),
          deploymentId: deployment.id,
          stream: (parsed.stream ?? "stdout") as BuildLog["stream"],
          line: parsed.line ?? raw,
          createdAt: data.ts ?? new Date().toISOString(),
        };
        setLines((prev) => [...prev, line].slice(-2000));
      } catch { /* ignore */ }
    };
    return () => { ws.close(); wsRef.current = null; };
  }, [appId, deployment.id, active]);

  // Auto-scroll inside the log pane only (not the page).
  useEffect(() => {
    scrollLogPaneToBottom(endRef.current);
  }, [lines]);

  return (
    <Stack gap={5}>
      <Stepper current={currentStage} deploymentStatus={deployment.status} />

      <div className="gisila-term">
        <div className="gisila-term__bar">
          <span>build log · #{deployment.id}</span>
          {active && (
            <span className="gisila-term__live">
              <span className="gisila-app__pulse gisila-app__pulse--live" />
              live
            </span>
          )}
        </div>
        <div className="gisila-term__body">
          {loading && (
            <p className="gisila-term__placeholder">Loading logs…</p>
          )}
          {!loading && lines.length === 0 && (
            <p className="gisila-term__placeholder">
              {active ? "Waiting for output…" : "No logs recorded for this deployment."}
            </p>
          )}
          {lines.map((l, i) => (
            <div key={i} className={lineClass(l.stream)}>
              <span className="gisila-term__ts">
                {l.createdAt ? l.createdAt.slice(11, 19) : "--:--:--"}
              </span>
              {l.stream === "system" && (
                <span className="gisila-term__stream">[sys]</span>
              )}
              {l.stream === "stderr" && (
                <span className="gisila-term__stream">[err]</span>
              )}
              {l.line}
            </div>
          ))}
          <div ref={endRef} />
        </div>
      </div>
    </Stack>
  );
}

// ── Main tab ──────────────────────────────────────────────────────────────────
export function DeploymentsTab({ appId }: { appId: number }) {
  const { data, mutate } = useSWR<ListResponse<Deployment>>(
    `/apps/${appId}/deployments/`,
    fetcher,
    { refreshInterval: 4000 }
  );
  const [selected, setSelected] = useState<Deployment | null>(null);

  // Auto-select most recent deployment
  useEffect(() => {
    if (data?.results.length && !selected) {
      setSelected(data.results[0]);
    }
    // Keep selected in sync with polling updates
    if (selected && data?.results) {
      const updated = data.results.find((d) => d.id === selected.id);
      if (updated) setSelected(updated);
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [data]);

  async function rollback(d: Deployment) {
    try {
      await api(`/apps/${appId}/deployments/${d.id}/rollback`, { method: "POST" });
      toast.success("Rollback queued");
      mutate();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed");
    }
  }

  if (!data) {
    return <SkeletonText paragraph lineCount={4} />;
  }

  if (data.results.length === 0) {
    return (
      <Tile className="gisila-empty">
        No deployments yet. Trigger one with{" "}
        <span className="gisila-app__mono">Deploy now</span>.
      </Tile>
    );
  }

  return (
    <div className="gisila-deploy">
      <TileGroup
        className="gisila-deploy__list"
        name="deployment"
        legend="Deployment history"
        valueSelected={selected ? String(selected.id) : undefined}
        onChange={(value) => {
          const picked = data.results.find((d) => String(d.id) === value);
          if (picked) setSelected(picked);
        }}
      >
        {data.results.map((d) => (
          <RadioTile key={d.id} id={`deployment-${d.id}`} value={String(d.id)}>
            <div className="gisila-deploy__item">
              <div className="gisila-deploy__item-head">
                <span className="gisila-app__mono">#{d.id}</span>
                <Tag type={statusTagType(d.status)} size="sm">
                  {d.status}
                </Tag>
                {d.isActive && (
                  <Tag type="green" size="sm">
                    live
                  </Tag>
                )}
              </div>
              <span className="gisila-app__label">
                {formatRelative(d.createdAt)}
              </span>
              {d.gitCommitSha && (
                <span className="gisila-app__inline gisila-app__mono">
                  <Branch size={16} />
                  {d.gitCommitSha.slice(0, 7)}
                </span>
              )}
            </div>
          </RadioTile>
        ))}
      </TileGroup>

      <div className="gisila-deploy__panel">
        {selected ? (
          <>
            <div className="gisila-app__toolbar">
              <div className="gisila-app__inline">
                <span>Deployment #{selected.id}</span>
                <Tag type={statusTagType(selected.status)} size="sm">
                  {selected.status}
                </Tag>
                {selected.finishedAt && (
                  <span className="gisila-app__inline gisila-app__label">
                    <Time size={16} />
                    {formatRelative(selected.finishedAt)}
                  </span>
                )}
              </div>
              <div className="gisila-app__row-actions">
                <Button
                  kind="ghost"
                  size="sm"
                  hasIconOnly
                  renderIcon={Renew}
                  iconDescription="Refresh deployments"
                  onClick={() => mutate()}
                />
                {selected.status === "succeeded" && !selected.isActive && (
                  <Button
                    kind="tertiary"
                    size="sm"
                    onClick={() => rollback(selected)}
                  >
                    Rollback
                  </Button>
                )}
              </div>
            </div>

            {selected.failureReason && (
              <InlineNotification
                kind="error"
                lowContrast
                hideCloseButton
                title="Error"
                subtitle={selected.failureReason}
              />
            )}

            <LogPanel appId={appId} deployment={selected} key={selected.id} />
          </>
        ) : (
          <Tile className="gisila-empty">
            Select a deployment to see its logs.
          </Tile>
        )}
      </div>
    </div>
  );
}
