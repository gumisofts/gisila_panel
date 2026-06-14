"use client";

import { useState } from "react";
import Link from "@/compat/link";
import useSWR, { mutate } from "swr";
import {
  Database,
  Plus,
  CheckCircle,
  AlertCircle,
  Loader,
  Star,
  ChevronRight,
  ServerCog,
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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { api, fetcher } from "@/lib/api";
import { usePermissions } from "@/lib/permissions";
import { cn } from "@/lib/utils";
import type { ListResponse, PostgresInstance, PgInstanceStatus } from "@/lib/types";

const SUPPORTED_VERSIONS = [14, 15, 16, 17, 18] as const;

const DEFAULT_PORTS: Record<number, number> = {
  14: 5414, 15: 5415, 16: 5416, 17: 5417, 18: 5418,
};

const STATUS_CONFIG: Record<
  PgInstanceStatus,
  { icon: React.ReactNode; label: string; variant: "default" | "secondary" | "destructive" | "outline" }
> = {
  running:      { icon: <CheckCircle className="h-3.5 w-3.5 text-emerald-500" />, label: "Running",      variant: "outline" },
  stopped:      { icon: <AlertCircle className="h-3.5 w-3.5 text-amber-500"  />, label: "Stopped",      variant: "secondary" },
  failed:       { icon: <AlertCircle className="h-3.5 w-3.5 text-red-500"    />, label: "Failed",       variant: "destructive" },
  pending:      { icon: <Loader      className="h-3.5 w-3.5 animate-spin text-blue-500" />, label: "Pending",  variant: "secondary" },
  installing:   { icon: <Loader      className="h-3.5 w-3.5 animate-spin text-blue-500" />, label: "Installing", variant: "secondary" },
  uninstalling: { icon: <Loader      className="h-3.5 w-3.5 animate-spin text-amber-500" />, label: "Removing", variant: "secondary" },
};

export default function DatabasesPage() {
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
    <div className="mx-auto max-w-4xl space-y-6 p-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold">Databases</h1>
          <p className="mt-0.5 text-sm text-muted-foreground">
            Manage PostgreSQL instances. Each version runs on its own port.
          </p>
        </div>
        {isSuperuser && (
          <Button size="sm" onClick={() => setShowInstall(true)}>
            <Plus className="mr-1.5 h-3.5 w-3.5" />
            Install version
          </Button>
        )}
      </div>

      {/* Instances list */}
      {isLoading ? (
        <p className="text-sm text-muted-foreground">Loading…</p>
      ) : instances.length === 0 ? (
        <Card>
          <CardContent className="flex flex-col items-center gap-3 py-16 text-center">
            <Database className="h-10 w-10 text-muted-foreground/40" />
            <div>
              <p className="font-medium">No PostgreSQL instances yet</p>
              <p className="mt-1 text-sm text-muted-foreground">
                Install a version to get started. Multiple versions can run side-by-side.
              </p>
            </div>
            {isSuperuser && (
              <Button size="sm" onClick={() => setShowInstall(true)}>
                <Plus className="mr-1.5 h-3.5 w-3.5" />
                Install version
              </Button>
            )}
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-3">
          {instances.map((inst) => {
            const sc = STATUS_CONFIG[inst.status] ?? STATUS_CONFIG.stopped;
            return (
              <Link key={inst.id} href={`/databases/${inst.id}`}>
                <Card className="cursor-pointer transition-colors hover:bg-accent/40">
                  <CardContent className="flex items-center gap-4 py-4">
                    <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-blue-500/10">
                      <Database className="h-5 w-5 text-blue-500" />
                    </div>

                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <span className="font-medium truncate">
                          {inst.displayName}
                        </span>
                        {inst.isDefault && (
                          <Badge variant="outline" className="gap-1 text-xs font-normal py-0">
                            <Star className="h-2.5 w-2.5 text-amber-400 fill-amber-400" />
                            Default
                          </Badge>
                        )}
                      </div>
                      <p className="text-sm text-muted-foreground">
                        PostgreSQL {inst.version} · port {inst.port}
                        {inst.dataDirectory ? ` · ${inst.dataDirectory}` : ""}
                      </p>
                    </div>

                    <div className="flex items-center gap-2 shrink-0">
                      <Badge variant={sc.variant} className="gap-1.5">
                        {sc.icon}
                        {sc.label}
                      </Badge>
                      <ChevronRight className="h-4 w-4 text-muted-foreground" />
                    </div>
                  </CardContent>
                </Card>
              </Link>
            );
          })}
        </div>
      )}

      {/* Available versions info */}
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="text-sm font-medium flex items-center gap-2">
            <ServerCog className="h-4 w-4 text-muted-foreground" />
            Available versions
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex flex-wrap gap-2">
            {SUPPORTED_VERSIONS.map((v) => {
              const installed = instances.some((i) => i.version === v);
              return (
                <div
                  key={v}
                  className={cn(
                    "flex items-center gap-1.5 rounded-md border px-3 py-1.5 text-sm",
                    installed
                      ? "border-emerald-500/30 bg-emerald-500/5 text-emerald-600 dark:text-emerald-400"
                      : "border-border text-muted-foreground"
                  )}
                >
                  <Database className="h-3.5 w-3.5" />
                  PostgreSQL {v}
                  {installed && (
                    <CheckCircle className="h-3 w-3 fill-emerald-500 text-white" />
                  )}
                </div>
              );
            })}
          </div>
        </CardContent>
      </Card>

      {/* Install dialog */}
      <Dialog open={showInstall} onOpenChange={setShowInstall}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Install PostgreSQL</DialogTitle>
          </DialogHeader>

          <div className="space-y-4 py-2">
            <div className="space-y-1.5">
              <Label>Version</Label>
              <Select value={version} onValueChange={(v) => {
                setVersion(v);
                setPort(String(DEFAULT_PORTS[Number(v)] ?? ""));
              }}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {SUPPORTED_VERSIONS.map((v) => (
                    <SelectItem key={v} value={String(v)}>
                      PostgreSQL {v}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-1.5">
              <Label>Display name</Label>
              <Input
                placeholder={`PostgreSQL ${version}`}
                value={displayName}
                onChange={(e) => setDisplayName(e.target.value)}
              />
            </div>

            <div className="space-y-1.5">
              <Label>Port</Label>
              <Input
                type="number"
                placeholder={String(DEFAULT_PORTS[Number(version)] ?? 5432)}
                value={port}
                onChange={(e) => setPort(e.target.value)}
              />
              <p className="text-xs text-muted-foreground">
                Each version must use a unique port. Default shown above.
              </p>
            </div>

            {installError && (
              <p className="text-sm text-destructive">{installError}</p>
            )}
          </div>

          <DialogFooter>
            <Button variant="outline" onClick={() => setShowInstall(false)}>
              Cancel
            </Button>
            <Button onClick={handleInstall} disabled={installing}>
              {installing ? (
                <Loader className="mr-1.5 h-3.5 w-3.5 animate-spin" />
              ) : (
                <Plus className="mr-1.5 h-3.5 w-3.5" />
              )}
              Install
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
