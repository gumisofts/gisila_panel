"use client";

import { useState, type ComponentProps, type ElementType } from "react";
import RouterLink from "@/compat/link";
import useSWR, { mutate } from "swr";
import {
  Add,
  CheckmarkOutline,
  ChevronRight,
  ServerProxy,
  Sprout,
  Star,
  WarningAlt,
} from "@carbon/icons-react";
import {
  Button,
  ClickableTile,
  Column,
  Grid,
  InlineLoading,
  InlineNotification,
  Modal,
  Select,
  SelectItem,
  SkeletonText,
  Stack,
  Tag,
  TextInput,
  Tile,
} from "@carbon/react";
import { api, fetcher } from "@/lib/api";
import { usePermissions } from "@/lib/permissions";
import type { ListResponse, MongoInstance, MongoInstanceStatus } from "@/lib/types";
import "../_databases.scss";

const SUPPORTED_VERSIONS = ["6.0", "7.0", "8.0"] as const;

const DEFAULT_PORTS: Record<string, number> = {
  "6.0": 27017, "7.0": 27018, "8.0": 27019,
};

type TagType = "red" | "green" | "blue" | "gray" | "cool-gray" | "warm-gray";

const STATUS_CONFIG: Record<
  MongoInstanceStatus,
  { icon?: ElementType; label: string; type: TagType }
> = {
  running:      { icon: CheckmarkOutline, label: "Running",    type: "green" },
  stopped:      { icon: WarningAlt,       label: "Stopped",    type: "gray" },
  failed:       { icon: WarningAlt,       label: "Failed",     type: "red" },
  pending:      {                         label: "Pending",    type: "blue" },
  installing:   {                         label: "Installing", type: "blue" },
  uninstalling: {                         label: "Removing",   type: "warm-gray" },
};

// See the note in postgres-instances.tsx: ClickableTile passes unknown props to
// its polymorphic internal Link, but does not type `as`.
const RouterTile = ClickableTile as React.ComponentType<
  ComponentProps<typeof ClickableTile> & { as?: ElementType }
>;

export function MongoInstances() {
  const { data, isLoading } = useSWR<ListResponse<MongoInstance>>(
    "/mongo/",
    fetcher,
    { refreshInterval: 5000 }
  );

  const { isSuperuser } = usePermissions();
  const [showInstall, setShowInstall] = useState(false);
  const [version, setVersion]         = useState<string>("7.0");
  const [displayName, setDisplayName] = useState("");
  const [port, setPort]               = useState<string>("");
  const [installing, setInstalling]   = useState(false);
  const [installError, setInstallError] = useState("");

  async function handleInstall() {
    setInstallError("");
    setInstalling(true);
    try {
      await api("/mongo/", {
        method: "POST",
        body: JSON.stringify({
          version,
          displayName: displayName || `MongoDB ${version}`,
          port: port ? Number(port) : DEFAULT_PORTS[version] ?? undefined,
        }),
      });
      mutate("/mongo/");
      setShowInstall(false);
      setDisplayName("");
      setPort("");
    } catch (e: unknown) {
      setInstallError(e instanceof Error ? e.message : "Installation failed.");
    } finally {
      setInstalling(false);
    }
  }

  const instances = data?.results ?? [];

  return (
    <Stack gap={6}>
      <div className="gisila-db__toolbar">
        <p className="gisila-db__note">
          NoSQL document database. Each version runs on its own port with authentication enabled.
        </p>
        {isSuperuser && (
          <Button size="sm" renderIcon={Add} onClick={() => setShowInstall(true)}>
            Install version
          </Button>
        )}
      </div>

      {isLoading ? (
        <SkeletonText paragraph lineCount={3} />
      ) : instances.length === 0 ? (
        <Tile>
          <div className="gisila-db__empty">
            <Sprout size={32} className="gisila-db__empty-icon" />
            <div>
              <p className="gisila-db__empty-title">No MongoDB instances yet</p>
              <p className="gisila-db__note">Install a version to get started.</p>
            </div>
            {isSuperuser && (
              <Button size="sm" renderIcon={Add} onClick={() => setShowInstall(true)}>
                Install version
              </Button>
            )}
          </div>
        </Tile>
      ) : (
        <Grid condensed className="gisila-db__list">
          {instances.map((inst) => {
            const sc = STATUS_CONFIG[inst.status] ?? STATUS_CONFIG.stopped;
            return (
              <Column key={inst.id} sm={4} md={8} lg={16}>
                <RouterTile
                  as={RouterLink}
                  href={`/databases/mongo/${inst.id}`}
                  renderIcon={ChevronRight}
                >
                  <div className="gisila-db__tile">
                    <span className="gisila-status-icon gisila-status-icon--success">
                      <Sprout size={20} />
                    </span>

                    <div className="gisila-db__tile-main">
                      <div className="gisila-db__tags">
                        <span className="gisila-db__tile-name">
                          {inst.displayName}
                        </span>
                        {inst.isDefault && (
                          <Tag type="blue" size="sm" renderIcon={Star}>
                            Default
                          </Tag>
                        )}
                      </div>
                      <p className="gisila-db__tile-meta">
                        MongoDB {inst.version} · port {inst.port}
                        {inst.dataDirectory ? ` · ${inst.dataDirectory}` : ""}
                      </p>
                    </div>

                    <Tag type={sc.type} renderIcon={sc.icon}>
                      {sc.label}
                    </Tag>
                  </div>
                </RouterTile>
              </Column>
            );
          })}
        </Grid>
      )}

      <Tile>
        <Stack gap={4}>
          <h3 className="gisila-db__tile-name gisila-db__icon-title">
            <ServerProxy size={16} />
            Available versions
          </h3>
          <div className="gisila-db__versions">
            {SUPPORTED_VERSIONS.map((v) => {
              const installed = instances.some((i) => i.version === v);
              return (
                <Tag
                  key={v}
                  type={installed ? "green" : "gray"}
                  renderIcon={installed ? CheckmarkOutline : Sprout}
                >
                  MongoDB {v}
                </Tag>
              );
            })}
          </div>
        </Stack>
      </Tile>

      <Modal
        open={showInstall}
        onRequestClose={() => setShowInstall(false)}
        onRequestSubmit={handleInstall}
        modalHeading="Install MongoDB"
        primaryButtonText="Install"
        primaryButtonDisabled={installing}
        secondaryButtonText="Cancel"
        size="sm"
      >
        <Stack gap={5}>
          <Select
            id="mongo-install-version"
            labelText="Version"
            value={version}
            onChange={(e) => {
              const v = e.target.value;
              setVersion(v);
              setPort(String(DEFAULT_PORTS[v] ?? ""));
            }}
          >
            {SUPPORTED_VERSIONS.map((v) => (
              <SelectItem key={v} value={v} text={`MongoDB ${v}`} />
            ))}
          </Select>

          <TextInput
            id="mongo-install-name"
            labelText="Display name"
            placeholder={`MongoDB ${version}`}
            value={displayName}
            onChange={(e) => setDisplayName(e.target.value)}
          />

          <TextInput
            id="mongo-install-port"
            type="number"
            labelText="Port"
            helperText="Each version must use a unique port. Default shown above."
            placeholder={String(DEFAULT_PORTS[version] ?? 27017)}
            value={port}
            onChange={(e) => setPort(e.target.value)}
          />

          {installing && <InlineLoading description="Installing…" />}

          {installError && (
            <InlineNotification
              kind="error"
              lowContrast
              hideCloseButton
              title={installError}
            />
          )}
        </Stack>
      </Modal>
    </Stack>
  );
}
