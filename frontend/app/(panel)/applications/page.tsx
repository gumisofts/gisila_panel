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
  Modal,
  Select,
  SelectItem,
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
  ApplicationVersion,
  DeployMode,
  ListResponse,
} from "@/lib/types";
import { DEPLOY_MODE_LABEL } from "@/lib/types";
import { toast } from "@/lib/toast";
import "../services/_services.scss";
import "./_applications.scss";

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
  // Seeded catalog rows with no toolchain yet — idle, not a job in flight.
  pending: "Not installed",
  disabled: "Disabled",
};

/// Statuses the backend is still working through — these poll and show a spinner
/// rather than a settled tag. `pending` is intentionally excluded: it means the
/// runtime exists in the catalog DB but nothing has been queued/installed.
const IN_PROGRESS = ["installing", "updating", "removing"];

const STATUS_TAG: Record<string, "green" | "red" | "gray" | "cool-gray"> = {
  installed: "green",
  failed: "red",
  disabled: "gray",
  pending: "cool-gray",
};

/// Builtins are seeded as Application rows even before a version lands on the
/// host. Those placeholders are not "installed" for catalog/list purposes.
function hasHostPresence(app: Application): boolean {
  if (app.versions.length > 0) return true;
  return app.status !== "pending";
}

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

/// One installed toolchain version of a versioned Application. Settled versions
/// are a tag — blue for the one new apps get, red when the install failed —
/// while a version the host is still working on shows the spinner instead.
function VersionTag({ version: v }: { version: ApplicationVersion }) {
  const label = STATUS_LABEL[v.status] ?? v.status;

  if (IN_PROGRESS.includes(v.status)) {
    return <InlineLoading status="active" description={`${v.version} · ${label}`} />;
  }

  const failed = v.status === "failed";
  const title = failed
    ? v.errorMessage ?? `${v.version} failed to install`
    : v.isDefault
      ? `${v.version} — the version new apps get`
      : `${v.version} — installed`;

  return (
    <span className="gisila-versions__tag" title={title}>
      <Tag as="span" size="sm" type={failed ? "red" : v.isDefault ? "blue" : "outline"}>
        {v.version}
      </Tag>
    </span>
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
    {
      refreshInterval: (data) => {
        const apps = data?.results ?? [];
        const busy = apps.some(
          (a) =>
            IN_PROGRESS.includes(a.status) ||
            a.versions.some((v) => IN_PROGRESS.includes(v.status)),
        );
        return busy ? 4000 : 0;
      },
    },
  );

  const catalog = catalogData?.results ?? [];
  const installed = installedData?.results ?? [];
  const onHost = installed.filter(hasHostPresence);

  const installedByKey = new Map(installed.map((a) => [a.key, a]));

  return (
    <Page>
      <PageHeader
        title="Runtimes"
        description="Language & runtime stacks (Python, Dart, Node, …) managed independently of the panel. Apps pick one of these as their deployment target."
      />

      <PageSection>
        {isLoading ? (
          <SkeletonTiles />
        ) : onHost.length === 0 ? (
          <Tile className="gisila-empty">
            No runtimes installed yet — pick one from the catalog below.
          </Tile>
        ) : (
          <Grid fullWidth withRowGap className="gisila-catalog__grid">
            {onHost.map((app) => (
              <Column key={app.id} sm={4} md={4} lg={8}>
                <InstalledTile app={app} />
              </Column>
            ))}
          </Grid>
        )}
      </PageSection>

      <PageSection title="Available runtimes">
        <Grid fullWidth withRowGap className="gisila-catalog__grid">
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
    <RouterTile as={RouterLink} href={`/runtimes/${app.id}`}>
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
          {app.versions.length > 0
            ? app.versions.map((v) => <VersionTag key={v.id} version={v} />)
            : app.defaultVersion && (
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
  const [choosing, setChoosing] = useState(false);
  const [version, setVersion] = useState("");
  const { isSuperuser } = usePermissions();

  // Seeded-but-empty rows still come back from /applications/; treat those as
  // catalog entries so Install stays available instead of "Installed · View".
  const isInstalled = !!installed && hasHostPresence(installed);

  // Versions already on the host — offering one of those again would only earn
  // a 409 from the backend.
  const present = new Set((installed?.versions ?? []).map((v) => v.version));
  const installable = def.availableVersions.filter((v) => !present.has(v));

  function openInstall() {
    const recommended = def.defaultVersion ?? "";
    setVersion(
      installable.includes(recommended) ? recommended : installable[0] ?? "",
    );
    setChoosing(true);
  }

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

  /// Installs the chosen version: a first install creates the Application,
  /// every later one is added alongside the versions already installed.
  async function installVersion() {
    if (!version) return;
    setChoosing(false);
    setInstalling(true);
    try {
      if (installed) {
        await api(`/applications/${installed.id}/versions`, {
          method: "POST",
          body: JSON.stringify({ version }),
        });
      } else {
        await api("/applications/", {
          method: "POST",
          body: JSON.stringify({ key: def.key, version }),
        });
      }
      mutate("/applications/");
      toast.success(`${def.displayName} ${version} install queued.`);
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

          {installing ? (
            <InlineLoading status="active" />
          ) : def.versioned ? (
            // Versioned runtimes stay installable after the first version, so
            // the tile keeps offering the next one alongside the link.
            <div className="gisila-versions__actions">
              {isInstalled && (
                <CarbonLink
                  as={RouterLink}
                  href={`/runtimes/${installed.id}`}
                  renderIcon={ArrowRight}
                  size="sm"
                >
                  Installed · View
                </CarbonLink>
              )}
              {isSuperuser && installable.length > 0 && (
                <Button
                  size="sm"
                  kind="tertiary"
                  renderIcon={Add}
                  onClick={openInstall}
                >
                  {isInstalled ? "Install another version" : "Install"}
                </Button>
              )}
            </div>
          ) : isInstalled ? (
            <CarbonLink
              as={RouterLink}
              href={`/runtimes/${installed.id}`}
              renderIcon={ArrowRight}
              size="sm"
            >
              Installed · View
            </CarbonLink>
          ) : isSuperuser ? (
            <Button
              size="sm"
              kind="tertiary"
              renderIcon={Add}
              onClick={quickInstall}
            >
              Install
            </Button>
          ) : null}
        </div>
      </Stack>

      <Modal
        open={choosing}
        size="sm"
        modalHeading={
          isInstalled
            ? `Install another ${def.displayName} version`
            : `Install ${def.displayName}`
        }
        modalLabel={def.key}
        primaryButtonText="Install"
        primaryButtonDisabled={!version}
        secondaryButtonText="Cancel"
        onRequestClose={() => setChoosing(false)}
        onRequestSubmit={() => void installVersion()}
      >
        <Stack gap={5}>
          <Select
            id={`install-version-${def.key}`}
            labelText="Version"
            value={version}
            onChange={(e) => setVersion(e.target.value)}
          >
            {installable.map((v) => (
              <SelectItem
                key={v}
                value={v}
                text={v === def.defaultVersion ? `${v} (recommended)` : v}
              />
            ))}
          </Select>
          <p className="gisila-detail__note">
            {isInstalled
              ? "The version is installed alongside the ones already on the host. Apps keep whichever version they pin."
              : "The toolchain is installed on the host in the background. More versions can be added afterwards."}
          </p>
        </Stack>
      </Modal>
    </Tile>
  );
}

function SkeletonTiles() {
  return (
    <Grid fullWidth withRowGap className="gisila-catalog__grid">
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
