"use client";

import { useEffect, useMemo, useState } from "react";
import useSWR from "swr";
import {
  Plus,
  Trash2,
  Save,
  Loader,
  Eye,
  EyeOff,
  Copy,
  Check,
  Database,
  Users,
  Network,
  Link2,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
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

function CopyButton({ text }: { text: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <button
      type="button"
      className="text-muted-foreground hover:text-foreground transition-colors shrink-0"
      title="Copy"
      onClick={() => {
        navigator.clipboard.writeText(text);
        setCopied(true);
        setTimeout(() => setCopied(false), 1500);
      }}
    >
      {copied ? (
        <Check className="h-3.5 w-3.5 text-emerald-500" />
      ) : (
        <Copy className="h-3.5 w-3.5" />
      )}
    </button>
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
    <div className="space-y-6">
      {/* ── Settings ─────────────────────────────────────────────── */}
      <section className="space-y-4">
        <h2 className="text-sm font-semibold flex items-center gap-2">
          <Network className="h-4 w-4 text-muted-foreground" />
          Settings
        </h2>
        <div className="grid gap-4 sm:grid-cols-2">
          {scalarFields.map((f) => (
            <ScalarField
              key={f.key}
              field={f}
              value={scalars[f.key] ?? ""}
              onChange={(v) => setScalars((p) => ({ ...p, [f.key]: v }))}
            />
          ))}
        </div>
      </section>

      {/* ── Databases ────────────────────────────────────────────── */}
      <section className="space-y-3">
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-semibold flex items-center gap-2">
            <Database className="h-4 w-4 text-muted-foreground" />
            Database servers (pools)
          </h2>
          <div className="flex items-center gap-2">
            <PickManaged
              onPick={(db) => setDatabases((p) => [...p, db])}
            />
            <Button
              size="sm"
              variant="outline"
              onClick={() =>
                setDatabases((p) => [
                  ...p,
                  { name: "", host: "", port: "5432", dbname: "" },
                ])
              }
            >
              <Plus className="mr-1.5 h-3.5 w-3.5" />
              Add
            </Button>
          </div>
        </div>

        {databases.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            No pools yet. Add one manually or pick from this panel&apos;s managed
            Postgres.
          </p>
        ) : (
          <div className="space-y-2">
            {databases.map((d, i) => (
              <DatabaseRow
                key={i}
                db={d}
                showSecret={showSecrets}
                onChange={(next) =>
                  setDatabases((p) => p.map((x, j) => (j === i ? next : x)))
                }
                onRemove={() =>
                  setDatabases((p) => p.filter((_, j) => j !== i))
                }
              />
            ))}
          </div>
        )}
      </section>

      {/* ── Users ────────────────────────────────────────────────── */}
      <section className="space-y-3">
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-semibold flex items-center gap-2">
            <Users className="h-4 w-4 text-muted-foreground" />
            Client users
          </h2>
          <div className="flex items-center gap-2">
            <button
              type="button"
              className="text-xs text-muted-foreground hover:text-foreground flex items-center gap-1"
              onClick={() => setShowSecrets((s) => !s)}
            >
              {showSecrets ? (
                <EyeOff className="h-3.5 w-3.5" />
              ) : (
                <Eye className="h-3.5 w-3.5" />
              )}
              {showSecrets ? "Hide" : "Show"} passwords
            </button>
            <Button
              size="sm"
              variant="outline"
              onClick={() =>
                setUsers((p) => [...p, { username: "", password: "" }])
              }
            >
              <Plus className="mr-1.5 h-3.5 w-3.5" />
              Add user
            </Button>
          </div>
        </div>

        {users.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            No users yet. Required unless auth type is{" "}
            <code className="text-xs">trust</code>.
          </p>
        ) : (
          <div className="space-y-2">
            {users.map((u, i) => (
              <div key={i} className="flex items-center gap-2">
                <Input
                  placeholder="username"
                  value={u.username}
                  className="h-8"
                  onChange={(e) =>
                    setUsers((p) =>
                      p.map((x, j) =>
                        j === i ? { ...x, username: e.target.value } : x,
                      ),
                    )
                  }
                />
                <Input
                  placeholder="password"
                  type={showSecrets ? "text" : "password"}
                  value={u.password}
                  className="h-8"
                  onChange={(e) =>
                    setUsers((p) =>
                      p.map((x, j) =>
                        j === i ? { ...x, password: e.target.value } : x,
                      ),
                    )
                  }
                />
                <Button
                  size="icon"
                  variant="ghost"
                  className="h-8 w-8 shrink-0 text-muted-foreground hover:text-destructive"
                  onClick={() =>
                    setUsers((p) => p.filter((_, j) => j !== i))
                  }
                >
                  <Trash2 className="h-3.5 w-3.5" />
                </Button>
              </div>
            ))}
          </div>
        )}
      </section>

      {/* ── Connection info ──────────────────────────────────────── */}
      {databases.length > 0 && (
        <ConnectionInfo
          databases={databases}
          listenPort={scalars["listen_port"] || "6432"}
          users={users}
        />
      )}

      <Button size="sm" disabled={saving} onClick={save}>
        {saving ? (
          <Loader className="mr-1.5 h-3.5 w-3.5 animate-spin" />
        ) : (
          <Save className="mr-1.5 h-3.5 w-3.5" />
        )}
        Save configuration
      </Button>
    </div>
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
  return (
    <div className="space-y-1.5">
      <Label className="flex items-center gap-1.5 text-xs">{field.label}</Label>
      {field.type === "select" ? (
        <select
          value={value}
          onChange={(e) => onChange(e.target.value)}
          className="flex h-8 w-full rounded-md border border-input bg-background px-3 py-1 text-sm ring-offset-background focus:outline-none focus:ring-2 focus:ring-ring"
        >
          {field.options?.map((opt) => (
            <option key={opt} value={opt}>
              {opt}
            </option>
          ))}
        </select>
      ) : (
        <Input
          type={field.type === "number" ? "number" : "text"}
          value={value}
          placeholder={field.placeholder ?? field.default}
          min={field.min}
          max={field.max}
          className="h-8"
          onChange={(e) => onChange(e.target.value)}
        />
      )}
      {field.hint && (
        <p className="text-[11px] text-muted-foreground">{field.hint}</p>
      )}
    </div>
  );
}

// ── Database row editor ────────────────────────────────────────────────────────

function DatabaseRow({
  db,
  showSecret,
  onChange,
  onRemove,
}: {
  db: PgbDatabase;
  showSecret: boolean;
  onChange: (next: PgbDatabase) => void;
  onRemove: () => void;
}) {
  const set = (patch: Partial<PgbDatabase>) => onChange({ ...db, ...patch });
  return (
    <Card>
      <CardContent className="py-3 space-y-2">
        <div className="grid gap-2 sm:grid-cols-4">
          <Field label="Pool name" required>
            <Input
              placeholder="app_pool"
              value={db.name}
              className="h-8"
              onChange={(e) => set({ name: e.target.value })}
            />
          </Field>
          <Field label="Host" required>
            <Input
              placeholder="127.0.0.1"
              value={db.host}
              className="h-8"
              onChange={(e) => set({ host: e.target.value })}
            />
          </Field>
          <Field label="Port">
            <Input
              type="number"
              placeholder="5432"
              value={db.port}
              className="h-8"
              onChange={(e) => set({ port: e.target.value })}
            />
          </Field>
          <Field label="Database" required>
            <Input
              placeholder="app_prod"
              value={db.dbname}
              className="h-8"
              onChange={(e) => set({ dbname: e.target.value })}
            />
          </Field>
          <Field label="User (optional)">
            <Input
              placeholder="(forwarded from client)"
              value={db.user ?? ""}
              className="h-8"
              onChange={(e) => set({ user: e.target.value })}
            />
          </Field>
          <Field label="Password (optional)">
            <Input
              type={showSecret ? "text" : "password"}
              value={db.password ?? ""}
              className="h-8"
              onChange={(e) => set({ password: e.target.value })}
            />
          </Field>
          <Field label="Pool size (optional)">
            <Input
              type="number"
              placeholder="default"
              value={db.pool_size ?? ""}
              className="h-8"
              onChange={(e) => set({ pool_size: e.target.value })}
            />
          </Field>
          <div className="flex items-end justify-end">
            <Button
              size="icon"
              variant="ghost"
              className="h-8 w-8 text-muted-foreground hover:text-destructive"
              onClick={onRemove}
            >
              <Trash2 className="h-3.5 w-3.5" />
            </Button>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}

function Field({
  label,
  required,
  children,
}: {
  label: string;
  required?: boolean;
  children: React.ReactNode;
}) {
  return (
    <div className="space-y-1">
      <Label className="text-[11px] flex items-center gap-1">
        {label}
        {required && <span className="text-red-500">*</span>}
      </Label>
      {children}
    </div>
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
    <div className="flex items-center gap-1.5">
      <select
        value={instanceId}
        onChange={(e) => setInstanceId(e.target.value)}
        className="h-8 rounded-md border border-input bg-background px-2 text-xs"
      >
        <option value="">Pick from managed…</option>
        {instances.map((i) => (
          <option key={i.id} value={String(i.id)}>
            {i.displayName} (:{i.port})
          </option>
        ))}
      </select>
      {instanceId && (
        <select
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
          className="h-8 rounded-md border border-input bg-background px-2 text-xs"
        >
          <option value="">Select database…</option>
          {dbs.map((d) => (
            <option key={d.id} value={String(d.id)}>
              {d.dbName}
            </option>
          ))}
        </select>
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
    <section className="space-y-3">
      <h2 className="text-sm font-semibold flex items-center gap-2">
        <Link2 className="h-4 w-4 text-muted-foreground" />
        Connection info
      </h2>
      <p className="text-[11px] text-muted-foreground">
        Point your apps at PgBouncer instead of Postgres directly. The pool name
        is used as the database name.
      </p>
      <div className="space-y-2">
        {databases
          .filter((d) => d.name?.trim())
          .map((d, i) => {
            const user = d.user || defaultUser || "user";
            const url = `postgresql://${user}@${host}:${listenPort}/${d.name}`;
            return (
              <div key={i} className="rounded-md border bg-muted/30 px-3 py-2">
                <div className="flex items-center gap-2">
                  <Badge variant="outline" className="text-[10px]">
                    {d.name}
                  </Badge>
                  <span className="text-[11px] text-muted-foreground">
                    host={host} port={listenPort} dbname={d.name}
                  </span>
                </div>
                <div className="mt-1.5 flex items-center gap-2">
                  <code className="flex-1 break-all text-xs font-mono">
                    {url}
                  </code>
                  <CopyButton text={url} />
                </div>
              </div>
            );
          })}
      </div>
    </section>
  );
}
