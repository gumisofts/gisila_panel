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
  { id: "dart",   label: "Dart" },
  { id: "go",     label: "Go" },
  { id: "rust",   label: "Rust" },
  { id: "zig",    label: "Zig" },
  { id: "bun",    label: "Bun" },
  { id: "node",   label: "Node.js" },
  { id: "python", label: "Python" },
  { id: "binary", label: "Binary" },
];

// Common CPython releases — the panel installs any of these via pyenv.
const PYTHON_VERSIONS = [
  "3.13.2", "3.13.1", "3.13.0",
  "3.12.9", "3.12.8", "3.12.7", "3.12.4",
  "3.11.11","3.11.10","3.11.9",
  "3.10.16","3.10.15",
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
    // Git deploy key
    deployKeyId: "" as string | number,
  });
  const [loading, setLoading] = useState(false);

  const isPython = form.runtime === "python";
  const isBinary = form.sourceType === "binary";

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
        gitUrl: form.gitUrl || undefined,
        gitBranch: form.gitBranch || undefined,
        buildCommand: form.buildCommand || undefined,
        startCommand: form.startCommand || undefined,
      };
      if (isPython) {
        payload.pythonVersion = form.pythonVersion;
        payload.pythonMode    = form.pythonMode;
        payload.wsgiApp       = form.wsgiApp || undefined;
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
          Pick a runtime and source. We'll create the Linux user, systemd unit,
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

            {/* Build + Start commands (hidden for binary — no build step needed) */}
            {!isBinary && (
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
