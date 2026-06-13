"use client";

import { useState } from "react";
import { useRouter } from "@/compat/navigation";
import useSWR from "swr";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { api, fetcher } from "@/lib/api";
import { cn } from "@/lib/utils";
import type { App, ListResponse, Project, SshKey, Team } from "@/lib/types";

// ── Constants ─────────────────────────────────────────────────────────────────

const RUNTIMES = [
  { id: "dart",   label: "Dart",    group: "compiled" },
  { id: "go",     label: "Go",      group: "compiled" },
  { id: "rust",   label: "Rust",    group: "compiled" },
  { id: "zig",    label: "Zig",     group: "compiled" },
  { id: "bun",    label: "Bun",     group: "js" },
  { id: "node",   label: "Node.js", group: "js" },
  { id: "python", label: "Python",  group: "python" },
  { id: "celery", label: "Celery",  group: "python" },
  { id: "static", label: "Static",  group: "static" },
  { id: "binary", label: "Binary",  group: "compiled" },
];

// Common CPython releases — the panel installs any of these via pyenv.
const PYTHON_VERSIONS = [
  "3.13.2", "3.13.1", "3.13.0",
  "3.12.9", "3.12.8", "3.12.7", "3.12.4",
  "3.11.11","3.11.10","3.11.9",
  "3.10.16","3.10.15",
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

// ── Page ─────────────────────────────────────────────────────────────────────

export default function NewAppPage() {
  const router = useRouter();
  const projects = useSWR<ListResponse<Project>>("/projects/", fetcher);
  const teams = useSWR<ListResponse<Team>>("/teams/", fetcher);
  const sshKeys = useSWR<{ results: SshKey[] }>("/me/security/ssh-keys", fetcher);

  // Quick project-create dialog state
  const [projDialog, setProjDialog] = useState(false);
  const [newProjTeam, setNewProjTeam] = useState("");
  const [newProjName, setNewProjName] = useState("");
  const [creatingProj, setCreatingProj] = useState(false);

  const [form, setForm] = useState({
    projectId: 0,
    name: "",
    runtime: "dart",
    sourceType: "git",
    gitUrl: "",
    gitBranch: "main",
    buildCommand: "",
    startCommand: "",
    // Python-specific
    pythonVersion: "3.12.4",
    pythonMode: "wsgi",
    wsgiApp: "",
    // Gunicorn tuning
    gunicornWorkers: "",
    gunicornThreads: "",
    gunicornTimeout: "",
    gunicornBind: "",
    gunicornExtraArgs: "",
    // Runtime version pins
    nodeVersion: NODE_VERSIONS[0],
    dartVersion: DART_VERSIONS[0],
    goVersion: GO_VERSIONS[0],
    rustVersion: RUST_VERSIONS[0],
    bunVersion: BUN_VERSIONS[0],
    // Celery-specific
    celeryApp: "",
    celeryWorkerCount: "2",
    celeryConcurrency: "4",
    celeryQueues: "",
    celeryBeatEnabled: false,
    celeryExtraArgs: "",
    // Static site
    staticRoot: "",
    staticSpa: false,
    // Git deploy key
    deployKeyId: "" as string | number,
    // Internal port
    internalPort: "",
  });
  const [loading, setLoading] = useState(false);

  const isPython = form.runtime === "python";
  const isCelery = form.runtime === "celery";
  const isStatic = form.runtime === "static";
  const isBinary = form.sourceType === "binary";
  const isNode = form.runtime === "node";
  const isBun  = form.runtime === "bun";
  const isDart = form.runtime === "dart";
  const isGo   = form.runtime === "go";
  const isRust = form.runtime === "rust";

  function set<K extends keyof typeof form>(k: K, v: (typeof form)[K]) {
    setForm((f) => ({ ...f, [k]: v }));
  }

  async function createProject(e: React.FormEvent) {
    e.preventDefault();
    setCreatingProj(true);
    try {
      const p = await api<Project>("/projects/", {
        method: "POST",
        body: JSON.stringify({ teamId: Number(newProjTeam), name: newProjName }),
      });
      await projects.mutate();
      set("projectId", p.id as number);
      setProjDialog(false);
      toast.success(`Project "${p.name}" created`);
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed to create project");
    } finally {
      setCreatingProj(false);
    }
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    try {
      const payload: Record<string, unknown> = {
        projectId: form.projectId,
        name: form.name,
        runtime: form.runtime,
        sourceType: form.sourceType,
        // Static sites are served directly by Nginx and have no listening port.
        ...(isStatic ? {} : { internalPort: Number(form.internalPort) }),
        gitUrl: form.gitUrl || undefined,
        gitBranch: form.gitBranch || undefined,
        buildCommand: form.buildCommand || undefined,
        startCommand: form.startCommand || undefined,
      };
      if (isPython) {
        payload.pythonVersion = form.pythonVersion;
        payload.pythonMode    = form.pythonMode;
        payload.wsgiApp       = form.wsgiApp || undefined;
        payload.gunicornWorkers = form.gunicornWorkers ? Number(form.gunicornWorkers) : undefined;
        payload.gunicornThreads = form.gunicornThreads ? Number(form.gunicornThreads) : undefined;
        payload.gunicornTimeout = form.gunicornTimeout ? Number(form.gunicornTimeout) : undefined;
        payload.gunicornBind    = form.gunicornBind || undefined;
        payload.gunicornExtraArgs = form.gunicornExtraArgs || undefined;
      }
      if (isCelery) {
        payload.pythonVersion     = form.pythonVersion;
        payload.celeryApp         = form.celeryApp || undefined;
        payload.celeryWorkerCount = form.celeryWorkerCount ? Number(form.celeryWorkerCount) : 2;
        payload.celeryConcurrency = form.celeryConcurrency ? Number(form.celeryConcurrency) : 4;
        payload.celeryQueues      = form.celeryQueues || undefined;
        payload.celeryBeatEnabled = form.celeryBeatEnabled;
        payload.celeryExtraArgs   = form.celeryExtraArgs || undefined;
      }
      if (isNode)  payload.nodeVersion = form.nodeVersion || undefined;
      if (isBun)   payload.bunVersion  = form.bunVersion  || undefined;
      if (isDart)  payload.dartVersion = form.dartVersion || undefined;
      if (isGo)    payload.goVersion   = form.goVersion   || undefined;
      if (isRust)  payload.rustVersion = form.rustVersion || undefined;
      if (isStatic) {
        payload.staticRoot = form.staticRoot || undefined;
        payload.staticSpa  = form.staticSpa;
      }
      if (form.sourceType === "git" && form.deployKeyId) {
        payload.deployKeyId = Number(form.deployKeyId);
      }
      const app = await api<App>("/apps/", {
        method: "POST",
        body: JSON.stringify(payload),
      });
      toast.success(`Created "${app.name}"`);
      router.push(`/apps/${app.id}`);
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed to create app");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="mx-auto max-w-3xl space-y-6 p-6">
      <header>
        <h1 className="text-xl font-semibold">New app</h1>
        <p className="mt-0.5 text-sm text-muted-foreground">
          Pick a runtime and source. We&apos;ll create the Linux user, systemd unit,
          AppArmor profile and Nginx vhost automatically.
        </p>
      </header>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">App details</CardTitle>
        </CardHeader>
        <CardContent>
          <form className="space-y-6" onSubmit={submit}>
            {/* Project */}
            <div className="space-y-1.5">
              <div className="flex items-center justify-between">
                <Label>Project</Label>
                <button
                  type="button"
                  className="text-xs text-primary hover:underline flex items-center gap-0.5"
                  onClick={() => {
                    setNewProjTeam(teams.data?.results[0] ? String(teams.data.results[0].id) : "");
                    setNewProjName("");
                    setProjDialog(true);
                  }}
                >
                  <span>+</span> New project
                </button>
              </div>
              <select
                className="h-9 w-full rounded-md border border-input bg-background px-3 text-sm"
                value={form.projectId}
                onChange={(e) => set("projectId", Number(e.target.value))}
                required
              >
                <option value={0} disabled>
                  {(projects.data?.results.length ?? 0) === 0
                    ? "No projects yet — create one above"
                    : "Choose a project…"}
                </option>
                {projects.data?.results.map((p) => (
                  <option key={p.id} value={p.id}>{p.name}</option>
                ))}
              </select>
            </div>

            {/* Name + Runtime */}
            <div className="grid gap-4 md:grid-cols-2">
              <div className="space-y-1.5">
                <Label htmlFor="name">App name</Label>
                <Input
                  id="name"
                  required
                  placeholder="my-api"
                  value={form.name}
                  onChange={(e) => set("name", e.target.value)}
                />
              </div>
              <div className="space-y-1.5">
                <Label>Runtime</Label>
                <div className="flex flex-wrap gap-1.5">
                  {RUNTIMES.map(({ id, label }) => (
                    <button
                      key={id}
                      type="button"
                      onClick={() => set("runtime", id)}
                      className={cn(
                        "rounded-md border px-2.5 py-1 text-xs font-medium transition-colors",
                        form.runtime === id
                          ? "border-primary bg-primary/10 text-foreground"
                          : "border-border bg-card text-muted-foreground hover:border-primary/40 hover:text-foreground",
                      )}
                    >
                      {label}
                    </button>
                  ))}
                </div>
              </div>
            </div>

            {/* Port — static sites are served directly by Nginx, no port. */}
            {!isStatic && (
              <div className="space-y-1.5">
                <Label htmlFor="internalPort">Internal port</Label>
                <Input
                  id="internalPort"
                  type="number"
                  min={1024}
                  max={65535}
                  required
                  placeholder="e.g. 8080"
                  value={form.internalPort}
                  onChange={(e) => set("internalPort", e.target.value)}
                />
                <p className="text-xs text-muted-foreground">
                  The port your app listens on (1024–65535). Must be unique across all apps.
                </p>
              </div>
            )}

            {/* ── Python-specific section ──────────────────────────────────── */}
            {isPython && (
              <Card className="border-blue-500/30 bg-blue-500/5">
                <CardContent className="space-y-5 pt-4">
                  <div className="flex items-center gap-2">
                    <Badge variant="secondary" className="text-[10px]">Python / WSGI·ASGI</Badge>
                    <span className="text-xs text-muted-foreground">
                      Served by Gunicorn via pyenv-managed virtualenv
                    </span>
                  </div>

                  {/* Python version */}
                  <div className="space-y-1.5">
                    <Label>Python version</Label>
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
                              : "border-border bg-card text-muted-foreground hover:border-blue-500/40",
                          )}
                        >
                          {v}
                        </button>
                      ))}
                    </div>
                    <p className="text-xs text-muted-foreground">
                      Installed via pyenv at <code className="font-mono">/opt/pyenv</code> during the first deploy.
                    </p>
                  </div>

                  {/* Server mode */}
                  <div className="space-y-1.5">
                    <Label>Server mode</Label>
                    <div className="grid grid-cols-2 gap-2">
                      {[
                        {
                          id: "wsgi",
                          label: "WSGI",
                          desc: "Django, Flask, Pyramid — synchronous apps",
                        },
                        {
                          id: "asgi",
                          label: "ASGI",
                          desc: "FastAPI, Django Channels, Starlette — async apps",
                        },
                      ].map(({ id, label, desc }) => (
                        <button
                          key={id}
                          type="button"
                          onClick={() => set("pythonMode", id)}
                          className={cn(
                            "flex flex-col items-start rounded-md border p-3 text-left transition-colors",
                            form.pythonMode === id
                              ? "border-blue-500 bg-blue-500/10"
                              : "border-border bg-card hover:border-blue-500/40",
                          )}
                        >
                          <span className="text-sm font-medium">{label}</span>
                          <span className="mt-0.5 text-xs text-muted-foreground">{desc}</span>
                        </button>
                      ))}
                    </div>
                    <p className="text-xs text-muted-foreground">
                      {form.pythonMode === "asgi"
                        ? "Uses uvicorn worker class: --worker-class uvicorn.workers.UvicornWorker"
                        : "Standard sync workers: --workers 4"}
                    </p>
                  </div>

                  {/* WSGI/ASGI application target */}
                  <div className="space-y-1.5">
                    <Label htmlFor="wsgiApp">
                      Application target
                      <span className="ml-1.5 text-[10px] font-normal text-muted-foreground">
                        (passed to gunicorn as the app argument)
                      </span>
                    </Label>
                    <Input
                      id="wsgiApp"
                      className="font-mono text-sm"
                      placeholder={
                        form.pythonMode === "asgi"
                          ? "myapp.asgi:application"
                          : "myapp.wsgi:application"
                      }
                      value={form.wsgiApp}
                      onChange={(e) => set("wsgiApp", e.target.value)}
                    />
                    <p className="text-xs text-muted-foreground">
                      Leave blank to default to <code className="font-mono">app:application</code>.
                      Examples: <code className="font-mono">myproject.wsgi:application</code> (Django),{" "}
                      <code className="font-mono">main:app</code> (FastAPI/Flask).
                    </p>
                  </div>

                  {/* Gunicorn tuning */}
                  <div className="space-y-3 rounded-md border border-blue-500/20 bg-background/40 p-3">
                    <Label className="text-xs uppercase tracking-wider text-muted-foreground">
                      Gunicorn (optional)
                    </Label>
                    <div className="grid grid-cols-3 gap-2">
                      <div className="space-y-1">
                        <Label htmlFor="g-workers" className="text-xs">Workers</Label>
                        <Input
                          id="g-workers"
                          type="number"
                          min={1}
                          placeholder="4"
                          value={form.gunicornWorkers}
                          onChange={(e) => set("gunicornWorkers", e.target.value)}
                        />
                      </div>
                      <div className="space-y-1">
                        <Label htmlFor="g-threads" className="text-xs">Threads</Label>
                        <Input
                          id="g-threads"
                          type="number"
                          min={1}
                          placeholder="1"
                          value={form.gunicornThreads}
                          onChange={(e) => set("gunicornThreads", e.target.value)}
                        />
                      </div>
                      <div className="space-y-1">
                        <Label htmlFor="g-timeout" className="text-xs">Timeout (s)</Label>
                        <Input
                          id="g-timeout"
                          type="number"
                          min={1}
                          placeholder="120"
                          value={form.gunicornTimeout}
                          onChange={(e) => set("gunicornTimeout", e.target.value)}
                        />
                      </div>
                    </div>
                    <div className="space-y-1">
                      <Label htmlFor="g-bind" className="text-xs">
                        Bind address
                        <span className="ml-1 text-[10px] text-muted-foreground">
                          (defaults to 0.0.0.0:$PORT)
                        </span>
                      </Label>
                      <Input
                        id="g-bind"
                        className="font-mono text-sm"
                        placeholder="0.0.0.0:$PORT"
                        value={form.gunicornBind}
                        onChange={(e) => set("gunicornBind", e.target.value)}
                      />
                    </div>
                    <div className="space-y-1">
                      <Label htmlFor="g-extra" className="text-xs">
                        Extra arguments
                        <span className="ml-1 text-[10px] text-muted-foreground">(optional)</span>
                      </Label>
                      <Input
                        id="g-extra"
                        className="font-mono text-sm"
                        placeholder="--max-requests 1000 --graceful-timeout 30"
                        value={form.gunicornExtraArgs}
                        onChange={(e) => set("gunicornExtraArgs", e.target.value)}
                      />
                    </div>
                  </div>
                </CardContent>
              </Card>
            )}

            {/* ── Runtime version pickers ──────────────────────────────────── */}
            {(isNode || isBun || isDart || isGo || isRust) && (
              <Card className="border-sky-500/30 bg-sky-500/5">
                <CardContent className="space-y-4 pt-4">
                  <div className="flex items-center gap-2">
                    <Badge variant="secondary" className="text-[10px]">Runtime version</Badge>
                    <span className="text-xs text-muted-foreground">
                      Pin a specific runtime version. Leave as-is to use the latest shown below.
                    </span>
                  </div>

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
                        <span className="font-mono">stable</span> is the recommended default. <span className="font-mono">nightly</span> enables unstable features.
                      </p>
                    </div>
                  )}
                </CardContent>
              </Card>
            )}

            {/* ── Celery-specific section ──────────────────────────────────── */}
            {isCelery && (
              <Card className="border-amber-500/30 bg-amber-500/5">
                <CardContent className="space-y-5 pt-4">
                  <div className="flex items-center gap-2">
                    <Badge variant="secondary" className="text-[10px]">Celery / Task queue</Badge>
                    <span className="text-xs text-muted-foreground">
                      Workers + Flower UI, served via Nginx proxy
                    </span>
                  </div>

                  {/* Python version (shared with Celery) */}
                  <div className="space-y-1.5">
                    <Label>Python version</Label>
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
                              : "border-border bg-card text-muted-foreground hover:border-amber-500/40",
                          )}
                        >
                          {v}
                        </button>
                      ))}
                    </div>
                  </div>

                  {/* Celery app path */}
                  <div className="space-y-1.5">
                    <Label htmlFor="celeryApp">
                      Celery application
                      <span className="ml-1.5 text-[10px] font-normal text-muted-foreground">(required)</span>
                    </Label>
                    <Input
                      id="celeryApp"
                      className="font-mono text-sm"
                      placeholder="myproject.celery:app"
                      required={isCelery}
                      value={form.celeryApp}
                      onChange={(e) => set("celeryApp", e.target.value)}
                    />
                    <p className="text-xs text-muted-foreground">
                      The Celery application instance, e.g.{" "}
                      <code className="font-mono">proj.celery:app</code> or{" "}
                      <code className="font-mono">myproject</code> for auto-discovery.
                    </p>
                  </div>

                  {/* Workers + concurrency + queues */}
                  <div className="space-y-3 rounded-md border border-amber-500/20 bg-background/40 p-3">
                    <Label className="text-xs uppercase tracking-wider text-muted-foreground">
                      Workers
                    </Label>
                    <div className="grid grid-cols-2 gap-3">
                      <div className="space-y-1">
                        <Label htmlFor="c-wcount" className="text-xs">
                          Worker processes
                        </Label>
                        <Input
                          id="c-wcount"
                          type="number"
                          min={1}
                          max={32}
                          placeholder="2"
                          value={form.celeryWorkerCount}
                          onChange={(e) => set("celeryWorkerCount", e.target.value)}
                        />
                        <p className="text-[10px] text-muted-foreground">
                          Number of separate worker processes to launch.
                        </p>
                      </div>
                      <div className="space-y-1">
                        <Label htmlFor="c-conc" className="text-xs">
                          Concurrency / worker
                        </Label>
                        <Input
                          id="c-conc"
                          type="number"
                          min={1}
                          max={64}
                          placeholder="4"
                          value={form.celeryConcurrency}
                          onChange={(e) => set("celeryConcurrency", e.target.value)}
                        />
                        <p className="text-[10px] text-muted-foreground">
                          Threads or processes per worker (-c).
                        </p>
                      </div>
                    </div>
                    <div className="space-y-1">
                      <Label htmlFor="c-queues" className="text-xs">
                        Queues
                        <span className="ml-1 text-[10px] text-muted-foreground">(optional)</span>
                      </Label>
                      <Input
                        id="c-queues"
                        className="font-mono text-sm"
                        placeholder="celery,high-priority,low-priority"
                        value={form.celeryQueues}
                        onChange={(e) => set("celeryQueues", e.target.value)}
                      />
                      <p className="text-[10px] text-muted-foreground">
                        Comma-separated queue names. Leave blank for the default queue.
                      </p>
                    </div>
                    <div className="space-y-1">
                      <Label htmlFor="c-extra" className="text-xs">
                        Extra worker arguments
                        <span className="ml-1 text-[10px] text-muted-foreground">(optional)</span>
                      </Label>
                      <Input
                        id="c-extra"
                        className="font-mono text-sm"
                        placeholder="--max-tasks-per-child=1000"
                        value={form.celeryExtraArgs}
                        onChange={(e) => set("celeryExtraArgs", e.target.value)}
                      />
                    </div>
                  </div>

                  {/* Beat scheduler */}
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
                        Launches a <code className="font-mono">celery beat</code> process alongside the workers
                        for periodic task scheduling.
                      </p>
                    </div>
                  </label>

                  <div className="rounded-md border border-amber-500/20 bg-amber-500/5 px-3 py-2 text-xs text-muted-foreground">
                    Flower monitoring UI is automatically deployed and accessible via your app&apos;s domain.
                    The internal port is proxied by Nginx.
                  </div>
                </CardContent>
              </Card>
            )}

            {/* ── Static site section ──────────────────────────────────────── */}
            {isStatic && (
              <Card className="border-green-500/30 bg-green-500/5">
                <CardContent className="space-y-5 pt-4">
                  <div className="flex items-center gap-2">
                    <Badge variant="secondary" className="text-[10px]">Static / HTML · CSS · JS</Badge>
                    <span className="text-xs text-muted-foreground">
                      Served directly by Nginx — no process required
                    </span>
                  </div>

                  <div className="space-y-1.5">
                    <Label htmlFor="staticRoot">
                      Static files directory
                      <span className="ml-1.5 text-[10px] font-normal text-muted-foreground">(optional)</span>
                    </Label>
                    <Input
                      id="staticRoot"
                      className="font-mono text-sm"
                      placeholder="dist"
                      value={form.staticRoot}
                      onChange={(e) => set("staticRoot", e.target.value)}
                    />
                    <p className="text-xs text-muted-foreground">
                      Path relative to the repository root where Nginx should serve files,
                      e.g. <code className="font-mono">dist</code> or <code className="font-mono">build/public</code>.
                      Leave blank to serve the repository root.
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
                        Falls back to <code className="font-mono">index.html</code> for all routes
                        (React, Vue, Angular, etc.).
                      </p>
                    </div>
                  </label>

                  <p className="text-xs text-muted-foreground">
                    Attach a domain after creating the app to make it publicly accessible via HTTPS.
                    Static assets (CSS/JS/images) receive a 1-year cache header automatically.
                  </p>
                </CardContent>
              </Card>
            )}

            {/* Source */}
            <div className="space-y-1.5">
              <Label>Source</Label>
              <div className="grid grid-cols-3 gap-2">
                {["git", "binary", "zip"].map((s) => (
                  <button
                    type="button"
                    key={s}
                    onClick={() => set("sourceType", s)}
                    className={cn(
                      "rounded-md border px-3 py-2 text-sm transition-colors",
                      form.sourceType === s
                        ? "border-primary bg-primary/10 text-foreground"
                        : "border-border bg-card text-muted-foreground hover:border-primary/30",
                    )}
                  >
                    {s}
                  </button>
                ))}
              </div>
            </div>

            {form.sourceType === "git" && (
              <div className="space-y-4">
                <div className="grid gap-4 md:grid-cols-2">
                  <div className="space-y-1.5">
                    <Label htmlFor="gitUrl">Git URL</Label>
                    <Input
                      id="gitUrl"
                      placeholder="git@github.com:you/repo.git"
                      value={form.gitUrl}
                      onChange={(e) => set("gitUrl", e.target.value)}
                    />
                  </div>
                  <div className="space-y-1.5">
                    <Label htmlFor="gitBranch">Branch</Label>
                    <Input
                      id="gitBranch"
                      value={form.gitBranch}
                      onChange={(e) => set("gitBranch", e.target.value)}
                    />
                  </div>
                </div>

                {/* Deploy key picker */}
                <div className="space-y-1.5">
                  <Label htmlFor="deployKey">
                    Deploy key
                    <span className="ml-1.5 text-[10px] font-normal text-muted-foreground">
                      (optional — required for private repos via SSH)
                    </span>
                  </Label>
                  <Select
                    value={String(form.deployKeyId)}
                    onValueChange={(v) => set("deployKeyId", v === "none" ? "" : v)}
                  >
                    <SelectTrigger id="deployKey">
                      <SelectValue placeholder="None — use HTTPS or public repo" />
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
                  {!(sshKeys.data?.results?.length) && (
                    <p className="text-xs text-muted-foreground">
                      No SSH keys yet.{" "}
                      <a href="/settings/ssh-keys" className="underline">
                        Generate a deploy key
                      </a>{" "}
                      to use with private repos.
                    </p>
                  )}
                </div>
              </div>
            )}

            {form.sourceType === "binary" && (
              <div className="rounded-md border border-dashed border-border bg-muted/30 px-4 py-3 text-sm text-muted-foreground">
                Upload your pre-compiled binary via the app detail page after
                creating the app. No build command is needed — the binary runs
                directly inside a sandboxed systemd unit.
              </div>
            )}

            {/* Build + Start commands — hidden for runtimes that don't need them */}
            {!isBinary && !isCelery && !isStatic && (
              <div className="grid gap-4 md:grid-cols-2">
                <div className="space-y-1.5">
                  <Label htmlFor="buildCommand">
                    Build command
                    <span className="ml-1 text-[10px] text-muted-foreground">(optional)</span>
                  </Label>
                  <Input
                    id="buildCommand"
                    placeholder={
                      isPython
                        ? "pip install -r requirements.txt"
                        : "dart compile exe bin/server.dart -o build/app"
                    }
                    value={form.buildCommand}
                    onChange={(e) => set("buildCommand", e.target.value)}
                  />
                  {isPython && (
                    <p className="text-xs text-muted-foreground">
                      Leave blank — gunicorn + uvicorn are installed automatically.
                    </p>
                  )}
                </div>
                <div className="space-y-1.5">
                  <Label htmlFor="startCommand">
                    Start command
                    <span className="ml-1 text-[10px] text-muted-foreground">(optional)</span>
                  </Label>
                  <Input
                    id="startCommand"
                    placeholder={
                      isPython
                        ? "Auto-generated gunicorn command"
                        : "./current/app"
                    }
                    disabled={isPython && !form.startCommand}
                    value={form.startCommand}
                    onChange={(e) => set("startCommand", e.target.value)}
                  />
                  {isPython && (
                    <p className="text-xs text-muted-foreground">
                      Leave blank to auto-generate the gunicorn command based on
                      mode + target above.
                    </p>
                  )}
                </div>
              </div>
            )}

            {/* Celery: optional build command (e.g. pip install extras) */}
            {isCelery && (
              <div className="space-y-1.5">
                <Label htmlFor="buildCommand">
                  Build command
                  <span className="ml-1 text-[10px] text-muted-foreground">(optional)</span>
                </Label>
                <Input
                  id="buildCommand"
                  className="font-mono text-sm"
                  placeholder="pip install -r requirements.txt"
                  value={form.buildCommand}
                  onChange={(e) => set("buildCommand", e.target.value)}
                />
                <p className="text-xs text-muted-foreground">
                  Leave blank — <code className="font-mono">requirements.txt</code> is installed automatically,
                  then celery + flower are added on top.
                </p>
              </div>
            )}

            {/* Static: optional build command (e.g. npm run build) */}
            {isStatic && (
              <div className="space-y-1.5">
                <Label htmlFor="buildCommand">
                  Build command
                  <span className="ml-1 text-[10px] text-muted-foreground">(optional)</span>
                </Label>
                <Input
                  id="buildCommand"
                  className="font-mono text-sm"
                  placeholder="npm ci && npm run build"
                  value={form.buildCommand}
                  onChange={(e) => set("buildCommand", e.target.value)}
                />
                <p className="text-xs text-muted-foreground">
                  Run a build step before Nginx serves the files (e.g. Vite, Next.js export, Hugo).
                  Leave blank for plain HTML/CSS/JS repos.
                </p>
              </div>
            )}

            {isBinary && (
              <div className="space-y-1.5">
                <Label htmlFor="startCommand">
                  Start command
                  <span className="ml-1 text-[10px] text-muted-foreground">(optional, defaults to ./current/app)</span>
                </Label>
                <Input
                  id="startCommand"
                  placeholder="./current/app --port $PORT"
                  value={form.startCommand}
                  onChange={(e) => set("startCommand", e.target.value)}
                />
              </div>
            )}

            <div className="flex justify-end gap-2 pt-2">
              <Button type="button" variant="outline" onClick={() => router.back()}>
                Cancel
              </Button>
              <Button type="submit" disabled={loading}>
                {loading ? "Creating…" : "Create app"}
              </Button>
            </div>
          </form>
        </CardContent>
      </Card>
      {/* Quick project create dialog */}
      <Dialog open={projDialog} onOpenChange={setProjDialog}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader>
            <DialogTitle>New Project</DialogTitle>
          </DialogHeader>
          <form onSubmit={createProject} className="space-y-4">
            {(teams.data?.results.length ?? 0) === 0 ? (
              <p className="text-sm text-muted-foreground">
                You need a team first.{" "}
                <a href="/teams" className="text-primary underline">
                  Create one
                </a>
                .
              </p>
            ) : (
              <>
                <div>
                  <Label htmlFor="qp-team">Team</Label>
                  <select
                    id="qp-team"
                    className="mt-1 h-9 w-full rounded-md border border-input bg-background px-3 text-sm"
                    value={newProjTeam}
                    onChange={(e) => setNewProjTeam(e.target.value)}
                    required
                  >
                    {teams.data?.results.map((t) => (
                      <option key={t.id} value={t.id}>{t.name}</option>
                    ))}
                  </select>
                </div>
                <div>
                  <Label htmlFor="qp-name">Project name</Label>
                  <Input
                    id="qp-name"
                    className="mt-1"
                    placeholder="my-backend"
                    value={newProjName}
                    onChange={(e) => setNewProjName(e.target.value)}
                    required
                  />
                </div>
              </>
            )}
            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setProjDialog(false)}>
                Cancel
              </Button>
              {(teams.data?.results.length ?? 0) > 0 && (
                <Button type="submit" disabled={creatingProj || !newProjName.trim()}>
                  {creatingProj ? "Creating…" : "Create"}
                </Button>
              )}
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  );
}
