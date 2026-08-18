"use client";

import { useState } from "react";
import { useParams, useRouter } from "@/compat/navigation";
import useSWR from "swr";
import {
  Breadcrumb,
  BreadcrumbItem,
  Button,
  ButtonSet,
  Link as CarbonLink,
  Modal,
  SkeletonText,
  Tab,
  TabList,
  TabPanel,
  TabPanels,
  Tabs,
  Tag,
  Tile,
} from "@carbon/react";
import {
  PlayFilled,
  Renew,
  Rocket,
  StopFilled,
  TrashCan,
} from "@carbon/icons-react";
import RouterLink from "@/compat/link";
import { toast } from "@/lib/toast";
import { api, fetcher } from "@/lib/api";
import { usePermissions } from "@/lib/permissions";
import { formatRelative } from "@/lib/utils";
import type { App } from "@/lib/types";
import { EXPOSE_MODE_LABEL } from "@/lib/types";
import { Page, PageHeader } from "@/components/page";
import { OverviewTab } from "./_tabs/overview";
import { DeploymentsTab } from "./_tabs/deployments";
import { EnvsTab } from "./_tabs/envs";
import { DomainsTab } from "./_tabs/domains";
import { LogsTab } from "./_tabs/logs";
import { ConsoleTab } from "./_tabs/console";
import { MetricsTab } from "./_tabs/metrics";
import { StorageTab } from "./_tabs/storage";
import { SettingsTab } from "./_tabs/settings";
import "./_app-detail.scss";

type TagType = "green" | "blue" | "cyan" | "red" | "gray";

/// Lifecycle state mapped onto Carbon's tag palette: green for healthy, blue
/// for in-flight work, red for anything that needs attention.
function statusTagType(status: string): TagType {
  switch (status) {
    case "running":
    case "succeeded":
      return "green";
    case "building":
    case "deploying":
      return "blue";
    case "queued":
      return "cyan";
    case "failed":
    case "crashed":
    case "deleting":
      return "red";
    default:
      return "gray";
  }
}

/// How the app's `internalPort` reaches the network, for the header/overview
/// connection-info line. `web` apps are only ever proxied via Nginx from
/// loopback; `tcp` apps bind every interface themselves (and are reachable
/// from the internet iff `publiclyReachable`); `internal` apps never leave
/// the box.
function bindAddressLabel(app: App): string {
  if (!app.internalPort) return "no port";
  if (app.exposeMode === "tcp") {
    return `0.0.0.0:${app.internalPort} (${
      app.publiclyReachable ? "public" : "not publicly reachable"
    })`;
  }
  if (app.exposeMode === "internal") {
    return `127.0.0.1:${app.internalPort} (internal only)`;
  }
  return `127.0.0.1:${app.internalPort}`;
}

export default function AppDetailPage() {
  const params = useParams<{ id: string }>();
  const router = useRouter();
  const appId = Number(params.id);
  const { data: app, mutate } = useSWR<App>(`/apps/${appId}`, fetcher, {
    refreshInterval: 5000,
  });
  const [confirmRemove, setConfirmRemove] = useState(false);
  const [removing, setRemoving] = useState(false);
  const [tabIndex, setTabIndex] = useState(0);
  const { canForProject } = usePermissions();

  if (!app) {
    return (
      <Page>
        <SkeletonText heading width="40%" />
        <SkeletonText paragraph lineCount={2} />
      </Page>
    );
  }

  async function lifecycle(action: "start" | "stop" | "restart") {
    try {
      await api(`/apps/${appId}/${action}`, { method: "POST" });
      toast.success(`${action} requested`);
      mutate();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed");
    }
  }

  async function deployNow() {
    if (!app) return;
    try {
      await api(`/apps/${appId}/deployments/`, {
        method: "POST",
        body: JSON.stringify({ sourceType: app.sourceType }),
      });
      toast.success("Deployment queued");
      mutate();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed");
    }
  }

  async function removeApp() {
    setRemoving(true);
    try {
      await api(`/apps/${appId}`, { method: "DELETE" });
      toast.success("App removal started");
      setConfirmRemove(false);
      router.push("/apps");
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed");
      setRemoving(false);
    }
  }

  // Role-based gating (backend enforces these too; this just hides controls).
  const canDeploy = canForProject(app.projectId, "developer");
  const canStop = canForProject(app.projectId, "admin");
  const canDelete = canForProject(app.projectId, "admin");

  // Removal is only offered to admins while the app isn't actively running,
  // building, or already being deleted — i.e. stopped/created/failed/crashed.
  const canRemove =
    canDelete && !["running", "building", "deleting"].includes(app.status);

  return (
    <Page>
      <div className="gisila-app">
        <Breadcrumb
          noTrailingSlash
          aria-label="Breadcrumb"
          className="gisila-app__breadcrumb"
        >
          <BreadcrumbItem>
            <CarbonLink as={RouterLink} href="/apps">
              Apps
            </CarbonLink>
          </BreadcrumbItem>
          <BreadcrumbItem isCurrentPage>{app.name}</BreadcrumbItem>
        </Breadcrumb>

        <PageHeader
          title={
            <span className="gisila-app__title">
              {app.name}
              <Tag type="cool-gray" size="sm">
                {app.runtime}
              </Tag>
              <Tag type={statusTagType(app.status)} size="sm">
                {app.status}
              </Tag>
              {app.exposeMode && app.exposeMode !== "web" && (
                <Tag type="purple" size="sm">
                  {EXPOSE_MODE_LABEL[app.exposeMode]}
                </Tag>
              )}
            </span>
          }
          description={
            <span className="gisila-app__mono">
              {app.linuxUser} · {bindAddressLabel(app)} · deployed{" "}
              {formatRelative(app.lastDeployedAt)}
            </span>
          }
          actions={
            <ButtonSet>
              {canDeploy && (
                <Button
                  kind="secondary"
                  size="sm"
                  renderIcon={PlayFilled}
                  onClick={() => lifecycle("start")}
                >
                  Start
                </Button>
              )}
              {canDeploy && (
                <Button
                  kind="secondary"
                  size="sm"
                  renderIcon={Renew}
                  onClick={() => lifecycle("restart")}
                >
                  Restart
                </Button>
              )}
              {canStop && (
                <Button
                  kind="secondary"
                  size="sm"
                  renderIcon={StopFilled}
                  onClick={() => lifecycle("stop")}
                >
                  Stop
                </Button>
              )}
              {canDeploy && (
                <Button
                  kind="primary"
                  size="sm"
                  renderIcon={Rocket}
                  onClick={deployNow}
                >
                  Deploy now
                </Button>
              )}
              {canRemove && (
                <Button
                  kind="danger"
                  size="sm"
                  renderIcon={TrashCan}
                  onClick={() => setConfirmRemove(true)}
                >
                  Remove
                </Button>
              )}
              {app.status === "deleting" && (
                <Button kind="danger" size="sm" renderIcon={TrashCan} disabled>
                  Removing…
                </Button>
              )}
            </ButtonSet>
          }
        />

        <Modal
          open={confirmRemove}
          danger
          size="sm"
          modalHeading={`Remove ${app.name}?`}
          modalLabel="Danger zone"
          primaryButtonText={removing ? "Removing…" : "Remove app"}
          primaryButtonDisabled={removing}
          secondaryButtonText="Cancel"
          onRequestClose={() => setConfirmRemove(false)}
          onRequestSubmit={removeApp}
        >
          <p>
            This permanently deletes the app and all of its resources — the
            systemd service, AppArmor profile, nginx vhost, TLS certificates, the
            Linux user, and every file under its work directory. Env vars, domains
            and deployment history are removed too. This cannot be undone.
          </p>
        </Modal>

        {/* Carbon renders every TabPanel and only hides the inactive ones, so the
            body of each tab is gated on the selected index. Several tabs open a
            WebSocket or start polling the moment they mount.

            Domains only make sense for `web` apps (nginx vhost + TLS) — `tcp`/
            `internal` apps have no domain to attach, so the tab is omitted
            rather than shown empty/disabled. Since tabs are matched by
            position, this is built from an array instead of a fixed JSX list. */}
        {(() => {
          const isWeb = !app.exposeMode || app.exposeMode === "web";
          const tabs: { label: string; content: React.ReactNode }[] = [
            { label: "Overview", content: <OverviewTab app={app} /> },
            {
              label: "Deployments",
              content: <DeploymentsTab appId={appId} />,
            },
            { label: "Environment", content: <EnvsTab appId={appId} /> },
            ...(isWeb
              ? [{ label: "Domains", content: <DomainsTab appId={appId} /> }]
              : []),
            { label: "Logs", content: <LogsTab appId={appId} /> },
            { label: "Console", content: <ConsoleTab appId={appId} /> },
            { label: "Metrics", content: <MetricsTab appId={appId} /> },
            { label: "Storage", content: <StorageTab appId={appId} /> },
            {
              label: "Settings",
              content: <SettingsTab app={app} onSaved={mutate} />,
            },
          ];
          return (
            <Tabs
              selectedIndex={Math.min(tabIndex, tabs.length - 1)}
              onChange={({ selectedIndex }) => setTabIndex(selectedIndex)}
            >
              <TabList aria-label="App sections" contained>
                {tabs.map((t) => (
                  <Tab key={t.label}>{t.label}</Tab>
                ))}
              </TabList>
              <TabPanels>
                {tabs.map((t, i) => (
                  <TabPanel key={t.label}>
                    {tabIndex === i && t.content}
                  </TabPanel>
                ))}
              </TabPanels>
            </Tabs>
          );
        })()}
      </div>
    </Page>
  );
}

export function StatCard({
  label,
  value,
}: {
  label: string;
  value: React.ReactNode;
}) {
  return (
    <Tile>
      <p className="gisila-app__label">{label}</p>
      <p className="gisila-app__stat">{value}</p>
    </Tile>
  );
}
