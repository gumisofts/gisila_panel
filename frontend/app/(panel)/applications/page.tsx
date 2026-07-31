"use client";

import { useState } from "react";
import Link from "@/compat/link";
import useSWR, { mutate } from "swr";
import {
  Blocks,
  CheckCircle,
  AlertCircle,
  Loader,
  Plus,
  ExternalLink,
  ArrowRight,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { api, fetcher } from "@/lib/api";
import { usePermissions } from "@/lib/permissions";
import { cn } from "@/lib/utils";
import type {
  Application,
  ApplicationDef,
  DeployMode,
  ListResponse,
} from "@/lib/types";
import { DEPLOY_MODE_LABEL } from "@/lib/types";
import { toast } from "sonner";

// ── Helpers ───────────────────────────────────────────────────────────────────

const STATUS_ICON: Record<string, React.ReactNode> = {
  installed: <CheckCircle className="h-3.5 w-3.5 text-emerald-500" />,
  failed: <AlertCircle className="h-3.5 w-3.5 text-red-500" />,
  installing: <Loader className="h-3.5 w-3.5 animate-spin text-blue-500" />,
  updating: <Loader className="h-3.5 w-3.5 animate-spin text-blue-500" />,
  removing: <Loader className="h-3.5 w-3.5 animate-spin text-zinc-400" />,
  pending: <Loader className="h-3.5 w-3.5 animate-spin text-zinc-400" />,
};

const STATUS_LABEL: Record<string, string> = {
  installed: "Installed",
  failed: "Failed",
  installing: "Installing…",
  updating: "Updating…",
  removing: "Removing…",
  pending: "Pending…",
  disabled: "Disabled",
};

// ── Page ─────────────────────────────────────────────────────────────────────

export default function ApplicationsPage() {
  const { data: catalogData } = useSWR<ListResponse<ApplicationDef>>(
    "/applications/catalog",
    fetcher,
  );
  const { data: installedData, isLoading } = useSWR<ListResponse<Application>>(
    "/applications/",
    fetcher,
    { refreshInterval: 4000 },
  );

  const catalog = catalogData?.results ?? [];
  const installed = installedData?.results ?? [];

  const installedByKey = new Map(installed.map((a) => [a.key, a]));

  return (
    <div className="mx-auto max-w-4xl space-y-8 p-6">
      {/* ── Installed ────────────────────────────────────────────────────────── */}
      <section>
        <header className="mb-4">
          <h1 className="text-xl font-semibold">Applications</h1>
          <p className="mt-0.5 text-sm text-muted-foreground">
            Runtime &amp; language stacks (Python, Dart, Node, …) managed
            independently of the panel. Apps pick one of these as their
            deployment target.
          </p>
        </header>

        {isLoading ? (
          <SkeletonRow />
        ) : installed.length === 0 ? (
          <Card>
            <CardContent className="py-10 text-center text-sm text-muted-foreground">
              No Applications installed yet — pick one from the catalog below.
            </CardContent>
          </Card>
        ) : (
          <div className="grid gap-3 sm:grid-cols-2">
            {installed.map((app) => (
              <InstalledCard key={app.id} app={app} />
            ))}
          </div>
        )}
      </section>

      {/* ── Catalog ──────────────────────────────────────────────────────────── */}
      <section>
        <h2 className="mb-4 flex items-center gap-2 text-sm font-semibold text-foreground/80">
          <Blocks className="h-4 w-4 text-muted-foreground" />
          Available Applications
        </h2>
        <div className="grid gap-3 sm:grid-cols-2">
          {catalog.map((def) => (
            <CatalogCard
              key={def.key}
              def={def}
              installed={installedByKey.get(def.key)}
            />
          ))}
        </div>
      </section>
    </div>
  );
}

// ── Installed card ────────────────────────────────────────────────────────────

function InstalledCard({ app }: { app: Application }) {
  const statusLabel = STATUS_LABEL[app.status] ?? app.status;
  const modes = app.deployModes.split(",").filter(Boolean) as DeployMode[];

  return (
    <Link
      href={`/applications/${app.id}`}
      className="group flex flex-col gap-3 rounded-lg border border-border bg-card p-4 transition-colors hover:border-primary/40 hover:bg-accent/30"
    >
      <div className="flex items-start justify-between gap-2">
        <div className="flex items-center gap-2.5">
          <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-md bg-primary/10 text-primary">
            <Blocks className="h-4 w-4" />
          </div>
          <div>
            <p className="text-sm font-medium leading-tight">{app.displayName}</p>
            <p className="text-[11px] text-muted-foreground font-mono">{app.key}</p>
          </div>
        </div>

        <div className="flex items-center gap-1.5 shrink-0">
          {STATUS_ICON[app.status] ?? null}
          <span
            className={cn(
              "text-xs font-medium",
              app.status === "installed"
                ? "text-emerald-600 dark:text-emerald-400"
                : app.status === "failed"
                  ? "text-red-500"
                  : "text-muted-foreground",
            )}
          >
            {statusLabel}
          </span>
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-1.5">
        {modes.map((m) => (
          <Badge key={m} variant="secondary" className="text-[10px] font-normal">
            {DEPLOY_MODE_LABEL[m] ?? m}
          </Badge>
        ))}
        {app.defaultVersion && (
          <Badge variant="muted" className="text-[10px] font-mono font-normal">
            {app.defaultVersion}
          </Badge>
        )}
      </div>

      {app.errorMessage && (
        <p className="truncate text-xs text-red-500">{app.errorMessage}</p>
      )}

      <div className="flex items-center justify-between pt-0.5">
        {app.installedAt ? (
          <span className="text-[10px] text-muted-foreground">
            Installed {new Date(app.installedAt).toLocaleDateString()}
          </span>
        ) : (
          <span />
        )}
        <span className="flex items-center gap-1 text-xs text-muted-foreground group-hover:text-foreground transition-colors">
          Configure
          <ArrowRight className="h-3 w-3" />
        </span>
      </div>
    </Link>
  );
}

// ── Catalog card ──────────────────────────────────────────────────────────────

function CatalogCard({
  def,
  installed,
}: {
  def: ApplicationDef;
  installed?: Application;
}) {
  const [installing, setInstalling] = useState(false);
  const { isSuperuser } = usePermissions();

  const isInstalled = !!installed;

  async function quickInstall() {
    if (isInstalled || installing) return;
    setInstalling(true);
    try {
      await api("/applications/", {
        method: "POST",
        body: JSON.stringify({ key: def.key }),
      });
      mutate("/applications/");
      toast.success(`${def.displayName} install queued.`);
    } catch (e: unknown) {
      toast.error(e instanceof Error ? e.message : "Install failed.");
    } finally {
      setInstalling(false);
    }
  }

  return (
    <div
      className={cn(
        "flex flex-col gap-3 rounded-lg border border-border bg-card p-4 transition-colors",
        isInstalled &&
          "border-emerald-500/30 bg-emerald-500/5 dark:bg-emerald-500/[0.03]",
      )}
    >
      <div className="flex items-start justify-between gap-3">
        <div className="flex items-center gap-2.5">
          <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-md bg-muted text-muted-foreground">
            <Blocks className="h-4 w-4" />
          </div>
          <div>
            <p className="text-sm font-medium">{def.displayName}</p>
            <div className="mt-0.5 flex flex-wrap gap-1">
              {def.deployModes.map((m) => (
                <Badge key={m} variant="secondary" className="text-[10px] font-normal">
                  {DEPLOY_MODE_LABEL[m] ?? m}
                </Badge>
              ))}
            </div>
          </div>
        </div>

        {def.docsUrl && (
          <a
            href={def.docsUrl}
            target="_blank"
            rel="noopener noreferrer"
            className="text-muted-foreground hover:text-foreground transition-colors"
            onClick={(e) => e.stopPropagation()}
          >
            <ExternalLink className="h-3.5 w-3.5" />
          </a>
        )}
      </div>

      <p className="text-xs text-muted-foreground leading-relaxed">
        {def.description}
      </p>

      <div className="flex items-center justify-between pt-0.5">
        <span className="text-[10px] text-muted-foreground uppercase tracking-wider">
          {def.versionHint ?? "no version pin"}
        </span>

        {isInstalled ? (
          <Link
            href={`/applications/${installed.id}`}
            className="flex items-center gap-1 text-xs font-medium text-emerald-600 dark:text-emerald-400 hover:underline"
          >
            <CheckCircle className="h-3 w-3" />
            Installed · View
            <ArrowRight className="h-3 w-3" />
          </Link>
        ) : isSuperuser ? (
          <Button
            size="sm"
            variant="outline"
            className="h-7 text-xs"
            disabled={installing}
            onClick={quickInstall}
          >
            {installing ? (
              <Loader className="h-3 w-3 animate-spin" />
            ) : (
              <Plus className="h-3 w-3" />
            )}
            Install
          </Button>
        ) : null}
      </div>
    </div>
  );
}

function SkeletonRow() {
  return (
    <div className="grid gap-3 sm:grid-cols-2">
      {[0, 1, 2].map((i) => (
        <div
          key={i}
          className="h-28 animate-pulse rounded-lg border border-border bg-card/40"
        />
      ))}
    </div>
  );
}
