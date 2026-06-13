"use client";

import { useState, useEffect } from "react";
import useSWR from "swr";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
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
import { cn } from "@/lib/utils";
import type { App, SshKey } from "@/lib/types";

const PYTHON_VERSIONS = [
  "3.13.2", "3.13.1", "3.13.0",
  "3.12.9", "3.12.8", "3.12.4",
  "3.11.11", "3.11.9",
  "3.10.16",
];

const NODE_VERSIONS = [
  // Active LTS "Krypton" — recommended default
  "24.16.0", "24.15.0", "24.14.1",
  // LTS "Jod" (22.13+ is required by pnpm 11)
  "22.22.3", "22.20.0", "22.13.0", "22.12.0",
  // LTS "Iron"
  "20.20.2", "20.19.6", "20.18.1",
  // Current line — newest features, shorter support window
  "26.3.0",
  // Legacy (EOL upstream) — kept for older apps
  "18.20.8",
];

const DART_VERSIONS = [
  "3.5.4", "3.5.3", "3.4.4", "3.4.3", "3.3.4", "3.3.3", "3.2.6", "3.1.5",
];

const GO_VERSIONS = [
  "1.23.4", "1.23.3", "1.23.2", "1.22.10", "1.22.9", "1.22.8", "1.21.13",
];

const RUST_VERSIONS = [
  "stable", "1.83.0", "1.82.0", "1.81.0", "1.80.1", "1.79.0", "nightly",
];

const BUN_VERSIONS = [
  "1.1.38", "1.1.34", "1.1.30", "1.1.21", "1.1.13", "1.0.36",
];

export function SettingsTab({
  app,
  onSaved,
}: {
  app: App;
  onSaved: () => void;
}) {
  const sshKeys = useSWR<{ results: SshKey[] }>("/me/security/ssh-keys", fetcher);

  const [form, setForm] = useState({
    name: app.name,
    gitUrl: app.gitUrl ?? "",
    gitBranch: app.gitBranch ?? "",
    buildCommand: app.buildCommand ?? "",
    startCommand: app.startCommand ?? "",
    healthCheckPath: app.healthCheckPath ?? "",
    memoryMbLimit: app.memoryMbLimit,
    cpuQuotaPercent: app.cpuQuotaPercent,
    tasksLimit: app.tasksLimit,
    pythonVersion: app.pythonVersion ?? "3.12.4",
    pythonMode: app.pythonMode ?? "wsgi",
    wsgiApp: app.wsgiApp ?? "",
    gunicornWorkers: app.gunicornWorkers != null ? String(app.gunicornWorkers) : "",
    gunicornThreads: app.gunicornThreads != null ? String(app.gunicornThreads) : "",
    gunicornTimeout: app.gunicornTimeout != null ? String(app.gunicornTimeout) : "",
    gunicornBind: app.gunicornBind ?? "",
    gunicornExtraArgs: app.gunicornExtraArgs ?? "",
    // Runtime version pins
    nodeVersion: app.nodeVersion ?? NODE_VERSIONS[0],
    dartVersion: app.dartVersion ?? DART_VERSIONS[0],
    goVersion: app.goVersion ?? GO_VERSIONS[0],
    rustVersion: app.rustVersion ?? RUST_VERSIONS[0],
    bunVersion: app.bunVersion ?? BUN_VERSIONS[0],
    // Celery
    celeryApp: app.celeryApp ?? "",
    celeryWorkerCount: app.celeryWorkerCount != null ? String(app.celeryWorkerCount) : "2",
    celeryConcurrency: app.celeryConcurrency != null ? String(app.celeryConcurrency) : "4",
    celeryQueues: app.celeryQueues ?? "",
    celeryBeatEnabled: app.celeryBeatEnabled ?? false,
    celeryExtraArgs: app.celeryExtraArgs ?? "",
    // Static
    staticRoot: app.staticRoot ?? "",
    staticSpa: app.staticSpa ?? false,
    deployKeyId: app.deployKeyId ? String(app.deployKeyId) : "",
    internalPort: app.internalPort != null ? String(app.internalPort) : "",
  });
  const [saving, setSaving] = useState(false);

  // Keep form in sync if SWR refreshes the app
  useEffect(() => {
    setForm({
      name: app.name,
      gitUrl: app.gitUrl ?? "",
      gitBranch: app.gitBranch ?? "",
      buildCommand: app.buildCommand ?? "",
      startCommand: app.startCommand ?? "",
      healthCheckPath: app.healthCheckPath ?? "",
      memoryMbLimit: app.memoryMbLimit,
      cpuQuotaPercent: app.cpuQuotaPercent,
      tasksLimit: app.tasksLimit,
      pythonVersion: app.pythonVersion ?? "3.12.4",
      pythonMode: app.pythonMode ?? "wsgi",
      wsgiApp: app.wsgiApp ?? "",
      gunicornWorkers: app.gunicornWorkers != null ? String(app.gunicornWorkers) : "",
      gunicornThreads: app.gunicornThreads != null ? String(app.gunicornThreads) : "",
      gunicornTimeout: app.gunicornTimeout != null ? String(app.gunicornTimeout) : "",
      gunicornBind: app.gunicornBind ?? "",
      gunicornExtraArgs: app.gunicornExtraArgs ?? "",
      nodeVersion: app.nodeVersion ?? NODE_VERSIONS[0],
      dartVersion: app.dartVersion ?? DART_VERSIONS[0],
      goVersion: app.goVersion ?? GO_VERSIONS[0],
      rustVersion: app.rustVersion ?? RUST_VERSIONS[0],
      bunVersion: app.bunVersion ?? BUN_VERSIONS[0],
      celeryApp: app.celeryApp ?? "",
      celeryWorkerCount: app.celeryWorkerCount != null ? String(app.celeryWorkerCount) : "2",
      celeryConcurrency: app.celeryConcurrency != null ? String(app.celeryConcurrency) : "4",
      celeryQueues: app.celeryQueues ?? "",
      celeryBeatEnabled: app.celeryBeatEnabled ?? false,
      celeryExtraArgs: app.celeryExtraArgs ?? "",
      staticRoot: app.staticRoot ?? "",
      staticSpa: app.staticSpa ?? false,
      deployKeyId: app.deployKeyId ? String(app.deployKeyId) : "",
      internalPort: app.internalPort != null ? String(app.internalPort) : "",
    });
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [app.id]);

  function set<K extends keyof typeof form>(k: K, v: (typeof form)[K]) {
    setForm((f) => ({ ...f, [k]: v }));
  }

  const isPython = app.runtime === "python";
  const isCelery = app.runtime === "celery";
  const isStatic = app.runtime === "static";
  const isBinary = app.sourceType === "binary";
  const isGit    = app.sourceType === "git";
  const isNode   = app.runtime === "node";
  const isBun    = app.runtime === "bun";
  const isDart   = app.runtime === "dart";
  const isGo     = app.runtime === "go";
  const isRust   = app.runtime === "rust";

  async function save(e: React.FormEvent) {
    e.preventDefault();
    setSaving(true);
    try {
      const patch: Record<string, unknown> = {
        name: form.name,
        gitUrl: form.gitUrl || undefined,
        gitBranch: form.gitBranch || undefined,
        buildCommand: form.buildCommand || undefined,
        startCommand: form.startCommand || undefined,
        healthCheckPath: form.healthCheckPath || undefined,
        memoryMbLimit: form.memoryMbLimit,
        cpuQuotaPercent: form.cpuQuotaPercent,
        tasksLimit: form.tasksLimit,
      };
      if (isPython) {
        patch.pythonVersion = form.pythonVersion;
        patch.pythonMode = form.pythonMode;
        patch.wsgiApp = form.wsgiApp || undefined;
        patch.gunicornWorkers = form.gunicornWorkers
          ? Number(form.gunicornWorkers)
          : undefined;
        patch.gunicornThreads = form.gunicornThreads
          ? Number(form.gunicornThreads)
          : undefined;
        patch.gunicornTimeout = form.gunicornTimeout
          ? Number(form.gunicornTimeout)
          : undefined;
        patch.gunicornBind = form.gunicornBind || undefined;
        patch.gunicornExtraArgs = form.gunicornExtraArgs || undefined;
      }
      if (isCelery) {
        patch.pythonVersion     = form.pythonVersion || undefined;
        patch.celeryApp         = form.celeryApp || undefined;
        patch.celeryWorkerCount = form.celeryWorkerCount ? Number(form.celeryWorkerCount) : undefined;
        patch.celeryConcurrency = form.celeryConcurrency ? Number(form.celeryConcurrency) : undefined;
        patch.celeryQueues      = form.celeryQueues || undefined;
        patch.celeryBeatEnabled = form.celeryBeatEnabled;
        patch.celeryExtraArgs   = form.celeryExtraArgs || undefined;
      }
      if (isNode)  patch.nodeVersion = form.nodeVersion || undefined;
      if (isBun)   patch.bunVersion  = form.bunVersion  || undefined;
      if (isDart)  patch.dartVersion = form.dartVersion || undefined;
      if (isGo)    patch.goVersion   = form.goVersion   || undefined;
      if (isRust)  patch.rustVersion = form.rustVersion || undefined;
      if (isStatic) {
        patch.staticRoot = form.staticRoot || undefined;
        patch.staticSpa  = form.staticSpa;
      }
      if (isGit) {
        patch.deployKeyId = form.deployKeyId ? Number(form.deployKeyId) : undefined;
      }
      if (form.internalPort) {
        patch.internalPort = Number(form.internalPort);
      }
      await api(`/apps/${app.id}`, { method: "PATCH", body: JSON.stringify(patch) });
      toast.success("App settings saved");
      onSaved();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed to save");
    } finally {
      setSaving(false);
    }
  }

  return (
    <form onSubmit={save} className="space-y-6 max-w-2xl">
      {/* General */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">General</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div>
            <Label htmlFor="s-name">App name</Label>
            <Input
              id="s-name"
              className="mt-1"
              value={form.name}
              onChange={(e) => set("name", e.target.value)}
              required
            />
          </div>
          <div>
            <Label htmlFor="s-port">Internal port</Label>
            <Input
              id="s-port"
              className="mt-1"
              type="number"
              min={1024}
              max={65535}
              value={form.internalPort}
              onChange={(e) => set("internalPort", e.target.value)}
              placeholder="e.g. 8080"
            />
            <p className="mt-1 text-xs text-muted-foreground">
              The port your app listens on. Changing this requires a redeploy.
            </p>
          </div>
        </CardContent>
      </Card>

      {/* Source */}
      {!isBinary && !isStatic && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">
              Source
              <span className="ml-2 text-xs font-normal text-muted-foreground capitalize">
                ({app.sourceType})
              </span>
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            {isGit && (
              <>
                <div className="grid gap-4 sm:grid-cols-2">
                  <div>
                    <Label htmlFor="s-git-url">Git URL</Label>
                    <Input
                      id="s-git-url"
                      className="mt-1 font-mono text-sm"
                      placeholder="git@github.com:you/repo.git"
                      value={form.gitUrl}
                      onChange={(e) => set("gitUrl", e.target.value)}
                    />
                  </div>
                  <div>
                    <Label htmlFor="s-git-branch">Branch</Label>
                    <Input
                      id="s-git-branch"
                      className="mt-1 font-mono text-sm"
                      value={form.gitBranch}
                      onChange={(e) => set("gitBranch", e.target.value)}
                    />
                  </div>
                </div>
                <div>
                  <Label htmlFor="s-deploy-key">
                    Deploy key
                    <span className="ml-1.5 text-[10px] font-normal text-muted-foreground">
                      (optional — for private repos)
                    </span>
                  </Label>
                  <Select
                    value={form.deployKeyId || "none"}
                    onValueChange={(v) => set("deployKeyId", v === "none" ? "" : v)}
                  >
                    <SelectTrigger id="s-deploy-key" className="mt-1">
                      <SelectValue placeholder="None (public repo / HTTPS)" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="none">None (public repo / HTTPS)</SelectItem>
                      {(sshKeys.data?.results ?? []).map((k) => (
                        <SelectItem key={k.id} value={String(k.id)}>
                          {k.name}
                          {k.algorithm && (
                            <span className="ml-2 text-xs text-muted-foreground">
                              ({k.algorithm})
                            </span>
                          )}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              </>
            )}
            <div className="grid gap-4 sm:grid-cols-2">
              <div>
                <Label htmlFor="s-build">
                  Build command
                  <span className="ml-1 text-[10px] text-muted-foreground">(optional)</span>
                </Label>
                <Input
                  id="s-build"
                  className="mt-1 font-mono text-sm"
                  placeholder={
                    isPython || isCelery
                      ? "pip install -r requirements.txt"
                      : "dart compile exe bin/server.dart -o build/app"
                  }
                  value={form.buildCommand}
                  onChange={(e) => set("buildCommand", e.target.value)}
                />
                {(isPython || isCelery) && (
                  <p className="mt-1 text-xs text-muted-foreground">
                    Leave blank — dependencies from <code className="font-mono">requirements.txt</code> are installed automatically.
                  </p>
                )}
              </div>
              <div>
                <Label htmlFor="s-start">
                  Start command
                  <span className="ml-1 text-[10px] text-muted-foreground">(optional)</span>
                </Label>
                <Input
                  id="s-start"
                  className="mt-1 font-mono text-sm"
                  placeholder={
                    isPython
                      ? "Auto-generated gunicorn command"
                      : isCelery
                        ? "Auto-generated from Celery settings below"
                        : "./current/app"
                  }
                  disabled={isCelery}
                  value={form.startCommand}
                  onChange={(e) => set("startCommand", e.target.value)}
                />
              </div>
            </div>
            <div>
              <Label htmlFor="s-health">
                Health check path
                <span className="ml-1 text-[10px] text-muted-foreground">(optional)</span>
              </Label>
              <Input
                id="s-health"
                className="mt-1 font-mono text-sm"
                placeholder="/health"
                value={form.healthCheckPath}
                onChange={(e) => set("healthCheckPath", e.target.value)}
              />
            </div>
          </CardContent>
        </Card>
      )}

      {/* Python */}
      {isPython && (
        <Card className="border-blue-500/30 bg-blue-500/5">
          <CardHeader>
            <CardTitle className="text-base">Python / WSGI · ASGI</CardTitle>
          </CardHeader>
          <CardContent className="space-y-5">
            <div>
              <Label className="mb-2 block">Python version</Label>
              <div className="flex flex-wrap gap-1.5">
                {PYTHON_VERSIONS.map((v) => (
                  <button
                    key={v}
                    type="button"
                    onClick={() => set("pythonVersion", v)}
                    className={cn(
                      "rounded-md border px-2.5 py-1 font-mono text-xs transition-colors",
                      form.pythonVersion === v
                        ? "border-blue-500 bg-blue-500/10 text-blue-600 dark:text-blue-400"
                        : "border-border bg-card text-muted-foreground hover:border-blue-500/40"
                    )}
                  >
                    {v}
                  </button>
                ))}
              </div>
            </div>
            <div>
              <Label className="mb-2 block">Server mode</Label>
              <div className="grid grid-cols-2 gap-2">
                {[
                  { id: "wsgi", label: "WSGI", desc: "Django, Flask — synchronous" },
                  { id: "asgi", label: "ASGI", desc: "FastAPI, Starlette — async" },
                ].map(({ id, label, desc }) => (
                  <button
                    key={id}
                    type="button"
                    onClick={() => set("pythonMode", id as "wsgi" | "asgi")}
                    className={cn(
                      "flex flex-col items-start rounded-md border p-3 text-left transition-colors",
                      form.pythonMode === id
                        ? "border-blue-500 bg-blue-500/10"
                        : "border-border bg-card hover:border-blue-500/40"
                    )}
                  >
                    <span className="text-sm font-medium">{label}</span>
                    <span className="mt-0.5 text-xs text-muted-foreground">{desc}</span>
                  </button>
                ))}
              </div>
            </div>
            <div>
              <Label htmlFor="s-wsgi">Application target</Label>
              <Input
                id="s-wsgi"
                className="mt-1 font-mono text-sm"
                placeholder={form.pythonMode === "asgi" ? "myapp.asgi:application" : "myapp.wsgi:application"}
                value={form.wsgiApp}
                onChange={(e) => set("wsgiApp", e.target.value)}
              />
            </div>

            {/* Gunicorn tuning */}
            <div className="space-y-4 rounded-md border border-border/60 bg-background/40 p-4">
              <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                Gunicorn
              </p>
              <div className="grid gap-4 sm:grid-cols-3">
                <div>
                  <Label htmlFor="s-gworkers">Workers</Label>
                  <Input
                    id="s-gworkers"
                    type="number"
                    min={1}
                    max={64}
                    className="mt-1"
                    placeholder="4"
                    value={form.gunicornWorkers}
                    onChange={(e) => set("gunicornWorkers", e.target.value)}
                  />
                </div>
                <div>
                  <Label htmlFor="s-gthreads">Threads / worker</Label>
                  <Input
                    id="s-gthreads"
                    type="number"
                    min={1}
                    max={64}
                    className="mt-1"
                    placeholder="1"
                    value={form.gunicornThreads}
                    onChange={(e) => set("gunicornThreads", e.target.value)}
                  />
                </div>
                <div>
                  <Label htmlFor="s-gtimeout">Timeout (s)</Label>
                  <Input
                    id="s-gtimeout"
                    type="number"
                    min={1}
                    max={3600}
                    className="mt-1"
                    placeholder="120"
                    value={form.gunicornTimeout}
                    onChange={(e) => set("gunicornTimeout", e.target.value)}
                  />
                </div>
              </div>
              <div>
                <Label htmlFor="s-gbind">
                  Bind address
                  <span className="ml-1 text-[10px] text-muted-foreground">(optional)</span>
                </Label>
                <Input
                  id="s-gbind"
                  className="mt-1 font-mono text-sm"
                  placeholder={`0.0.0.0:${app.internalPort} (internal port)`}
                  value={form.gunicornBind}
                  onChange={(e) => set("gunicornBind", e.target.value)}
                />
                <p className="mt-1 text-xs text-muted-foreground">
                  Defaults to <code className="font-mono">0.0.0.0:$PORT</code>{" "}
                  (the app&apos;s internal port {app.internalPort}). Only override
                  if you keep the same port so the nginx proxy still resolves.
                </p>
              </div>
              <div>
                <Label htmlFor="s-gextra">
                  Extra arguments
                  <span className="ml-1 text-[10px] text-muted-foreground">(optional)</span>
                </Label>
                <Input
                  id="s-gextra"
                  className="mt-1 font-mono text-sm"
                  placeholder="--max-requests 1000 --graceful-timeout 30"
                  value={form.gunicornExtraArgs}
                  onChange={(e) => set("gunicornExtraArgs", e.target.value)}
                />
              </div>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Runtime version */}
      {(isNode || isBun || isDart || isGo || isRust) && (
        <Card className="border-sky-500/30 bg-sky-500/5">
          <CardHeader>
            <CardTitle className="text-base">Runtime version</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <p className="text-xs text-muted-foreground">
              Changing the version takes effect on the next deployment.
            </p>

            {isNode && (
              <div className="space-y-1.5">
                <Label>Node.js version</Label>
                <div className="flex flex-wrap gap-1.5">
                  {NODE_VERSIONS.map((v) => (
                    <button
                      key={v}
                      type="button"
                      onClick={() => set("nodeVersion", v)}
                      className={`rounded px-2 py-0.5 text-xs font-mono border transition-colors
                        ${form.nodeVersion === v
                          ? "bg-sky-500 text-white border-sky-500"
                          : "border-border bg-background hover:bg-muted"}`}
                    >
                      {v}
                    </button>
                  ))}
                </div>
              </div>
            )}

            {isBun && (
              <div className="space-y-1.5">
                <Label>Bun version</Label>
                <div className="flex flex-wrap gap-1.5">
                  {BUN_VERSIONS.map((v) => (
                    <button
                      key={v}
                      type="button"
                      onClick={() => set("bunVersion", v)}
                      className={`rounded px-2 py-0.5 text-xs font-mono border transition-colors
                        ${form.bunVersion === v
                          ? "bg-sky-500 text-white border-sky-500"
                          : "border-border bg-background hover:bg-muted"}`}
                    >
                      {v}
                    </button>
                  ))}
                </div>
              </div>
            )}

            {isDart && (
              <div className="space-y-1.5">
                <Label>Dart SDK version</Label>
                <div className="flex flex-wrap gap-1.5">
                  {DART_VERSIONS.map((v) => (
                    <button
                      key={v}
                      type="button"
                      onClick={() => set("dartVersion", v)}
                      className={`rounded px-2 py-0.5 text-xs font-mono border transition-colors
                        ${form.dartVersion === v
                          ? "bg-sky-500 text-white border-sky-500"
                          : "border-border bg-background hover:bg-muted"}`}
                    >
                      {v}
                    </button>
                  ))}
                </div>
              </div>
            )}

            {isGo && (
              <div className="space-y-1.5">
                <Label>Go version</Label>
                <div className="flex flex-wrap gap-1.5">
                  {GO_VERSIONS.map((v) => (
                    <button
                      key={v}
                      type="button"
                      onClick={() => set("goVersion", v)}
                      className={`rounded px-2 py-0.5 text-xs font-mono border transition-colors
                        ${form.goVersion === v
                          ? "bg-sky-500 text-white border-sky-500"
                          : "border-border bg-background hover:bg-muted"}`}
                    >
                      {v}
                    </button>
                  ))}
                </div>
              </div>
            )}

            {isRust && (
              <div className="space-y-1.5">
                <Label>Rust toolchain</Label>
                <div className="flex flex-wrap gap-1.5">
                  {RUST_VERSIONS.map((v) => (
                    <button
                      key={v}
                      type="button"
                      onClick={() => set("rustVersion", v)}
                      className={`rounded px-2 py-0.5 text-xs font-mono border transition-colors
                        ${form.rustVersion === v
                          ? "bg-sky-500 text-white border-sky-500"
                          : "border-border bg-background hover:bg-muted"}`}
                    >
                      {v}
                    </button>
                  ))}
                </div>
                <p className="text-xs text-muted-foreground">
                  <span className="font-mono">stable</span> is recommended. <span className="font-mono">nightly</span> enables unstable features.
                </p>
              </div>
            )}
          </CardContent>
        </Card>
      )}

      {/* Celery */}
      {isCelery && (
        <Card className="border-amber-500/30 bg-amber-500/5">
          <CardHeader>
            <CardTitle className="text-base">Celery / Task queue</CardTitle>
          </CardHeader>
          <CardContent className="space-y-5">
            {/* Python version */}
            <div>
              <Label className="mb-2 block">Python version</Label>
              <div className="flex flex-wrap gap-1.5">
                {PYTHON_VERSIONS.map((v) => (
                  <button
                    key={v}
                    type="button"
                    onClick={() => set("pythonVersion", v)}
                    className={cn(
                      "rounded-md border px-2.5 py-1 font-mono text-xs transition-colors",
                      form.pythonVersion === v
                        ? "border-amber-500 bg-amber-500/10 text-amber-600 dark:text-amber-400"
                        : "border-border bg-card text-muted-foreground hover:border-amber-500/40"
                    )}
                  >
                    {v}
                  </button>
                ))}
              </div>
            </div>

            <div>
              <Label htmlFor="s-celery-app">Celery application</Label>
              <Input
                id="s-celery-app"
                className="mt-1 font-mono text-sm"
                placeholder="myproject.celery:app"
                value={form.celeryApp}
                onChange={(e) => set("celeryApp", e.target.value)}
              />
              <p className="mt-1 text-xs text-muted-foreground">
                e.g. <code className="font-mono">proj.celery:app</code> or{" "}
                <code className="font-mono">myproject</code> for auto-discovery.
              </p>
            </div>

            <div className="space-y-4 rounded-md border border-border/60 bg-background/40 p-4">
              <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                Workers
              </p>
              <div className="grid gap-4 sm:grid-cols-2">
                <div>
                  <Label htmlFor="s-cwcount">Worker processes</Label>
                  <Input
                    id="s-cwcount"
                    type="number"
                    min={1}
                    max={32}
                    className="mt-1"
                    placeholder="2"
                    value={form.celeryWorkerCount}
                    onChange={(e) => set("celeryWorkerCount", e.target.value)}
                  />
                  <p className="mt-1 text-xs text-muted-foreground">
                    Each worker is a separate systemd service.
                  </p>
                </div>
                <div>
                  <Label htmlFor="s-cconc">Concurrency / worker</Label>
                  <Input
                    id="s-cconc"
                    type="number"
                    min={1}
                    max={64}
                    className="mt-1"
                    placeholder="4"
                    value={form.celeryConcurrency}
                    onChange={(e) => set("celeryConcurrency", e.target.value)}
                  />
                  <p className="mt-1 text-xs text-muted-foreground">
                    Passed as <code className="font-mono">-c</code> to each worker.
                  </p>
                </div>
              </div>
              <div>
                <Label htmlFor="s-cqueues">
                  Queues
                  <span className="ml-1 text-[10px] text-muted-foreground">(optional)</span>
                </Label>
                <Input
                  id="s-cqueues"
                  className="mt-1 font-mono text-sm"
                  placeholder="celery,high-priority"
                  value={form.celeryQueues}
                  onChange={(e) => set("celeryQueues", e.target.value)}
                />
              </div>
              <div>
                <Label htmlFor="s-cextra">
                  Extra arguments
                  <span className="ml-1 text-[10px] text-muted-foreground">(optional)</span>
                </Label>
                <Input
                  id="s-cextra"
                  className="mt-1 font-mono text-sm"
                  placeholder="--max-tasks-per-child=1000"
                  value={form.celeryExtraArgs}
                  onChange={(e) => set("celeryExtraArgs", e.target.value)}
                />
              </div>
            </div>

            <label className="flex cursor-pointer items-center gap-3 rounded-md border border-amber-500/20 bg-background/40 p-3">
              <input
                type="checkbox"
                className="h-4 w-4 rounded border-border"
                checked={form.celeryBeatEnabled}
                onChange={(e) => set("celeryBeatEnabled", e.target.checked)}
              />
              <div>
                <p className="text-sm font-medium">Enable Celery Beat scheduler</p>
                <p className="mt-0.5 text-xs text-muted-foreground">
                  Launches a <code className="font-mono">celery beat</code> process alongside
                  the workers for periodic task scheduling.
                </p>
              </div>
            </label>

            <div className="rounded-md border border-amber-500/20 bg-amber-500/5 px-3 py-2 text-xs text-muted-foreground">
              Flower monitoring UI is automatically deployed on this app&apos;s port ({app.internalPort}) and
              proxied via Nginx. No extra configuration needed.
            </div>
          </CardContent>
        </Card>
      )}

      {/* Static */}
      {isStatic && (
        <Card className="border-green-500/30 bg-green-500/5">
          <CardHeader>
            <CardTitle className="text-base">Static site</CardTitle>
          </CardHeader>
          <CardContent className="space-y-5">
            <div>
              <Label htmlFor="s-build">
                Build command
                <span className="ml-1.5 text-[10px] font-normal text-muted-foreground">(optional)</span>
              </Label>
              <Input
                id="s-build"
                className="mt-1 font-mono text-sm"
                placeholder="npm ci && npm run build"
                value={form.buildCommand}
                onChange={(e) => set("buildCommand", e.target.value)}
              />
              <p className="mt-1 text-xs text-muted-foreground">
                Run a build step before Nginx serves the files (e.g. Vite, CRA, Hugo).
                Leave blank for plain HTML/CSS/JS repos.
              </p>
            </div>

            <div>
              <Label htmlFor="s-static-root">
                Static files directory
                <span className="ml-1.5 text-[10px] font-normal text-muted-foreground">(optional)</span>
              </Label>
              <Input
                id="s-static-root"
                className="mt-1 font-mono text-sm"
                placeholder="dist"
                value={form.staticRoot}
                onChange={(e) => set("staticRoot", e.target.value)}
              />
              <p className="mt-1 text-xs text-muted-foreground">
                Path relative to the repository root that Nginx serves, e.g.{" "}
                <code className="font-mono">dist</code> or{" "}
                <code className="font-mono">build/public</code>. Leave blank for the repo root.
              </p>
            </div>

            <label className="flex cursor-pointer items-center gap-3 rounded-md border border-green-500/20 bg-background/40 p-3">
              <input
                type="checkbox"
                className="h-4 w-4 rounded border-border"
                checked={form.staticSpa}
                onChange={(e) => set("staticSpa", e.target.checked)}
              />
              <div>
                <p className="text-sm font-medium">SPA mode</p>
                <p className="mt-0.5 text-xs text-muted-foreground">
                  Falls back to <code className="font-mono">index.html</code> for all routes.
                  Required for React, Vue, Angular, and other client-side routers.
                </p>
              </div>
            </label>

            <div className="rounded-md border border-green-500/20 bg-background/40 p-3">
              <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-2">
                Nginx behavior
              </p>
              <ul className="space-y-1 text-xs text-muted-foreground">
                <li>• Files are served directly — no application process runs.</li>
                <li>• CSS/JS/image assets receive a 1-year <code className="font-mono">Cache-Control: immutable</code> header.</li>
                <li>• Attach a domain to get an automatic Let&apos;s Encrypt certificate.</li>
              </ul>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Resources */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Resource limits</CardTitle>
        </CardHeader>
        <CardContent className="grid gap-4 sm:grid-cols-3">
          <div>
            <Label htmlFor="s-mem">Memory (MB)</Label>
            <Input
              id="s-mem"
              type="number"
              min={64}
              max={32768}
              className="mt-1"
              value={form.memoryMbLimit}
              onChange={(e) => set("memoryMbLimit", Number(e.target.value))}
            />
          </div>
          <div>
            <Label htmlFor="s-cpu">CPU quota (%)</Label>
            <Input
              id="s-cpu"
              type="number"
              min={1}
              max={400}
              className="mt-1"
              value={form.cpuQuotaPercent}
              onChange={(e) => set("cpuQuotaPercent", Number(e.target.value))}
            />
          </div>
          <div>
            <Label htmlFor="s-tasks">Tasks max</Label>
            <Input
              id="s-tasks"
              type="number"
              min={10}
              max={4096}
              className="mt-1"
              value={form.tasksLimit}
              onChange={(e) => set("tasksLimit", Number(e.target.value))}
            />
          </div>
        </CardContent>
      </Card>

      <div className="flex justify-end gap-2">
        <Button type="submit" disabled={saving}>
          {saving ? "Saving…" : "Save changes"}
        </Button>
      </div>
    </form>
  );
}
