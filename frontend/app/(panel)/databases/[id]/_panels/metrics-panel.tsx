"use client";

import useSWR from "swr";
import { Activity, Chip } from "@carbon/icons-react";
import {
  Column,
  Grid,
  InlineLoading,
  Stack,
  StructuredListBody,
  StructuredListCell,
  StructuredListHead,
  StructuredListRow,
  StructuredListWrapper,
  Tile,
} from "@carbon/react";
import { PageSection } from "@/components/page";
import { fetcher } from "@/lib/api";
import "../../_databases.scss";

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
    <Column sm={2} md={2} lg={4}>
      <Tile className="gisila-db__stat">
        <p className="gisila-db__stat-label">{label}</p>
        <p className="gisila-db__stat-value">{value}</p>
        {sub && <p className="gisila-db__stat-sub">{sub}</p>}
      </Tile>
    </Column>
  );
}

const HEADING = (
  <span className="gisila-db__icon-title">
    <Activity size={16} />
    Metrics
  </span>
);

export function MetricsPanel({ id, running }: { id: string; running: boolean }) {
  const { data } = useSWR<DbMetrics>(
    running ? `/databases/${id}/metrics` : null,
    fetcher,
    { refreshInterval: 5000 },
  );

  if (!running) return null;

  if (!data || data.status === "initializing") {
    return (
      <PageSection title={HEADING}>
        <Tile>
          <InlineLoading description="Setting up the monitoring role… metrics will appear shortly." />
        </Tile>
      </PageSection>
    );
  }

  if (data.status !== "ok") {
    return (
      <PageSection title={HEADING}>
        <Tile>
          <p className="gisila-db__note">Metrics unavailable. {data.detail ?? ""}</p>
        </Tile>
      </PageSection>
    );
  }

  const c = data.connections!;
  const t = data.throughput!;
  const connPct = c.max > 0 ? Math.round((c.total / c.max) * 100) : 0;
  const cpuPct = data.host ? (data.host.cpuPercent / 100).toFixed(1) : null;

  return (
    <PageSection title={HEADING}>
      <Stack gap={5}>
        <Grid condensed className="gisila-db__stats">
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
                <>
                  <Chip size={16} />
                  {cpuPct}%
                </>
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
                <>
                  <Chip size={16} />
                  {fmtBytes(data.host.memBytes)}
                </>
              ) : (
                "—"
              )
            }
          />

          <Stat label="Cache hit" value={`${((data.cacheHitRatio ?? 0) * 100).toFixed(1)}%`} />
          <Stat label="Commits" value={t.commits.toLocaleString()} />
          <Stat label="Rollbacks" value={t.rollbacks.toLocaleString()} sub={`${t.deadlocks} deadlocks`} />
          <Stat label="Uptime" value={fmtUptime(data.uptimeSeconds)} />
        </Grid>

        {data.databases && data.databases.length > 0 && (
          <StructuredListWrapper aria-label="Database sizes" isCondensed>
            <StructuredListHead>
              <StructuredListRow head>
                <StructuredListCell head>Database</StructuredListCell>
                <StructuredListCell head className="gisila-db__size-value">
                  Size
                </StructuredListCell>
              </StructuredListRow>
            </StructuredListHead>
            <StructuredListBody>
              {data.databases.map((d) => (
                <StructuredListRow key={d.name}>
                  <StructuredListCell>
                    <span className="gisila-db__mono">{d.name}</span>
                  </StructuredListCell>
                  <StructuredListCell className="gisila-db__size-value">
                    {fmtBytes(d.sizeBytes)}
                  </StructuredListCell>
                </StructuredListRow>
              ))}
            </StructuredListBody>
          </StructuredListWrapper>
        )}
      </Stack>
    </PageSection>
  );
}
