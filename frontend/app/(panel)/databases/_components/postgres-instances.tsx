"use client";

import { useState, type ComponentProps, type ElementType } from "react";
import RouterLink from "@/compat/link";
import useSWR, { mutate } from "swr";
import {
  Add,
  CheckmarkOutline,
  ChevronRight,
  DataBase,
  ServerProxy,
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
import type { ListResponse, PostgresInstance, PgInstanceStatus } from "@/lib/types";
import "../_databases.scss";

const SUPPORTED_VERSIONS = [14, 15, 16, 17, 18] as const;

const DEFAULT_PORTS: Record<number, number> = {
  14: 5414, 15: 5415, 16: 5416, 17: 5417, 18: 5418,
};

type TagType = "red" | "green" | "blue" | "gray" | "cool-gray" | "warm-gray";

const STATUS_CONFIG: Record<
  PgInstanceStatus,
  { icon?: ElementType; label: string; type: TagType }
> = {
  running:      { icon: CheckmarkOutline, label: "Running",    type: "green" },
  stopped:      { icon: WarningAlt,       label: "Stopped",    type: "gray" },
  failed:       { icon: WarningAlt,       label: "Failed",     type: "red" },
  pending:      {                         label: "Pending",    type: "blue" },
  installing:   {                         label: "Installing", type: "blue" },
  uninstalling: {                         label: "Removing",   type: "warm-gray" },
};

// Carbon forwards unrecognised props from ClickableTile straight to its
// internal Link, which is polymorphic — but ClickableTile's own prop types stop
// at the anchor, so `as` has to be reintroduced here to keep client-side
// routing instead of a full page load.
const RouterTile = ClickableTile as React.ComponentType<
  ComponentProps<typeof ClickableTile> & { as?: ElementType }
>;

export function PostgresInstances() {
  const { data, isLoading } = useSWR<ListResponse<PostgresInstance>>(
    "/databases/",
    fetcher,
    { refreshInterval: 5000 }
  );

  const { isSuperuser } = usePermissions();
  const [showInstall, setShowInstall] = useState(false);
  const [version, setVersion]         = useState<string>("16");
  const [displayName, setDisplayName] = useState("");
  const [port, setPort]               = useState<string>("");
  const [installing, setInstalling]   = useState(false);
  const [installError, setInstallError] = useState("");

  async function handleInstall() {
    setInstallError("");
    setInstalling(true);
    try {
      await api("/databases/", {
        method: "POST",
        body: JSON.stringify({
          version: Number(version),
          displayName: displayName || `PostgreSQL ${version}`,
          port: port ? Number(port) : DEFAULT_PORTS[Number(version)] ?? undefined,
        }),
      });
      mutate("/databases/");
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
          Each version runs on its own port. Multiple versions can run side-by-side.
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
            <DataBase size={32} className="gisila-db__empty-icon" />
            <div>
              <p className="gisila-db__empty-title">No PostgreSQL instances yet</p>
              <p className="gisila-db__note">
                Install a version to get started. Multiple versions can run side-by-side.
              </p>
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
                  href={`/databases/${inst.id}`}
                  renderIcon={ChevronRight}
                >
                  <div className="gisila-db__tile">
                    <span className="gisila-status-icon gisila-status-icon--brand">
                      <DataBase size={20} />
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
                        {inst.isSystem && (
                          <Tag type="cool-gray" size="sm" renderIcon={ServerProxy}>
                            System
                          </Tag>
                        )}
                      </div>
                      <p className="gisila-db__tile-meta">
                        PostgreSQL {inst.version} · port {inst.port}
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
                  renderIcon={installed ? CheckmarkOutline : DataBase}
                >
                  PostgreSQL {v}
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
        modalHeading="Install PostgreSQL"
        primaryButtonText="Install"
        primaryButtonDisabled={installing}
        secondaryButtonText="Cancel"
        size="sm"
      >
        <Stack gap={5}>
          <Select
            id="pg-install-version"
            labelText="Version"
            value={version}
            onChange={(e) => {
              const v = e.target.value;
              setVersion(v);
              setPort(String(DEFAULT_PORTS[Number(v)] ?? ""));
            }}
          >
            {SUPPORTED_VERSIONS.map((v) => (
              <SelectItem key={v} value={String(v)} text={`PostgreSQL ${v}`} />
            ))}
          </Select>

          <TextInput
            id="pg-install-name"
            labelText="Display name"
            placeholder={`PostgreSQL ${version}`}
            value={displayName}
            onChange={(e) => setDisplayName(e.target.value)}
          />

          <TextInput
            id="pg-install-port"
            type="number"
            labelText="Port"
            helperText="Each version must use a unique port. Default shown above."
            placeholder={String(DEFAULT_PORTS[Number(version)] ?? 5432)}
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
