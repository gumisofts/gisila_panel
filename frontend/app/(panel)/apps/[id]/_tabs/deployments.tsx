"use client";

import { useEffect, useRef, useState } from "react";
import useSWR from "swr";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { StatusDot } from "@/components/ui/status-dot";
import { api, fetcher, getToken } from "@/lib/api";
import { formatRelative } from "@/lib/utils";
import type { BuildLog, Deployment, ListResponse } from "@/lib/types";
import {
  CheckCircle2,
  Circle,
  Clock,
  GitBranch,
  Hammer,
  Loader2,
  RefreshCw,
  ServerCog,
  XCircle,
  Zap,
} from "lucide-react";
import { cn } from "@/lib/utils";

// ── Stage detection ────────────────────────────────────────────────────────────
const STAGES = [
  {
    id: "provision",
    label: "Provision",
    icon: ServerCog,
    match: /provision/i,
  },
  {
    id: "build",
    label: "Fetch & Build",
    icon: Hammer,
    match: /^\[?agent.*\bbuild\b|git clone|pip install|dart compile|go build|cargo build/i,
  },
  {
    id: "apply-unit",
    label: "Configure",
    icon: ServerCog,
    match: /apply-unit|apply.vhost/i,
  },
  {
    id: "restart",
    label: "Start",
    icon: Zap,
    match: /^\[?agent.*\brestart\b|^\[?agent.*\bstart\b/i,
  },
  {
    id: "done",
    label: "Done",
    icon: CheckCircle2,
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

// ── WS_URL ────────────────────────────────────────────────────────────────────
const WS_BASE =
  (process.env.NEXT_PUBLIC_WS_URL ??
    process.env.NEXT_PUBLIC_API_URL?.replace(/^http/, "ws") ??
    "ws://localhost:8000") + "/ws";

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

  return (
    <div className="flex items-center gap-0 overflow-x-auto pb-1">
      {STAGES.map((stage, idx) => {
        const done = idx < currentIdx || stage.id === "done" && current === "done";
        const active = idx === currentIdx && stage.id !== "done";
        const isFailed = failed && active;
        const Icon = stage.icon;

        return (
          <div key={stage.id} className="flex items-center">
            <div
              className={cn(
                "flex items-center gap-1.5 rounded-md px-2.5 py-1.5 text-xs font-medium transition-colors",
                isFailed
                  ? "text-destructive"
                  : done || stage.id === "done" && current === "done"
                  ? "text-green-600 dark:text-green-400"
                  : active
                  ? "text-foreground"
                  : "text-muted-foreground/50"
              )}
            >
              {isFailed ? (
                <XCircle className="h-3.5 w-3.5 text-destructive" />
              ) : done ? (
                <CheckCircle2 className="h-3.5 w-3.5 text-green-500" />
              ) : active ? (
                current === "done" ? (
                  <CheckCircle2 className="h-3.5 w-3.5 text-green-500" />
                ) : (
                  <Loader2 className="h-3.5 w-3.5 animate-spin text-primary" />
                )
              ) : (
                <Circle className="h-3.5 w-3.5" />
              )}
              {stage.label}
            </div>
            {idx < STAGES.length - 1 && (
              <div
                className={cn(
                  "h-px w-6 shrink-0",
                  idx < currentIdx ? "bg-green-500/50" : "bg-border"
                )}
              />
            )}
          </div>
        );
      })}
    </div>
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

  // Auto-scroll
  useEffect(() => {
    endRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [lines]);

  return (
    <div className="flex flex-col gap-3 h-full">
      {/* Stepper */}
      <Stepper current={currentStage} deploymentStatus={deployment.status} />

      {/* Terminal */}
      <div className="flex-1 min-h-0 rounded-md border border-border/60 bg-[#0d1117] overflow-hidden">
        <div className="flex items-center gap-2 border-b border-white/5 bg-white/5 px-3 py-1.5">
          <div className="h-2.5 w-2.5 rounded-full bg-red-500/70" />
          <div className="h-2.5 w-2.5 rounded-full bg-yellow-500/70" />
          <div className="h-2.5 w-2.5 rounded-full bg-green-500/70" />
          <span className="ml-2 text-xs text-white/40 font-mono">
            build log · #{deployment.id}
          </span>
          {active && (
            <span className="ml-auto flex items-center gap-1 text-xs text-emerald-400">
              <span className="h-1.5 w-1.5 rounded-full bg-emerald-400 animate-pulse" />
              live
            </span>
          )}
        </div>
        <div className="h-[420px] overflow-y-auto p-3 font-mono text-xs scrollbar-thin">
          {loading && (
            <p className="text-white/40">Loading logs…</p>
          )}
          {!loading && lines.length === 0 && (
            <p className="text-white/40">
              {active ? "Waiting for output…" : "No logs recorded for this deployment."}
            </p>
          )}
          {lines.map((l, i) => (
            <div
              key={i}
              className={cn(
                "leading-5",
                l.stream === "stderr"
                  ? "text-red-400"
                  : l.stream === "system"
                  ? "text-fuchsia-400"
                  : "text-[#e6edf3]"
              )}
            >
              <span className="mr-2 select-none text-white/25">
                {l.createdAt ? l.createdAt.slice(11, 19) : "--:--:--"}
              </span>
              {l.stream === "system" && (
                <span className="mr-1 text-white/30">[sys]</span>
              )}
              {l.stream === "stderr" && (
                <span className="mr-1 text-red-500/70">[err]</span>
              )}
              {l.line}
            </div>
          ))}
          <div ref={endRef} />
        </div>
      </div>
    </div>
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
    return <div className="h-32 animate-pulse rounded-xl border border-border/60 bg-card/40" />;
  }

  if (data.results.length === 0) {
    return (
      <Card>
        <CardContent className="py-12 text-center text-sm text-muted-foreground">
          No deployments yet. Trigger one with{" "}
          <span className="font-mono font-medium">Deploy now</span>.
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="flex gap-4 h-[560px]">
      {/* Deployment list */}
      <div className="w-56 shrink-0 space-y-1 overflow-y-auto pr-1 scrollbar-thin">
        {data.results.map((d) => (
          <button
            key={d.id}
            onClick={() => setSelected(d)}
            className={cn(
              "w-full rounded-lg border px-3 py-2.5 text-left text-sm transition-colors",
              selected?.id === d.id
                ? "border-primary/50 bg-primary/5"
                : "border-border/60 bg-card/60 hover:border-border hover:bg-card"
            )}
          >
            <div className="flex items-center gap-2">
              <StatusDot status={d.status} />
              <span className="font-mono font-medium text-xs">#{d.id}</span>
              {d.isActive && (
                <Badge variant="success" className="ml-auto text-[10px] px-1 py-0">
                  live
                </Badge>
              )}
            </div>
            <p className="mt-1 text-[10px] text-muted-foreground truncate">
              {formatRelative(d.createdAt)}
            </p>
            <div className="mt-1 flex items-center gap-1">
              {d.gitCommitSha && (
                <span className="flex items-center gap-0.5 text-[10px] text-muted-foreground font-mono">
                  <GitBranch className="h-2.5 w-2.5" />
                  {d.gitCommitSha.slice(0, 7)}
                </span>
              )}
              <span className={cn(
                "text-[10px] capitalize",
                d.status === "succeeded" ? "text-green-500" :
                d.status === "failed"    ? "text-destructive" :
                                           "text-muted-foreground"
              )}>
                {d.status}
              </span>
            </div>
          </button>
        ))}
      </div>

      {/* Log panel */}
      <div className="flex-1 min-w-0 flex flex-col">
        {selected ? (
          <>
            {/* Header */}
            <div className="mb-3 flex items-center justify-between">
              <div className="flex items-center gap-2">
                <StatusDot status={selected.status} />
                <span className="font-medium text-sm">
                  Deployment #{selected.id}
                </span>
                <Badge variant="muted" className="text-xs capitalize">
                  {selected.status}
                </Badge>
                {selected.finishedAt && (
                  <span className="text-xs text-muted-foreground flex items-center gap-1">
                    <Clock className="h-3 w-3" />
                    {formatRelative(selected.finishedAt)}
                  </span>
                )}
              </div>
              <div className="flex items-center gap-2">
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={() => mutate()}
                  className="h-7"
                >
                  <RefreshCw className="h-3.5 w-3.5" />
                </Button>
                {selected.status === "succeeded" && !selected.isActive && (
                  <Button
                    size="sm"
                    variant="outline"
                    onClick={() => rollback(selected)}
                    className="h-7"
                  >
                    Rollback
                  </Button>
                )}
              </div>
            </div>

            {selected.failureReason && (
              <div className="mb-3 rounded-md border border-destructive/30 bg-destructive/5 px-3 py-2 text-xs text-destructive">
                <span className="font-medium">Error: </span>
                {selected.failureReason}
              </div>
            )}

            <LogPanel appId={appId} deployment={selected} key={selected.id} />
          </>
        ) : (
          <div className="flex h-full items-center justify-center text-sm text-muted-foreground">
            Select a deployment to see its logs.
          </div>
        )}
      </div>
    </div>
  );
}
