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
    deployKeyId: app.deployKeyId ? String(app.deployKeyId) : "",
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
      deployKeyId: app.deployKeyId ? String(app.deployKeyId) : "",
    });
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [app.id]);

  function set<K extends keyof typeof form>(k: K, v: (typeof form)[K]) {
    setForm((f) => ({ ...f, [k]: v }));
  }

  const isPython = app.runtime === "python";
  const isBinary = app.sourceType === "binary";
  const isGit = app.sourceType === "git";

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
      if (isGit) {
        patch.deployKeyId = form.deployKeyId ? Number(form.deployKeyId) : undefined;
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
        </CardContent>
      </Card>

      {/* Source */}
      {!isBinary && (
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
                  placeholder={isPython ? "pip install -r requirements.txt" : "dart compile exe bin/server.dart -o build/app"}
                  value={form.buildCommand}
                  onChange={(e) => set("buildCommand", e.target.value)}
                />
                {isPython && (
                  <p className="mt-1 text-xs text-muted-foreground">
                    Leave blank — gunicorn + uvicorn are installed automatically.
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
                  placeholder={isPython ? "Auto-generated gunicorn command" : "./current/app"}
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
