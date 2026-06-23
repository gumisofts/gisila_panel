"use client";

import { useState } from "react";
import { useParams, useRouter } from "@/compat/navigation";
import useSWR, { mutate } from "swr";
import {
  Leaf,
  Plus,
  CheckCircle,
  AlertCircle,
  Loader,
  Star,
  Play,
  Square,
  Trash2,
  Copy,
  Eye,
  EyeOff,
  ArrowLeft,
  Table2,
  HardDriveDownload,
  Globe,
  KeyRound,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { api, fetcher } from "@/lib/api";
import { usePermissions } from "@/lib/permissions";
import { cn } from "@/lib/utils";
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

const INST_STATUS: Record<
  MongoInstanceStatus,
  { icon: React.ReactNode; label: string; color: string }
> = {
  running:      { icon: <CheckCircle className="h-4 w-4 text-emerald-500" />, label: "Running",    color: "text-emerald-600 dark:text-emerald-400" },
  stopped:      { icon: <AlertCircle className="h-4 w-4 text-amber-500"  />, label: "Stopped",    color: "text-amber-600 dark:text-amber-400" },
  failed:       { icon: <AlertCircle className="h-4 w-4 text-red-500"    />, label: "Failed",     color: "text-red-600 dark:text-red-400" },
  pending:      { icon: <Loader      className="h-4 w-4 animate-spin text-blue-500" />, label: "Pending",    color: "text-blue-600" },
  installing:   { icon: <Loader      className="h-4 w-4 animate-spin text-blue-500" />, label: "Installing", color: "text-blue-600" },
  uninstalling: { icon: <Loader      className="h-4 w-4 animate-spin text-amber-500" />, label: "Removing",   color: "text-amber-600" },
};

const DB_STATUS_BADGE: Record<MongoDatabaseStatus, { label: string; variant: "default" | "secondary" | "destructive" | "outline" }> = {
  pending: { label: "Pending", variant: "secondary" },
  active:  { label: "Active",  variant: "outline"   },
  failed:  { label: "Failed",  variant: "destructive" },
  dropped: { label: "Dropped", variant: "secondary" },
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

function RoleToggles({
  value,
  onChange,
  disabled,
}: {
  value: string[];
  onChange: (next: string[]) => void;
  disabled?: boolean;
}) {
  const toggle = (key: string) =>
    onChange(value.includes(key) ? value.filter((k) => k !== key) : [...value, key]);
  return (
    <div className="grid gap-1.5">
      {MONGO_ROLES.map((a) => {
        const on = value.includes(a.key);
        return (
          <button
            key={a.key}
            type="button"
            disabled={disabled}
            onClick={() => toggle(a.key)}
            className={cn(
              "flex items-start gap-2 rounded-md border px-3 py-2 text-left transition-colors disabled:opacity-50",
              on
                ? a.danger
                  ? "border-destructive/50 bg-destructive/10"
                  : "border-primary/50 bg-primary/10"
                : "border-input hover:bg-muted/50",
            )}
          >
            <span
              className={cn(
                "mt-0.5 flex h-4 w-4 shrink-0 items-center justify-center rounded border text-[10px]",
                on ? (a.danger ? "border-destructive bg-destructive text-white" : "border-primary bg-primary text-white") : "border-input",
              )}
            >
              {on ? "✓" : ""}
            </span>
            <span className="min-w-0">
              <span className="block text-sm font-medium leading-tight">
                <span className="font-mono">{a.key}</span>
                <span className="ml-1.5 font-normal text-muted-foreground">{a.label}</span>
                {a.danger && (
                  <span className="ml-1.5 text-xs font-semibold text-destructive">danger</span>
                )}
              </span>
              <span className="block text-xs text-muted-foreground">{a.hint}</span>
            </span>
          </button>
        );
      })}
    </div>
  );
}

function CopyButton({ text }: { text: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <button
      className="text-muted-foreground hover:text-foreground transition-colors"
      onClick={() => {
        navigator.clipboard.writeText(text);
        setCopied(true);
        setTimeout(() => setCopied(false), 1500);
      }}
    >
      {copied ? (
        <CheckCircle className="h-3.5 w-3.5 text-emerald-500" />
      ) : (
        <Copy className="h-3.5 w-3.5" />
      )}
    </button>
  );
}

function ConnRow({ label, value, secret }: { label: string; value: string; secret?: boolean }) {
  const [show, setShow] = useState(!secret);
  return (
    <div className="flex items-center justify-between gap-2 py-1.5 text-sm border-b border-border last:border-0">
      <span className="text-muted-foreground w-24 shrink-0">{label}</span>
      <span className="font-mono text-xs flex-1 min-w-0 truncate">
        {show ? value : "••••••••"}
      </span>
      <div className="flex items-center gap-1.5 shrink-0">
        {secret && (
          <button
            className="text-muted-foreground hover:text-foreground"
            onClick={() => setShow((v) => !v)}
          >
            {show ? <EyeOff className="h-3.5 w-3.5" /> : <Eye className="h-3.5 w-3.5" />}
          </button>
        )}
        <CopyButton text={value} />
      </div>
    </div>
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
    <Card className="border-violet-500/30 bg-violet-500/5">
      <CardHeader>
        <CardTitle className="flex items-center gap-2 text-base">
          <Globe className="h-4 w-4 text-violet-500" />
          Public access
          {instance.isPublic ? (
            <Badge variant="outline" className="ml-1 text-[10px]">Public</Badge>
          ) : (
            <Badge variant="secondary" className="ml-1 text-[10px]">Private</Badge>
          )}
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        {instance.isPublic ? (
          <>
            <p className="text-sm text-muted-foreground">
              Reachable over TLS at{" "}
              <code className="font-mono">
                {instance.publicDomain}:{instance.port}
              </code>{" "}
              (connect with <code className="font-mono">tls=true</code>).
            </p>
            <Button
              variant="outline"
              size="sm"
              className="text-destructive hover:text-destructive"
              disabled={busy}
              onClick={() => save(false)}
            >
              Make private
            </Button>
          </>
        ) : (
          <>
            <div>
              <Label htmlFor="mongo-domain">Domain</Label>
              <Input
                id="mongo-domain"
                className="mt-1 font-mono text-sm max-w-sm"
                placeholder="mongo.example.com"
                value={domain}
                onChange={(e) => setDomain(e.target.value)}
              />
            </div>
            <div className="rounded-md border border-border bg-muted/40 p-3 text-xs text-muted-foreground space-y-1.5">
              <p>
                Opens the server to the internet over TLS: obtains a Let&apos;s
                Encrypt certificate for the domain, enables TLS, and listens on
                all interfaces at <code className="font-mono">{instance.port}</code>.
              </p>
              <p>
                Point a DNS <code className="font-mono">A</code> record at this
                server and open port{" "}
                <code className="font-mono">{instance.port}</code> first. The cert
                needs port 80 reachable.
              </p>
            </div>
            <Button size="sm" disabled={busy} onClick={() => save(true)}>
              {busy ? "Enabling…" : "Make public"}
            </Button>
          </>
        )}
        {pending && <p className="text-xs text-amber-500">Exposure in progress…</p>}
        {error && <p className="text-xs text-destructive">{error}</p>}
      </CardContent>
    </Card>
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
      <div className="flex items-center gap-2 p-8 text-sm text-muted-foreground">
        <Loader className="h-4 w-4 animate-spin" />
        Loading…
      </div>
    );
  }

  const sc = INST_STATUS[instance.status] ?? INST_STATUS.stopped;
  const databases = dbsData?.results ?? [];
  const isRunning = instance.status === "running";

  return (
    <div className="mx-auto max-w-4xl space-y-6 p-6">
      <button
        className="flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground transition-colors"
        onClick={() => router.push("/databases")}
      >
        <ArrowLeft className="h-3.5 w-3.5" />
        All instances
      </button>

      <div className="flex items-start justify-between gap-4">
        <div className="flex items-center gap-3">
          <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-emerald-500/10">
            <Leaf className="h-6 w-6 text-emerald-500" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h1 className="text-xl font-semibold">{instance.displayName}</h1>
              {instance.isDefault && (
                <Badge variant="outline" className="gap-1 py-0 text-xs font-normal">
                  <Star className="h-2.5 w-2.5 fill-amber-400 text-amber-400" />
                  Default
                </Badge>
              )}
            </div>
            <p className={cn("text-sm flex items-center gap-1.5 mt-0.5", sc.color)}>
              {sc.icon} {sc.label} · MongoDB {instance.version} · port {instance.port}
            </p>
          </div>
        </div>

        <div className="flex items-center gap-2 flex-wrap justify-end">
          {isSuperuser && !instance.isDefault && isRunning && (
            <Button variant="outline" size="sm" onClick={() => action(`/mongo/${id}/set-default`)} disabled={!!busy}>
              <Star className="mr-1.5 h-3.5 w-3.5" />
              Set default
            </Button>
          )}
          {isSuperuser && instance.status === "stopped" && (
            <Button variant="outline" size="sm" onClick={() => action(`/mongo/${id}/start`)} disabled={!!busy}>
              <Play className="mr-1.5 h-3.5 w-3.5" />
              Start
            </Button>
          )}
          {isSuperuser && isRunning && (
            <Button variant="outline" size="sm" onClick={() => action(`/mongo/${id}/stop`)} disabled={!!busy}>
              <Square className="mr-1.5 h-3.5 w-3.5" />
              Stop
            </Button>
          )}
          {isSuperuser && !instance.isDefault && (
            <Button
              variant="outline"
              size="sm"
              className="text-destructive hover:text-destructive"
              onClick={async () => {
                if (!confirm(`Uninstall MongoDB ${instance.version}? All data will be deleted.`)) return;
                await action(`/mongo/${id}`, "DELETE");
                router.push("/databases");
              }}
              disabled={!!busy}
            >
              <Trash2 className="mr-1.5 h-3.5 w-3.5" />
              Uninstall
            </Button>
          )}
        </div>
      </div>

      {instance.errorMessage && (
        <div className="rounded-md border border-destructive/40 bg-destructive/5 px-4 py-3 text-sm text-destructive">
          {instance.errorMessage}
        </div>
      )}

      <MongoMetricsPanel id={String(id)} running={isRunning} />

      {isSuperuser && isRunning && (
        <PublicAccessCard instance={instance} instKey={instKey} />
      )}

      <div className="space-y-3">
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-medium flex items-center gap-2">
            <Table2 className="h-4 w-4 text-muted-foreground" />
            Databases &amp; users
          </h2>
          {isRunning && isSuperuser && (
            <Button size="sm" variant="outline" onClick={() => setShowCreate(true)}>
              <Plus className="mr-1.5 h-3.5 w-3.5" />
              Create database
            </Button>
          )}
        </div>

        {databases.length === 0 ? (
          <Card>
            <CardContent className="flex flex-col items-center gap-3 py-12 text-center">
              <Table2 className="h-8 w-8 text-muted-foreground/30" />
              <div>
                <p className="text-sm font-medium">No databases yet</p>
                <p className="mt-0.5 text-xs text-muted-foreground">
                  {isRunning
                    ? "Create a database and user to get started."
                    : "Start the instance first to create databases."}
                </p>
              </div>
              {isRunning && (
                <Button size="sm" onClick={() => setShowCreate(true)}>
                  <Plus className="mr-1.5 h-3.5 w-3.5" />
                  Create database
                </Button>
              )}
            </CardContent>
          </Card>
        ) : (
          <div className="space-y-2">
            {databases.map((db) => {
              const dbSc = DB_STATUS_BADGE[db.status] ?? DB_STATUS_BADGE.active;
              return (
                <Card key={db.id}>
                  <CardContent className="py-4">
                    <div className="flex items-start justify-between gap-4">
                      <div className="min-w-0">
                        <div className="flex items-center gap-2">
                          <span className="font-mono font-medium text-sm">{db.dbName}</span>
                          <Badge variant={dbSc.variant} className="text-xs py-0">
                            {dbSc.label}
                          </Badge>
                        </div>
                        <p className="text-xs text-muted-foreground mt-0.5">
                          User: <span className="font-mono">{db.userName}</span>
                        </p>
                        {db.roles?.length > 0 && (
                          <div className="mt-1 flex flex-wrap gap-1">
                            {db.roles.map((a) => (
                              <Badge
                                key={a}
                                variant={a.endsWith("AnyDatabase") || a === "clusterMonitor" ? "destructive" : "secondary"}
                                className="py-0 font-mono text-[10px]"
                              >
                                {a}
                              </Badge>
                            ))}
                          </div>
                        )}
                        {db.errorMessage && (
                          <p className="mt-1 text-xs text-destructive">{db.errorMessage}</p>
                        )}
                      </div>
                      <div className="flex items-center gap-2 shrink-0">
                        <Button size="sm" variant="ghost" onClick={() => showConnection(db)} className="h-7 px-2 text-xs">
                          Connection info
                        </Button>
                        {db.status === "active" && isSuperuser && (
                          <Button size="sm" variant="ghost" onClick={() => openPerms(db)} className="h-7 px-2 text-xs">
                            <KeyRound className="mr-1 h-3.5 w-3.5" />
                            Roles
                          </Button>
                        )}
                        {db.status === "active" && isSuperuser && (
                          <Button size="sm" variant="ghost" onClick={() => setBackupsDb(db)} className="h-7 px-2 text-xs">
                            <HardDriveDownload className="mr-1 h-3.5 w-3.5" />
                            Backups
                          </Button>
                        )}
                        {isSuperuser && (
                          <Button
                            size="sm"
                            variant="ghost"
                            className="h-7 px-2 text-destructive hover:text-destructive"
                            onClick={() => handleDrop(db.id)}
                            disabled={!!busy}
                          >
                            <Trash2 className="h-3.5 w-3.5" />
                          </Button>
                        )}
                      </div>
                    </div>
                  </CardContent>
                </Card>
              );
            })}
          </div>
        )}
      </div>

      <ConfigPanel
        id={String(id)}
        running={isRunning}
        apiBase="/mongo"
        note="Changing these rewrites the mongod config and restarts the server. Leave a field blank to keep the current value."
      />

      {/* Create database dialog */}
      <Dialog open={showCreate} onOpenChange={setShowCreate}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Create database</DialogTitle>
          </DialogHeader>
          <div className="space-y-4 py-2">
            <div className="space-y-1.5">
              <Label>Database name</Label>
              <Input placeholder="myapp" value={newDb} onChange={(e) => setNewDb(e.target.value)} />
            </div>
            <div className="space-y-1.5">
              <Label>User</Label>
              <Input placeholder="myapp_user" value={newUser} onChange={(e) => setNewUser(e.target.value)} />
            </div>
            <div className="space-y-1.5">
              <Label>Password</Label>
              <Input
                type="password"
                placeholder="Leave blank to auto-generate"
                value={newPass}
                onChange={(e) => setNewPass(e.target.value)}
              />
            </div>
            <div className="space-y-1.5">
              <Label>Roles</Label>
              <RoleToggles value={newRoles} onChange={setNewRoles} disabled={creating} />
              <p className="text-xs text-muted-foreground">
                Roles are granted on this database unless they are instance-wide
                (the <span className="font-mono">*AnyDatabase</span> roles).
              </p>
            </div>
            {createError && <p className="text-sm text-destructive">{createError}</p>}
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowCreate(false)}>Cancel</Button>
            <Button onClick={handleCreate} disabled={creating || !newDb || !newUser}>
              {creating && <Loader className="mr-1.5 h-3.5 w-3.5 animate-spin" />}
              Create
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Edit roles dialog */}
      <Dialog open={!!permsDb} onOpenChange={(o) => !o && setPermsDb(null)}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>
              Roles
              {permsDb && (
                <span className="ml-1.5 font-mono text-sm font-normal text-muted-foreground">
                  {permsDb.userName}
                </span>
              )}
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-3 py-2">
            <RoleToggles value={permsRoles} onChange={setPermsRoles} disabled={permsBusy} />
            <p className="text-xs text-muted-foreground">
              Changes are applied with <span className="font-mono">updateUser</span>; roles you
              turn off are revoked.
            </p>
            {permsError && <p className="text-sm text-destructive">{permsError}</p>}
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setPermsDb(null)} disabled={permsBusy}>
              Cancel
            </Button>
            <Button onClick={handleUpdatePerms} disabled={permsBusy}>
              {permsBusy && <Loader className="mr-1.5 h-3.5 w-3.5 animate-spin" />}
              Save roles
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Connection info dialog */}
      <Dialog open={!!justCreated} onOpenChange={() => setJustCreated(null)}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>Connection info — {justCreated?.dbName}</DialogTitle>
          </DialogHeader>
          {justCreated?.connection ? (
            <div className="space-y-4 py-2">
              <div className="rounded-md border border-amber-500/30 bg-amber-500/5 px-3 py-2 text-xs text-amber-600 dark:text-amber-400">
                Save this password now — it will not be shown again in plain text.
              </div>
              <Card>
                <CardContent className="py-3 px-4">
                  <ConnRow label="Host"     value={justCreated.connection.host} />
                  <ConnRow label="Port"     value={String(justCreated.connection.port)} />
                  <ConnRow label="Database" value={justCreated.connection.database} />
                  <ConnRow label="Username" value={justCreated.connection.username} />
                  <ConnRow label="Password" value={justCreated.connection.password} secret />
                  <ConnRow label="Auth DB"  value={justCreated.connection.authSource} />
                </CardContent>
              </Card>
              <div className="space-y-1.5">
                <Label className="text-xs text-muted-foreground">
                  Connection URI{justCreated.connection.publicUrl ? " (local)" : ""}
                </Label>
                <div className="flex items-center gap-2">
                  <code className="flex-1 rounded-md bg-muted px-3 py-2 text-xs font-mono break-all">
                    {justCreated.connection.url}
                  </code>
                  <CopyButton text={justCreated.connection.url} />
                </div>
              </div>
              {justCreated.connection.publicUrl && (
                <div className="space-y-1.5">
                  <Label className="text-xs text-muted-foreground">Public URI (TLS)</Label>
                  <div className="flex items-center gap-2">
                    <code className="flex-1 rounded-md bg-muted px-3 py-2 text-xs font-mono break-all">
                      {justCreated.connection.publicUrl}
                    </code>
                    <CopyButton text={justCreated.connection.publicUrl} />
                  </div>
                </div>
              )}
            </div>
          ) : (
            <p className="py-4 text-sm text-muted-foreground">
              Connection info not available yet — the database is still being provisioned.
            </p>
          )}
          <DialogFooter>
            <Button onClick={() => setJustCreated(null)}>Done</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <BackupsDialog
        instanceId={String(id)}
        db={backupsDb}
        onClose={() => setBackupsDb(null)}
        apiBase="/mongo"
        scopes={["full"]}
        uploadAccept=".archive,.gz,.archive.gz"
        uploadNote="Upload a mongodump .archive (optionally gzipped) to restore into this database. Restoring may overwrite existing data."
      />
    </div>
  );
}
