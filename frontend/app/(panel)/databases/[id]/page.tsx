"use client";

import { useState } from "react";
import { useParams, useRouter } from "@/compat/navigation";
import useSWR, { mutate } from "swr";
import {
  Database,
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

// ── Status helpers ─────────────────────────────────────────────────────────────

const INST_STATUS: Record<
  PgInstanceStatus,
  { icon: React.ReactNode; label: string; color: string }
> = {
  running:      { icon: <CheckCircle className="h-4 w-4 text-emerald-500" />, label: "Running",      color: "text-emerald-600 dark:text-emerald-400" },
  stopped:      { icon: <AlertCircle className="h-4 w-4 text-amber-500"  />, label: "Stopped",      color: "text-amber-600 dark:text-amber-400" },
  failed:       { icon: <AlertCircle className="h-4 w-4 text-red-500"    />, label: "Failed",       color: "text-red-600 dark:text-red-400" },
  pending:      { icon: <Loader      className="h-4 w-4 animate-spin text-blue-500" />, label: "Pending",      color: "text-blue-600" },
  installing:   { icon: <Loader      className="h-4 w-4 animate-spin text-blue-500" />, label: "Installing",   color: "text-blue-600" },
  uninstalling: { icon: <Loader      className="h-4 w-4 animate-spin text-amber-500" />, label: "Removing",    color: "text-amber-600" },
};

const DB_STATUS_BADGE: Record<PgDatabaseStatus, { label: string; variant: "default" | "secondary" | "destructive" | "outline" }> = {
  pending: { label: "Pending", variant: "secondary" },
  active:  { label: "Active",  variant: "outline"   },
  failed:  { label: "Failed",  variant: "destructive" },
  dropped: { label: "Dropped", variant: "secondary" },
};

// ── Copy helper ────────────────────────────────────────────────────────────────

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

// ── Connection string row ──────────────────────────────────────────────────────

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

// ── Main page ─────────────────────────────────────────────────────────────────

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
  const [creating, setCreating]       = useState(false);
  const [createError, setCreateError] = useState("");
  const [justCreated, setJustCreated] = useState<PostgresDatabase | null>(null);
  const [backupsDb, setBackupsDb] = useState<PostgresDatabase | null>(null);

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
        }),
      });
      mutate(dbsKey);
      setShowCreate(false);
      setNewDb(""); setNewRole(""); setNewPass(""); setNewExts("");
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
      {/* Back */}
      <button
        className="flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground transition-colors"
        onClick={() => router.push("/databases")}
      >
        <ArrowLeft className="h-3.5 w-3.5" />
        All instances
      </button>

      {/* Instance header */}
      <div className="flex items-start justify-between gap-4">
        <div className="flex items-center gap-3">
          <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-blue-500/10">
            <Database className="h-6 w-6 text-blue-500" />
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
              {sc.icon} {sc.label} · PostgreSQL {instance.version} · port {instance.port}
            </p>
          </div>
        </div>

        <div className="flex items-center gap-2 flex-wrap justify-end">
          {isSuperuser && !instance.isDefault && isRunning && (
            <Button
              variant="outline"
              size="sm"
              onClick={() => action(`/databases/${id}/set-default`)}
              disabled={!!busy}
            >
              <Star className="mr-1.5 h-3.5 w-3.5" />
              Set default
            </Button>
          )}
          {isSuperuser && instance.status === "stopped" && (
            <Button
              variant="outline"
              size="sm"
              onClick={() => action(`/databases/${id}/start`)}
              disabled={!!busy}
            >
              <Play className="mr-1.5 h-3.5 w-3.5" />
              Start
            </Button>
          )}
          {isSuperuser && isRunning && (
            <Button
              variant="outline"
              size="sm"
              onClick={() => action(`/databases/${id}/stop`)}
              disabled={!!busy}
            >
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
                if (!confirm(`Uninstall PostgreSQL ${instance.version}? All data will be deleted.`)) return;
                await action(`/databases/${id}`, "DELETE");
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

      {/* Metrics */}
      <MetricsPanel id={String(id)} running={isRunning} />

      {/* Databases section */}
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
                    ? "Create a database and role to get started."
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
                          Role: <span className="font-mono">{db.roleName}</span>
                          {db.extensions.length > 0 && (
                            <> · Extensions: {db.extensions.join(", ")}</>
                          )}
                        </p>
                        {db.errorMessage && (
                          <p className="mt-1 text-xs text-destructive">{db.errorMessage}</p>
                        )}
                      </div>
                      <div className="flex items-center gap-2 shrink-0">
                        <Button
                          size="sm"
                          variant="ghost"
                          onClick={() => showConnection(db)}
                          className="h-7 px-2 text-xs"
                        >
                          Connection info
                        </Button>
                        {db.status === "active" && isSuperuser && (
                          <Button
                            size="sm"
                            variant="ghost"
                            onClick={() => setBackupsDb(db)}
                            className="h-7 px-2 text-xs"
                          >
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

      {/* Configuration */}
      <ConfigPanel id={String(id)} running={isRunning} />

      {/* Create database dialog */}
      <Dialog open={showCreate} onOpenChange={setShowCreate}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Create database</DialogTitle>
          </DialogHeader>
          <div className="space-y-4 py-2">
            <div className="space-y-1.5">
              <Label>Database name</Label>
              <Input
                placeholder="myapp_production"
                value={newDb}
                onChange={(e) => setNewDb(e.target.value)}
              />
            </div>
            <div className="space-y-1.5">
              <Label>Role / user</Label>
              <Input
                placeholder="myapp_user"
                value={newRole}
                onChange={(e) => setNewRole(e.target.value)}
              />
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
              <Label>Extensions</Label>
              <Input
                placeholder="uuid-ossp, pg_trgm, postgis"
                value={newExts}
                onChange={(e) => setNewExts(e.target.value)}
              />
              <p className="text-xs text-muted-foreground">
                Comma-separated extension names. Optional.
              </p>
            </div>
            {createError && (
              <p className="text-sm text-destructive">{createError}</p>
            )}
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowCreate(false)}>Cancel</Button>
            <Button onClick={handleCreate} disabled={creating || !newDb || !newRole}>
              {creating && <Loader className="mr-1.5 h-3.5 w-3.5 animate-spin" />}
              Create
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Connection info dialog */}
      <Dialog open={!!justCreated} onOpenChange={() => setJustCreated(null)}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>
              Connection info — {justCreated?.dbName}
            </DialogTitle>
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
                </CardContent>
              </Card>
              <div className="space-y-1.5">
                <Label className="text-xs text-muted-foreground">Connection URL</Label>
                <div className="flex items-center gap-2">
                  <code className="flex-1 rounded-md bg-muted px-3 py-2 text-xs font-mono break-all">
                    {justCreated.connection.url}
                  </code>
                  <CopyButton text={justCreated.connection.url} />
                </div>
              </div>
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

      {/* Backups dialog */}
      <BackupsDialog
        instanceId={String(id)}
        db={backupsDb}
        onClose={() => setBackupsDb(null)}
      />
    </div>
  );
}
