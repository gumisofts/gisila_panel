"use client";

import { useEffect, useState, type ReactNode } from "react";
import { useRouter } from "@/compat/navigation";
import useSWR from "swr";
import { Add } from "@carbon/icons-react";
import {
  Button,
  ButtonSet,
  Checkbox,
  Form,
  FormGroup,
  InlineNotification,
  Link as CarbonLink,
  Modal,
  NumberInput,
  RadioButton,
  RadioButtonGroup,
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
import { Page, PageHeader, PageSection } from "@/components/page";
import { api, fetcher } from "@/lib/api";
import type {
  App,
  Application,
  ApplicationDef,
  DeployMode,
  ExposeMode,
  ListResponse,
  Project,
  SshKey,
  Team,
} from "@/lib/types";
import { DEPLOY_MODE_LABEL, EXPOSE_MODE_LABEL } from "@/lib/types";
import { versionItems } from "../_runtime-versions";
import "../_apps.scss";

// ── Page ─────────────────────────────────────────────────────────────────────

export default function NewAppPage() {
  const router = useRouter();
  const projects = useSWR<ListResponse<Project>>("/projects/", fetcher);
  const teams = useSWR<ListResponse<Team>>("/teams/", fetcher);
  const sshKeys = useSWR<{ results: SshKey[] }>("/me/security/ssh-keys", fetcher);
  const applications = useSWR<ListResponse<Application>>("/applications/", fetcher);
  const catalog = useSWR<ListResponse<ApplicationDef>>(
    "/applications/catalog",
    fetcher,
  );
  const installedApps = (applications.data?.results ?? []).filter(
    (a) => a.status === "installed",
  );
  const appsList = applications.data?.results;
  const catalogList = catalog.data?.results;

  // Quick project-create dialog state
  const [projDialog, setProjDialog] = useState(false);
  const [newProjTeam, setNewProjTeam] = useState("");
  const [newProjName, setNewProjName] = useState("");
  const [creatingProj, setCreatingProj] = useState(false);

  const [form, setForm] = useState({
    projectId: 0,
    name: "",
    runtime: "dart",
    applicationId: 0,
    deploymentMode: "" as DeployMode | "",
    sourceType: "git",
    gitUrl: "",
    gitBranch: "main",
    sourceSubdir: "",
    buildCommand: "",
    startCommand: "",
    // Python-specific
    pythonVersion: "3.13.15",
    pythonMode: "wsgi",
    wsgiApp: "",
    // Gunicorn tuning
    gunicornWorkers: "",
    gunicornThreads: "",
    gunicornTimeout: "",
    gunicornBind: "",
    gunicornExtraArgs: "",
    // Runtime version pins. These are only the initial selection — the option
    // lists themselves come from the Application catalog.
    nodeVersion: "24.19.0",
    dartVersion: "3.12.2",
    goVersion: "1.26.5",
    rustVersion: "stable",
    bunVersion: "1.3.14",
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
    // Network exposure — web (default) | tcp | internal. Immutable after
    // creation.
    exposeMode: "web" as ExposeMode,
    publiclyReachable: true,
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

  const selectedApplication = installedApps.find(
    (a) => a.id === form.applicationId,
  );
  const applicationModes = (selectedApplication?.deployModes.split(",").filter(
    Boolean,
  ) ?? []) as DeployMode[];

  function selectApplication(app: Application) {
    setForm((f) => ({
      ...f,
      runtime: app.key,
      applicationId: app.id,
      deploymentMode: app.defaultDeployMode,
    }));
  }

  // Default to the first installed Application once the catalog loads.
  useEffect(() => {
    if (form.applicationId === 0 && installedApps.length > 0) {
      selectApplication(installedApps[0]);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [installedApps.length]);

  async function createProject(e?: React.FormEvent) {
    e?.preventDefault();
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
        applicationId: form.applicationId || undefined,
        runtime: form.runtime,
        deploymentMode: form.deploymentMode || undefined,
        sourceType: form.sourceType,
        // Static sites are served directly by Nginx and have no listening port.
        ...(isStatic ? {} : { internalPort: Number(form.internalPort) }),
        gitUrl: form.gitUrl || undefined,
        gitBranch: form.gitBranch || undefined,
        sourceSubdir: form.sourceSubdir || undefined,
        buildCommand: form.buildCommand || undefined,
        startCommand: form.startCommand || undefined,
        // Static sites are always web-exposed (Nginx serves the files
        // directly) — exposeMode only applies to process-backed runtimes.
        exposeMode: isStatic ? "web" : form.exposeMode,
        ...(!isStatic && form.exposeMode === "tcp"
          ? { publiclyReachable: form.publiclyReachable }
          : {}),
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
      if (isNode || isStatic) payload.nodeVersion = form.nodeVersion || undefined;
      if (isBun)   payload.bunVersion  = form.bunVersion  || undefined;
      if (isDart)  payload.dartVersion = form.dartVersion || undefined;
      if (isGo)    payload.goVersion   = form.goVersion   || undefined;
      if (isRust)  payload.rustVersion = form.rustVersion || undefined;
      if (isStatic) {
        payload.staticRoot = form.staticRoot;
        payload.staticSpa = form.staticSpa;
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

  const teamCount = teams.data?.results.length ?? 0;

  return (
    <Page>
      <PageHeader
        title="New app"
        description="Pick a runtime and source. We'll create the Linux user, systemd unit, AppArmor profile and Nginx vhost automatically."
      />

      <PageSection title="App details">
        <Form onSubmit={submit}>
          <Stack gap={7}>
            {/* Project */}
            <div className="gisila-app-form__field-with-action">
              <Select
                id="projectId"
                labelText="Project"
                value={form.projectId}
                onChange={(e) => set("projectId", Number(e.target.value))}
                required
              >
                <SelectItem
                  value={0}
                  disabled
                  text={
                    (projects.data?.results.length ?? 0) === 0
                      ? "No projects yet — create one above"
                      : "Choose a project…"
                  }
                />
                {projects.data?.results.map((p) => (
                  <SelectItem key={p.id} value={p.id} text={p.name} />
                ))}
              </Select>
              <Button
                type="button"
                kind="ghost"
                renderIcon={Add}
                onClick={() => {
                  setNewProjTeam(teams.data?.results[0] ? String(teams.data.results[0].id) : "");
                  setNewProjName("");
                  setProjDialog(true);
                }}
              >
                New project
              </Button>
            </div>

            {/* Name + Runtime */}
            <div className="gisila-app-form__two-col">
              <TextInput
                id="name"
                labelText="App name"
                required
                placeholder="my-api"
                value={form.name}
                onChange={(e) => set("name", e.target.value)}
              />
              {installedApps.length === 0 ? (
                <FormGroup legendText="Runtime">
                  <p className="gisila-app-form__hint">
                    No runtimes installed yet.{" "}
                    <CarbonLink href="/runtimes">Install one</CarbonLink> from
                    Runtimes first.
                  </p>
                </FormGroup>
              ) : (
                <RadioButtonGroup
                  name="application"
                  legendText="Runtime"
                  orientation="vertical"
                  valueSelected={form.applicationId}
                  onChange={(selection) => {
                    const app = installedApps.find(
                      (a) => a.id === Number(selection),
                    );
                    if (app) selectApplication(app);
                  }}
                >
                  {installedApps.map((app) => (
                    <RadioButton
                      key={app.id}
                      id={`application-${app.id}`}
                      value={app.id}
                      labelText={app.displayName}
                    />
                  ))}
                </RadioButtonGroup>
              )}
            </div>

            {/* Deployment mode — only shown when the selected Application supports
                more than one mechanism (e.g. Node/Bun: build vs. run as-is). */}
            {applicationModes.length > 1 && (
              <div className="gisila-tile-grid gisila-tile-grid--2">
                <TileGroup
                  name="deploymentMode"
                  legend="Deployment mode"
                  valueSelected={form.deploymentMode}
                  onChange={(selection) => set("deploymentMode", selection)}
                >
                  {applicationModes.map((m) => (
                    <RadioTile key={m} id={`deployment-mode-${m}`} value={m}>
                      <span className="gisila-app-form__tile-title">
                        {DEPLOY_MODE_LABEL[m] ?? m}
                      </span>
                      <span className="gisila-app-form__tile-desc">
                        {m === "build_execute"
                          ? "Compile/package first, then execute the built artifact."
                          : "Run the source directly — no build step."}
                      </span>
                    </RadioTile>
                  ))}
                </TileGroup>
              </div>
            )}

            {/* Port — static sites are served directly by Nginx, no port. */}
            {!isStatic && (
              <NumberInput
                id="internalPort"
                label="Internal port"
                min={1024}
                max={65535}
                required
                allowEmpty
                placeholder="e.g. 8080"
                value={form.internalPort}
                onChange={(_event, { value }) =>
                  set("internalPort", String(value))
                }
                helperText="The port your app listens on (1024–65535). Must be unique across all apps."
              />
            )}

            {/* Exposure — how the app reaches the network. Static sites are
                always Nginx-served, so the picker doesn't apply to them. */}
            {!isStatic && (
              <div className="gisila-tile-grid gisila-tile-grid--3">
                <TileGroup
                  name="exposeMode"
                  legend="Exposure"
                  valueSelected={form.exposeMode}
                  onChange={(selection) =>
                    set("exposeMode", selection as ExposeMode)
                  }
                >
                  {(["web", "tcp", "internal"] as ExposeMode[]).map((m) => (
                    <RadioTile key={m} id={`expose-mode-${m}`} value={m}>
                      <span className="gisila-app-form__tile-title">
                        {EXPOSE_MODE_LABEL[m]}
                      </span>
                      <span className="gisila-app-form__tile-desc">
                        {m === "web"
                          ? "Nginx reverse proxy + a domain, TLS included."
                          : m === "tcp"
                            ? "Direct TCP port, no Nginx/domain — for custom protocols (game servers, MQTT, gRPC, …)."
                            : "No public exposure — background workers, sidecars reachable only from localhost."}
                      </span>
                    </RadioTile>
                  ))}
                </TileGroup>
              </div>
            )}

            {!isStatic && form.exposeMode === "tcp" && (
              <Tile>
                <Stack gap={5}>
                  <div className="gisila-app-form__banner">
                    <Tag type="purple" size="sm">TCP service</Tag>
                    <span className="gisila-app-form__hint">
                      No reverse proxy in front — the app talks directly to clients
                    </span>
                  </div>

                  <Checkbox
                    id="publiclyReachable"
                    labelText="Publicly reachable"
                    checked={form.publiclyReachable}
                    onChange={(_event, { checked }) =>
                      set("publiclyReachable", checked)
                    }
                    helperText="Opens the port on the host firewall. Turn this off to keep the app reachable only from other local processes."
                  />

                  <InlineNotification
                    kind="warning"
                    lowContrast
                    hideCloseButton
                    title="Bind to 0.0.0.0, not 127.0.0.1"
                    subtitle="Your app must listen on 0.0.0.0:$PORT — there is no Nginx in front to reach it via loopback."
                  />
                </Stack>
              </Tile>
            )}

            {/* ── Python-specific section ──────────────────────────────────── */}
            {isPython && (
              <Tile>
                <Stack gap={5}>
                  <div className="gisila-app-form__banner">
                    <Tag type="blue" size="sm">Python / WSGI·ASGI</Tag>
                    <span className="gisila-app-form__hint">
                      Served by Gunicorn via pyenv-managed virtualenv
                    </span>
                  </div>

                  {/* Python version */}
                  <Select
                    id="pythonVersion"
                    labelText="Python version"
                    value={form.pythonVersion}
                    onChange={(e) => set("pythonVersion", e.target.value)}
                    helperText={
                      <>
                        Installed via pyenv at{" "}
                        <code className="gisila-code">/opt/pyenv</code> during the
                        first deploy.
                      </>
                    }
                  >
                    {versionItems("python", form.pythonVersion, appsList, catalogList)}
                  </Select>

                  {/* Server mode */}
                  <div className="gisila-tile-grid gisila-tile-grid--2">
                    <TileGroup
                      name="pythonMode"
                      legend="Server mode"
                      valueSelected={form.pythonMode}
                      onChange={(selection) => set("pythonMode", selection)}
                    >
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
                        <RadioTile key={id} id={`python-mode-${id}`} value={id}>
                          <span className="gisila-app-form__tile-title">{label}</span>
                          <span className="gisila-app-form__tile-desc">{desc}</span>
                        </RadioTile>
                      ))}
                    </TileGroup>
                    <p className="gisila-app-form__hint">
                      {form.pythonMode === "asgi"
                        ? "Uses uvicorn worker class: --worker-class uvicorn.workers.UvicornWorker"
                        : "Standard sync workers: --workers 4"}
                    </p>
                  </div>

                  {/* WSGI/ASGI application target */}
                  <TextInput
                    id="wsgiApp"
                    labelText={labelWithNote(
                      "Application target",
                      "(passed to gunicorn as the app argument)",
                    )}
                    placeholder={
                      form.pythonMode === "asgi"
                        ? "myapp.asgi:application"
                        : "myapp.wsgi:application"
                    }
                    value={form.wsgiApp}
                    onChange={(e) => set("wsgiApp", e.target.value)}
                    helperText={
                      <>
                        Leave blank to default to{" "}
                        <code className="gisila-code">app:application</code>.
                        Examples:{" "}
                        <code className="gisila-code">myproject.wsgi:application</code>{" "}
                        (Django), <code className="gisila-code">main:app</code>{" "}
                        (FastAPI/Flask).
                      </>
                    }
                  />

                  {/* Gunicorn tuning */}
                  <FormGroup legendText="Gunicorn (optional)">
                    <Stack gap={5}>
                      <div className="gisila-app-form__three-col">
                        <NumberInput
                          id="g-workers"
                          label="Workers"
                          min={1}
                          allowEmpty
                          placeholder="4"
                          value={form.gunicornWorkers}
                          onChange={(_event, { value }) =>
                            set("gunicornWorkers", String(value))
                          }
                        />
                        <NumberInput
                          id="g-threads"
                          label="Threads"
                          min={1}
                          allowEmpty
                          placeholder="1"
                          value={form.gunicornThreads}
                          onChange={(_event, { value }) =>
                            set("gunicornThreads", String(value))
                          }
                        />
                        <NumberInput
                          id="g-timeout"
                          label="Timeout (s)"
                          min={1}
                          allowEmpty
                          placeholder="120"
                          value={form.gunicornTimeout}
                          onChange={(_event, { value }) =>
                            set("gunicornTimeout", String(value))
                          }
                        />
                      </div>
                      <TextInput
                        id="g-bind"
                        labelText={labelWithNote(
                          "Bind address",
                          "(defaults to 0.0.0.0:$PORT)",
                        )}
                        placeholder="0.0.0.0:$PORT"
                        value={form.gunicornBind}
                        onChange={(e) => set("gunicornBind", e.target.value)}
                      />
                      <TextInput
                        id="g-extra"
                        labelText={labelWithNote("Extra arguments", "(optional)")}
                        placeholder="--max-requests 1000 --graceful-timeout 30"
                        value={form.gunicornExtraArgs}
                        onChange={(e) => set("gunicornExtraArgs", e.target.value)}
                      />
                    </Stack>
                  </FormGroup>
                </Stack>
              </Tile>
            )}

            {/* ── Runtime version pickers ──────────────────────────────────── */}
            {(isNode || isBun || isDart || isGo || isRust || isStatic) && (
              <Tile>
                <Stack gap={5}>
                  <div className="gisila-app-form__banner">
                    <Tag type="cyan" size="sm">Runtime version</Tag>
                    <span className="gisila-app-form__hint">
                      {isStatic
                        ? "Node.js used for the static build (npm / Vite / …)."
                        : "Pin a specific runtime version. Leave as-is to use the latest shown below."}
                    </span>
                  </div>

                  {(isNode || isStatic) && (
                    <Select
                      id="nodeVersion"
                      labelText="Node.js version"
                      value={form.nodeVersion}
                      onChange={(e) => set("nodeVersion", e.target.value)}
                    >
                      {versionItems("node", form.nodeVersion, appsList, catalogList)}
                    </Select>
                  )}

                  {isBun && (
                    <Select
                      id="bunVersion"
                      labelText="Bun version"
                      value={form.bunVersion}
                      onChange={(e) => set("bunVersion", e.target.value)}
                    >
                      {versionItems("bun", form.bunVersion, appsList, catalogList)}
                    </Select>
                  )}

                  {isDart && (
                    <Select
                      id="dartVersion"
                      labelText="Dart SDK version"
                      value={form.dartVersion}
                      onChange={(e) => set("dartVersion", e.target.value)}
                    >
                      {versionItems("dart", form.dartVersion, appsList, catalogList)}
                    </Select>
                  )}

                  {isGo && (
                    <Select
                      id="goVersion"
                      labelText="Go version"
                      value={form.goVersion}
                      onChange={(e) => set("goVersion", e.target.value)}
                    >
                      {versionItems("go", form.goVersion, appsList, catalogList)}
                    </Select>
                  )}

                  {isRust && (
                    <Select
                      id="rustVersion"
                      labelText="Rust toolchain"
                      value={form.rustVersion}
                      onChange={(e) => set("rustVersion", e.target.value)}
                      helperText={
                        <>
                          <span className="gisila-code">stable</span> is the
                          recommended default.{" "}
                          <span className="gisila-code">nightly</span> enables
                          unstable features.
                        </>
                      }
                    >
                      {versionItems("rust", form.rustVersion, appsList, catalogList)}
                    </Select>
                  )}
                </Stack>
              </Tile>
            )}

            {/* ── Celery-specific section ──────────────────────────────────── */}
            {isCelery && (
              <Tile>
                <Stack gap={5}>
                  <div className="gisila-app-form__banner">
                    <Tag type="magenta" size="sm">Celery / Task queue</Tag>
                    <span className="gisila-app-form__hint">
                      Workers + Flower UI, served via Nginx proxy
                    </span>
                  </div>

                  {/* Python version (shared with Celery) */}
                  <Select
                    id="celeryPythonVersion"
                    labelText="Python version"
                    value={form.pythonVersion}
                    onChange={(e) => set("pythonVersion", e.target.value)}
                  >
                    {versionItems("python", form.pythonVersion, appsList, catalogList)}
                  </Select>

                  {/* Celery app path */}
                  <TextInput
                    id="celeryApp"
                    labelText={labelWithNote("Celery application", "(required)")}
                    placeholder="myproject.celery:app"
                    required={isCelery}
                    value={form.celeryApp}
                    onChange={(e) => set("celeryApp", e.target.value)}
                    helperText={
                      <>
                        The Celery application instance, e.g.{" "}
                        <code className="gisila-code">proj.celery:app</code> or{" "}
                        <code className="gisila-code">myproject</code> for
                        auto-discovery.
                      </>
                    }
                  />

                  {/* Workers + concurrency + queues */}
                  <FormGroup legendText="Workers">
                    <Stack gap={5}>
                      <div className="gisila-app-form__two-col">
                        <NumberInput
                          id="c-wcount"
                          label="Worker processes"
                          min={1}
                          max={32}
                          allowEmpty
                          placeholder="2"
                          value={form.celeryWorkerCount}
                          onChange={(_event, { value }) =>
                            set("celeryWorkerCount", String(value))
                          }
                          helperText="Number of separate worker processes to launch."
                        />
                        <NumberInput
                          id="c-conc"
                          label="Concurrency / worker"
                          min={1}
                          max={64}
                          allowEmpty
                          placeholder="4"
                          value={form.celeryConcurrency}
                          onChange={(_event, { value }) =>
                            set("celeryConcurrency", String(value))
                          }
                          helperText="Threads or processes per worker (-c)."
                        />
                      </div>
                      <TextInput
                        id="c-queues"
                        labelText={labelWithNote("Queues", "(optional)")}
                        placeholder="celery,high-priority,low-priority"
                        value={form.celeryQueues}
                        onChange={(e) => set("celeryQueues", e.target.value)}
                        helperText="Comma-separated queue names. Leave blank for the default queue."
                      />
                      <TextInput
                        id="c-extra"
                        labelText={labelWithNote(
                          "Extra worker arguments",
                          "(optional)",
                        )}
                        placeholder="--max-tasks-per-child=1000"
                        value={form.celeryExtraArgs}
                        onChange={(e) => set("celeryExtraArgs", e.target.value)}
                      />
                    </Stack>
                  </FormGroup>

                  {/* Beat scheduler */}
                  <Checkbox
                    id="celeryBeatEnabled"
                    labelText="Enable Celery Beat scheduler"
                    checked={form.celeryBeatEnabled}
                    onChange={(_event, { checked }) =>
                      set("celeryBeatEnabled", checked)
                    }
                    helperText={
                      <>
                        Launches a{" "}
                        <code className="gisila-code">celery beat</code> process
                        alongside the workers for periodic task scheduling.
                      </>
                    }
                  />

                  <InlineNotification
                    kind="info"
                    lowContrast
                    hideCloseButton
                    title="Flower monitoring"
                    subtitle="Flower monitoring UI is automatically deployed and accessible via your app's domain. The internal port is proxied by Nginx."
                  />
                </Stack>
              </Tile>
            )}

            {/* ── Static site section ──────────────────────────────────────── */}
            {isStatic && (
              <Tile>
                <Stack gap={5}>
                  <div className="gisila-app-form__banner">
                    <Tag type="green" size="sm">Static / HTML · CSS · JS</Tag>
                    <span className="gisila-app-form__hint">
                      Served directly by Nginx — no process required
                    </span>
                  </div>

                  <TextInput
                    id="staticRoot"
                    labelText={labelWithNote(
                      "Static files directory",
                      "(optional)",
                    )}
                    placeholder="dist"
                    value={form.staticRoot}
                    onChange={(e) => set("staticRoot", e.target.value)}
                    helperText={
                      <>
                        Path relative to the repository root where Nginx should
                        serve files, e.g.{" "}
                        <code className="gisila-code">dist</code> or{" "}
                        <code className="gisila-code">build/public</code>. Leave
                        blank to serve the repository root.
                      </>
                    }
                  />

                  <Checkbox
                    id="staticSpa"
                    labelText="SPA mode"
                    checked={form.staticSpa}
                    onChange={(_event, { checked }) =>
                      set("staticSpa", checked)
                    }
                    helperText={
                      <>
                        Falls back to{" "}
                        <code className="gisila-code">index.html</code> for all
                        routes (React, Vue, Angular, etc.).
                      </>
                    }
                  />

                  <p className="gisila-app-form__hint">
                    Attach a domain after creating the app to make it publicly accessible via HTTPS.
                    Static assets (CSS/JS/images) receive a 1-year cache header automatically.
                  </p>
                </Stack>
              </Tile>
            )}

            {/* Source */}
            <div className="gisila-tile-grid gisila-tile-grid--3">
              <TileGroup
                name="sourceType"
                legend="Source"
                valueSelected={form.sourceType}
                onChange={(selection) => set("sourceType", selection)}
              >
                {["git", "binary", "zip"].map((s) => (
                  <RadioTile key={s} id={`source-type-${s}`} value={s}>
                    {s}
                  </RadioTile>
                ))}
              </TileGroup>
            </div>

            {form.sourceType === "git" && (
              <Stack gap={5}>
                <div className="gisila-app-form__two-col">
                  <TextInput
                    id="gitUrl"
                    labelText="Git URL"
                    placeholder="git@github.com:you/repo.git"
                    value={form.gitUrl}
                    onChange={(e) => set("gitUrl", e.target.value)}
                  />
                  <TextInput
                    id="gitBranch"
                    labelText="Branch"
                    value={form.gitBranch}
                    onChange={(e) => set("gitBranch", e.target.value)}
                  />
                </div>

                <TextInput
                  id="sourceSubdir"
                  labelText={labelWithNote(
                    "Directory",
                    "(optional — for monorepos)",
                  )}
                  placeholder="e.g. apps/api"
                  value={form.sourceSubdir}
                  onChange={(e) => set("sourceSubdir", e.target.value)}
                  helperText="If this repo contains multiple projects, set the path to the one to build and run. Leave blank to use the repo root."
                />

                {/* Deploy key picker */}
                <Select
                  id="deployKey"
                  labelText={labelWithNote(
                    "Deploy key",
                    "(optional — required for private repos via SSH)",
                  )}
                  value={form.deployKeyId === "" ? "none" : String(form.deployKeyId)}
                  onChange={(e) =>
                    set("deployKeyId", e.target.value === "none" ? "" : e.target.value)
                  }
                  helperText={
                    !sshKeys.data?.results?.length ? (
                      <>
                        No SSH keys yet.{" "}
                        <CarbonLink href="/settings/ssh-keys">
                          Generate a deploy key
                        </CarbonLink>{" "}
                        to use with private repos.
                      </>
                    ) : undefined
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
              </Stack>
            )}

            {form.sourceType === "binary" && (
              <InlineNotification
                kind="info"
                lowContrast
                hideCloseButton
                title="Binary upload"
                subtitle="Upload your pre-compiled binary via the app detail page after creating the app. No build command is needed — the binary runs directly inside a sandboxed systemd unit."
              />
            )}

            {/* Build + Start commands — hidden for runtimes that don't need them */}
            {!isBinary && !isCelery && !isStatic && (
              <div className="gisila-app-form__two-col">
                <TextInput
                  id="buildCommand"
                  labelText={labelWithNote("Build command", "(optional)")}
                  placeholder={
                    isPython
                      ? "pip install -r requirements.txt"
                      : "dart compile exe bin/server.dart -o build/app"
                  }
                  value={form.buildCommand}
                  onChange={(e) => set("buildCommand", e.target.value)}
                  helperText={
                    isPython
                      ? "Leave blank — gunicorn + uvicorn are installed automatically."
                      : undefined
                  }
                />
                <TextInput
                  id="startCommand"
                  labelText={labelWithNote("Start command", "(optional)")}
                  placeholder={
                    isPython
                      ? "Auto-generated gunicorn command"
                      : "./current/app"
                  }
                  disabled={isPython && !form.startCommand}
                  value={form.startCommand}
                  onChange={(e) => set("startCommand", e.target.value)}
                  helperText={
                    isPython
                      ? "Leave blank to auto-generate the gunicorn command based on mode + target above."
                      : undefined
                  }
                />
              </div>
            )}

            {/* Celery: optional build command (e.g. pip install extras) */}
            {isCelery && (
              <TextInput
                id="buildCommand"
                labelText={labelWithNote("Build command", "(optional)")}
                placeholder="pip install -r requirements.txt"
                value={form.buildCommand}
                onChange={(e) => set("buildCommand", e.target.value)}
                helperText={
                  <>
                    Leave blank —{" "}
                    <code className="gisila-code">requirements.txt</code> is
                    installed automatically, then celery + flower are added on
                    top.
                  </>
                }
              />
            )}

            {/* Static: optional build command (e.g. npm run build) */}
            {isStatic && (
              <TextInput
                id="buildCommand"
                labelText={labelWithNote("Build command", "(optional)")}
                placeholder="npm ci && npm run build"
                value={form.buildCommand}
                onChange={(e) => set("buildCommand", e.target.value)}
                helperText="Run a build step before Nginx serves the files (e.g. Vite, Next.js export, Hugo). Leave blank for plain HTML/CSS/JS repos."
              />
            )}

            {isBinary && (
              <TextInput
                id="startCommand"
                labelText={labelWithNote(
                  "Start command",
                  "(optional, defaults to ./current/app)",
                )}
                placeholder="./current/app --port $PORT"
                value={form.startCommand}
                onChange={(e) => set("startCommand", e.target.value)}
              />
            )}

            <ButtonSet className="gisila-app-form__actions">
              <Button type="button" kind="secondary" onClick={() => router.back()}>
                Cancel
              </Button>
              <Button type="submit" kind="primary" disabled={loading}>
                {loading ? "Creating…" : "Create app"}
              </Button>
            </ButtonSet>
          </Stack>
        </Form>
      </PageSection>

      {/* Quick project create dialog */}
      <Modal
        open={projDialog}
        modalHeading="New Project"
        size="sm"
        primaryButtonText={creatingProj ? "Creating…" : "Create"}
        secondaryButtonText="Cancel"
        primaryButtonDisabled={
          teamCount === 0 || creatingProj || !newProjName.trim()
        }
        onRequestClose={() => setProjDialog(false)}
        onRequestSubmit={() => void createProject()}
      >
        <Stack gap={5}>
          {teamCount === 0 ? (
            <p className="gisila-app-form__hint">
              You need a team first.{" "}
              <CarbonLink href="/teams">Create one</CarbonLink>.
            </p>
          ) : (
            <>
              <Select
                id="qp-team"
                labelText="Team"
                value={newProjTeam}
                onChange={(e) => setNewProjTeam(e.target.value)}
                required
              >
                {teams.data?.results.map((t) => (
                  <SelectItem key={t.id} value={t.id} text={t.name} />
                ))}
              </Select>
              <TextInput
                id="qp-name"
                labelText="Project name"
                placeholder="my-backend"
                value={newProjName}
                onChange={(e) => setNewProjName(e.target.value)}
                required
              />
            </>
          )}
        </Stack>
      </Modal>
    </Page>
  );
}

/// Carbon field labels are a single node, so the parenthetical asides the form
/// uses throughout ride along inside the label rather than as sibling markup.
function labelWithNote(label: string, note: string): ReactNode {
  return (
    <>
      {label}{" "}
      <span className="gisila-app-form__label-note">{note}</span>
    </>
  );
}
