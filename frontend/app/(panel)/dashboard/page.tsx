"use client";

import Link from "next/link";
import useSWR from "swr";
import { Boxes, Globe, Rocket, Users } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { StatusDot } from "@/components/ui/status-dot";
import { fetcher } from "@/lib/api";
import { formatRelative } from "@/lib/utils";
import type { App, ListResponse, Project, Team } from "@/lib/types";

export default function DashboardPage() {
  const apps = useSWR<ListResponse<App>>("/apps/", fetcher);
  const projects = useSWR<ListResponse<Project>>("/projects/", fetcher);
  const teams = useSWR<ListResponse<Team>>("/teams/", fetcher);

  const recentApps = apps.data?.results.slice(0, 6) ?? [];

  return (
    <div className="container space-y-8 py-8">
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">
            Welcome back
          </h1>
          <p className="text-sm text-muted-foreground">
            Your apps, projects, and infrastructure at a glance.
          </p>
        </div>
      </header>

      <section className="grid grid-cols-2 gap-4 md:grid-cols-4">
        <Stat
          icon={<Boxes className="h-5 w-5" />}
          label="Apps"
          value={apps.data?.results.length}
        />
        <Stat
          icon={<Rocket className="h-5 w-5" />}
          label="Running"
          value={
            apps.data?.results.filter((a) => a.status === "running").length
          }
        />
        <Stat
          icon={<Users className="h-5 w-5" />}
          label="Teams"
          value={teams.data?.results.length}
        />
        <Stat
          icon={<Globe className="h-5 w-5" />}
          label="Projects"
          value={projects.data?.results.length}
        />
      </section>

      <section>
        <header className="mb-3 flex items-center justify-between">
          <h2 className="text-sm font-semibold uppercase tracking-wider text-muted-foreground">
            Recent apps
          </h2>
          <Link
            href="/apps"
            className="text-xs font-medium text-primary hover:underline"
          >
            View all →
          </Link>
        </header>
        {recentApps.length === 0 ? (
          <EmptyApps />
        ) : (
          <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
            {recentApps.map((app) => (
              <AppCard key={app.id} app={app} />
            ))}
          </div>
        )}
      </section>
    </div>
  );
}

function Stat({
  icon,
  label,
  value,
}: {
  icon: React.ReactNode;
  label: string;
  value: number | undefined;
}) {
  return (
    <Card>
      <CardContent className="flex items-center gap-4 p-5">
        <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/15 text-primary">
          {icon}
        </div>
        <div>
          <p className="text-xs uppercase tracking-wider text-muted-foreground">
            {label}
          </p>
          <p className="text-2xl font-semibold">{value ?? "—"}</p>
        </div>
      </CardContent>
    </Card>
  );
}

function AppCard({ app }: { app: App }) {
  return (
    <Link
      href={`/apps/${app.id}`}
      className="group block rounded-xl border border-border/60 bg-card/60 p-5 transition hover:border-primary/40 hover:bg-card"
    >
      <div className="flex items-start justify-between">
        <div>
          <div className="flex items-center gap-2">
            <StatusDot status={app.status} />
            <h3 className="font-medium">{app.name}</h3>
          </div>
          <p className="mt-1 text-xs text-muted-foreground">
            {app.runtime} · port {app.internalPort}
          </p>
        </div>
        <Badge variant="secondary">{app.status}</Badge>
      </div>
      <div className="mt-4 flex items-center justify-between border-t border-border/60 pt-3 text-xs text-muted-foreground">
        <span>Deployed {formatRelative(app.lastDeployedAt)}</span>
        <span className="font-mono">{app.linuxUser}</span>
      </div>
    </Link>
  );
}

function EmptyApps() {
  return (
    <Card>
      <CardHeader>
        <CardTitle>No apps yet</CardTitle>
      </CardHeader>
      <CardContent>
        <p className="text-sm text-muted-foreground">
          Create your first app to start deploying. You can ship a pre-compiled
          binary, point at a Git repo, or upload a ZIP.
        </p>
        <Link
          href="/apps/new"
          className="mt-4 inline-flex items-center gap-2 rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground hover:bg-primary/90"
        >
          Create your first app
        </Link>
      </CardContent>
    </Card>
  );
}
