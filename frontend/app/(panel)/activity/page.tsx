"use client";

import useSWR from "swr";
import { Activity } from "lucide-react";
import { Card, CardContent } from "@/components/ui/card";
import { fetcher } from "@/lib/api";
import { formatRelative } from "@/lib/utils";
import type { App, Deployment, ListResponse } from "@/lib/types";

export default function ActivityPage() {
  const apps = useSWR<ListResponse<App>>("/apps/", fetcher);
  const appList = apps.data?.results ?? [];

  return (
    <div className="container space-y-6 py-8">
      <header>
        <h1 className="text-2xl font-semibold tracking-tight">Activity</h1>
        <p className="text-sm text-muted-foreground">
          Recent deployments across every app in your panel.
        </p>
      </header>
      <div className="space-y-2">
        {appList.length === 0 && (
          <Card>
            <CardContent className="py-12 text-center text-sm text-muted-foreground">
              No activity yet.
            </CardContent>
          </Card>
        )}
        {appList.map((app) => (
          <AppActivity key={app.id} app={app} />
        ))}
      </div>
    </div>
  );
}

function AppActivity({ app }: { app: App }) {
  const { data } = useSWR<ListResponse<Deployment>>(
    `/apps/${app.id}/deployments/`,
    fetcher,
  );
  const items = data?.results.slice(0, 5) ?? [];
  return (
    <Card>
      <CardContent className="p-5">
        <div className="mb-3 flex items-center gap-2 text-sm font-medium">
          <Activity className="h-4 w-4 text-primary" />
          {app.name}
        </div>
        {items.length === 0 ? (
          <p className="text-xs text-muted-foreground">No deployments yet.</p>
        ) : (
          <ul className="space-y-1.5 text-sm">
            {items.map((d) => (
              <li
                key={d.id}
                className="flex items-center justify-between text-muted-foreground"
              >
                <span>
                  #{d.id} · {d.status}
                </span>
                <span className="text-xs">{formatRelative(d.createdAt)}</span>
              </li>
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  );
}
