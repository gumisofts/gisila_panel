"use client";

import { useParams } from "@/compat/navigation";
import useSWR from "swr";
import { toast } from "sonner";
import { Play, RotateCw, Square, Rocket } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { StatusDot } from "@/components/ui/status-dot";
import {
  Tabs,
  TabsContent,
  TabsList,
  TabsTrigger,
} from "@/components/ui/tabs";
import { api, fetcher } from "@/lib/api";
import { formatRelative } from "@/lib/utils";
import type { App } from "@/lib/types";
import { OverviewTab } from "./_tabs/overview";
import { DeploymentsTab } from "./_tabs/deployments";
import { EnvsTab } from "./_tabs/envs";
import { DomainsTab } from "./_tabs/domains";
import { LogsTab } from "./_tabs/logs";
import { ConsoleTab } from "./_tabs/console";
import { MetricsTab } from "./_tabs/metrics";
import { SettingsTab } from "./_tabs/settings";

export default function AppDetailPage() {
  const params = useParams<{ id: string }>();
  const appId = Number(params.id);
  const { data: app, mutate } = useSWR<App>(`/apps/${appId}`, fetcher, {
    refreshInterval: 5000,
  });

  if (!app) {
    return (
      <div className="container py-8">
        <div className="h-24 animate-pulse rounded-xl border border-border/60 bg-card/40" />
      </div>
    );
  }

  async function lifecycle(action: "start" | "stop" | "restart") {
    try {
      await api(`/apps/${appId}/${action}`, { method: "POST" });
      toast.success(`${action} requested`);
      mutate();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed");
    }
  }

  async function deployNow() {
    if (!app) return;
    try {
      await api(`/apps/${appId}/deployments/`, {
        method: "POST",
        body: JSON.stringify({ sourceType: app.sourceType }),
      });
      toast.success("Deployment queued");
      mutate();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed");
    }
  }

  return (
    <div className="container space-y-6 py-8">
      <header className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <div className="flex items-center gap-3">
            <StatusDot status={app.status} />
            <h1 className="text-2xl font-semibold tracking-tight">
              {app.name}
            </h1>
            <Badge variant="muted">{app.runtime}</Badge>
            <Badge variant="secondary">{app.status}</Badge>
          </div>
          <p className="mt-1 font-mono text-xs text-muted-foreground">
            {app.linuxUser} · 127.0.0.1:{app.internalPort} · deployed{" "}
            {formatRelative(app.lastDeployedAt)}
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button onClick={() => lifecycle("start")} variant="outline" size="sm">
            <Play className="h-4 w-4" /> Start
          </Button>
          <Button onClick={() => lifecycle("restart")} variant="outline" size="sm">
            <RotateCw className="h-4 w-4" /> Restart
          </Button>
          <Button onClick={() => lifecycle("stop")} variant="outline" size="sm">
            <Square className="h-4 w-4" /> Stop
          </Button>
          <Button onClick={deployNow} size="sm">
            <Rocket className="h-4 w-4" /> Deploy now
          </Button>
        </div>
      </header>

      <Tabs defaultValue="overview">
        <TabsList>
          <TabsTrigger value="overview">Overview</TabsTrigger>
          <TabsTrigger value="deployments">Deployments</TabsTrigger>
          <TabsTrigger value="envs">Environment</TabsTrigger>
          <TabsTrigger value="domains">Domains</TabsTrigger>
          <TabsTrigger value="logs">Logs</TabsTrigger>
          <TabsTrigger value="console">Console</TabsTrigger>
          <TabsTrigger value="metrics">Metrics</TabsTrigger>
          <TabsTrigger value="settings">Settings</TabsTrigger>
        </TabsList>
        <TabsContent value="overview"><OverviewTab app={app} /></TabsContent>
        <TabsContent value="deployments"><DeploymentsTab appId={appId} /></TabsContent>
        <TabsContent value="envs"><EnvsTab appId={appId} /></TabsContent>
        <TabsContent value="domains"><DomainsTab appId={appId} /></TabsContent>
        <TabsContent value="logs"><LogsTab appId={appId} /></TabsContent>
        <TabsContent value="console"><ConsoleTab appId={appId} /></TabsContent>
        <TabsContent value="metrics"><MetricsTab appId={appId} /></TabsContent>
        <TabsContent value="settings">
          <SettingsTab app={app} onSaved={mutate} />
        </TabsContent>
      </Tabs>
    </div>
  );
}

export function StatCard({
  label,
  value,
}: {
  label: string;
  value: React.ReactNode;
}) {
  return (
    <Card>
      <CardHeader className="pb-1">
        <CardTitle className="text-xs uppercase tracking-wider text-muted-foreground">
          {label}
        </CardTitle>
      </CardHeader>
      <CardContent className="text-xl font-semibold">{value}</CardContent>
    </Card>
  );
}
