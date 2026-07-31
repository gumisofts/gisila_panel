"use client";

import { useState } from "react";
import RouterLink from "@/compat/link";
import useSWR, { mutate } from "swr";
import {
  Add,
  Application as ApplicationIcon,
  ArrowRight,
  Launch,
} from "@carbon/icons-react";
import {
  Button,
  ClickableTile,
  Column,
  Grid,
  InlineLoading,
  Link as CarbonLink,
  SkeletonText,
  Stack,
  Tag,
  Tile,
} from "@carbon/react";
import { Page, PageHeader, PageSection } from "@/components/page";
import { api, fetcher } from "@/lib/api";
import { usePermissions } from "@/lib/permissions";
import type {
  Application,
  ApplicationDef,
  DeployMode,
  ListResponse,
} from "@/lib/types";
import { DEPLOY_MODE_LABEL } from "@/lib/types";
import { toast } from "@/lib/toast";
import "../services/_services.scss";

// ── Helpers ───────────────────────────────────────────────────────────────────

/// ClickableTile renders Carbon's polymorphic Link and forwards unknown props to
/// it, but its own props are typed against an anchor, so `as` — how the tile is
/// handed to react-router instead of doing a document navigation — is declared
/// here.
const RouterTile = ClickableTile as React.ComponentType<
  React.ComponentProps<typeof ClickableTile> & { as?: React.ElementType }
>;

const STATUS_LABEL: Record<string, string> = {
  installed: "Installed",
  failed: "Failed",
  installing: "Installing…",
  updating: "Updating…",
  removing: "Removing…",
  pending: "Pending…",
  disabled: "Disabled",
};

/// Statuses the backend is still working through — these poll and show a spinner
/// rather than a settled tag.
const IN_PROGRESS = ["installing", "updating", "removing", "pending"];

const STATUS_TAG: Record<string, "green" | "red" | "gray"> = {
  installed: "green",
  failed: "red",
  disabled: "gray",
};

function StatusIndicator({ status }: { status: string }) {
  const label = STATUS_LABEL[status] ?? status;
  if (IN_PROGRESS.includes(status)) {
    return <InlineLoading status="active" description={label} />;
  }
  return (
    <Tag type={STATUS_TAG[status] ?? "cool-gray"} size="sm">
      {label}
    </Tag>
  );
}

// ── Page ─────────────────────────────────────────────────────────────────────

export default function ApplicationsPage() {
  const { data: catalogData } = useSWR<ListResponse<ApplicationDef>>(
    "/applications/catalog",
    fetcher,
  );
  const { data: installedData, isLoading } = useSWR<ListResponse<Application>>(
    "/applications/",
    fetcher,
    { refreshInterval: 4000 },
  );

  const catalog = catalogData?.results ?? [];
  const installed = installedData?.results ?? [];

  const installedByKey = new Map(installed.map((a) => [a.key, a]));

  return (
    <Page>
      <PageHeader
        title="Applications"
        description="Runtime & language stacks (Python, Dart, Node, …) managed independently of the panel. Apps pick one of these as their deployment target."
      />

      <PageSection>
        {isLoading ? (
          <SkeletonTiles />
        ) : installed.length === 0 ? (
          <Tile className="gisila-empty">
            No Applications installed yet — pick one from the catalog below.
          </Tile>
        ) : (
          <Grid fullWidth withRowGap>
            {installed.map((app) => (
              <Column key={app.id} sm={4} md={4} lg={8}>
                <InstalledTile app={app} />
              </Column>
            ))}
          </Grid>
        )}
      </PageSection>

      <PageSection title="Available Applications">
        <Grid fullWidth withRowGap>
          {catalog.map((def) => (
            <Column key={def.key} sm={4} md={4} lg={8}>
              <CatalogTile def={def} installed={installedByKey.get(def.key)} />
            </Column>
          ))}
        </Grid>
      </PageSection>
    </Page>
  );
}

// ── Installed tile ────────────────────────────────────────────────────────────

function InstalledTile({ app }: { app: Application }) {
  const modes = app.deployModes.split(",").filter(Boolean) as DeployMode[];

  return (
    <RouterTile as={RouterLink} href={`/applications/${app.id}`}>
      <Stack gap={4}>
        <div className="gisila-catalog__row">
          <div className="gisila-catalog__ident">
            <span className="gisila-catalog__icon">
              <ApplicationIcon size={20} />
            </span>
            <div>
              <p className="gisila-catalog__name">{app.displayName}</p>
              <p className="gisila-catalog__key">{app.key}</p>
            </div>
          </div>
          <StatusIndicator status={app.status} />
        </div>

        <div className="gisila-catalog__tags">
          {modes.map((m) => (
            <Tag key={m} type="cool-gray" size="sm">
              {DEPLOY_MODE_LABEL[m] ?? m}
            </Tag>
          ))}
          {app.defaultVersion && (
            <Tag type="outline" size="sm">
              {app.defaultVersion}
            </Tag>
          )}
        </div>

        {app.errorMessage && (
          <p className="gisila-catalog__error">{app.errorMessage}</p>
        )}

        <div className="gisila-catalog__row">
          <span className="gisila-catalog__meta">
            {app.installedAt
              ? `Installed ${new Date(app.installedAt).toLocaleDateString()}`
              : ""}
          </span>
          <span className="gisila-catalog__cta">
            Configure
            <ArrowRight size={16} />
          </span>
        </div>
      </Stack>
    </RouterTile>
  );
}

// ── Catalog tile ──────────────────────────────────────────────────────────────

function CatalogTile({
  def,
  installed,
}: {
  def: ApplicationDef;
  installed?: Application;
}) {
  const [installing, setInstalling] = useState(false);
  const { isSuperuser } = usePermissions();

  const isInstalled = !!installed;

  async function quickInstall() {
    if (isInstalled || installing) return;
    setInstalling(true);
    try {
      await api("/applications/", {
        method: "POST",
        body: JSON.stringify({ key: def.key }),
      });
      mutate("/applications/");
      toast.success(`${def.displayName} install queued.`);
    } catch (e: unknown) {
      toast.error(e instanceof Error ? e.message : "Install failed.");
    } finally {
      setInstalling(false);
    }
  }

  return (
    <Tile
      className={isInstalled ? "gisila-catalog__tile--installed" : undefined}
    >
      <Stack gap={4}>
        <div className="gisila-catalog__row">
          <div className="gisila-catalog__ident">
            <span className="gisila-catalog__icon">
              <ApplicationIcon size={20} />
            </span>
            <div>
              <p className="gisila-catalog__name">{def.displayName}</p>
              <div className="gisila-catalog__tags">
                {def.deployModes.map((m) => (
                  <Tag key={m} type="cool-gray" size="sm">
                    {DEPLOY_MODE_LABEL[m] ?? m}
                  </Tag>
                ))}
              </div>
            </div>
          </div>

          {def.docsUrl && (
            <CarbonLink
              href={def.docsUrl}
              target="_blank"
              rel="noopener noreferrer"
              renderIcon={Launch}
              size="sm"
              onClick={(e) => e.stopPropagation()}
            >
              Docs
            </CarbonLink>
          )}
        </div>

        <p className="gisila-catalog__desc">{def.description}</p>

        <div className="gisila-catalog__row">
          <span className="gisila-catalog__summary-label">
            {def.versionHint ?? "no version pin"}
          </span>

          {isInstalled ? (
            <CarbonLink
              as={RouterLink}
              href={`/applications/${installed.id}`}
              renderIcon={ArrowRight}
              size="sm"
            >
              Installed · View
            </CarbonLink>
          ) : isSuperuser ? (
            installing ? (
              <InlineLoading status="active" />
            ) : (
              <Button
                size="sm"
                kind="tertiary"
                renderIcon={Add}
                onClick={quickInstall}
              >
                Install
              </Button>
            )
          ) : null}
        </div>
      </Stack>
    </Tile>
  );
}

function SkeletonTiles() {
  return (
    <Grid fullWidth withRowGap>
      {[0, 1, 2].map((i) => (
        <Column key={i} sm={4} md={4} lg={8}>
          <Tile>
            <SkeletonText paragraph lineCount={3} />
          </Tile>
        </Column>
      ))}
    </Grid>
  );
}
