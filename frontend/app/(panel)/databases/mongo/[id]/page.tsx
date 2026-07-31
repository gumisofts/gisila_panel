"use client";

import { useState, type ElementType } from "react";
import RouterLink from "@/compat/link";
import { useParams, useRouter } from "@/compat/navigation";
import useSWR, { mutate } from "swr";
import {
  Add,
  CheckmarkOutline,
  Download,
  Earth,
  Password,
  PlayFilled,
  Sprout,
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
import { MongoMetricsPanel } from "./_panels/metrics-panel";
import { ConfigPanel } from "../../[id]/_panels/config-panel";
import { BackupsDialog } from "../../[id]/_panels/backups-panel";
import type {
  MongoInstance,
  MongoDatabase,
  ListResponse,
  MongoInstanceStatus,
  MongoDatabaseStatus,
} from "@/lib/types";
import "../../_databases.scss";

type TagType = "red" | "green" | "blue" | "gray" | "cool-gray" | "warm-gray";

const INST_STATUS: Record<
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

const DB_STATUS_TAG: Record<MongoDatabaseStatus, { label: string; type: TagType }> = {
  pending: { label: "Pending", type: "blue" },
  active:  { label: "Active",  type: "green" },
  failed:  { label: "Failed",  type: "red" },
  dropped: { label: "Dropped", type: "gray" },
};

// MongoDB built-in roles offered when creating/editing a user. Mirrors the
// backend allowlist (kMongoRoles). `danger` flags instance-wide privileges.
const MONGO_ROLES: { key: string; label: string; hint: string; danger?: boolean }[] = [
  { key: "read",                 label: "Read",                  hint: "Read-only access to this database." },
  { key: "readWrite",            label: "Read / write",          hint: "Read and write this database." },
  { key: "dbAdmin",              label: "DB admin",              hint: "Indexes, stats, schema admin on this database." },
  { key: "dbOwner",              label: "DB owner",              hint: "Full control of this database." },
  { key: "readAnyDatabase",      label: "Read any database",     hint: "Read every database on the server.", danger: true },
  { key: "readWriteAnyDatabase", label: "Read/write any database", hint: "Read/write every database.", danger: true },
  { key: "dbAdminAnyDatabase",   label: "DB admin any database", hint: "Administer every database.", danger: true },
  { key: "clusterMonitor",       label: "Cluster monitor",       hint: "Read server-wide monitoring data.", danger: true },
];

/// `idPrefix` keeps the input ids unique — the create and edit dialogs both
/// stay mounted at the same time.
function RoleToggles({
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
      {MONGO_ROLES.map((a) => (
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

function PublicAccessCard({
  instance,
  instKey,
}: {
  instance: MongoInstance;
  instKey: string;
}) {
  const [domain, setDomain] = useState(instance.publicDomain ?? "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  const pending = instance.isPublic && !instance.publicDomain;

  async function save(isPublic: boolean) {
    setError("");
    if (isPublic && !domain.trim()) {
      setError("Enter a domain, e.g. mongo.example.com");
      return;
    }
    setBusy(true);
    try {
      await api(`/mongo/${instance.id}/expose`, {
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
              (connect with <span className="gisila-db__mono">tls=true</span>).
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
              id="mongo-domain"
              labelText="Domain"
              placeholder="mongo.example.com"
              value={domain}
              onChange={(e) => setDomain(e.target.value)}
            />
            <Stack gap={3}>
              <p className="gisila-db__hint">
                Opens the server to the internet over TLS: obtains a Let&apos;s
                Encrypt certificate for the domain, enables TLS, and listens on
                all interfaces at{" "}
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

export default function MongoInstancePage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();

  const instKey = `/mongo/${id}`;
  const dbsKey = `/mongo/${id}/dbs`;

  const { data: instance, isLoading: instLoading } =
    useSWR<MongoInstance>(instKey, fetcher, { refreshInterval: 4000 });

  const { data: dbsData } =
    useSWR<ListResponse<MongoDatabase>>(dbsKey, fetcher, { refreshInterval: 4000 });

  const { isSuperuser } = usePermissions();
  const [busy, setBusy] = useState<string | null>(null);
  const [showCreate, setShowCreate]   = useState(false);
  const [newDb, setNewDb]             = useState("");
  const [newUser, setNewUser]         = useState("");
  const [newPass, setNewPass]         = useState("");
  const [newRoles, setNewRoles]       = useState<string[]>(["readWrite"]);
  const [creating, setCreating]       = useState(false);
  const [createError, setCreateError] = useState("");
  const [justCreated, setJustCreated] = useState<MongoDatabase | null>(null);
  const [backupsDb, setBackupsDb] = useState<MongoDatabase | null>(null);
  const [permsDb, setPermsDb]       = useState<MongoDatabase | null>(null);
  const [permsRoles, setPermsRoles] = useState<string[]>([]);
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
      const result: MongoDatabase = await api(`/mongo/${id}/dbs`, {
        method: "POST",
        body: JSON.stringify({
          dbName: newDb,
          userName: newUser,
          password: newPass || undefined,
          roles: newRoles,
        }),
      });
      mutate(dbsKey);
      setShowCreate(false);
      setNewDb(""); setNewUser(""); setNewPass(""); setNewRoles(["readWrite"]);
      setJustCreated(result);
    } catch (e: unknown) {
      setCreateError(e instanceof Error ? e.message : "Failed to create database.");
    } finally {
      setCreating(false);
    }
  }

  async function showConnection(db: MongoDatabase) {
    try {
      const full = await api<MongoDatabase>(`/mongo/${id}/dbs/${db.id}`);
      setJustCreated(full);
    } catch {
      setJustCreated(db);
    }
  }

  async function handleDrop(dbId: number) {
    if (!confirm("Drop this database and its user? This cannot be undone.")) return;
    await action(`/mongo/${id}/dbs/${dbId}`, "DELETE", dbsKey);
    mutate(dbsKey);
  }

  function openPerms(db: MongoDatabase) {
    setPermsError("");
    setPermsRoles(db.roles ?? []);
    setPermsDb(db);
  }

  async function handleUpdatePerms() {
    if (!permsDb) return;
    setPermsError("");
    setPermsBusy(true);
    try {
      await api(`/mongo/${id}/dbs/${permsDb.id}/roles`, {
        method: "PUT",
        body: JSON.stringify({ roles: permsRoles }),
      });
      mutate(dbsKey);
      setPermsDb(null);
    } catch (e: unknown) {
      setPermsError(e instanceof Error ? e.message : "Failed to update roles.");
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
            <span className="gisila-status-icon gisila-status-icon--success">
              <Sprout size={20} />
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
          </span>
        }
        description={`MongoDB ${instance.version} · port ${instance.port}`}
        actions={
          <>
            {isSuperuser && !instance.isDefault && isRunning && (
              <Button
                kind="tertiary"
                size="sm"
                renderIcon={Star}
                onClick={() => action(`/mongo/${id}/set-default`)}
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
                onClick={() => action(`/mongo/${id}/start`)}
                disabled={!!busy}
              >
                Start
              </Button>
            )}
            {isSuperuser && isRunning && (
              <Button
                kind="tertiary"
                size="sm"
                renderIcon={StopFilled}
                onClick={() => action(`/mongo/${id}/stop`)}
                disabled={!!busy}
              >
                Stop
              </Button>
            )}
            {isSuperuser && !instance.isDefault && (
              <Button
                kind="danger--tertiary"
                size="sm"
                renderIcon={TrashCan}
                onClick={async () => {
                  if (!confirm(`Uninstall MongoDB ${instance.version}? All data will be deleted.`)) return;
                  await action(`/mongo/${id}`, "DELETE");
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

      <MongoMetricsPanel id={String(id)} running={isRunning} />

      {isSuperuser && isRunning && (
        <PageSection>
          <PublicAccessCard instance={instance} instKey={instKey} />
        </PageSection>
      )}

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
                    ? "Create a database and user to get started."
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
                  <TableHeader>User</TableHeader>
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
                        <span className="gisila-db__mono">{db.userName}</span>
                        {db.roles?.length > 0 && (
                          <div className="gisila-db__tags">
                            {db.roles.map((a) => (
                              <Tag
                                key={a}
                                size="sm"
                                type={
                                  a.endsWith("AnyDatabase") || a === "clusterMonitor"
                                    ? "red"
                                    : "cool-gray"
                                }
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
                              Roles
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

      <ConfigPanel
        id={String(id)}
        running={isRunning}
        apiBase="/mongo"
        note="Changing these rewrites the mongod config and restarts the server. Leave a field blank to keep the current value."
      />

      {/* Create database dialog */}
      <Modal
        open={showCreate}
        onRequestClose={() => setShowCreate(false)}
        onRequestSubmit={handleCreate}
        modalHeading="Create database"
        primaryButtonText="Create"
        primaryButtonDisabled={creating || !newDb || !newUser}
        secondaryButtonText="Cancel"
        size="sm"
        hasScrollingContent
      >
        <Stack gap={5}>
          <TextInput
            id="mongo-new-db"
            labelText="Database name"
            placeholder="myapp"
            value={newDb}
            onChange={(e) => setNewDb(e.target.value)}
          />
          <TextInput
            id="mongo-new-user"
            labelText="User"
            placeholder="myapp_user"
            value={newUser}
            onChange={(e) => setNewUser(e.target.value)}
          />
          <PasswordInput
            id="mongo-new-pass"
            labelText="Password"
            placeholder="Leave blank to auto-generate"
            value={newPass}
            onChange={(e) => setNewPass(e.target.value)}
          />
          <FormGroup legendText="Roles">
            <Stack gap={4}>
              <RoleToggles
                idPrefix="mongo-new-role"
                value={newRoles}
                onChange={setNewRoles}
                disabled={creating}
              />
              <p className="gisila-db__hint">
                Roles are granted on this database unless they are instance-wide
                (the <span className="gisila-db__mono">*AnyDatabase</span> roles).
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

      {/* Edit roles dialog */}
      <Modal
        open={!!permsDb}
        onRequestClose={() => setPermsDb(null)}
        onRequestSubmit={handleUpdatePerms}
        modalHeading="Roles"
        modalLabel={permsDb?.userName}
        primaryButtonText="Save roles"
        primaryButtonDisabled={permsBusy}
        secondaryButtonText="Cancel"
        size="sm"
        hasScrollingContent
      >
        <Stack gap={5}>
          <RoleToggles
            idPrefix="mongo-perms-role"
            value={permsRoles}
            onChange={setPermsRoles}
            disabled={permsBusy}
          />
          <p className="gisila-db__hint">
            Changes are applied with{" "}
            <span className="gisila-db__mono">updateUser</span>; roles you turn
            off are revoked.
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
                <ConnRow label="Auth DB"  value={justCreated.connection.authSource} />
              </StructuredListBody>
            </StructuredListWrapper>
            <div>
              <p className="gisila-db__hint">
                Connection URI{justCreated.connection.publicUrl ? " (local)" : ""}
              </p>
              <CodeSnippet type="single" feedbackTimeout={1500}>
                {justCreated.connection.url}
              </CodeSnippet>
            </div>
            {justCreated.connection.publicUrl && (
              <div>
                <p className="gisila-db__hint">Public URI (TLS)</p>
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

      <BackupsDialog
        instanceId={String(id)}
        db={backupsDb}
        onClose={() => setBackupsDb(null)}
        apiBase="/mongo"
        scopes={["full"]}
        uploadAccept=".archive,.gz,.archive.gz"
        uploadNote="Upload a mongodump .archive (optionally gzipped) to restore into this database. Restoring may overwrite existing data."
      />
    </Page>
  );
}
