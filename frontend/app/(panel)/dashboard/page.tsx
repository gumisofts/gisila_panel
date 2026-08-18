"use client";

import useSWR from "swr";
import {
  Application,
  ArrowRight,
  Earth,
  Rocket,
  UserMultiple,
} from "@carbon/icons-react";
import {
  Button,
  ClickableTile,
  Column,
  Grid,
  Link as CarbonLink,
  ProgressBar,
  Tag,
  Tile,
} from "@carbon/react";
import type { ComponentProps, ElementType } from "react";
import RouterLink from "@/compat/link";
import { Page, PageHeader, PageSection } from "@/components/page";
import { fetcher } from "@/lib/api";
import { usePermissions } from "@/lib/permissions";
import { formatRelative } from "@/lib/utils";
import type {
  App,
  AppUsage,
  HostStatsSnapshot,
  ListResponse,
  Project,
  Team,
} from "@/lib/types";
import "../_batch-a.scss";

// Above this a bar turns red (matches the AlertRule "critical" severity);
// above the warning line it turns amber but stays "active" so it doesn't
// claim an actual alert has fired — that's the alert rules' job, not the
// dashboard's.
const WARN_PERCENT = 70;
const CRIT_PERCENT = 90;

// ClickableTile renders Carbon's polymorphic Link and forwards the props it
// does not recognise, so `as` reaches it at runtime — its prop type just never
// declared the escape hatch. Aliasing it keeps router navigation on the card.
const LinkTile = ClickableTile as React.ComponentType<
  ComponentProps<typeof ClickableTile> & { as?: ElementType }
>;

// Carbon's Tag colours stand in for the old status dot: the tone already
// carries the state, so the dot and the label no longer say it twice.
const STATUS_TAG: Record<
  string,
  "green" | "blue" | "gray" | "cool-gray" | "red" | "magenta"
> = {
  running: "green",
  building: "blue",
  created: "gray",
  stopped: "cool-gray",
  failed: "red",
  crashed: "red",
  deleting: "magenta",
};

export default function DashboardPage() {
  const apps = useSWR<ListResponse<App>>("/apps/", fetcher);
  const projects = useSWR<ListResponse<Project>>("/projects/", fetcher);
  const teams = useSWR<ListResponse<Team>>("/teams/", fetcher);
  const { isSuperuser } = usePermissions();

  const recentApps = apps.data?.results.slice(0, 6) ?? [];

  return (
    <Page>
      <PageHeader
        title="Welcome back"
        description="Your apps, projects, and infrastructure at a glance."
      />

      <Grid condensed className="gisila-cards">
        <Column sm={2} md={2} lg={4}>
          <Stat
            icon={<Application size={20} />}
            label="Apps"
            value={apps.data?.results.length}
          />
        </Column>
        <Column sm={2} md={2} lg={4}>
          <Stat
            icon={<Rocket size={20} />}
            label="Running"
            value={
              apps.data?.results.filter((a) => a.status === "running").length
            }
          />
        </Column>
        <Column sm={2} md={2} lg={4}>
          <Stat
            icon={<UserMultiple size={20} />}
            label="Teams"
            value={teams.data?.results.length}
          />
        </Column>
        <Column sm={2} md={2} lg={4}>
          <Stat
            icon={<Earth size={20} />}
            label="Projects"
            value={projects.data?.results.length}
          />
        </Column>
      </Grid>

      {isSuperuser && <ServerResources />}

      <AppsByUsage />

      <PageSection
        title="Recent apps"
        actions={
          <CarbonLink as={RouterLink} href="/apps" renderIcon={ArrowRight}>
            View all
          </CarbonLink>
        }
      >
        {recentApps.length === 0 ? (
          <EmptyApps />
        ) : (
          <Grid condensed className="gisila-cards">
            {recentApps.map((app) => (
              <Column key={app.id} sm={4} md={4} lg={5}>
                <AppCard app={app} />
              </Column>
            ))}
          </Grid>
        )}
      </PageSection>
    </Page>
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
    <Tile>
      <div className="gisila-stat">
        <span className="gisila-status-icon gisila-status-icon--brand">
          {icon}
        </span>
        <div>
          <p className="gisila-stat__label">{label}</p>
          <p className="gisila-stat__value">{value ?? "—"}</p>
        </div>
      </div>
    </Tile>
  );
}

interface HostStatsResponse {
  snapshot: HostStatsSnapshot | null;
}

// Superuser-only, mirroring who system-scope alert rules notify — this reads
// the same `/notifications/host-stats` snapshot the rule editor previews
// against, just polled at the sampler's own cadence instead of on demand.
function ServerResources() {
  const { data } = useSWR<HostStatsResponse>(
    "/notifications/host-stats",
    fetcher,
    { refreshInterval: 20_000 },
  );
  const snapshot = data?.snapshot;

  return (
    <PageSection
      title="Server resources"
      description={
        snapshot ? `Updated ${formatRelative(snapshot.sampledAt)}` : undefined
      }
      actions={
        <CarbonLink as={RouterLink} href="/settings/notifications">
          Configure alerts
        </CarbonLink>
      }
    >
      {!data ? (
        <Tile>
          <p className="gisila-card__body">Loading host metrics…</p>
        </Tile>
      ) : !snapshot ? (
        <Tile>
          <p className="gisila-card__body">
            No host metrics yet — they appear once the worker takes its
            first sample, about 20 seconds after it starts.
          </p>
        </Tile>
      ) : (
        <Grid condensed className="gisila-cards">
          <Column sm={4} md={4} lg={5}>
            <ResourceBar
              label="CPU"
              percent={snapshot.cpuPercent}
              detail={
                snapshot.cpuPercent != null
                  ? `${snapshot.cpuPercent}% used`
                  : "Warming up…"
              }
            />
          </Column>
          <Column sm={4} md={4} lg={5}>
            <ResourceBar
              label="Memory"
              percent={snapshot.memPercent}
              detail={`${fmtBytes(snapshot.memUsedBytes)} / ${fmtBytes(snapshot.memTotalBytes)} used`}
            />
          </Column>
          <Column sm={4} md={4} lg={5}>
            <ResourceBar
              label="Disk"
              percent={snapshot.diskPercent}
              detail={`${fmtBytes(snapshot.diskUsedBytes)} / ${fmtBytes(snapshot.diskTotalBytes)} used`}
            />
          </Column>
        </Grid>
      )}
    </PageSection>
  );
}

function ResourceBar({
  label,
  percent,
  detail,
}: {
  label: string;
  percent?: number | null;
  detail: string;
}) {
  return (
    <Tile className="gisila-resource">
      <UsageBar label={label} percent={percent} detail={detail} />
    </Tile>
  );
}

// Bare bar, no enclosing Tile — [ResourceBar] wraps this for the standalone
// host-resource grid; [AppUsageCard] embeds it directly since the whole card
// is already one clickable tile and nesting tiles there reads oddly.
function UsageBar({
  label,
  percent,
  detail,
}: {
  label: string;
  percent?: number | null;
  detail: string;
}) {
  const tier =
    percent == null
      ? "ok"
      : percent >= CRIT_PERCENT
        ? "crit"
        : percent >= WARN_PERCENT
          ? "warn"
          : "ok";

  return (
    <ProgressBar
      label={label}
      value={percent ?? 0}
      max={100}
      status={tier === "crit" ? "error" : "active"}
      helperText={detail}
      className={`gisila-resource__bar gisila-resource__bar--${tier}`}
    />
  );
}

function fmtBytes(n: number): string {
  if (!n) return "0 B";
  const u = ["B", "KB", "MB", "GB", "TB"];
  const i = Math.min(Math.floor(Math.log(n) / Math.log(1024)), u.length - 1);
  return `${(n / 1024 ** i).toFixed(i === 0 ? 0 : 1)} ${u[i]}`;
}

// Percent used of a configured limit — same "percent of quota" the alert
// evaluator computes for app-scope rules, so a bar reading 90% here lines up
// with what would trip a 90%-threshold alert rule on this app.
function quotaPercent(used: number, limit: number): number | null {
  return limit > 0 ? Math.round((used / limit) * 100) : null;
}

interface AppUsageResponse {
  results: AppUsage[];
}

// Not superuser-gated — unlike host stats, per-app usage follows normal team
// RBAC (`AppsService.listForUser` already scopes the endpoint), so any
// member sees usage for apps they can otherwise see.
function AppsByUsage() {
  const { data } = useSWR<AppUsageResponse>(
    "/apps/metrics-summary",
    fetcher,
    { refreshInterval: 20_000 },
  );

  const ranked = (data?.results ?? [])
    .map((u) => ({
      ...u,
      cpuOfQuota: quotaPercent(u.cpuPercent / 100, u.cpuQuotaPercent),
      memOfQuota: quotaPercent(u.memBytes / (1024 * 1024), u.memoryMbLimit),
    }))
    .sort(
      (a, b) =>
        Math.max(b.cpuOfQuota ?? 0, b.memOfQuota ?? 0) -
        Math.max(a.cpuOfQuota ?? 0, a.memOfQuota ?? 0),
    )
    .slice(0, 4);

  // No running apps have reported a fresh sample yet — nothing worth
  // ranking, so skip the section rather than show an empty shell.
  if (ranked.length === 0) return null;

  return (
    <PageSection
      title="Apps by usage"
      description="Running apps closest to their configured CPU/memory limits."
    >
      <Grid condensed className="gisila-cards">
        {ranked.map((u) => (
          <Column key={u.appId} sm={4} md={4} lg={5}>
            <AppUsageCard usage={u} />
          </Column>
        ))}
      </Grid>
    </PageSection>
  );
}

function AppUsageCard({
  usage,
}: {
  usage: AppUsage & { cpuOfQuota: number | null; memOfQuota: number | null };
}) {
  return (
    <LinkTile
      as={RouterLink}
      href={`/apps/${usage.appId}`}
      className="gisila-app-usage"
    >
      <div className="gisila-card__head">
        <h3 className="gisila-card__title">{usage.name}</h3>
        <Tag type={STATUS_TAG[usage.status] ?? "gray"} size="sm">
          {usage.status}
        </Tag>
      </div>
      <UsageBar
        label="CPU"
        percent={usage.cpuOfQuota}
        detail={`${(usage.cpuPercent / 100).toFixed(1)}% of ${usage.cpuQuotaPercent}% quota`}
      />
      <UsageBar
        label="Memory"
        percent={usage.memOfQuota}
        detail={`${fmtBytes(usage.memBytes)} / ${usage.memoryMbLimit} MB limit`}
      />
    </LinkTile>
  );
}

function AppCard({ app }: { app: App }) {
  return (
    <LinkTile as={RouterLink} href={`/apps/${app.id}`}>
      <div className="gisila-card__head">
        <div>
          <h3 className="gisila-card__title">{app.name}</h3>
          <p className="gisila-card__meta">
            {app.runtime} · port {app.internalPort}
          </p>
        </div>
        <Tag type={STATUS_TAG[app.status] ?? "gray"} size="sm">
          {app.status}
        </Tag>
      </div>
      <div className="gisila-card__foot">
        <span>Deployed {formatRelative(app.lastDeployedAt)}</span>
        <span className="gisila-card__mono">{app.linuxUser}</span>
      </div>
    </LinkTile>
  );
}

function EmptyApps() {
  return (
    <Tile>
      <h3 className="gisila-card__title">No apps yet</h3>
      <p className="gisila-card__body">
        Create your first app to start deploying. You can ship a pre-compiled
        binary, point at a Git repo, or upload a ZIP.
      </p>
      <div className="gisila-card__cta">
        <Button as={RouterLink} href="/apps/new">
          Create your first app
        </Button>
      </div>
    </Tile>
  );
}
