"use client";

import { useState, useEffect, type ReactNode } from "react";
import useSWR from "swr";
import {
  Button,
  Checkbox,
  Form,
  InlineNotification,
  RadioTile,
  Select,
  SelectItem,
  Stack,
  Tag,
  TextInput,
  Tile,
  TileGroup,
} from "@carbon/react";
import { toast } from "@/lib/toast";
import { api, fetcher } from "@/lib/api";
import type {
  App,
  Application,
  ApplicationDef,
  ListResponse,
  SshKey,
} from "@/lib/types";
import { versionItems } from "../../_runtime-versions";
import "../_app-detail.scss";

/// A pinned toolchain version. The list is long enough that a Carbon Select
/// beats a wall of radio tiles, and the value is a plain string either way.
/// Option lists come from the Application catalog via `versionItems`.
function VersionSelect({
  id,
  labelText,
  value,
  onChange,
  helperText,
  children,
}: {
  id: string;
  labelText: string;
  value: string;
  onChange: (value: string) => void;
  helperText?: React.ReactNode;
  children: ReactNode;
}) {
  return (
    <Select
      id={id}
      labelText={labelText}
      helperText={helperText}
      value={value}
      onChange={(e) => onChange(e.target.value)}
    >
      {children}
    </Select>
  );
}

export function SettingsTab({
  app,
  onSaved,
}: {
  app: App;
  onSaved: () => void;
}) {
  const sshKeys = useSWR<{ results: SshKey[] }>("/me/security/ssh-keys", fetcher);
  const applications = useSWR<ListResponse<Application>>("/applications/", fetcher);
  const catalog = useSWR<ListResponse<ApplicationDef>>(
    "/applications/catalog",
    fetcher,
  );
  const appsList = applications.data?.results;
  const catalogList = catalog.data?.results;

  const [form, setForm] = useState({
    name: app.name,
    gitUrl: app.gitUrl ?? "",
    gitBranch: app.gitBranch ?? "",
    sourceSubdir: app.sourceSubdir ?? "",
    buildCommand: app.buildCommand ?? "",
    startCommand: app.startCommand ?? "",
    healthCheckPath: app.healthCheckPath ?? "",
    memoryMbLimit: app.memoryMbLimit,
    cpuQuotaPercent: app.cpuQuotaPercent,
    tasksLimit: app.tasksLimit,
    pythonVersion: app.pythonVersion ?? "3.13.15",
    pythonMode: app.pythonMode ?? "wsgi",
    wsgiApp: app.wsgiApp ?? "",
    gunicornWorkers: app.gunicornWorkers != null ? String(app.gunicornWorkers) : "",
    gunicornThreads: app.gunicornThreads != null ? String(app.gunicornThreads) : "",
    gunicornTimeout: app.gunicornTimeout != null ? String(app.gunicornTimeout) : "",
    gunicornBind: app.gunicornBind ?? "",
    gunicornExtraArgs: app.gunicornExtraArgs ?? "",
    // Runtime version pins. Option lists come from the Application catalog.
    nodeVersion: app.nodeVersion ?? "24.19.0",
    dartVersion: app.dartVersion ?? "3.12.2",
    goVersion: app.goVersion ?? "1.26.5",
    rustVersion: app.rustVersion ?? "stable",
    bunVersion: app.bunVersion ?? "1.3.14",
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
    mediaEnabled: app.mediaEnabled ?? false,
    mediaMaxUploadMb: app.mediaMaxUploadMb != null ? String(app.mediaMaxUploadMb) : "25",
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
      sourceSubdir: app.sourceSubdir ?? "",
      buildCommand: app.buildCommand ?? "",
      startCommand: app.startCommand ?? "",
      healthCheckPath: app.healthCheckPath ?? "",
      memoryMbLimit: app.memoryMbLimit,
      cpuQuotaPercent: app.cpuQuotaPercent,
      tasksLimit: app.tasksLimit,
      pythonVersion: app.pythonVersion ?? "3.13.15",
      pythonMode: app.pythonMode ?? "wsgi",
      wsgiApp: app.wsgiApp ?? "",
      gunicornWorkers: app.gunicornWorkers != null ? String(app.gunicornWorkers) : "",
      gunicornThreads: app.gunicornThreads != null ? String(app.gunicornThreads) : "",
      gunicornTimeout: app.gunicornTimeout != null ? String(app.gunicornTimeout) : "",
      gunicornBind: app.gunicornBind ?? "",
      gunicornExtraArgs: app.gunicornExtraArgs ?? "",
      nodeVersion: app.nodeVersion ?? "24.19.0",
      dartVersion: app.dartVersion ?? "3.12.2",
      goVersion: app.goVersion ?? "1.26.5",
      rustVersion: app.rustVersion ?? "stable",
      bunVersion: app.bunVersion ?? "1.3.14",
      celeryApp: app.celeryApp ?? "",
      celeryWorkerCount: app.celeryWorkerCount != null ? String(app.celeryWorkerCount) : "2",
      celeryConcurrency: app.celeryConcurrency != null ? String(app.celeryConcurrency) : "4",
      celeryQueues: app.celeryQueues ?? "",
      celeryBeatEnabled: app.celeryBeatEnabled ?? false,
      celeryExtraArgs: app.celeryExtraArgs ?? "",
      staticRoot: app.staticRoot ?? "",
      staticSpa: app.staticSpa ?? false,
      mediaEnabled: app.mediaEnabled ?? false,
      mediaMaxUploadMb: app.mediaMaxUploadMb != null ? String(app.mediaMaxUploadMb) : "25",
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
        sourceSubdir: form.sourceSubdir || undefined,
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
      if (isNode || isStatic) patch.nodeVersion = form.nodeVersion || undefined;
      if (isBun)   patch.bunVersion  = form.bunVersion  || undefined;
      if (isDart)  patch.dartVersion = form.dartVersion || undefined;
      if (isGo)    patch.goVersion   = form.goVersion   || undefined;
      if (isRust)  patch.rustVersion = form.rustVersion || undefined;
      if (isStatic) {
        patch.staticRoot = form.staticRoot || undefined;
        patch.staticSpa  = form.staticSpa;
      } else {
        // Local disk media (Model A) — not applicable to static sites.
        patch.mediaEnabled = form.mediaEnabled;
        patch.mediaMaxUploadMb = form.mediaMaxUploadMb
          ? Number(form.mediaMaxUploadMb)
          : undefined;
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
    <Form onSubmit={save}>
      <Stack gap={6}>
        {/* General */}
        <Tile>
          <h3 className="gisila-app__tile-title">General</h3>
          <Stack gap={5}>
            <TextInput
              id="s-name"
              labelText="App name"
              value={form.name}
              onChange={(e) => set("name", e.target.value)}
              required
            />
            <TextInput
              id="s-port"
              labelText="Internal port"
              type="number"
              min={1024}
              max={65535}
              value={form.internalPort}
              onChange={(e) => set("internalPort", e.target.value)}
              placeholder="e.g. 8080"
              helperText="The port your app listens on. Changing this requires a redeploy."
            />
          </Stack>
        </Tile>

        {/* Source */}
        {!isBinary && !isStatic && (
          <Tile>
            <h3 className="gisila-app__tile-title">
              Source{" "}
              <Tag type="cool-gray" size="sm">
                {app.sourceType}
              </Tag>
            </h3>
            <Stack gap={5}>
              {isGit && (
                <>
                  <div className="gisila-app__form-row">
                    <div className="gisila-app__form-field">
                      <TextInput
                        id="s-git-url"
                        labelText="Git URL"
                        placeholder="git@github.com:you/repo.git"
                        value={form.gitUrl}
                        onChange={(e) => set("gitUrl", e.target.value)}
                      />
                    </div>
                    <div className="gisila-app__form-field">
                      <TextInput
                        id="s-git-branch"
                        labelText="Branch"
                        value={form.gitBranch}
                        onChange={(e) => set("gitBranch", e.target.value)}
                      />
                    </div>
                  </div>
                  <TextInput
                    id="s-source-subdir"
                    labelText="Directory (optional — for monorepos)"
                    placeholder="e.g. apps/api"
                    value={form.sourceSubdir}
                    onChange={(e) => set("sourceSubdir", e.target.value)}
                    helperText="If this repo contains multiple projects, set the path to the one to build and run. Leave blank to use the repo root. Takes effect on the next deploy."
                  />
                  <Select
                    id="s-deploy-key"
                    labelText="Deploy key (optional — for private repos)"
                    value={form.deployKeyId || "none"}
                    onChange={(e) =>
                      set("deployKeyId", e.target.value === "none" ? "" : e.target.value)
                    }
                  >
                    <SelectItem value="none" text="None (public repo / HTTPS)" />
                    {(sshKeys.data?.results ?? []).map((k) => (
                      <SelectItem
                        key={k.id}
                        value={String(k.id)}
                        text={k.algorithm ? `${k.name} (${k.algorithm})` : k.name}
                      />
                    ))}
                  </Select>
                </>
              )}
              <div className="gisila-app__form-row">
                <div className="gisila-app__form-field">
                  <TextInput
                    id="s-build"
                    labelText="Build command (optional)"
                    placeholder={
                      isPython || isCelery
                        ? "pip install -r requirements.txt"
                        : "dart compile exe bin/server.dart -o build/app"
                    }
                    value={form.buildCommand}
                    onChange={(e) => set("buildCommand", e.target.value)}
                    helperText={
                      isPython || isCelery
                        ? "Leave blank — dependencies from requirements.txt are installed automatically."
                        : undefined
                    }
                  />
                </div>
                <div className="gisila-app__form-field">
                  <TextInput
                    id="s-start"
                    labelText="Start command (optional)"
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
              <TextInput
                id="s-health"
                labelText="Health check path (optional)"
                placeholder="/health"
                value={form.healthCheckPath}
                onChange={(e) => set("healthCheckPath", e.target.value)}
              />
            </Stack>
          </Tile>
        )}

        {/* Python */}
        {isPython && (
          <Tile>
            <h3 className="gisila-app__tile-title">Python / WSGI · ASGI</h3>
            <Stack gap={6}>
              <VersionSelect
                id="s-python-version"
                labelText="Python version"
                value={form.pythonVersion}
                onChange={(v) => set("pythonVersion", v)}
              >
                {versionItems("python", form.pythonVersion, appsList, catalogList)}
              </VersionSelect>

              <TileGroup
                name="s-python-mode"
                legend="Server mode"
                valueSelected={form.pythonMode}
                onChange={(v) => set("pythonMode", v)}
              >
                <RadioTile id="s-mode-wsgi" value="wsgi">
                  <strong>WSGI</strong>
                  <p className="gisila-app__hint">Django, Flask — synchronous</p>
                </RadioTile>
                <RadioTile id="s-mode-asgi" value="asgi">
                  <strong>ASGI</strong>
                  <p className="gisila-app__hint">FastAPI, Starlette — async</p>
                </RadioTile>
              </TileGroup>

              <TextInput
                id="s-wsgi"
                labelText="Application target"
                placeholder={
                  form.pythonMode === "asgi"
                    ? "myapp.asgi:application"
                    : "myapp.wsgi:application"
                }
                value={form.wsgiApp}
                onChange={(e) => set("wsgiApp", e.target.value)}
              />

              {/* Gunicorn tuning */}
              <div className="gisila-app__choice">
                <Stack gap={5}>
                  <p className="gisila-app__label">Gunicorn</p>
                  <div className="gisila-app__form-row">
                    <div className="gisila-app__form-field">
                      <TextInput
                        id="s-gworkers"
                        labelText="Workers"
                        type="number"
                        min={1}
                        max={64}
                        placeholder="4"
                        value={form.gunicornWorkers}
                        onChange={(e) => set("gunicornWorkers", e.target.value)}
                      />
                    </div>
                    <div className="gisila-app__form-field">
                      <TextInput
                        id="s-gthreads"
                        labelText="Threads / worker"
                        type="number"
                        min={1}
                        max={64}
                        placeholder="1"
                        value={form.gunicornThreads}
                        onChange={(e) => set("gunicornThreads", e.target.value)}
                      />
                    </div>
                    <div className="gisila-app__form-field">
                      <TextInput
                        id="s-gtimeout"
                        labelText="Timeout (s)"
                        type="number"
                        min={1}
                        max={3600}
                        placeholder="120"
                        value={form.gunicornTimeout}
                        onChange={(e) => set("gunicornTimeout", e.target.value)}
                      />
                    </div>
                  </div>
                  <TextInput
                    id="s-gbind"
                    labelText="Bind address (optional)"
                    placeholder={`0.0.0.0:${app.internalPort} (internal port)`}
                    value={form.gunicornBind}
                    onChange={(e) => set("gunicornBind", e.target.value)}
                    helperText={`Defaults to 0.0.0.0:$PORT (the app's internal port ${app.internalPort}). Only override if you keep the same port so the nginx proxy still resolves.`}
                  />
                  <TextInput
                    id="s-gextra"
                    labelText="Extra arguments (optional)"
                    placeholder="--max-requests 1000 --graceful-timeout 30"
                    value={form.gunicornExtraArgs}
                    onChange={(e) => set("gunicornExtraArgs", e.target.value)}
                  />
                </Stack>
              </div>
            </Stack>
          </Tile>
        )}

        {/* Runtime version */}
        {(isNode || isBun || isDart || isGo || isRust || isStatic) && (
          <Tile>
            <h3 className="gisila-app__tile-title">Runtime version</h3>
            <Stack gap={5}>
              <p className="gisila-app__label">
                {isStatic
                  ? "Node.js used for the static build command (npm / Vite / …). Takes effect on the next deployment."
                  : "Changing the version takes effect on the next deployment."}
              </p>

              {(isNode || isStatic) && (
                <VersionSelect
                  id="s-node-version"
                  labelText="Node.js version"
                  value={form.nodeVersion}
                  onChange={(v) => set("nodeVersion", v)}
                >
                  {versionItems("node", form.nodeVersion, appsList, catalogList)}
                </VersionSelect>
              )}

              {isBun && (
                <VersionSelect
                  id="s-bun-version"
                  labelText="Bun version"
                  value={form.bunVersion}
                  onChange={(v) => set("bunVersion", v)}
                >
                  {versionItems("bun", form.bunVersion, appsList, catalogList)}
                </VersionSelect>
              )}

              {isDart && (
                <VersionSelect
                  id="s-dart-version"
                  labelText="Dart SDK version"
                  value={form.dartVersion}
                  onChange={(v) => set("dartVersion", v)}
                >
                  {versionItems("dart", form.dartVersion, appsList, catalogList)}
                </VersionSelect>
              )}

              {isGo && (
                <VersionSelect
                  id="s-go-version"
                  labelText="Go version"
                  value={form.goVersion}
                  onChange={(v) => set("goVersion", v)}
                >
                  {versionItems("go", form.goVersion, appsList, catalogList)}
                </VersionSelect>
              )}

              {isRust && (
                <VersionSelect
                  id="s-rust-version"
                  labelText="Rust toolchain"
                  value={form.rustVersion}
                  onChange={(v) => set("rustVersion", v)}
                  helperText="stable is recommended. nightly enables unstable features."
                >
                  {versionItems("rust", form.rustVersion, appsList, catalogList)}
                </VersionSelect>
              )}
            </Stack>
          </Tile>
        )}

        {/* Celery */}
        {isCelery && (
          <Tile>
            <h3 className="gisila-app__tile-title">Celery / Task queue</h3>
            <Stack gap={6}>
              <VersionSelect
                id="s-celery-python-version"
                labelText="Python version"
                value={form.pythonVersion}
                onChange={(v) => set("pythonVersion", v)}
              >
                {versionItems("python", form.pythonVersion, appsList, catalogList)}
              </VersionSelect>

              <TextInput
                id="s-celery-app"
                labelText="Celery application"
                placeholder="myproject.celery:app"
                value={form.celeryApp}
                onChange={(e) => set("celeryApp", e.target.value)}
                helperText="e.g. proj.celery:app or myproject for auto-discovery."
              />

              <div className="gisila-app__choice">
                <Stack gap={5}>
                  <p className="gisila-app__label">Workers</p>
                  <div className="gisila-app__form-row">
                    <div className="gisila-app__form-field">
                      <TextInput
                        id="s-cwcount"
                        labelText="Worker processes"
                        type="number"
                        min={1}
                        max={32}
                        placeholder="2"
                        value={form.celeryWorkerCount}
                        onChange={(e) => set("celeryWorkerCount", e.target.value)}
                        helperText="Each worker is a separate systemd service."
                      />
                    </div>
                    <div className="gisila-app__form-field">
                      <TextInput
                        id="s-cconc"
                        labelText="Concurrency / worker"
                        type="number"
                        min={1}
                        max={64}
                        placeholder="4"
                        value={form.celeryConcurrency}
                        onChange={(e) => set("celeryConcurrency", e.target.value)}
                        helperText="Passed as -c to each worker."
                      />
                    </div>
                  </div>
                  <TextInput
                    id="s-cqueues"
                    labelText="Queues (optional)"
                    placeholder="celery,high-priority"
                    value={form.celeryQueues}
                    onChange={(e) => set("celeryQueues", e.target.value)}
                  />
                  <TextInput
                    id="s-cextra"
                    labelText="Extra arguments (optional)"
                    placeholder="--max-tasks-per-child=1000"
                    value={form.celeryExtraArgs}
                    onChange={(e) => set("celeryExtraArgs", e.target.value)}
                  />
                </Stack>
              </div>

              <div className="gisila-app__choice">
                <Checkbox
                  id="s-celery-beat"
                  labelText="Enable Celery Beat scheduler"
                  checked={form.celeryBeatEnabled}
                  onChange={(_, { checked }) => set("celeryBeatEnabled", checked)}
                />
                <p className="gisila-app__hint">
                  Launches a <code>celery beat</code> process alongside the
                  workers for periodic task scheduling.
                </p>
              </div>

              <InlineNotification
                kind="info"
                lowContrast
                hideCloseButton
                title="Flower"
                subtitle={`Monitoring UI is automatically deployed on this app's port (${app.internalPort}) and proxied via Nginx. No extra configuration needed.`}
              />
            </Stack>
          </Tile>
        )}

        {/* Static */}
        {isStatic && (
          <Tile>
            <h3 className="gisila-app__tile-title">Static site</h3>
            <Stack gap={6}>
              <TextInput
                id="s-static-build"
                labelText="Build command (optional)"
                placeholder="npm ci && npm run build"
                value={form.buildCommand}
                onChange={(e) => set("buildCommand", e.target.value)}
                helperText="Run a build step before Nginx serves the files (e.g. Vite, CRA, Hugo). Leave blank for plain HTML/CSS/JS repos."
              />

              <TextInput
                id="s-static-root"
                labelText="Static files directory (optional)"
                placeholder="dist"
                value={form.staticRoot}
                onChange={(e) => set("staticRoot", e.target.value)}
                helperText="Path relative to the repository root that Nginx serves, e.g. dist or build/public. Leave blank for the repo root."
              />

              <div className="gisila-app__choice">
                <Checkbox
                  id="s-static-spa"
                  labelText="SPA mode"
                  checked={form.staticSpa}
                  onChange={(_, { checked }) => set("staticSpa", checked)}
                />
                <p className="gisila-app__hint">
                  Falls back to <code>index.html</code> for all routes. Required
                  for React, Vue, Angular, and other client-side routers.
                </p>
              </div>

              <div className="gisila-app__note">
                <p className="gisila-app__label">Nginx behavior</p>
                <div className="gisila-app__note-list">
                  <span>
                    • Files are served directly — no application process runs.
                  </span>
                  <span>
                    • CSS/JS/image assets receive a 1-year{" "}
                    <code>Cache-Control: immutable</code> header.
                  </span>
                  <span>
                    • Attach a domain to get an automatic Let&apos;s Encrypt
                    certificate.
                  </span>
                </div>
              </div>
            </Stack>
          </Tile>
        )}

        {/* Media (local disk) */}
        {!isStatic && (
          <Tile>
            <h3 className="gisila-app__tile-title">
              Media storage (local disk)
            </h3>
            <Stack gap={5}>
              <div className="gisila-app__choice">
                <Checkbox
                  id="s-media-enabled"
                  labelText="Enable file uploads on disk"
                  checked={form.mediaEnabled}
                  onChange={(_, { checked }) => set("mediaEnabled", checked)}
                />
                <p className="gisila-app__hint">
                  Creates a persistent <code>shared/media</code> directory and
                  exposes <code>MEDIA_ROOT</code> to your app. Nginx serves it at{" "}
                  <code>/media/</code> and offers an internal{" "}
                  <code>/_protected/</code> location for auth-gated downloads via{" "}
                  <code>X-Accel-Redirect</code>.
                </p>
              </div>
              {form.mediaEnabled && (
                <div style={{ maxInlineSize: "12rem" }}>
                  <TextInput
                    id="s-media-max"
                    labelText="Max upload size (MB)"
                    type="number"
                    min={1}
                    max={5120}
                    value={form.mediaMaxUploadMb}
                    onChange={(e) => set("mediaMaxUploadMb", e.target.value)}
                    helperText="Sets nginx client_max_body_size for this app. MEDIA_ROOT takes effect on the next deploy."
                  />
                </div>
              )}
            </Stack>
          </Tile>
        )}

        {/* Resources */}
        <Tile>
          <h3 className="gisila-app__tile-title">Resource limits</h3>
          <div className="gisila-app__form-row">
            <div className="gisila-app__form-field">
              <TextInput
                id="s-mem"
                labelText="Memory (MB)"
                type="number"
                min={64}
                max={32768}
                value={form.memoryMbLimit}
                onChange={(e) => set("memoryMbLimit", Number(e.target.value))}
              />
            </div>
            <div className="gisila-app__form-field">
              <TextInput
                id="s-cpu"
                labelText="CPU quota (%)"
                type="number"
                min={1}
                max={400}
                value={form.cpuQuotaPercent}
                onChange={(e) => set("cpuQuotaPercent", Number(e.target.value))}
              />
            </div>
            <div className="gisila-app__form-field">
              <TextInput
                id="s-tasks"
                labelText="Tasks max"
                type="number"
                min={10}
                max={4096}
                value={form.tasksLimit}
                onChange={(e) => set("tasksLimit", Number(e.target.value))}
              />
            </div>
          </div>
        </Tile>

        <div className="gisila-app__row-actions">
          <Button type="submit" disabled={saving}>
            {saving ? "Saving…" : "Save changes"}
          </Button>
        </div>
      </Stack>
    </Form>
  );
}
