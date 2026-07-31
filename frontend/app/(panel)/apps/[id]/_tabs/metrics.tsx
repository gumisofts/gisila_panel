"use client";

import useSWR from "swr";
import {
  Area,
  AreaChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { Column, Grid, Tile } from "@carbon/react";
import { fetcher } from "@/lib/api";
import type { MetricSample } from "@/lib/types";
import "../_app-detail.scss";

interface MetricsResponse {
  app: { id: number; name: string; status: string };
  samples: MetricSample[];
}

// Recharts takes plain CSS strings, so the charts can read Carbon's theme
// tokens directly and follow the active theme zone without a re-render.
const AXIS = "var(--cds-border-subtle-01)";
const TICK = "var(--cds-text-secondary)";
const SERIES = "var(--cds-interactive)";
const SERIES_ALT = "var(--cds-support-success)";

const TOOLTIP_STYLE = {
  background: "var(--cds-layer-01)",
  border: "1px solid var(--cds-border-subtle-01)",
  color: "var(--cds-text-primary)",
  fontSize: 12,
};

export function MetricsTab({ appId }: { appId: number }) {
  const { data } = useSWR<MetricsResponse>(
    `/apps/${appId}/metrics/`,
    fetcher,
    { refreshInterval: 5000 },
  );

  const points =
    data?.samples.map((s) => ({
      t: new Date(s.sampledAt).toLocaleTimeString(),
      cpu: s.cpuPercent / 100,
      memMb: Math.round((s.memBytes ?? 0) / (1024 * 1024)),
    })) ?? [];

  return (
    <Grid condensed>
      <Column sm={4} md={4} lg={8} className="gisila-app__col">
        <Tile>
          <h3 className="gisila-app__tile-title">CPU (%)</h3>
          <div className="gisila-app__chart">
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={points}>
                <CartesianGrid strokeDasharray="3 3" stroke={AXIS} />
                <XAxis dataKey="t" stroke={AXIS} tick={{ fontSize: 10, fill: TICK }} />
                <YAxis stroke={AXIS} tick={{ fontSize: 10, fill: TICK }} />
                <Tooltip contentStyle={TOOLTIP_STYLE} />
                <Area
                  type="monotone"
                  dataKey="cpu"
                  stroke={SERIES}
                  fill={SERIES}
                  fillOpacity={0.18}
                  strokeWidth={2}
                />
              </AreaChart>
            </ResponsiveContainer>
          </div>
        </Tile>
      </Column>

      <Column sm={4} md={4} lg={8} className="gisila-app__col">
        <Tile>
          <h3 className="gisila-app__tile-title">Memory (MB)</h3>
          <div className="gisila-app__chart">
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={points}>
                <CartesianGrid strokeDasharray="3 3" stroke={AXIS} />
                <XAxis dataKey="t" stroke={AXIS} tick={{ fontSize: 10, fill: TICK }} />
                <YAxis stroke={AXIS} tick={{ fontSize: 10, fill: TICK }} />
                <Tooltip contentStyle={TOOLTIP_STYLE} />
                <Area
                  type="monotone"
                  dataKey="memMb"
                  stroke={SERIES_ALT}
                  fill={SERIES_ALT}
                  fillOpacity={0.18}
                  strokeWidth={2}
                />
              </AreaChart>
            </ResponsiveContainer>
          </div>
        </Tile>
      </Column>

      {points.length === 0 && (
        <Column sm={4} md={8} lg={16} className="gisila-app__col">
          <Tile className="gisila-empty">
            No samples yet. The collector records CPU and memory every ~20s
            while the app is running — give it a minute after a deploy.
          </Tile>
        </Column>
      )}
    </Grid>
  );
}
