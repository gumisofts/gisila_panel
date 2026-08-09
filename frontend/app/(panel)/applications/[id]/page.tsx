"use client";

import { useEffect, useState } from "react";
import RouterLink from "@/compat/link";
import { useParams, useRouter } from "@/compat/navigation";
import useSWR, { mutate } from "swr";
import { Add, ArrowRight, Launch, Save, Star, TrashCan } from "@carbon/icons-react";
import {
  Breadcrumb,
  BreadcrumbItem,
  Button,
  Form,
  InlineLoading,
  InlineNotification,
  Link as CarbonLink,
  Modal,
  Select,
  SelectItem,
  SkeletonText,
  Stack,
  StructuredListBody,
  StructuredListCell,
  StructuredListRow,
  StructuredListWrapper,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableHeader,
  TableRow,
  Tag,
  TextInput,
  Tile,
} from "@carbon/react";
import { Page, PageHeader, PageSection } from "@/components/page";
import { api, fetcher } from "@/lib/api";
import { usePermissions } from "@/lib/permissions";
import type {
  App,
  Application,
  ApplicationDef,
  ApplicationVersion,
  DeployMode,
  ListResponse,
} from "@/lib/types";
import { DEPLOY_MODE_LABEL } from "@/lib/types";
import { toast } from "@/lib/toast";
import "../../services/_services.scss";
import "../_applications.scss";

const STATUS_LABEL: Record<string, string> = {
  installed: "Installed",
  failed: "Failed",
  installing: "Installing…",
  updating: "Updating…",
  removing: "Removing…",
  // Seeded catalog row with no toolchain — idle, not a job in flight.
  pending: "Not installed",
};

const IN_PROGRESS = ["installing", "updating", "removing"];

const STATUS_TAG: Record<string, "green" | "red" | "cool-gray"> = {
  installed: "green",
  failed: "red",
  pending: "cool-gray",
};

function StatusIndicator({ status }: { status: string }) {
  const label = STATUS_LABEL[status] ?? status;
  if (IN_PROGRESS.includes(status)) {
    return <InlineLoading status="active" description={label} />;
  }
  return (
    <Tag type={STATUS_TAG[status] ?? "cool-gray"} size="md">
      {label}
    </Tag>
  );
}

export default function ApplicationDetailPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();

  const { data: app, isLoading } = useSWR<Application>(
    `/applications/${id}`,
    fetcher,
    {
      // A settled Application can still have a version installing on the host,
      // so the page also polls while any single version is in flight.
      refreshInterval: (a) => {
        if (!a) return 0;
        if (IN_PROGRESS.includes(a.status)) return 2000;
        if (a.versions.some((v) => IN_PROGRESS.includes(v.status))) return 4000;
        return 0;
      },
    },
  );

  const def = app?._def;

  if (isLoading) return <PageSkeleton />;
  if (!app) return null;

  return (
    <Page>
      <Breadcrumb noTrailingSlash className="gisila-breadcrumb">
        <BreadcrumbItem>
          <CarbonLink as={RouterLink} href="/runtimes">
            Runtimes
          </CarbonLink>
        </BreadcrumbItem>
        <BreadcrumbItem isCurrentPage>{app.displayName}</BreadcrumbItem>
      </Breadcrumb>

      <PageHeader
        title={app.displayName}
        description={<span className="gisila-detail__key">{app.key}</span>}
        actions={<StatusIndicator status={app.status} />}
      />

      {(app.errorMessage || def?.docsUrl || def?.description) && (
        <PageSection>
          <Stack gap={5}>
            {app.errorMessage && (
              <InlineNotification
                kind="error"
                lowContrast
                hideCloseButton
                title={app.errorMessage}
              />
            )}

            {def?.docsUrl && (
              <CarbonLink
                href={def.docsUrl}
                target="_blank"
                rel="noopener noreferrer"
                renderIcon={Launch}
                size="sm"
              >
                Documentation
              </CarbonLink>
            )}

            {def?.description && (
              <p className="gisila-detail__note">{def.description}</p>
            )}
          </Stack>
        </PageSection>
      )}

      {def?.versioned && (
        <VersionsSection
          app={app}
          def={def}
          onChanged={() => mutate(`/applications/${id}`)}
        />
      )}

      <DefaultsForm
        app={app}
        def={def}
        onSaved={() => mutate(`/applications/${id}`)}
      />

      <AppsUsingSection applicationId={app.id} />

      <ApplicationActions
        app={app}
        onDone={() => router.push("/runtimes")}
      />
    </Page>
  );
}

// ── Installed versions ────────────────────────────────────────────────────────

/// The versions of a versioned Application that are on the host. Several live
/// side by side; one of them is the version new apps get when they don't pin
/// their own.
function VersionsSection({
  app,
  def,
  onChanged,
}: {
  app: Application;
  def: ApplicationDef;
  onChanged: () => void;
}) {
  const { isSuperuser } = usePermissions();
  const [installing, setInstalling] = useState(false);
  const [choosing, setChoosing] = useState(false);
  const [version, setVersion] = useState("");
  const [removing, setRemoving] = useState<ApplicationVersion | null>(null);
  const [busy, setBusy] = useState(false);

  const present = new Set(app.versions.map((v) => v.version));
  const installable = def.availableVersions.filter((v) => !present.has(v));

  function openInstall() {
    const recommended = def.defaultVersion ?? "";
    setVersion(
      installable.includes(recommended) ? recommended : installable[0] ?? "",
    );
    setChoosing(true);
  }

  async function install() {
    if (!version) return;
    setChoosing(false);
    setInstalling(true);
    try {
      await api(`/applications/${app.id}/versions`, {
        method: "POST",
        body: JSON.stringify({ version }),
      });
      toast.success(`${version} install queued.`);
      onChanged();
    } catch (e: unknown) {
      toast.error(e instanceof Error ? e.message : "Install failed.");
    } finally {
      setInstalling(false);
    }
  }

  async function makeDefault(v: ApplicationVersion) {
    setBusy(true);
    try {
      await api(`/applications/${app.id}/versions/${v.id}/default`, {
        method: "POST",
      });
      toast.success(`New apps will use ${v.version}.`);
      onChanged();
    } catch (e: unknown) {
      toast.error(e instanceof Error ? e.message : "Failed to set the default.");
    } finally {
      setBusy(false);
    }
  }

  /// Removes one version. The backend refuses (409) while any app still pins
  /// it and explains which — that message is the whole point of the toast.
  async function remove(v: ApplicationVersion) {
    setBusy(true);
    try {
      await api(`/applications/${app.id}/versions/${v.id}`, { method: "DELETE" });
      toast.success(`${v.version} removal queued.`);
      onChanged();
    } catch (e: unknown) {
      toast.error(e instanceof Error ? e.message : "Removal failed.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <PageSection
      title="Installed versions"
      description="Several versions of this runtime can live on the host at once. Apps pin the version they were created with; the default is what new apps get."
      actions={
        isSuperuser &&
        (installing ? (
          <InlineLoading status="active" description="Installing…" />
        ) : (
          <Button
            size="sm"
            kind="tertiary"
            renderIcon={Add}
            disabled={installable.length === 0}
            onClick={openInstall}
          >
            Install version
          </Button>
        ))
      }
    >
      {app.versions.length === 0 ? (
        <Tile>
          <p className="gisila-versions__muted">
            No versions installed yet — install one to deploy apps against this
            runtime.
          </p>
        </Tile>
      ) : (
        <TableContainer>
          <Table size="lg">
            <TableHead>
              <TableRow>
                <TableHeader>Version</TableHeader>
                <TableHeader>Status</TableHeader>
                <TableHeader>Default</TableHeader>
                <TableHeader>Installed</TableHeader>
                <TableHeader>Actions</TableHeader>
              </TableRow>
            </TableHead>
            <TableBody>
              {app.versions.map((v) => (
                <TableRow key={v.id}>
                  <TableCell>
                    <span className="gisila-versions__version">{v.version}</span>
                    {v.errorMessage && (
                      <span className="gisila-versions__error">
                        {v.errorMessage}
                      </span>
                    )}
                  </TableCell>
                  <TableCell>
                    <StatusIndicator status={v.status} />
                  </TableCell>
                  <TableCell>
                    {v.isDefault ? (
                      <Tag type="blue" size="sm" renderIcon={Star}>
                        Default
                      </Tag>
                    ) : (
                      <span className="gisila-versions__muted">—</span>
                    )}
                  </TableCell>
                  <TableCell>
                    {v.installedAt
                      ? new Date(v.installedAt).toLocaleDateString()
                      : "—"}
                  </TableCell>
                  <TableCell>
                    <div className="gisila-versions__actions">
                      {isSuperuser && !v.isDefault && v.status === "installed" && (
                        <Button
                          kind="ghost"
                          size="sm"
                          renderIcon={Star}
                          disabled={busy}
                          onClick={() => void makeDefault(v)}
                        >
                          Make default
                        </Button>
                      )}
                      {isSuperuser && (
                        <Button
                          kind="danger--ghost"
                          size="sm"
                          hasIconOnly
                          renderIcon={TrashCan}
                          iconDescription={`Remove ${v.version}`}
                          disabled={busy || v.status === "removing"}
                          onClick={() => setRemoving(v)}
                        />
                      )}
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </TableContainer>
      )}

      <Modal
        open={choosing}
        size="sm"
        modalHeading={`Install a ${app.displayName} version`}
        modalLabel={app.key}
        primaryButtonText="Install"
        primaryButtonDisabled={!version}
        secondaryButtonText="Cancel"
        onRequestClose={() => setChoosing(false)}
        onRequestSubmit={() => void install()}
      >
        <Stack gap={5}>
          <Select
            id="install-version"
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
            Installed alongside the versions already on the host. Existing apps
            keep the version they pin.
          </p>
        </Stack>
      </Modal>

      <Modal
        open={!!removing}
        danger
        modalHeading={`Remove ${app.displayName} ${removing?.version ?? ""}?`}
        modalLabel={app.key}
        primaryButtonText="Remove"
        secondaryButtonText="Cancel"
        onRequestClose={() => setRemoving(null)}
        onRequestSubmit={() => {
          const target = removing;
          setRemoving(null);
          if (target) void remove(target);
        }}
      >
        <p className="gisila-detail__note">
          The toolchain is deleted from the host. Blocked while any app still
          pins this version — the other installed versions are untouched.
        </p>
      </Modal>
    </PageSection>
  );
}

// ── Deployment defaults form ──────────────────────────────────────────────────

function DefaultsForm({
  app,
  def,
  onSaved,
}: {
  app: Application;
  def?: ApplicationDef;
  onSaved: () => void;
}) {
  const modes = (app.deployModes.split(",").filter(Boolean) as DeployMode[]);

  const [version, setVersion] = useState(app.defaultVersion ?? "");
  const [deployMode, setDeployMode] = useState<DeployMode>(app.defaultDeployMode);
  const [buildCommand, setBuildCommand] = useState(app.defaultBuildCommand ?? "");
  const [startCommand, setStartCommand] = useState(app.defaultStartCommand ?? "");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    setVersion(app.defaultVersion ?? "");
    setDeployMode(app.defaultDeployMode);
    setBuildCommand(app.defaultBuildCommand ?? "");
    setStartCommand(app.defaultStartCommand ?? "");
  }, [app.id, app.defaultVersion, app.defaultDeployMode, app.defaultBuildCommand, app.defaultStartCommand]);

  const { isSuperuser } = usePermissions();

  // A versioned Application can only default to a version that is actually on
  // the host — plus whatever it currently points at, so a stale value is
  // visible rather than silently swapped for the first option.
  const onHost = app.versions
    .filter((v) => v.status === "installed")
    .map((v) => v.version);
  const versionOptions =
    version && !onHost.includes(version) ? [version, ...onHost] : onHost;

  async function save() {
    setSaving(true);
    try {
      await api(`/applications/${app.id}`, {
        method: "PATCH",
        body: JSON.stringify({
          defaultVersion: version || null,
          defaultDeployMode: deployMode,
          defaultBuildCommand: buildCommand || null,
          defaultStartCommand: startCommand || null,
        }),
      });
      toast.success("Deployment defaults saved.");
      onSaved();
    } catch (e: unknown) {
      toast.error(e instanceof Error ? e.message : "Failed to save.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <PageSection
      title="Deployment defaults"
      description="These seed new Apps created against this runtime. Existing Apps keep their own configured values."
    >
      <Form onSubmit={(e) => e.preventDefault()}>
        <Stack gap={5}>
          {def?.versioned ? (
            <Select
              id="version"
              labelText="Default version"
              value={version}
              helperText="Only versions installed on this host can be the default. Install more from the section above."
              onChange={(e) => setVersion(e.target.value)}
              disabled={!isSuperuser}
            >
              <SelectItem value="" text="No default — apps pick their own" />
              {versionOptions.map((v) => (
                <SelectItem key={v} value={v} text={v} />
              ))}
            </Select>
          ) : (
            <TextInput
              id="version"
              labelText="Default version"
              className="gisila-field--mono"
              value={version}
              placeholder={def?.versionHint ?? "e.g. 3.13.15"}
              helperText={def?.versionHint}
              onChange={(e) => setVersion(e.target.value)}
              disabled={!isSuperuser}
            />
          )}

          {modes.length > 1 && (
            <Select
              id="deployMode"
              labelText="Default deployment mode"
              value={deployMode}
              onChange={(e) => setDeployMode(e.target.value as DeployMode)}
              disabled={!isSuperuser}
            >
              {modes.map((m) => (
                <SelectItem key={m} value={m} text={DEPLOY_MODE_LABEL[m] ?? m} />
              ))}
            </Select>
          )}

          <TextInput
            id="buildCommand"
            labelText="Default build command"
            className="gisila-field--mono"
            value={buildCommand}
            placeholder="leave empty to use the plugin's built-in default"
            onChange={(e) => setBuildCommand(e.target.value)}
            disabled={!isSuperuser}
          />

          <TextInput
            id="startCommand"
            labelText="Default start command"
            className="gisila-field--mono"
            value={startCommand}
            placeholder="leave empty to use the plugin's built-in default"
            onChange={(e) => setStartCommand(e.target.value)}
            disabled={!isSuperuser}
          />

          {isSuperuser &&
            (saving ? (
              <InlineLoading status="active" description="Saving…" />
            ) : (
              <Button size="md" renderIcon={Save} onClick={save}>
                Save defaults
              </Button>
            ))}
        </Stack>
      </Form>
    </PageSection>
  );
}

// ── Apps using this runtime ───────────────────────────────────────────────────

function AppsUsingSection({ applicationId }: { applicationId: number }) {
  const { data } = useSWR<ListResponse<App>>("/apps/", fetcher);
  const inUse = (data?.results ?? []).filter(
    (a) => Number(a.applicationId) === Number(applicationId),
  );

  return (
    <PageSection title={`Apps using this runtime (${inUse.length})`}>
      {inUse.length === 0 ? (
        <p className="gisila-detail__note">
          No apps reference this runtime yet.
        </p>
      ) : (
        <StructuredListWrapper aria-label="Apps using this runtime" isCondensed>
          <StructuredListBody>
            {inUse.map((a) => (
              <StructuredListRow key={a.id}>
                <StructuredListCell>
                  <CarbonLink
                    as={RouterLink}
                    href={`/apps/${a.id}`}
                    renderIcon={ArrowRight}
                  >
                    {a.name}
                  </CarbonLink>
                </StructuredListCell>
                <StructuredListCell>
                  <Tag type="cool-gray" size="sm">
                    #{a.id}
                  </Tag>
                </StructuredListCell>
              </StructuredListRow>
            ))}
          </StructuredListBody>
        </StructuredListWrapper>
      )}
    </PageSection>
  );
}

// ── Actions ───────────────────────────────────────────────────────────────────

function ApplicationActions({
  app,
  onDone,
}: {
  app: Application;
  onDone: () => void;
}) {
  const [busy, setBusy] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const { isSuperuser } = usePermissions();

  if (!isSuperuser) return null;

  const isInProgress = ["installing", "updating", "removing"].includes(
    app.status,
  );

  async function remove() {
    setBusy(true);
    try {
      await api(`/applications/${app.id}`, { method: "DELETE" });
      toast.success("Removal queued.");
      onDone();
    } catch (e: unknown) {
      toast.error(e instanceof Error ? e.message : "Removal failed.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <PageSection title="Actions">
      <Stack gap={3}>
        {busy ? (
          <InlineLoading status="active" description="Removing…" />
        ) : (
          <Button
            size="md"
            kind="danger--tertiary"
            renderIcon={TrashCan}
            disabled={isInProgress}
            onClick={() => setConfirming(true)}
          >
            Remove
          </Button>
        )}
        <p className="gisila-detail__note">
          Blocked while any App still references this runtime.
        </p>
      </Stack>

      <Modal
        open={confirming}
        danger
        modalHeading={`Remove ${app.displayName}?`}
        modalLabel={app.key}
        primaryButtonText="Remove"
        secondaryButtonText="Cancel"
        onRequestClose={() => setConfirming(false)}
        onRequestSubmit={() => {
          setConfirming(false);
          void remove();
        }}
      >
        <p className="gisila-detail__note">
          The runtime is queued for removal from the host. Apps that still
          reference this runtime will block it.
        </p>
      </Modal>
    </PageSection>
  );
}

function PageSkeleton() {
  return (
    <Page>
      <SkeletonText heading width="40%" />
      <Tile>
        <Stack gap={5}>
          {[0, 1, 2, 3].map((i) => (
            <SkeletonText key={i} />
          ))}
        </Stack>
      </Tile>
    </Page>
  );
}
