"use client";

import { useEffect, useState } from "react";
import RouterLink from "@/compat/link";
import { useParams, useRouter } from "@/compat/navigation";
import useSWR, { mutate } from "swr";
import { ArrowRight, Launch, Save, TrashCan } from "@carbon/icons-react";
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
  Tag,
  TextInput,
  Tile,
} from "@carbon/react";
import { Page, PageHeader, PageSection } from "@/components/page";
import { api, fetcher } from "@/lib/api";
import { usePermissions } from "@/lib/permissions";
import type { Application, ApplicationDef, DeployMode } from "@/lib/types";
import { DEPLOY_MODE_LABEL } from "@/lib/types";
import { toast } from "@/lib/toast";
import "../../services/_services.scss";

const STATUS_LABEL: Record<string, string> = {
  installed: "Installed",
  failed: "Failed",
  installing: "Installing…",
  updating: "Updating…",
  removing: "Removing…",
  pending: "Pending…",
};

const IN_PROGRESS = ["installing", "updating", "removing", "pending"];

const STATUS_TAG: Record<string, "green" | "red"> = {
  installed: "green",
  failed: "red",
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
      refreshInterval: (a) =>
        a && ["installing", "updating", "removing", "pending"].includes(a.status)
          ? 2000
          : 0,
    },
  );

  const def = app?._def;

  if (isLoading) return <PageSkeleton />;
  if (!app) return null;

  return (
    <Page>
      <Breadcrumb noTrailingSlash className="gisila-breadcrumb">
        <BreadcrumbItem>
          <CarbonLink as={RouterLink} href="/applications">
            Applications
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

      <DefaultsForm
        app={app}
        def={def}
        onSaved={() => mutate(`/applications/${id}`)}
      />

      <AppsUsingSection applicationId={app.id} />

      <ApplicationActions
        app={app}
        onDone={() => router.push("/applications")}
      />
    </Page>
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
      description="These seed new Apps created against this Application. Existing Apps keep their own configured values."
    >
      <Form onSubmit={(e) => e.preventDefault()}>
        <Stack gap={5}>
          <TextInput
            id="version"
            labelText="Default version"
            className="gisila-field--mono"
            value={version}
            placeholder={def?.versionHint ?? "e.g. 3.12.4"}
            helperText={def?.versionHint}
            onChange={(e) => setVersion(e.target.value)}
            disabled={!isSuperuser}
          />

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

// ── Apps using this Application ───────────────────────────────────────────────

function AppsUsingSection({ applicationId }: { applicationId: number }) {
  const { data } = useSWR<{ results: { id: number; name: string }[] }>(
    "/apps/",
    fetcher,
  );
  const apps = (data?.results ?? []) as unknown as {
    id: number;
    name: string;
    applicationId?: number | null;
  }[];
  const inUse = apps.filter((a) => a.applicationId === applicationId);

  return (
    <PageSection title={`Apps using this Application (${inUse.length})`}>
      {inUse.length === 0 ? (
        <p className="gisila-detail__note">
          No apps reference this Application yet.
        </p>
      ) : (
        <StructuredListWrapper aria-label="Apps using this Application" isCondensed>
          <StructuredListBody>
            {inUse.map((a) => (
              <StructuredListRow key={a.id}>
                <StructuredListCell>
                  <CarbonLink href={`/apps/${a.id}`} renderIcon={ArrowRight}>
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

  const isInProgress = ["installing", "updating", "removing", "pending"].includes(
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
          Blocked while any App still references this Application.
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
          reference this Application will block it.
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
