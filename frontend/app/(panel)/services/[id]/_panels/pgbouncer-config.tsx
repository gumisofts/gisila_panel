"use client";

import { useEffect, useMemo, useState } from "react";
import useSWR from "swr";
import { Add, Save, TrashCan, View, ViewOff } from "@carbon/icons-react";
import {
  Button,
  CodeSnippet,
  Form,
  FormGroup,
  InlineLoading,
  NumberInput,
  PasswordInput,
  Select,
  SelectItem,
  Stack,
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
import { PageSection } from "@/components/page";
import { api, fetcher } from "@/lib/api";
import { toast } from "@/lib/toast";
import type {
  ManagedService,
  ServiceDef,
  ConfigField,
  PgbDatabase,
  PgbUser,
  PostgresInstance,
  PostgresDatabase,
  ListResponse,
} from "@/lib/types";
import "../../_services.scss";

// ── Helpers ─────────────────────────────────────────────────────────────────

function parseList<T>(raw: string | undefined): T[] {
  if (!raw) return [];
  try {
    const v = JSON.parse(raw);
    return Array.isArray(v) ? (v as T[]) : [];
  } catch {
    return [];
  }
}

function RequiredLabel({ children }: { children: string }) {
  return (
    <span className="gisila-label">
      {children}
      <span className="gisila-required">*</span>
    </span>
  );
}

// ── Main panel ──────────────────────────────────────────────────────────────

export function PgBouncerConfig({
  svc,
  def,
  onSaved,
}: {
  svc: ManagedService;
  def: ServiceDef;
  onSaved: () => void;
}) {
  const stored: Record<string, string> = useMemo(() => {
    try {
      return JSON.parse(svc.config) as Record<string, string>;
    } catch {
      return {};
    }
  }, [svc.config]);

  const scalarFields = def.configSchema; // databases/users are not in the schema

  const [scalars, setScalars] = useState<Record<string, string>>({});
  const [databases, setDatabases] = useState<PgbDatabase[]>([]);
  const [users, setUsers] = useState<PgbUser[]>([]);
  const [saving, setSaving] = useState(false);
  const [showSecrets, setShowSecrets] = useState(false);

  // Seed all state from the stored config whenever it changes.
  useEffect(() => {
    setScalars(
      Object.fromEntries(
        scalarFields.map((f) => [f.key, stored[f.key] ?? f.default ?? ""]),
      ),
    );
    setDatabases(parseList<PgbDatabase>(stored["databases"]));
    setUsers(parseList<PgbUser>(stored["users"]));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [svc.config]);

  async function save() {
    // Light validation before persisting.
    for (const d of databases) {
      if (!d.name?.trim() || !d.host?.trim() || !d.dbname?.trim()) {
        toast.error("Each database needs a name, host and dbname.");
        return;
      }
    }
    for (const u of users) {
      if (!u.username?.trim()) {
        toast.error("Each user needs a username.");
        return;
      }
    }
    setSaving(true);
    try {
      const config: Record<string, string> = {
        ...scalars,
        databases: JSON.stringify(databases),
        users: JSON.stringify(users),
      };
      await api(`/services/${svc.id}/config`, {
        method: "PUT",
        body: JSON.stringify({ config }),
      });
      toast.success("PgBouncer configuration saved.");
      onSaved();
    } catch (e: unknown) {
      toast.error(e instanceof Error ? e.message : "Failed to save.");
    } finally {
      setSaving(false);
    }
  }

  return (
    // Nothing here submits: saving goes through the button below, so the form
    // element only groups the controls (as it did before the migration).
    <Form onSubmit={(e) => e.preventDefault()}>
      <PageSection title="Settings">
        <div className="gisila-fields">
          {scalarFields.map((f) => (
            <ScalarField
              key={f.key}
              field={f}
              value={scalars[f.key] ?? ""}
              onChange={(v) => setScalars((p) => ({ ...p, [f.key]: v }))}
            />
          ))}
        </div>
      </PageSection>

      <PageSection
        title="Database servers (pools)"
        actions={
          <>
            <PickManaged onPick={(db) => setDatabases((p) => [...p, db])} />
            <Button
              size="sm"
              kind="ghost"
              renderIcon={Add}
              onClick={() =>
                setDatabases((p) => [
                  ...p,
                  { name: "", host: "", port: "5432", dbname: "" },
                ])
              }
            >
              Add
            </Button>
          </>
        }
      >
        {databases.length === 0 ? (
          <p className="gisila-detail__note">
            No pools yet. Add one manually or pick from this panel&apos;s managed
            Postgres.
          </p>
        ) : (
          <Stack gap={4}>
            {databases.map((d, i) => (
              <DatabaseRow
                key={i}
                index={i}
                db={d}
                showSecret={showSecrets}
                onToggleSecret={() => setShowSecrets((s) => !s)}
                onChange={(next) =>
                  setDatabases((p) => p.map((x, j) => (j === i ? next : x)))
                }
                onRemove={() =>
                  setDatabases((p) => p.filter((_, j) => j !== i))
                }
              />
            ))}
          </Stack>
        )}
      </PageSection>

      <PageSection
        title="Client users"
        actions={
          <>
            <Button
              size="sm"
              kind="ghost"
              renderIcon={showSecrets ? ViewOff : View}
              onClick={() => setShowSecrets((s) => !s)}
            >
              {showSecrets ? "Hide" : "Show"} passwords
            </Button>
            <Button
              size="sm"
              kind="ghost"
              renderIcon={Add}
              onClick={() =>
                setUsers((p) => [...p, { username: "", password: "" }])
              }
            >
              Add user
            </Button>
          </>
        }
      >
        {users.length === 0 ? (
          <p className="gisila-detail__note">
            No users yet. Required unless auth type is{" "}
            <CodeSnippet type="inline">trust</CodeSnippet>.
          </p>
        ) : (
          <TableContainer>
            <Table size="sm">
              <TableHead>
                <TableRow>
                  <TableHeader>Username</TableHeader>
                  <TableHeader>Password</TableHeader>
                  <TableHeader className="gisila-table__actions">
                    Remove
                  </TableHeader>
                </TableRow>
              </TableHead>
              <TableBody>
                {users.map((u, i) => (
                  <TableRow key={i}>
                    <TableCell>
                      <TextInput
                        id={`pgb-user-name-${i}`}
                        labelText="Username"
                        hideLabel
                        size="sm"
                        placeholder="username"
                        value={u.username}
                        onChange={(e) =>
                          setUsers((p) =>
                            p.map((x, j) =>
                              j === i ? { ...x, username: e.target.value } : x,
                            ),
                          )
                        }
                      />
                    </TableCell>
                    <TableCell>
                      <PasswordInput
                        id={`pgb-user-password-${i}`}
                        labelText="Password"
                        hideLabel
                        size="sm"
                        placeholder="password"
                        type={showSecrets ? "text" : "password"}
                        onTogglePasswordVisibility={() =>
                          setShowSecrets((s) => !s)
                        }
                        value={u.password}
                        onChange={(e) =>
                          setUsers((p) =>
                            p.map((x, j) =>
                              j === i ? { ...x, password: e.target.value } : x,
                            ),
                          )
                        }
                      />
                    </TableCell>
                    <TableCell className="gisila-table__actions">
                      <Button
                        kind="ghost"
                        size="sm"
                        hasIconOnly
                        renderIcon={TrashCan}
                        iconDescription="Remove"
                        onClick={() =>
                          setUsers((p) => p.filter((_, j) => j !== i))
                        }
                      />
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </TableContainer>
        )}
      </PageSection>

      {databases.length > 0 && (
        <ConnectionInfo
          databases={databases}
          listenPort={scalars["listen_port"] || "6432"}
          users={users}
        />
      )}

      <PageSection>
        {saving ? (
          <InlineLoading status="active" description="Saving…" />
        ) : (
          <Button size="md" renderIcon={Save} onClick={save}>
            Save configuration
          </Button>
        )}
      </PageSection>
    </Form>
  );
}

// ── Scalar field (number / string / select) ───────────────────────────────────

function ScalarField({
  field,
  value,
  onChange,
}: {
  field: ConfigField;
  value: string;
  onChange: (v: string) => void;
}) {
  if (field.type === "select") {
    return (
      <Select
        id={`pgb-${field.key}`}
        labelText={field.label}
        helperText={field.hint}
        value={value}
        onChange={(e) => onChange(e.target.value)}
      >
        {field.options?.map((opt) => (
          <SelectItem key={opt} value={opt} text={opt} />
        ))}
      </Select>
    );
  }

  if (field.type === "number") {
    return (
      <NumberInput
        id={`pgb-${field.key}`}
        label={field.label}
        helperText={field.hint}
        value={value}
        min={field.min}
        max={field.max}
        allowEmpty
        // Every config value is persisted as a string, so the number is written
        // straight back into the flat string map.
        onChange={(_event, { value: next }) => onChange(String(next))}
      />
    );
  }

  return (
    <TextInput
      id={`pgb-${field.key}`}
      labelText={field.label}
      helperText={field.hint}
      value={value}
      placeholder={field.placeholder ?? field.default}
      onChange={(e) => onChange(e.target.value)}
    />
  );
}

// ── Database row editor ────────────────────────────────────────────────────────

function DatabaseRow({
  index,
  db,
  showSecret,
  onToggleSecret,
  onChange,
  onRemove,
}: {
  index: number;
  db: PgbDatabase;
  showSecret: boolean;
  onToggleSecret: () => void;
  onChange: (next: PgbDatabase) => void;
  onRemove: () => void;
}) {
  const set = (patch: Partial<PgbDatabase>) => onChange({ ...db, ...patch });
  const id = (name: string) => `pgb-db-${index}-${name}`;

  return (
    <Tile>
      <FormGroup legendText={db.name || `Pool ${index + 1}`}>
        <div className="gisila-fields">
          <TextInput
            id={id("name")}
            labelText={<RequiredLabel>Pool name</RequiredLabel>}
            placeholder="app_pool"
            value={db.name}
            onChange={(e) => set({ name: e.target.value })}
          />
          <TextInput
            id={id("host")}
            labelText={<RequiredLabel>Host</RequiredLabel>}
            className="gisila-field--mono"
            placeholder="127.0.0.1"
            value={db.host}
            onChange={(e) => set({ host: e.target.value })}
          />
          <NumberInput
            id={id("port")}
            label="Port"
            value={db.port}
            allowEmpty
            onChange={(_event, { value }) => set({ port: String(value) })}
          />
          <TextInput
            id={id("dbname")}
            labelText={<RequiredLabel>Database</RequiredLabel>}
            placeholder="app_prod"
            value={db.dbname}
            onChange={(e) => set({ dbname: e.target.value })}
          />
          <TextInput
            id={id("user")}
            labelText="User (optional)"
            placeholder="(forwarded from client)"
            value={db.user ?? ""}
            onChange={(e) => set({ user: e.target.value })}
          />
          <PasswordInput
            id={id("password")}
            labelText="Password (optional)"
            type={showSecret ? "text" : "password"}
            onTogglePasswordVisibility={onToggleSecret}
            value={db.password ?? ""}
            onChange={(e) => set({ password: e.target.value })}
          />
          <NumberInput
            id={id("pool_size")}
            label="Pool size (optional)"
            value={db.pool_size ?? ""}
            allowEmpty
            onChange={(_event, { value }) => set({ pool_size: String(value) })}
          />
          <div className="gisila-row-actions">
            <Button
              kind="ghost"
              hasIconOnly
              renderIcon={TrashCan}
              iconDescription="Remove"
              onClick={onRemove}
            />
          </div>
        </div>
      </FormGroup>
    </Tile>
  );
}

// ── Pick from managed Postgres ─────────────────────────────────────────────────

function PickManaged({ onPick }: { onPick: (db: PgbDatabase) => void }) {
  const { data: instData } = useSWR<ListResponse<PostgresInstance>>(
    "/databases",
    fetcher,
  );
  const instances = (instData?.results ?? []).filter(
    (i) => i.status === "running",
  );

  const [instanceId, setInstanceId] = useState<string>("");
  const { data: dbData } = useSWR<ListResponse<PostgresDatabase>>(
    instanceId ? `/databases/${instanceId}/dbs` : null,
    fetcher,
  );
  const instance = instances.find((i) => String(i.id) === instanceId);
  const dbs = (dbData?.results ?? []).filter((d) => d.status === "active");

  if (instances.length === 0) return null;

  return (
    <div className="gisila-picker">
      <Select
        id="pgb-pick-instance"
        labelText="Pick from managed instance"
        hideLabel
        size="sm"
        value={instanceId}
        onChange={(e) => setInstanceId(e.target.value)}
      >
        <SelectItem value="" text="Pick from managed…" />
        {instances.map((i) => (
          <SelectItem
            key={i.id}
            value={String(i.id)}
            text={`${i.displayName} (:${i.port})`}
          />
        ))}
      </Select>
      {instanceId && (
        <Select
          id="pgb-pick-database"
          labelText="Pick a database"
          hideLabel
          size="sm"
          value=""
          onChange={(e) => {
            const db = dbs.find((d) => String(d.id) === e.target.value);
            if (db && instance) {
              onPick({
                name: db.dbName,
                host: "127.0.0.1",
                port: String(instance.port),
                dbname: db.dbName,
                user: db.roleName,
              });
              setInstanceId("");
            }
          }}
        >
          <SelectItem value="" text="Select database…" />
          {dbs.map((d) => (
            <SelectItem key={d.id} value={String(d.id)} text={d.dbName} />
          ))}
        </Select>
      )}
    </div>
  );
}

// ── Connection info ────────────────────────────────────────────────────────────

function ConnectionInfo({
  databases,
  listenPort,
  users,
}: {
  databases: PgbDatabase[];
  listenPort: string;
  users: PgbUser[];
}) {
  const host =
    typeof window !== "undefined" ? window.location.hostname : "<server>";
  const defaultUser = users[0]?.username;

  return (
    <PageSection
      title="Connection info"
      description="Point your apps at PgBouncer instead of Postgres directly. The pool name is used as the database name."
    >
      <Stack gap={5}>
        {databases
          .filter((d) => d.name?.trim())
          .map((d, i) => {
            const user = d.user || defaultUser || "user";
            const url = `postgresql://${user}@${host}:${listenPort}/${d.name}`;
            return (
              <Stack key={i} gap={2}>
                <div className="gisila-catalog__tags">
                  <Tag type="outline" size="sm">
                    {d.name}
                  </Tag>
                  <span className="gisila-catalog__meta">
                    host={host} port={listenPort} dbname={d.name}
                  </span>
                </div>
                <CodeSnippet type="single" feedback="Copied!">
                  {url}
                </CodeSnippet>
              </Stack>
            );
          })}
      </Stack>
    </PageSection>
  );
}
