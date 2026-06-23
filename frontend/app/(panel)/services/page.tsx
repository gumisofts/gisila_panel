"use client";

import { useState } from "react";
import Link from "@/compat/link";
import useSWR, { mutate } from "swr";
import {
  Database,
  Mail,
  LayoutGrid,
  Network,
  CheckCircle,
  AlertCircle,
  Loader,
  Plus,
  ExternalLink,
  ArrowRight,
  ServerCog,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { api, fetcher } from "@/lib/api";
import { usePermissions } from "@/lib/permissions";
import { cn } from "@/lib/utils";
import type { ListResponse, ManagedService, ServiceDef } from "@/lib/types";

// ── Helpers ───────────────────────────────────────────────────────────────────

const STATUS_ICON: Record<string, React.ReactNode> = {
  running:      <CheckCircle className="h-3.5 w-3.5 text-emerald-500" />,
  config_only:  <CheckCircle className="h-3.5 w-3.5 text-emerald-500" />,
  stopped:      <AlertCircle className="h-3.5 w-3.5 text-amber-500" />,
  failed:       <AlertCircle className="h-3.5 w-3.5 text-red-500" />,
  installing:   <Loader className="h-3.5 w-3.5 animate-spin text-blue-500" />,
  uninstalling: <Loader className="h-3.5 w-3.5 animate-spin text-zinc-400" />,
  pending:      <Loader className="h-3.5 w-3.5 animate-spin text-zinc-400" />,
};

const STATUS_LABEL: Record<string, string> = {
  running:      "Running",
  config_only:  "Active",
  stopped:      "Stopped",
  failed:       "Failed",
  installing:   "Installing…",
  uninstalling: "Removing…",
  pending:      "Pending…",
};

const CATEGORY_ICON: Record<string, React.ReactNode> = {
  cache: <Database className="h-4 w-4" />,
  email: <Mail className="h-4 w-4" />,
  queue: <LayoutGrid className="h-4 w-4" />,
  database: <Network className="h-4 w-4" />,
};

const CATEGORY_COLOR: Record<string, string> = {
  cache: "bg-violet-500/10 text-violet-500",
  email: "bg-blue-500/10 text-blue-500",
  queue: "bg-amber-500/10 text-amber-500",
  database: "bg-emerald-500/10 text-emerald-500",
};

const SERVICE_CATEGORY: Record<string, string> = {
  redis: "cache", memcached: "cache",
  smtp: "email", mailpit: "email",
  pgbouncer: "database",
};

/** Pull the most useful config key-values to surface on the card, driven by the
 *  catalog [def] (its summaryKeys + field labels). Falls back to the first few
 *  config values when the def is unavailable. */
function summaryFields(
  config: Record<string, string>,
  def?: ServiceDef,
): { label: string; value: string }[] {
  const pairs: { label: string; value: string }[] = [];

  if (def && def.summaryKeys && def.summaryKeys.length > 0) {
    for (const key of def.summaryKeys) {
      const v = config[key];
      if (!v) continue;
      const field = def.configSchema.find((f) => f.key === key);
      pairs.push({
        label: field?.label ?? key,
        value: field?.secret ? "••••••••" : v,
      });
    }
  } else {
    // No summaryKeys declared — show the first few non-empty values generically.
    for (const [k, v] of Object.entries(config).slice(0, 3)) {
      if (v) pairs.push({ label: k, value: v });
    }
  }

  return pairs.slice(0, 4);
}

// ── Page ─────────────────────────────────────────────────────────────────────

export default function ServicesPage() {
  const { data: catalogData } = useSWR<ListResponse<ServiceDef>>(
    "/services/catalog",
    fetcher,
  );
  const { data: installedData, isLoading } = useSWR<
    ListResponse<ManagedService>
  >("/services/", fetcher, { refreshInterval: 4000 });

  const catalog  = catalogData?.results  ?? [];
  const installed = installedData?.results ?? [];

  // Map service type → installed service (one per type enforced by backend).
  const installedByType = new Map(installed.map((s) => [s.serviceType, s]));
  // Map service type → catalog def, so installed cards render generically.
  const defsByType = new Map(catalog.map((d) => [d.type, d]));

  return (
    <div className="mx-auto max-w-4xl space-y-8 p-6">
      {/* ── Installed ────────────────────────────────────────────────────────── */}
      <section>
        <header className="mb-4">
          <h1 className="text-xl font-semibold">Services</h1>
          <p className="mt-0.5 text-sm text-muted-foreground">
            Host-level services managed by your panel.
          </p>
        </header>

        {isLoading ? (
          <SkeletonRow />
        ) : installed.length === 0 ? (
          <Card>
            <CardContent className="py-10 text-center text-sm text-muted-foreground">
              No services installed yet — pick one from the catalog below.
            </CardContent>
          </Card>
        ) : (
          <div className="grid gap-3 sm:grid-cols-2">
            {installed.map((svc) => (
              <InstalledCard key={svc.id} svc={svc} def={defsByType.get(svc.serviceType)} />
            ))}
          </div>
        )}
      </section>

      {/* ── Catalog ──────────────────────────────────────────────────────────── */}
      <section>
        <h2 className="mb-4 flex items-center gap-2 text-sm font-semibold text-foreground/80">
          <ServerCog className="h-4 w-4 text-muted-foreground" />
          Available services
        </h2>
        <div className="grid gap-3 sm:grid-cols-2">
          {catalog.map((def) => (
            <CatalogCard
              key={def.type}
              def={def}
              installed={installedByType.get(def.type)}
            />
          ))}
        </div>
      </section>
    </div>
  );
}

// ── Installed card ────────────────────────────────────────────────────────────

function InstalledCard({ svc, def }: { svc: ManagedService; def?: ServiceDef }) {
  const config: Record<string, string> = (() => {
    try { return JSON.parse(svc.config) as Record<string, string>; }
    catch { return {}; }
  })();

  const details = summaryFields(config, def);
  const statusLabel = STATUS_LABEL[svc.status] ?? svc.status;
  const category = def?.category ?? SERVICE_CATEGORY[svc.serviceType] ?? "";

  return (
    <Link
      href={`/services/${svc.id}`}
      className="group flex flex-col gap-3 rounded-lg border border-border bg-card p-4 transition-colors hover:border-primary/40 hover:bg-accent/30"
    >
      {/* Header row */}
      <div className="flex items-start justify-between gap-2">
        <div className="flex items-center gap-2.5">
          <div className={cn(
            "flex h-8 w-8 shrink-0 items-center justify-center rounded-md",
            CATEGORY_COLOR[category] ?? "bg-muted text-muted-foreground",
          )}>
            {CATEGORY_ICON[category] ?? <ServerCog className="h-4 w-4" />}
          </div>
          <div>
            <p className="text-sm font-medium leading-tight">{svc.displayName}</p>
            <p className="text-[11px] text-muted-foreground font-mono">{svc.serviceType}</p>
          </div>
        </div>

        <div className="flex items-center gap-1.5 shrink-0">
          {STATUS_ICON[svc.status] ?? null}
          <span className={cn(
            "text-xs font-medium",
            svc.status === "running" || svc.status === "config_only"
              ? "text-emerald-600 dark:text-emerald-400"
              : svc.status === "failed"
              ? "text-red-500"
              : svc.status === "stopped"
              ? "text-amber-500"
              : "text-muted-foreground",
          )}>
            {statusLabel}
          </span>
        </div>
      </div>

      {/* Config summary */}
      {details.length > 0 && (
        <div className="grid grid-cols-2 gap-x-4 gap-y-1 rounded-md bg-muted/50 px-3 py-2">
          {details.map(({ label, value }) => (
            <div key={label} className="flex items-baseline gap-1.5 min-w-0">
              <span className="text-[10px] uppercase tracking-wider text-muted-foreground shrink-0">
                {label}
              </span>
              <span className="text-xs font-mono font-medium truncate">{value}</span>
            </div>
          ))}
        </div>
      )}

      {svc.errorMessage && (
        <p className="truncate text-xs text-red-500">{svc.errorMessage}</p>
      )}

      {/* Footer */}
      <div className="flex items-center justify-between pt-0.5">
        {svc.installedAt ? (
          <span className="text-[10px] text-muted-foreground">
            Installed {new Date(svc.installedAt).toLocaleDateString()}
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
  def: ServiceDef;
  installed?: ManagedService;
}) {
  const [installing, setInstalling] = useState(false);
  const [error, setError] = useState("");
  const { isSuperuser } = usePermissions();

  const isInstalled = !!installed;

  async function quickInstall() {
    if (isInstalled || installing) return;
    setError("");
    setInstalling(true);
    try {
      await api("/services/", {
        method: "POST",
        body: JSON.stringify({
          serviceType: def.type,
          displayName: def.name,
          config: {},
        }),
      });
      mutate("/services/");
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Install failed.");
    } finally {
      setInstalling(false);
    }
  }

  return (
    <div className={cn(
      "flex flex-col gap-3 rounded-lg border border-border bg-card p-4 transition-colors",
      isInstalled && "border-emerald-500/30 bg-emerald-500/5 dark:bg-emerald-500/[0.03]",
    )}>
      {/* Header */}
      <div className="flex items-start justify-between gap-3">
        <div className="flex items-center gap-2.5">
          <div className={cn(
            "flex h-8 w-8 shrink-0 items-center justify-center rounded-md",
            CATEGORY_COLOR[def.category] ?? "bg-muted text-muted-foreground",
          )}>
            {CATEGORY_ICON[def.category]}
          </div>
          <div>
            <p className="text-sm font-medium">{def.name}</p>
            <Badge variant="secondary" className="mt-0.5 text-[10px] capitalize font-normal">
              {def.category}
            </Badge>
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

      {error && <p className="text-xs text-red-500">{error}</p>}

      {/* Footer */}
      <div className="flex items-center justify-between pt-0.5">
        <span className="text-[10px] text-muted-foreground uppercase tracking-wider">
          {def.requiresInstall ? "apt + systemd" : "config only"}
        </span>

        {isInstalled ? (
          <Link
            href={`/services/${installed.id}`}
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
            {def.requiresInstall ? "Install" : "Configure"}
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
