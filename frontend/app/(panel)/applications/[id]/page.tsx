"use client";

import { useEffect, useState } from "react";
import { useParams, useRouter } from "@/compat/navigation";
import useSWR, { mutate } from "swr";
import {
  CheckCircle,
  AlertCircle,
  Loader,
  Trash2,
  Save,
  ExternalLink,
  ArrowLeft,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";
import { Card, CardContent } from "@/components/ui/card";
import { api, fetcher } from "@/lib/api";
import { usePermissions } from "@/lib/permissions";
import { cn } from "@/lib/utils";
import type { Application, ApplicationDef, DeployMode } from "@/lib/types";
import { DEPLOY_MODE_LABEL } from "@/lib/types";
import { toast } from "sonner";

const STATUS_META: Record<
  string,
  { icon: React.ReactNode; label: string; color: string }
> = {
  installed: {
    icon: <CheckCircle className="h-4 w-4" />,
    label: "Installed",
    color: "text-emerald-500",
  },
  failed: {
    icon: <AlertCircle className="h-4 w-4" />,
    label: "Failed",
    color: "text-red-500",
  },
  installing: {
    icon: <Loader className="h-4 w-4 animate-spin" />,
    label: "Installing…",
    color: "text-blue-500",
  },
  updating: {
    icon: <Loader className="h-4 w-4 animate-spin" />,
    label: "Updating…",
    color: "text-blue-500",
  },
  removing: {
    icon: <Loader className="h-4 w-4 animate-spin" />,
    label: "Removing…",
    color: "text-zinc-400",
  },
  pending: {
    icon: <Loader className="h-4 w-4 animate-spin" />,
    label: "Pending…",
    color: "text-zinc-400",
  },
};

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
  const statusMeta = STATUS_META[app?.status ?? ""] ?? {
    icon: null,
    label: app?.status ?? "unknown",
    color: "text-muted-foreground",
  };

  if (isLoading) return <PageSkeleton />;
  if (!app) return null;

  return (
    <div className="container max-w-2xl space-y-6 py-8">
      <div>
        <button
          onClick={() => router.push("/applications")}
          className="mb-4 flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground"
        >
          <ArrowLeft className="h-3.5 w-3.5" />
          Applications
        </button>

        <div className="flex items-start justify-between gap-4">
          <div>
            <h1 className="text-xl font-semibold tracking-tight">
              {app.displayName}
            </h1>
            <p className="mt-0.5 text-sm text-muted-foreground font-mono">
              {app.key}
            </p>
          </div>

          <div className={cn("flex items-center gap-1.5 mt-1", statusMeta.color)}>
            {statusMeta.icon}
            <span className="text-sm font-medium">{statusMeta.label}</span>
          </div>
        </div>

        {app.errorMessage && (
          <div className="mt-3 rounded-md border border-red-500/30 bg-red-500/5 px-3 py-2 text-xs text-red-500">
            {app.errorMessage}
          </div>
        )}

        {def?.docsUrl && (
          <a
            href={def.docsUrl}
            target="_blank"
            rel="noopener noreferrer"
            className="mt-2 inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground"
          >
            <ExternalLink className="h-3 w-3" />
            Documentation
          </a>
        )}

        {def?.description && (
          <p className="mt-3 text-sm text-muted-foreground leading-relaxed">
            {def.description}
          </p>
        )}
      </div>

      <Separator />

      <DefaultsForm
        app={app}
        def={def}
        onSaved={() => mutate(`/applications/${id}`)}
      />

      <Separator />

      <AppsUsingSection applicationId={app.id} />

      <Separator />

      <ApplicationActions app={app} onDone={() => router.push("/applications")} />
    </div>
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
    <div className="space-y-5">
      <h2 className="text-sm font-semibold">Deployment defaults</h2>
      <p className="text-xs text-muted-foreground">
        These seed new Apps created against this Application. Existing Apps
        keep their own configured values.
      </p>

      <div className="space-y-1.5">
        <Label htmlFor="version">Default version</Label>
        <Input
          id="version"
          value={version}
          placeholder={def?.versionHint ?? "e.g. 3.12.4"}
          onChange={(e) => setVersion(e.target.value)}
          disabled={!isSuperuser}
          className="h-8 font-mono"
        />
        {def?.versionHint && (
          <p className="text-xs text-muted-foreground">{def.versionHint}</p>
        )}
      </div>

      {modes.length > 1 && (
        <div className="space-y-1.5">
          <Label htmlFor="deployMode">Default deployment mode</Label>
          <select
            id="deployMode"
            value={deployMode}
            onChange={(e) => setDeployMode(e.target.value as DeployMode)}
            disabled={!isSuperuser}
            className="flex h-8 w-full rounded-md border border-input bg-background px-3 py-1 text-sm ring-offset-background focus:outline-none focus:ring-2 focus:ring-ring"
          >
            {modes.map((m) => (
              <option key={m} value={m}>
                {DEPLOY_MODE_LABEL[m] ?? m}
              </option>
            ))}
          </select>
        </div>
      )}

      <div className="space-y-1.5">
        <Label htmlFor="buildCommand">Default build command</Label>
        <Input
          id="buildCommand"
          value={buildCommand}
          placeholder="leave empty to use the plugin's built-in default"
          onChange={(e) => setBuildCommand(e.target.value)}
          disabled={!isSuperuser}
          className="h-8 font-mono"
        />
      </div>

      <div className="space-y-1.5">
        <Label htmlFor="startCommand">Default start command</Label>
        <Input
          id="startCommand"
          value={startCommand}
          placeholder="leave empty to use the plugin's built-in default"
          onChange={(e) => setStartCommand(e.target.value)}
          disabled={!isSuperuser}
          className="h-8 font-mono"
        />
      </div>

      {isSuperuser && (
        <Button size="sm" disabled={saving} onClick={save}>
          {saving ? (
            <Loader className="h-3.5 w-3.5 animate-spin" />
          ) : (
            <Save className="h-3.5 w-3.5" />
          )}
          Save defaults
        </Button>
      )}
    </div>
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
    <div className="space-y-3">
      <h2 className="text-sm font-semibold">
        Apps using this Application ({inUse.length})
      </h2>
      {inUse.length === 0 ? (
        <p className="text-xs text-muted-foreground">
          No apps reference this Application yet.
        </p>
      ) : (
        <Card>
          <CardContent className="divide-y divide-border p-0">
            {inUse.map((a) => (
              <a
                key={a.id}
                href={`/apps/${a.id}`}
                className="flex items-center justify-between px-4 py-2.5 text-sm hover:bg-accent/40"
              >
                {a.name}
                <Badge variant="secondary" className="text-[10px]">
                  #{a.id}
                </Badge>
              </a>
            ))}
          </CardContent>
        </Card>
      )}
    </div>
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
    <div className="space-y-3">
      <h2 className="text-sm font-semibold">Actions</h2>
      <Button
        size="sm"
        variant="outline"
        className="text-red-500 hover:text-red-600 border-red-500/30 hover:bg-red-500/5"
        disabled={isInProgress || busy}
        onClick={remove}
      >
        {busy ? (
          <Loader className="h-3.5 w-3.5 animate-spin" />
        ) : (
          <Trash2 className="h-3.5 w-3.5" />
        )}
        Remove
      </Button>
      <p className="text-xs text-muted-foreground">
        Blocked while any App still references this Application.
      </p>
    </div>
  );
}

function PageSkeleton() {
  return (
    <div className="container max-w-2xl space-y-6 py-8">
      <div className="h-16 animate-pulse rounded-md bg-card" />
      <Card>
        <CardContent className="space-y-4 py-6">
          {[0, 1, 2, 3].map((i) => (
            <div key={i} className="h-8 animate-pulse rounded bg-muted" />
          ))}
        </CardContent>
      </Card>
    </div>
  );
}
