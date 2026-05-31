"use client";

import Link from "@/compat/link";
import useSWR from "swr";
import { Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { StatusDot } from "@/components/ui/status-dot";
import { Badge } from "@/components/ui/badge";
import { fetcher } from "@/lib/api";
import { formatRelative } from "@/lib/utils";
import type { App, ListResponse } from "@/lib/types";

export default function AppsPage() {
  const { data, isLoading } = useSWR<ListResponse<App>>("/apps/", fetcher);

  return (
    <div className="container space-y-6 py-8">
      <header className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Apps</h1>
          <p className="text-sm text-muted-foreground">
            Every backend service running across your panel.
          </p>
        </div>
        <Button asChild>
          <Link href="/apps/new">
            <Plus className="h-4 w-4" /> New app
          </Link>
        </Button>
      </header>

      {isLoading ? (
        <SkeletonGrid />
      ) : data?.results.length ? (
        <div className="grid gap-3 lg:grid-cols-2">
          {data.results.map((app) => (
            <Link
              key={app.id}
              href={`/apps/${app.id}`}
              className="group block rounded-xl border border-border/60 bg-card/60 p-5 transition hover:border-primary/40 hover:bg-card"
            >
              <div className="flex items-start justify-between gap-3">
                <div>
                  <div className="flex items-center gap-2">
                    <StatusDot status={app.status} />
                    <h3 className="font-medium">{app.name}</h3>
                    <Badge variant="muted" className="text-[10px]">
                      {app.runtime}
                    </Badge>
                  </div>
                  <p className="mt-1 truncate font-mono text-xs text-muted-foreground">
                    {app.linuxUser} → 127.0.0.1:{app.internalPort}
                  </p>
                </div>
                <Badge variant="secondary">{app.status}</Badge>
              </div>
              <div className="mt-4 grid grid-cols-3 gap-3 border-t border-border/60 pt-3 text-xs text-muted-foreground">
                <div>
                  <p className="uppercase tracking-wider">Memory</p>
                  <p className="text-foreground">{app.memoryMbLimit} MB</p>
                </div>
                <div>
                  <p className="uppercase tracking-wider">CPU</p>
                  <p className="text-foreground">{app.cpuQuotaPercent}%</p>
                </div>
                <div>
                  <p className="uppercase tracking-wider">Deployed</p>
                  <p className="text-foreground">
                    {formatRelative(app.lastDeployedAt)}
                  </p>
                </div>
              </div>
            </Link>
          ))}
        </div>
      ) : (
        <Card>
          <CardContent className="py-12 text-center text-sm text-muted-foreground">
            No apps yet —{" "}
            <Link href="/apps/new" className="text-primary hover:underline">
              create your first
            </Link>
            .
          </CardContent>
        </Card>
      )}
    </div>
  );
}

function SkeletonGrid() {
  return (
    <div className="grid gap-3 lg:grid-cols-2">
      {[0, 1, 2, 3].map((i) => (
        <div
          key={i}
          className="h-32 animate-pulse rounded-xl border border-border/60 bg-card/40"
        />
      ))}
    </div>
  );
}
