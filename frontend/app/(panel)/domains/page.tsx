"use client";

import type { ComponentProps, ElementType } from "react";
import RouterLink from "@/compat/link";
import useSWR from "swr";
import { Earth } from "@carbon/icons-react";
import { ClickableTile, Stack, Tag, Tile } from "@carbon/react";
import { Page, PageHeader } from "@/components/page";
import { fetcher } from "@/lib/api";
import type { App, Domain, ListResponse } from "@/lib/types";
import "../_batch-a.scss";

interface AppWithDomains extends App {
  domains?: Domain[];
}

// ClickableTile forwards unrecognised props to Carbon's polymorphic Link, so
// `as` works at runtime even though the prop type omits it.
const LinkTile = ClickableTile as React.ComponentType<
  ComponentProps<typeof ClickableTile> & { as?: ElementType }
>;

export default function DomainsPage() {
  const apps = useSWR<ListResponse<App>>("/apps/", fetcher);

  return (
    <Page>
      <PageHeader
        title="Domains"
        description="Manage custom hostnames + automatic Let’s Encrypt certificates."
      />

      <Stack gap={3}>
        {apps.data?.results.map((app) => (
          <LinkTile
            key={app.id}
            as={RouterLink}
            href={`/apps/${app.id}#domains`}
          >
            <div className="gisila-row">
              <div className="gisila-row__main">
                <span className="gisila-status-icon gisila-status-icon--brand">
                  <Earth size={16} />
                </span>
                <div>
                  <p className="gisila-card__title">{app.name}</p>
                  <p className="gisila-card__meta">
                    {app.runtime} · port {app.internalPort}
                  </p>
                </div>
              </div>
              <Tag type="cool-gray" size="sm">
                manage
              </Tag>
            </div>
          </LinkTile>
        ))}
        {apps.data?.results.length === 0 && (
          <Tile className="gisila-empty">
            You don&rsquo;t have any apps yet.
          </Tile>
        )}
      </Stack>
    </Page>
  );
}
