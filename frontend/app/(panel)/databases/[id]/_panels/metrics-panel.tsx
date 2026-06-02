"use client";

import useSWR from "swr";
import { Activity, Cpu, MemoryStick, Loader } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { fetcher } from "@/lib/api";

interface DbMetrics {
  status: "ok" | "initializing" | "not_running" | "error";
  detail?: string;
  host?: { cpuPercent: number; memBytes: number; sampledAt: string } | null;
  connections?: {
    total: number;
    active: number;
    idle: number;
    idleInTransaction: number;
    waiting: number;
    max: number;
  };
  throughput?: {
    commits: number;
    rollbacks: number;
    inserted: number;
    updated: number;
    deleted: number;
    deadlocks: number;
  };
  cacheHitRatio?: number;
  uptimeSeconds?: number;
  databases?: { name: string; sizeBytes: number }[];
}

function fmtBytes(n: number): string {
  if (!n) return "0 B";
  const u = ["B", "KB", "MB", "GB", "TB"];
  const i = Math.min(Math.floor(Math.log(n) / Math.log(1024)), u.length - 1);
  return `${(n / 1024 ** i).toFixed(i === 0 ? 0 : 1)} ${u[i]}`;
}

function fmtUptime(s?: number): string {
  if (!s) return "—";
  const d = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (d > 0) return `${d}d ${h}h`;
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m`;
}

function Stat({ label, value, sub }: { label: string; value: React.ReactNode; sub?: string }) {
  return (
    <div className="rounded-lg border border-border/60 bg-card/40 p-3">
      <p className="text-xs uppercase tracking-wider text-muted-foreground">{label}</p>
      <p className="mt-1 text-lg font-semibold tabular-nums">{value}</p>
      {sub && <p className="text-xs text-muted-foreground">{sub}</p>}
    </div>
  );
}

export function MetricsPanel({ id, running }: { id: string; running: boolean }) {
  const { data } = useSWR<DbMetrics>(
    running ? `/databases/${id}/metrics` : null,
    fetcher,
    { refreshInterval: 5000 },
  );

  if (!running) return null;

  if (!data || data.status === "initializing") {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-sm">
            <Activity className="h-4 w-4 text-muted-foreground" /> Metrics
          </CardTitle>
        </CardHeader>
        <CardContent className="flex items-center gap-2 py-6 text-sm text-muted-foreground">
          <Loader className="h-4 w-4 animate-spin" />
          Setting up the monitoring role… metrics will appear shortly.
        </CardContent>
      </Card>
    );
  }

  if (data.status !== "ok") {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-sm">
            <Activity className="h-4 w-4 text-muted-foreground" /> Metrics
          </CardTitle>
        </CardHeader>
        <CardContent className="py-6 text-sm text-muted-foreground">
          Metrics unavailable. {data.detail ?? ""}
        </CardContent>
      </Card>
    );
  }

  const c = data.connections!;
  const t = data.throughput!;
  const connPct = c.max > 0 ? Math.round((c.total / c.max) * 100) : 0;
  const cpuPct = data.host ? (data.host.cpuPercent / 100).toFixed(1) : null;

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2 text-sm">
          <Activity className="h-4 w-4 text-muted-foreground" /> Metrics
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <Stat
            label="Connections"
            value={`${c.total} / ${c.max}`}
            sub={`${connPct}% used`}
          />
          <Stat label="Active" value={c.active} sub={`${c.idle} idle · ${c.waiting} waiting`} />
          <Stat
            label="CPU"
            value={
              cpuPct !== null ? (
                <span className="flex items-center gap-1">
                  <Cpu className="h-4 w-4 text-muted-foreground" />
                  {cpuPct}%
                </span>
              ) : (
                "—"
              )
            }
            sub="of one core"
          />
          <Stat
            label="Memory"
            value={
              data.host ? (
                <span className="flex items-center gap-1">
                  <MemoryStick className="h-4 w-4 text-muted-foreground" />
                  {fmtBytes(data.host.memBytes)}
                </span>
              ) : (
                "—"
              )
            }
          />
        </div>

        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <Stat label="Cache hit" value={`${((data.cacheHitRatio ?? 0) * 100).toFixed(1)}%`} />
          <Stat label="Commits" value={t.commits.toLocaleString()} />
          <Stat label="Rollbacks" value={t.rollbacks.toLocaleString()} sub={`${t.deadlocks} deadlocks`} />
          <Stat label="Uptime" value={fmtUptime(data.uptimeSeconds)} />
        </div>

        {data.databases && data.databases.length > 0 && (
          <div className="rounded-lg border border-border/60">
            <p className="border-b border-border/60 px-3 py-2 text-xs uppercase tracking-wider text-muted-foreground">
              Database sizes
            </p>
            <div className="divide-y divide-border/60">
              {data.databases.map((d) => (
                <div key={d.name} className="flex items-center justify-between px-3 py-2 text-sm">
                  <span className="font-mono">{d.name}</span>
                  <span className="tabular-nums text-muted-foreground">{fmtBytes(d.sizeBytes)}</span>
                </div>
              ))}
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
