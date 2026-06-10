"use client";

import { useEffect, useRef, useState } from "react";
import { useParams, useRouter } from "@/compat/navigation";
import useSWR, { mutate } from "swr";
import {
  CheckCircle,
  AlertCircle,
  Loader,
  Play,
  Square,
  Trash2,
  Save,
  ExternalLink,
  ArrowLeft,
  Eye,
  EyeOff,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";
import { api, fetcher, getToken, getWsBase } from "@/lib/api";
import { cn } from "@/lib/utils";
import type {
  ManagedService,
  ServiceDef,
  ConfigField,
} from "@/lib/types";
import { toast } from "sonner";
import { PgBouncerConfig } from "./_panels/pgbouncer-config";

// ── Status display ────────────────────────────────────────────────────────────

const STATUS_META: Record<
  string,
  { icon: React.ReactNode; label: string; color: string }
> = {
  running: {
    icon: <CheckCircle className="h-4 w-4" />,
    label: "Running",
    color: "text-emerald-500",
  },
  config_only: {
    icon: <CheckCircle className="h-4 w-4" />,
    label: "Configured",
    color: "text-emerald-500",
  },
  stopped: {
    icon: <Square className="h-4 w-4" />,
    label: "Stopped",
    color: "text-amber-500",
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
  pending: {
    icon: <Loader className="h-4 w-4 animate-spin" />,
    label: "Pending…",
    color: "text-zinc-400",
  },
  uninstalling: {
    icon: <Loader className="h-4 w-4 animate-spin" />,
    label: "Uninstalling…",
    color: "text-zinc-400",
  },
};

// ── Page ─────────────────────────────────────────────────────────────────────

export default function ServiceDetailPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();

  const { data: svc, isLoading } = useSWR<ManagedService>(
    `/services/${id}`,
    fetcher,
    {
      // Poll while an async action is in progress.
      refreshInterval: (s) =>
        s &&
        ["installing", "pending", "uninstalling"].includes(s.status)
          ? 2000
          : 0,
    },
  );

  const def = svc?._def as ServiceDef | undefined;
  const statusMeta = STATUS_META[svc?.status ?? ""] ?? {
    icon: null,
    label: svc?.status ?? "unknown",
    color: "text-muted-foreground",
  };

  if (isLoading) return <PageSkeleton />;
  if (!svc) return null;

  return (
    <div className="container max-w-2xl space-y-6 py-8">
      {/* Header */}
      <div>
        <button
          onClick={() => router.push("/services")}
          className="mb-4 flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground"
        >
          <ArrowLeft className="h-3.5 w-3.5" />
          Services
        </button>

        <div className="flex items-start justify-between gap-4">
          <div>
            <h1 className="text-xl font-semibold tracking-tight">
              {svc.displayName}
            </h1>
            <p className="mt-0.5 text-sm text-muted-foreground font-mono">
              {svc.serviceType}
            </p>
          </div>

          <div className={cn("flex items-center gap-1.5 mt-1", statusMeta.color)}>
            {statusMeta.icon}
            <span className="text-sm font-medium">{statusMeta.label}</span>
          </div>
        </div>

        {svc.errorMessage && (
          <div className="mt-3 rounded-md border border-red-500/30 bg-red-500/5 px-3 py-2 text-xs text-red-500">
            {svc.errorMessage}
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
      </div>

      <Separator />

      {/* Config form — PgBouncer gets a dedicated editor for its repeating
          databases/users structures; everything else uses the generic form. */}
      {def && svc.serviceType === "pgbouncer" ? (
        <PgBouncerConfig
          svc={svc}
          def={def}
          onSaved={() => mutate(`/services/${id}`)}
        />
      ) : (
        def && (
          <ConfigForm
            svc={svc}
            def={def}
            onSaved={() => mutate(`/services/${id}`)}
          />
        )
      )}

      {/* Live install / lifecycle logs (only for services installed on the host) */}
      {def?.requiresInstall && (
        <>
          <Separator />
          <ServiceLogPanel serviceId={svc.id} status={svc.status} />
        </>
      )}

      <Separator />

      {/* Actions */}
      <ServiceActions svc={svc} onDone={() => router.push("/services")} />
    </div>
  );
}

// ── Live install / lifecycle logs ──────────────────────────────────────────────

const WS_BASE = getWsBase();

interface SvcLogLine {
  ts: string;
  stream: string;
  line: string;
}

function ServiceLogPanel({
  serviceId,
  status,
}: {
  serviceId: number;
  status: string;
}) {
  const [lines, setLines] = useState<SvcLogLine[]>([]);
  const endRef = useRef<HTMLDivElement>(null);
  const active = ["installing", "pending", "uninstalling"].includes(status);

  useEffect(() => {
    const token = getToken();
    if (!token) return;

    let ws: WebSocket | null = null;
    let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
    let attempt = 0;
    let closed = false;

    function connect() {
      ws = new WebSocket(`${WS_BASE}/services/${serviceId}/logs`);

      ws.onopen = () => {
        attempt = 0;
        // History replays the full buffer, so reset to avoid duplicates.
        setLines([]);
        ws?.send(JSON.stringify({ token, serviceId }));
      };

      ws.onmessage = (ev) => {
        try {
          const data = JSON.parse(ev.data);
          if (data.error) return;
          const raw =
            typeof data.message === "string"
              ? data.message
              : JSON.stringify(data.message);
          let parsed: { stream?: string; line?: string } = {};
          try {
            parsed = JSON.parse(raw);
          } catch {
            parsed = { line: raw };
          }
          setLines((prev) =>
            [
              ...prev,
              {
                ts: data.ts ?? new Date().toISOString(),
                stream: parsed.stream ?? "stdout",
                line: parsed.line ?? raw,
              },
            ].slice(-1000),
          );
        } catch {
          /* ignore */
        }
      };

      ws.onclose = () => {
        if (closed) return;
        const delay = Math.min(1000 * 2 ** attempt, 10000);
        attempt += 1;
        reconnectTimer = setTimeout(connect, delay);
      };

      ws.onerror = () => ws?.close();
    }

    connect();

    return () => {
      closed = true;
      if (reconnectTimer) clearTimeout(reconnectTimer);
      ws?.close();
    };
  }, [serviceId]);

  useEffect(() => {
    endRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [lines]);

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between">
        <h2 className="text-sm font-semibold">Install logs</h2>
        {active && (
          <span className="flex items-center gap-1.5 text-xs text-emerald-500">
            <span className="h-1.5 w-1.5 rounded-full bg-emerald-500 animate-pulse" />
            live
          </span>
        )}
      </div>
      <div className="h-64 overflow-y-auto rounded-md border border-border/60 bg-[#0d1117] p-3 font-mono text-xs scrollbar-thin">
        {lines.length === 0 ? (
          <p className="text-white/40">
            {active ? "Waiting for output…" : "No logs yet. Trigger an install or restart to see live output."}
          </p>
        ) : (
          lines.map((l, i) => (
            <div
              key={i}
              className={cn(
                "leading-5",
                l.stream === "stderr"
                  ? "text-red-400"
                  : l.stream === "system"
                    ? "text-fuchsia-400"
                    : "text-[#e6edf3]",
              )}
            >
              <span className="mr-2 select-none text-white/25">
                {l.ts.slice(11, 19)}
              </span>
              {l.line}
            </div>
          ))
        )}
        <div ref={endRef} />
      </div>
    </div>
  );
}

// ── Config form ───────────────────────────────────────────────────────────────

function ConfigForm({
  svc,
  def,
  onSaved,
}: {
  svc: ManagedService;
  def: ServiceDef;
  onSaved: () => void;
}) {
  // Parse stored config JSON.
  const storedConfig: Record<string, string> = (() => {
    try {
      return JSON.parse(svc.config) as Record<string, string>;
    } catch {
      return {};
    }
  })();

  // Build initial form state from stored values, falling back to defaults.
  const initial = Object.fromEntries(
    def.configSchema.map((f) => [
      f.key,
      storedConfig[f.key] ?? f.default ?? "",
    ]),
  );

  const [values, setValues] = useState<Record<string, string>>(initial);
  const [visible, setVisible] = useState<Record<string, boolean>>({});
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    setValues(initial);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [svc.config]);

  function set(key: string, value: string) {
    setValues((p) => ({ ...p, [key]: value }));
  }

  async function save() {
    setSaving(true);
    try {
      await api(`/services/${svc.id}/config`, {
        method: "PUT",
        body: JSON.stringify({ config: values }),
      });
      toast.success("Configuration saved.");
      onSaved();
    } catch (e: unknown) {
      toast.error(e instanceof Error ? e.message : "Failed to save.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="space-y-5">
      <h2 className="text-sm font-semibold">Configuration</h2>

      {def.configSchema.map((field) => (
        <FieldRow
          key={field.key}
          field={field}
          value={values[field.key] ?? ""}
          isVisible={visible[field.key] ?? false}
          onChange={(v) => set(field.key, v)}
          onToggleVisible={() =>
            setVisible((p) => ({ ...p, [field.key]: !p[field.key] }))
          }
        />
      ))}

      <Button size="sm" disabled={saving} onClick={save}>
        {saving ? <Loader className="h-3.5 w-3.5 animate-spin" /> : <Save className="h-3.5 w-3.5" />}
        Save configuration
      </Button>
    </div>
  );
}

// ── Single config field ───────────────────────────────────────────────────────

function FieldRow({
  field,
  value,
  isVisible,
  onChange,
  onToggleVisible,
}: {
  field: ConfigField;
  value: string;
  isVisible: boolean;
  onChange: (v: string) => void;
  onToggleVisible: () => void;
}) {
  const isPassword = field.type === "password";
  const isBoolean = field.type === "boolean";
  const isSelect = field.type === "select";

  return (
    <div className="space-y-1.5">
      <Label htmlFor={field.key} className="flex items-center gap-1.5">
        {field.label}
        {field.required && <span className="text-red-500">*</span>}
        {field.secret && (
          <Badge variant="muted" className="text-[9px]">
            secret
          </Badge>
        )}
      </Label>

      {isBoolean ? (
        <div className="flex items-center gap-2">
          <button
            type="button"
            role="switch"
            aria-checked={value === "true"}
            onClick={() => onChange(value === "true" ? "false" : "true")}
            className={cn(
              "relative inline-flex h-5 w-9 rounded-full transition-colors",
              value === "true" ? "bg-primary" : "bg-border",
            )}
          >
            <span
              className={cn(
                "absolute top-0.5 left-0.5 h-4 w-4 rounded-full bg-white shadow transition-transform",
                value === "true" && "translate-x-4",
              )}
            />
          </button>
          <span className="text-sm text-muted-foreground">
            {value === "true" ? "Enabled" : "Disabled"}
          </span>
        </div>
      ) : isSelect ? (
        <select
          id={field.key}
          value={value}
          onChange={(e) => onChange(e.target.value)}
          className="flex h-8 w-full rounded-md border border-input bg-background px-3 py-1 text-sm ring-offset-background focus:outline-none focus:ring-2 focus:ring-ring"
        >
          {field.options?.map((opt) => (
            <option key={opt} value={opt}>
              {opt}
            </option>
          ))}
        </select>
      ) : (
        <div className="relative">
          <Input
            id={field.key}
            type={isPassword && !isVisible ? "password" : "text"}
            value={value}
            placeholder={field.placeholder ?? field.default}
            onChange={(e) => onChange(e.target.value)}
            className={cn("h-8", isPassword && "pr-9")}
          />
          {isPassword && (
            <button
              type="button"
              onClick={onToggleVisible}
              className="absolute right-2.5 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
            >
              {isVisible ? (
                <EyeOff className="h-3.5 w-3.5" />
              ) : (
                <Eye className="h-3.5 w-3.5" />
              )}
            </button>
          )}
        </div>
      )}

      {field.hint && (
        <p className="text-xs text-muted-foreground">{field.hint}</p>
      )}
    </div>
  );
}

// ── Service actions ───────────────────────────────────────────────────────────

function ServiceActions({
  svc,
  onDone,
}: {
  svc: ManagedService;
  onDone: () => void;
}) {
  const [busy, setBusy] = useState<string | null>(null);

  async function act(action: "start" | "stop" | "uninstall") {
    setBusy(action);
    try {
      if (action === "uninstall") {
        await api(`/services/${svc.id}`, { method: "DELETE" });
        toast.success("Uninstall queued.");
        onDone();
      } else {
        await api(`/services/${svc.id}/${action}`, { method: "POST" });
        toast.success(`${action === "start" ? "Started" : "Stopped"}.`);
        mutate(`/services/${svc.id}`);
        mutate("/services/");
      }
    } catch (e: unknown) {
      toast.error(e instanceof Error ? e.message : "Action failed.");
    } finally {
      setBusy(null);
    }
  }

  const isInProgress = ["installing", "pending", "uninstalling"].includes(
    svc.status,
  );
  const isConfigOnly = svc.status === "config_only";

  return (
    <div className="space-y-3">
      <h2 className="text-sm font-semibold">Actions</h2>
      <div className="flex flex-wrap items-center gap-2">
        {!isConfigOnly && (
          <>
            {svc.status !== "running" && (
              <Button
                size="sm"
                variant="outline"
                disabled={isInProgress || !!busy}
                onClick={() => act("start")}
              >
                {busy === "start" ? (
                  <Loader className="h-3.5 w-3.5 animate-spin" />
                ) : (
                  <Play className="h-3.5 w-3.5" />
                )}
                Start
              </Button>
            )}
            {svc.status === "running" && (
              <Button
                size="sm"
                variant="outline"
                disabled={isInProgress || !!busy}
                onClick={() => act("stop")}
              >
                {busy === "stop" ? (
                  <Loader className="h-3.5 w-3.5 animate-spin" />
                ) : (
                  <Square className="h-3.5 w-3.5" />
                )}
                Stop
              </Button>
            )}
          </>
        )}

        <Button
          size="sm"
          variant="outline"
          className="text-red-500 hover:text-red-600 border-red-500/30 hover:bg-red-500/5"
          disabled={isInProgress || !!busy}
          onClick={() => act("uninstall")}
        >
          {busy === "uninstall" ? (
            <Loader className="h-3.5 w-3.5 animate-spin" />
          ) : (
            <Trash2 className="h-3.5 w-3.5" />
          )}
          {isConfigOnly ? "Remove" : "Uninstall"}
        </Button>
      </div>
    </div>
  );
}

// ── Loading skeleton ──────────────────────────────────────────────────────────

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
