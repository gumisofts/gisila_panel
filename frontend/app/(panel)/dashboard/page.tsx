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
  Tag,
  Tile,
} from "@carbon/react";
import type { ComponentProps, ElementType } from "react";
import RouterLink from "@/compat/link";
import { Page, PageHeader, PageSection } from "@/components/page";
import { fetcher } from "@/lib/api";
import { formatRelative } from "@/lib/utils";
import type { App, ListResponse, Project, Team } from "@/lib/types";
import "../_batch-a.scss";

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
