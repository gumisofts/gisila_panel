"use client";

import { useState, type ElementType } from "react";
import RouterLink from "@/compat/link";
import { useParams, useRouter } from "@/compat/navigation";
import useSWR, { mutate } from "swr";
import {
  Add,
  CheckmarkOutline,
  DataBase,
  Download,
  Earth,
  Password,
  PlayFilled,
  ServerProxy,
  Star,
  StopFilled,
  Table as TableIcon,
  TrashCan,
  View,
  ViewOff,
  WarningAlt,
} from "@carbon/icons-react";
import {
  Breadcrumb,
  BreadcrumbItem,
  Button,
  Checkbox,
  CodeSnippet,
  CopyButton,
  FormGroup,
  InlineLoading,
  InlineNotification,
  Link as CarbonLink,
  Modal,
  PasswordInput,
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
import { MetricsPanel } from "./_panels/metrics-panel";
import { ConfigPanel } from "./_panels/config-panel";
import { BackupsDialog } from "./_panels/backups-panel";
import type {
  PostgresInstance,
  PostgresDatabase,
  ListResponse,
  PgInstanceStatus,
  PgDatabaseStatus,
} from "@/lib/types";
import "../_databases.scss";

// ── Status helpers ─────────────────────────────────────────────────────────────

type TagType = "red" | "green" | "blue" | "gray" | "cool-gray" | "warm-gray";

const INST_STATUS: Record<
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

const DB_STATUS_TAG: Record<PgDatabaseStatus, { label: string; type: TagType }> = {
  pending: { label: "Pending", type: "blue" },
  active:  { label: "Active",  type: "green" },
  failed:  { label: "Failed",  type: "red" },
  dropped: { label: "Dropped", type: "gray" },
};

// ── Role attributes (database-user permissions) ──────────────────────────────
// Mirrors the backend whitelist (kRoleAttributes). LOGIN is always granted and
// is not shown here. `danger` flags privileges that are risky on a shared host.
const ROLE_ATTRS: { key: string; label: string; hint: string; danger?: boolean }[] = [
  { key: "CREATEDB",    label: "Create databases", hint: "Required by Prisma migrate (shadow database)." },
  { key: "CREATEROLE",  label: "Create roles",     hint: "Create and manage other roles." },
  { key: "REPLICATION", label: "Replication",      hint: "Start replication / use replication slots." },
  { key: "BYPASSRLS",   label: "Bypass RLS",       hint: "Skip row-level security policies." },
  { key: "SUPERUSER",   label: "Superuser",        hint: "Full control of the entire instance.", danger: true },
];

/// Checkbox list for selecting role attributes. `value`/`onChange` work on an
/// uppercase attribute-key array. `idPrefix` keeps the input ids unique — both
/// dialogs that use this stay mounted at the same time.
function RoleAttrToggles({
  idPrefix,
  value,
  onChange,
  disabled,
}: {
  idPrefix: string;
  value: string[];
  onChange: (next: string[]) => void;
  disabled?: boolean;
}) {
  return (
    <Stack gap={3}>
      {ROLE_ATTRS.map((a) => (
        <Checkbox
          key={a.key}
          id={`${idPrefix}-${a.key}`}
          checked={value.includes(a.key)}
          disabled={disabled}
          onChange={(_evt, { checked }) =>
            onChange(
              checked
                ? [...value, a.key]
                : value.filter((k) => k !== a.key),
            )
          }
          labelText={
            <>
              <span className="gisila-db__role-title">
                <span className="gisila-db__mono">{a.key}</span>
                <span className="gisila-db__note">{a.label}</span>
                {a.danger && <span className="gisila-db__danger">danger</span>}
              </span>
              <span className="gisila-db__role-hint">{a.hint}</span>
            </>
          }
        />
      ))}
    </Stack>
  );
}

// ── Connection string row ──────────────────────────────────────────────────────

function ConnRow({ label, value, secret }: { label: string; value: string; secret?: boolean }) {
  const [show, setShow] = useState(!secret);
  return (
    <StructuredListRow>
      <StructuredListCell noWrap>{label}</StructuredListCell>
      <StructuredListCell className="gisila-db__conn-value">
        <span className="gisila-db__mono">{show ? value : "••••••••"}</span>
      </StructuredListCell>
      <StructuredListCell className="gisila-db__conn-actions">
        {secret && (
          <Button
            kind="ghost"
            size="sm"
            hasIconOnly
            renderIcon={show ? ViewOff : View}
            iconDescription={show ? "Hide" : "Show"}
            onClick={() => setShow((v) => !v)}
          />
        )}
        <CopyButton
          iconDescription={`Copy ${label.toLowerCase()}`}
          feedbackTimeout={1500}
          onClick={() => navigator.clipboard.writeText(value)}
        />
      </StructuredListCell>
    </StructuredListRow>
  );
}

// ── Main page ─────────────────────────────────────────────────────────────────

function PublicAccessCard({
  instance,
  instKey,
}: {
  instance: PostgresInstance;
  instKey: string;
}) {
  const [domain, setDomain] = useState(instance.publicDomain ?? "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  const pending = instance.isPublic && !instance.publicDomain;

  async function save(isPublic: boolean) {
    setError("");
    if (isPublic && !domain.trim()) {
      setError("Enter a domain, e.g. db.example.com");
      return;
    }
    setBusy(true);
    try {
      await api(`/databases/${instance.id}/expose`, {
        method: "POST",
        body: JSON.stringify({ isPublic, domain: domain.trim() }),
      });
      mutate(instKey);
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Failed to update exposure.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <Tile>
      <Stack gap={5}>
        <h3 className="gisila-db__tile-name gisila-db__icon-title">
          <Earth size={16} />
          Public access
          {instance.isPublic ? (
            <Tag as="span" type="purple" size="sm">Public</Tag>
          ) : (
            <Tag as="span" type="cool-gray" size="sm">Private</Tag>
          )}
        </h3>

        {instance.isPublic ? (
          <>
            <p className="gisila-db__note">
              Reachable over TLS at{" "}
              <span className="gisila-db__mono">
                {instance.publicDomain}:{instance.port}
              </span>{" "}
              (connect with <span className="gisila-db__mono">sslmode=verify-full</span>).
            </p>
            <div>
              <Button
                kind="danger--tertiary"
                size="sm"
                disabled={busy}
                onClick={() => save(false)}
              >
                Make private
              </Button>
            </div>
          </>
        ) : (
          <>
            <TextInput
              id="pg-domain"
              labelText="Domain"
              placeholder="db.example.com"
              value={domain}
              onChange={(e) => setDomain(e.target.value)}
            />
            <Stack gap={3}>
              <p className="gisila-db__hint">
                Opens the cluster to the internet over TLS: obtains a Let&apos;s
                Encrypt certificate for the domain, enables SSL, and allows
                SSL-only connections to{" "}
                <span className="gisila-db__mono">{instance.port}</span>.
              </p>
              <p className="gisila-db__hint">
                Point a DNS <span className="gisila-db__mono">A</span> record at this
                server and open port{" "}
                <span className="gisila-db__mono">{instance.port}</span> first. The cert
                needs port 80 reachable.
              </p>
            </Stack>
            <div>
              <Button size="sm" disabled={busy} onClick={() => save(true)}>
                {busy ? "Enabling…" : "Make public"}
              </Button>
            </div>
          </>
        )}

        {pending && (
          <InlineNotification
            kind="warning"
            lowContrast
            hideCloseButton
            title="Exposure in progress…"
          />
        )}
        {error && (
          <InlineNotification kind="error" lowContrast hideCloseButton title={error} />
        )}
      </Stack>
    </Tile>
  );
}

export default function InstancePage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();

  const instKey = `/databases/${id}`;
  const dbsKey  = `/databases/${id}/dbs`;

  const { data: instance, isLoading: instLoading } =
    useSWR<PostgresInstance>(instKey, fetcher, { refreshInterval: 4000 });

  const { data: dbsData } =
    useSWR<ListResponse<PostgresDatabase>>(dbsKey, fetcher, { refreshInterval: 4000 });

  const { isSuperuser } = usePermissions();
  const [busy, setBusy] = useState<string | null>(null);
  const [showCreate, setShowCreate]   = useState(false);
  const [newDb, setNewDb]             = useState("");
  const [newRole, setNewRole]         = useState("");
  const [newPass, setNewPass]         = useState("");
  const [newExts, setNewExts]         = useState("");
  const [newAttrs, setNewAttrs]       = useState<string[]>([]);
  const [creating, setCreating]       = useState(false);
  const [createError, setCreateError] = useState("");
  const [justCreated, setJustCreated] = useState<PostgresDatabase | null>(null);
  const [backupsDb, setBackupsDb] = useState<PostgresDatabase | null>(null);
  // Edit-permissions dialog state.
  const [permsDb, setPermsDb]       = useState<PostgresDatabase | null>(null);
  const [permsAttrs, setPermsAttrs] = useState<string[]>([]);
  const [permsBusy, setPermsBusy]   = useState(false);
  const [permsError, setPermsError] = useState("");

  async function action(path: string, method = "POST", key?: string) {
    setBusy(path);
    try {
      await api(path, { method });
      mutate(instKey);
      if (key) mutate(key);
    } finally {
      setBusy(null);
    }
  }

  async function handleCreate() {
    setCreateError("");
    setCreating(true);
    try {
      const result: PostgresDatabase = await api(`/databases/${id}/dbs`, {
        method: "POST",
        body: JSON.stringify({
          dbName:  newDb,
          roleName: newRole,
          password: newPass || undefined,
          extensions: newExts
            ? newExts.split(",").map((e) => e.trim()).filter(Boolean)
            : [],
          roleAttributes: newAttrs,
        }),
      });
      mutate(dbsKey);
      setShowCreate(false);
      setNewDb(""); setNewRole(""); setNewPass(""); setNewExts(""); setNewAttrs([]);
      setJustCreated(result);
    } catch (e: unknown) {
      setCreateError(e instanceof Error ? e.message : "Failed to create database.");
    } finally {
      setCreating(false);
    }
  }

  async function showConnection(db: PostgresDatabase) {
    // The list endpoint omits connection info (the plain-text password is only
    // returned for a single database), so fetch the single-database view, which
    // includes it. Fall back to the row we already have on error.
    try {
      const full = await api<PostgresDatabase>(`/databases/${id}/dbs/${db.id}`);
      setJustCreated(full);
    } catch {
      setJustCreated(db);
    }
  }

  async function handleDrop(dbId: number) {
    if (!confirm("Drop this database and its role? This cannot be undone.")) return;
    await action(`/databases/${id}/dbs/${dbId}`, "DELETE", dbsKey);
    mutate(dbsKey);
  }

  function openPerms(db: PostgresDatabase) {
    setPermsError("");
    setPermsAttrs(db.roleAttributes ?? []);
    setPermsDb(db);
  }

  async function handleUpdatePerms() {
    if (!permsDb) return;
    setPermsError("");
    setPermsBusy(true);
    try {
      await api(`/databases/${id}/dbs/${permsDb.id}/role`, {
        method: "PUT",
        body: JSON.stringify({ roleAttributes: permsAttrs }),
      });
      mutate(dbsKey);
      setPermsDb(null);
    } catch (e: unknown) {
      setPermsError(e instanceof Error ? e.message : "Failed to update permissions.");
    } finally {
      setPermsBusy(false);
    }
  }

  if (instLoading || !instance) {
    return (
      <Page>
        <InlineLoading description="Loading…" />
      </Page>
    );
  }

  const sc = INST_STATUS[instance.status] ?? INST_STATUS.stopped;
  const databases = dbsData?.results ?? [];
  const isRunning = instance.status === "running";

  return (
    <Page>
      <Breadcrumb noTrailingSlash>
        <BreadcrumbItem>
          <CarbonLink as={RouterLink} href="/databases">
            All instances
          </CarbonLink>
        </BreadcrumbItem>
        <BreadcrumbItem isCurrentPage>{instance.displayName}</BreadcrumbItem>
      </Breadcrumb>

      <PageHeader
        title={
          <span className="gisila-db__tags">
            <span className="gisila-status-icon gisila-status-icon--brand">
              <DataBase size={20} />
            </span>
            {instance.displayName}
            <Tag as="span" type={sc.type} renderIcon={sc.icon}>
              {sc.label}
            </Tag>
            {instance.isDefault && (
              <Tag as="span" type="blue" size="sm" renderIcon={Star}>
                Default
              </Tag>
            )}
            {instance.isSystem && (
              <Tag as="span" type="cool-gray" size="sm" renderIcon={ServerProxy}>
                System
              </Tag>
            )}
          </span>
        }
        description={
          <>
            PostgreSQL {instance.version} · port {instance.port}
            {instance.isSystem && (
              <span className="gisila-db__subnote">
                This is the database the panel runs on. Its port and version are
                fixed and it cannot be stopped or removed.
              </span>
            )}
          </>
        }
        actions={
          <>
            {isSuperuser && !instance.isDefault && isRunning && (
              <Button
                kind="tertiary"
                size="sm"
                renderIcon={Star}
                onClick={() => action(`/databases/${id}/set-default`)}
                disabled={!!busy}
              >
                Set default
              </Button>
            )}
            {isSuperuser && instance.status === "stopped" && (
              <Button
                kind="tertiary"
                size="sm"
                renderIcon={PlayFilled}
                onClick={() => action(`/databases/${id}/start`)}
                disabled={!!busy}
              >
                Start
              </Button>
            )}
            {isSuperuser && isRunning && !instance.isSystem && (
              <Button
                kind="tertiary"
                size="sm"
                renderIcon={StopFilled}
                onClick={() => action(`/databases/${id}/stop`)}
                disabled={!!busy}
              >
                Stop
              </Button>
            )}
            {isSuperuser && !instance.isDefault && !instance.isSystem && (
              <Button
                kind="danger--tertiary"
                size="sm"
                renderIcon={TrashCan}
                onClick={async () => {
                  if (!confirm(`Uninstall PostgreSQL ${instance.version}? All data will be deleted.`)) return;
                  await action(`/databases/${id}`, "DELETE");
                  router.push("/databases");
                }}
                disabled={!!busy}
              >
                Uninstall
              </Button>
            )}
          </>
        }
      />

      {instance.errorMessage && (
        <InlineNotification
          kind="error"
          lowContrast
          hideCloseButton
          title={instance.errorMessage}
        />
      )}

      {/* Metrics */}
      <MetricsPanel id={String(id)} running={isRunning} />

      {/* Public access (not for the panel's own system cluster) */}
      {isSuperuser && isRunning && !instance.isSystem && (
        <PageSection>
          <PublicAccessCard instance={instance} instKey={instKey} />
        </PageSection>
      )}

      {/* Databases section */}
      <PageSection
        title={
          <span className="gisila-db__icon-title">
            <TableIcon size={16} />
            Databases &amp; users
          </span>
        }
        actions={
          isRunning && isSuperuser && (
            <Button
              size="sm"
              kind="tertiary"
              renderIcon={Add}
              onClick={() => setShowCreate(true)}
            >
              Create database
            </Button>
          )
        }
      >
        {databases.length === 0 ? (
          <Tile>
            <div className="gisila-db__empty">
              <TableIcon size={32} className="gisila-db__empty-icon" />
              <div>
                <p className="gisila-db__empty-title">No databases yet</p>
                <p className="gisila-db__note">
                  {isRunning
                    ? "Create a database and role to get started."
                    : "Start the instance first to create databases."}
                </p>
              </div>
              {isRunning && (
                <Button size="sm" renderIcon={Add} onClick={() => setShowCreate(true)}>
                  Create database
                </Button>
              )}
            </div>
          </Tile>
        ) : (
          <TableContainer>
            <Table size="lg">
              <TableHead>
                <TableRow>
                  <TableHeader>Database</TableHeader>
                  <TableHeader>Role</TableHeader>
                  <TableHeader>Status</TableHeader>
                  <TableHeader>Actions</TableHeader>
                </TableRow>
              </TableHead>
              <TableBody>
                {databases.map((db) => {
                  const dbSc = DB_STATUS_TAG[db.status] ?? DB_STATUS_TAG.active;
                  return (
                    <TableRow key={db.id}>
                      <TableCell>
                        <span className="gisila-db__mono">{db.dbName}</span>
                        {db.errorMessage && (
                          <span className="gisila-db__suberror">
                            {db.errorMessage}
                          </span>
                        )}
                      </TableCell>
                      <TableCell>
                        <span className="gisila-db__mono">{db.roleName}</span>
                        {db.extensions.length > 0 && (
                          <span className="gisila-db__subnote">
                            Extensions: {db.extensions.join(", ")}
                          </span>
                        )}
                        {db.roleAttributes?.length > 0 && (
                          <div className="gisila-db__tags">
                            {db.roleAttributes.map((a) => (
                              <Tag
                                key={a}
                                size="sm"
                                type={a === "SUPERUSER" ? "red" : "cool-gray"}
                              >
                                {a}
                              </Tag>
                            ))}
                          </div>
                        )}
                      </TableCell>
                      <TableCell>
                        <Tag type={dbSc.type} size="sm">{dbSc.label}</Tag>
                      </TableCell>
                      <TableCell>
                        <div className="gisila-db__row-actions">
                          <Button kind="ghost" size="sm" onClick={() => showConnection(db)}>
                            Connection info
                          </Button>
                          {db.status === "active" && isSuperuser && (
                            <Button
                              kind="ghost"
                              size="sm"
                              renderIcon={Password}
                              onClick={() => openPerms(db)}
                            >
                              Permissions
                            </Button>
                          )}
                          {db.status === "active" && isSuperuser && (
                            <Button
                              kind="ghost"
                              size="sm"
                              renderIcon={Download}
                              onClick={() => setBackupsDb(db)}
                            >
                              Backups
                            </Button>
                          )}
                          {isSuperuser && (
                            <Button
                              kind="danger--ghost"
                              size="sm"
                              hasIconOnly
                              renderIcon={TrashCan}
                              iconDescription={`Drop ${db.dbName}`}
                              onClick={() => handleDrop(db.id)}
                              disabled={!!busy}
                            />
                          )}
                        </div>
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </TableContainer>
        )}
      </PageSection>

      {/* Configuration */}
      <ConfigPanel id={String(id)} running={isRunning} />

      {/* Create database dialog */}
      <Modal
        open={showCreate}
        onRequestClose={() => setShowCreate(false)}
        onRequestSubmit={handleCreate}
        modalHeading="Create database"
        primaryButtonText="Create"
        primaryButtonDisabled={creating || !newDb || !newRole}
        secondaryButtonText="Cancel"
        size="sm"
        hasScrollingContent
      >
        <Stack gap={5}>
          <TextInput
            id="pg-new-db"
            labelText="Database name"
            placeholder="myapp_production"
            value={newDb}
            onChange={(e) => setNewDb(e.target.value)}
          />
          <TextInput
            id="pg-new-role"
            labelText="Role / user"
            placeholder="myapp_user"
            value={newRole}
            onChange={(e) => setNewRole(e.target.value)}
          />
          <PasswordInput
            id="pg-new-pass"
            labelText="Password"
            placeholder="Leave blank to auto-generate"
            value={newPass}
            onChange={(e) => setNewPass(e.target.value)}
          />
          <TextInput
            id="pg-new-exts"
            labelText="Extensions"
            helperText="Comma-separated extension names. Optional."
            placeholder="uuid-ossp, pg_trgm, postgis"
            value={newExts}
            onChange={(e) => setNewExts(e.target.value)}
          />
          <FormGroup legendText="Role permissions">
            <Stack gap={4}>
              <RoleAttrToggles
                idPrefix="pg-new-attr"
                value={newAttrs}
                onChange={setNewAttrs}
                disabled={creating}
              />
              <p className="gisila-db__hint">
                The role can always log in and owns its database. Grant extra
                attributes only as needed — e.g.{" "}
                <span className="gisila-db__mono">CREATEDB</span> for Prisma
                migrations.
              </p>
            </Stack>
          </FormGroup>
          {creating && <InlineLoading description="Creating…" />}
          {createError && (
            <InlineNotification
              kind="error"
              lowContrast
              hideCloseButton
              title={createError}
            />
          )}
        </Stack>
      </Modal>

      {/* Edit role permissions dialog */}
      <Modal
        open={!!permsDb}
        onRequestClose={() => setPermsDb(null)}
        onRequestSubmit={handleUpdatePerms}
        modalHeading="Role permissions"
        modalLabel={permsDb?.roleName}
        primaryButtonText="Save permissions"
        primaryButtonDisabled={permsBusy}
        secondaryButtonText="Cancel"
        size="sm"
      >
        <Stack gap={5}>
          <RoleAttrToggles
            idPrefix="pg-perms-attr"
            value={permsAttrs}
            onChange={setPermsAttrs}
            disabled={permsBusy}
          />
          <p className="gisila-db__hint">
            Changes are applied with{" "}
            <span className="gisila-db__mono">ALTER ROLE</span>; attributes you
            turn off are revoked. The role keeps{" "}
            <span className="gisila-db__mono">LOGIN</span> and ownership of its
            database.
          </p>
          {permsBusy && <InlineLoading description="Saving…" />}
          {permsError && (
            <InlineNotification
              kind="error"
              lowContrast
              hideCloseButton
              title={permsError}
            />
          )}
        </Stack>
      </Modal>

      {/* Connection info dialog */}
      <Modal
        open={!!justCreated}
        onRequestClose={() => setJustCreated(null)}
        onRequestSubmit={() => setJustCreated(null)}
        modalHeading={`Connection info — ${justCreated?.dbName ?? ""}`}
        primaryButtonText="Done"
        size="md"
      >
        {justCreated?.connection ? (
          <Stack gap={5}>
            <InlineNotification
              kind="warning"
              lowContrast
              hideCloseButton
              title="Save this password now — it will not be shown again in plain text."
            />
            <StructuredListWrapper aria-label="Connection details" isCondensed>
              <StructuredListBody>
                <ConnRow label="Host"     value={justCreated.connection.host} />
                <ConnRow label="Port"     value={String(justCreated.connection.port)} />
                <ConnRow label="Database" value={justCreated.connection.database} />
                <ConnRow label="Username" value={justCreated.connection.username} />
                <ConnRow label="Password" value={justCreated.connection.password} secret />
              </StructuredListBody>
            </StructuredListWrapper>
            <div>
              <p className="gisila-db__hint">
                Connection URL{justCreated.connection.publicUrl ? " (local)" : ""}
              </p>
              <CodeSnippet type="single" feedbackTimeout={1500}>
                {justCreated.connection.url}
              </CodeSnippet>
            </div>
            {justCreated.connection.publicUrl && (
              <div>
                <p className="gisila-db__hint">Public URL (TLS)</p>
                <CodeSnippet type="single" feedbackTimeout={1500}>
                  {justCreated.connection.publicUrl}
                </CodeSnippet>
              </div>
            )}
          </Stack>
        ) : (
          <p className="gisila-db__note">
            Connection info not available yet — the database is still being
            provisioned.
          </p>
        )}
      </Modal>

      {/* Backups dialog */}
      <BackupsDialog
        instanceId={String(id)}
        db={backupsDb}
        onClose={() => setBackupsDb(null)}
      />
    </Page>
  );
}
