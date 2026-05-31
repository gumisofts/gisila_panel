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
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { fetcher } from "@/lib/api";
import type { MetricSample } from "@/lib/types";

interface MetricsResponse {
  app: { id: number; name: string; status: string };
  samples: MetricSample[];
}

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
    <div className="grid gap-4 md:grid-cols-2">
      <Card>
        <CardHeader>
          <CardTitle>CPU (%)</CardTitle>
        </CardHeader>
        <CardContent className="h-56">
          <ResponsiveContainer width="100%" height="100%">
            <AreaChart data={points}>
              <CartesianGrid strokeDasharray="3 3" opacity={0.2} />
              <XAxis dataKey="t" tick={{ fontSize: 10 }} />
              <YAxis tick={{ fontSize: 10 }} />
              <Tooltip
                contentStyle={{
                  background: "hsl(var(--card))",
                  border: "1px solid hsl(var(--border))",
                  fontSize: 12,
                }}
              />
              <Area
                type="monotone"
                dataKey="cpu"
                stroke="hsl(var(--primary))"
                fill="hsl(var(--primary) / 0.18)"
                strokeWidth={2}
              />
            </AreaChart>
          </ResponsiveContainer>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Memory (MB)</CardTitle>
        </CardHeader>
        <CardContent className="h-56">
          <ResponsiveContainer width="100%" height="100%">
            <AreaChart data={points}>
              <CartesianGrid strokeDasharray="3 3" opacity={0.2} />
              <XAxis dataKey="t" tick={{ fontSize: 10 }} />
              <YAxis tick={{ fontSize: 10 }} />
              <Tooltip
                contentStyle={{
                  background: "hsl(var(--card))",
                  border: "1px solid hsl(var(--border))",
                  fontSize: 12,
                }}
              />
              <Area
                type="monotone"
                dataKey="memMb"
                stroke="#10b981"
                fill="rgba(16,185,129,0.18)"
                strokeWidth={2}
              />
            </AreaChart>
          </ResponsiveContainer>
        </CardContent>
      </Card>

      {points.length === 0 && (
        <div className="md:col-span-2 rounded-xl border border-dashed border-border/60 p-12 text-center text-sm text-muted-foreground">
          No samples yet. Metrics start streaming once the app is running.
        </div>
      )}
    </div>
  );
}
