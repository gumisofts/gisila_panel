"use client";

import type { ComponentType, ElementType } from "react";
import useSWR from "swr";
import { Add } from "@carbon/icons-react";
import {
  Button,
  ClickableTile,
  type ClickableTileProps,
  Column,
  Grid,
  Link as CarbonLink,
  SkeletonPlaceholder,
  Tag,
  Tile,
} from "@carbon/react";
import RouterLink from "@/compat/link";
import { Page, PageHeader } from "@/components/page";
import { fetcher } from "@/lib/api";
import { formatRelative } from "@/lib/utils";
import type { App, AppStatus, ListResponse } from "@/lib/types";
import "./_apps.scss";

// ClickableTile renders through Carbon's polymorphic Link and forwards unknown
// props to it, so `as` selects the router link at runtime — ClickableTileProps
// simply doesn't declare it.
const RouterTile = ClickableTile as ComponentType<
  ClickableTileProps & { as?: ElementType }
>;

type TagType = "green" | "blue" | "red" | "gray" | "cool-gray" | "magenta";

const STATUS_TAG: Record<AppStatus, TagType> = {
  running: "green",
  building: "blue",
  created: "cool-gray",
  stopped: "gray",
  failed: "red",
  crashed: "red",
  deleting: "magenta",
};

export default function AppsPage() {
  const { data, isLoading } = useSWR<ListResponse<App>>("/apps/", fetcher);

  return (
    <Page>
      <PageHeader
        title="Apps"
        description="Every backend service running across your panel."
        actions={
          <Button as={RouterLink} href="/apps/new" renderIcon={Add}>
            New app
          </Button>
        }
      />

      {isLoading ? (
        <SkeletonGrid />
      ) : data?.results.length ? (
        <Grid narrow className="gisila-apps__grid">
          {data.results.map((app) => (
            <Column
              key={app.id}
              sm={4}
              md={8}
              lg={8}
              className="gisila-apps__column"
            >
              <RouterTile
                as={RouterLink}
                href={`/apps/${app.id}`}
                className="gisila-app-tile"
              >
                <div className="gisila-app-tile__head">
                  <div>
                    <div className="gisila-app-tile__identity">
                      <span className="gisila-app-tile__name">{app.name}</span>
                      <Tag type="cool-gray" size="sm">
                        {app.runtime}
                      </Tag>
                    </div>
                    <p className="gisila-app-tile__endpoint">
                      {app.linuxUser} → 127.0.0.1:{app.internalPort}
                    </p>
                  </div>
                  <Tag type={STATUS_TAG[app.status] ?? "gray"} size="sm">
                    {app.status}
                  </Tag>
                </div>
                <div className="gisila-app-tile__meta">
                  <Meta label="Memory" value={`${app.memoryMbLimit} MB`} />
                  <Meta label="CPU" value={`${app.cpuQuotaPercent}%`} />
                  <Meta
                    label="Deployed"
                    value={formatRelative(app.lastDeployedAt)}
                  />
                </div>
              </RouterTile>
            </Column>
          ))}
        </Grid>
      ) : (
        <Tile className="gisila-empty">
          No apps yet —{" "}
          <CarbonLink as={RouterLink} href="/apps/new">
            create your first
          </CarbonLink>
          .
        </Tile>
      )}
    </Page>
  );
}

function Meta({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="gisila-app-tile__meta-label">{label}</p>
      <p className="gisila-app-tile__meta-value">{value}</p>
    </div>
  );
}

function SkeletonGrid() {
  return (
    <Grid narrow className="gisila-apps__grid">
      {[0, 1, 2, 3].map((i) => (
        <Column key={i} sm={4} md={8} lg={8} className="gisila-apps__column">
          <SkeletonPlaceholder className="gisila-apps__skeleton" />
        </Column>
      ))}
    </Grid>
  );
}
