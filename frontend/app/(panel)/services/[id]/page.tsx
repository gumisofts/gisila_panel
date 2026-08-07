"use client";

import { useEffect, useRef, useState } from "react";
import RouterLink from "@/compat/link";
import { useParams, useRouter } from "@/compat/navigation";
import useSWR, { mutate } from "swr";
import {
  Launch,
  PlayFilled,
  Renew,
  Save,
  StopFilled,
  TrashCan,
} from "@carbon/icons-react";
import {
  Breadcrumb,
  BreadcrumbItem,
  Button,
  Form,
  InlineLoading,
  InlineNotification,
  Link as CarbonLink,
  Modal,
  NumberInput,
  PasswordInput,
  Select,
  SelectItem,
  SkeletonText,
  Stack,
  Tag,
  TextInput,
  Tile,
  Toggle,
} from "@carbon/react";
import { Page, PageHeader, PageSection } from "@/components/page";
import { api, fetcher, getToken, getWsBase } from "@/lib/api";
import { usePermissions } from "@/lib/permissions";
import type {
  ManagedService,
  ServiceDef,
  ConfigField,
} from "@/lib/types";
import { toast } from "@/lib/toast";
import { PgBouncerConfig } from "./_panels/pgbouncer-config";
import "../_services.scss";

// ── Status display ────────────────────────────────────────────────────────────

const STATUS_LABEL: Record<string, string> = {
  running: "Running",
  config_only: "Configured",
  stopped: "Stopped",
  failed: "Failed",
  installing: "Installing…",
  pending: "Pending…",
  uninstalling: "Uninstalling…",
};

const IN_PROGRESS = ["installing", "pending", "uninstalling"];

const STATUS_TAG: Record<string, "green" | "red" | "magenta"> = {
  running: "green",
  config_only: "green",
  stopped: "magenta",
  failed: "red",
};

function StatusIndicator({ status }: { status: string }) {
  const label = STATUS_LABEL[status] ?? status;
  if (IN_PROGRESS.includes(status)) {
    return <InlineLoading status="active" description={label} />;
  }
  return (
    <Tag type={STATUS_TAG[status] ?? "cool-gray"} size="md">
      {label}
    </Tag>
  );
}

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

  if (isLoading) return <PageSkeleton />;
  if (!svc) return null;

  return (
    <Page>
      <Breadcrumb noTrailingSlash className="gisila-breadcrumb">
        <BreadcrumbItem>
          <CarbonLink as={RouterLink} href="/services">
            Services
          </CarbonLink>
        </BreadcrumbItem>
        <BreadcrumbItem isCurrentPage>{svc.displayName}</BreadcrumbItem>
      </Breadcrumb>

      <PageHeader
        title={svc.displayName}
        description={<span className="gisila-detail__key">{svc.serviceType}</span>}
        actions={<StatusIndicator status={svc.status} />}
      />

      {(svc.errorMessage || def?.docsUrl) && (
        <PageSection>
          <Stack gap={5}>
            {svc.errorMessage && (
              <InlineNotification
                kind="error"
                lowContrast
                hideCloseButton
                title={svc.errorMessage}
              />
            )}

            {def?.docsUrl && (
              <CarbonLink
                href={def.docsUrl}
                target="_blank"
                rel="noopener noreferrer"
                renderIcon={Launch}
                size="sm"
              >
                Documentation
              </CarbonLink>
            )}
          </Stack>
        </PageSection>
      )}

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
        <ServiceLogPanel serviceId={svc.id} status={svc.status} />
      )}

      <ServiceActions svc={svc} onDone={() => router.push("/services")} />
    </Page>
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
    <PageSection
      title="Install logs"
      actions={
        active ? (
          <Tag type="green" size="sm">
            live
          </Tag>
        ) : undefined
      }
    >
      <div className="gisila-logs">
        {lines.length === 0 ? (
          <p className="gisila-logs__empty">
            {active ? "Waiting for output…" : "No logs yet. Trigger an install or restart to see live output."}
          </p>
        ) : (
          lines.map((l, i) => (
            <div
              key={i}
              className={
                l.stream === "stderr"
                  ? "gisila-logs__line gisila-logs__line--stderr"
                  : l.stream === "system"
                    ? "gisila-logs__line gisila-logs__line--system"
                    : "gisila-logs__line"
              }
            >
              <span className="gisila-logs__ts">{l.ts.slice(11, 19)}</span>
              {l.line}
            </div>
          ))
        )}
        <div ref={endRef} />
      </div>
    </PageSection>
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
      toast.success(
        svc.status === "failed"
          ? "Configuration saved — reinstall queued."
          : "Configuration saved.",
      );
      onSaved();
    } catch (e: unknown) {
      toast.error(e instanceof Error ? e.message : "Failed to save.");
    } finally {
      setSaving(false);
    }
  }

  const saveLabel =
    svc.status === "failed" ? "Save & retry install" : "Save configuration";

  return (
    <PageSection title="Configuration">
      <Form onSubmit={(e) => e.preventDefault()}>
        <Stack gap={5}>
          {svc.status === "failed" && (
            <InlineNotification
              kind="warning"
              lowContrast
              hideCloseButton
              title="Installation failed"
              subtitle="Fill in required fields below, then save to retry — or remove the service and install again from the catalog."
            />
          )}
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

          {saving ? (
            <InlineLoading status="active" description="Saving…" />
          ) : (
            <Button size="md" renderIcon={Save} onClick={save}>
              {saveLabel}
            </Button>
          )}
        </Stack>
      </Form>
    </PageSection>
  );
}

// ── Single config field ───────────────────────────────────────────────────────

/// Carbon has no "required" or "secret" affordance on its inputs, so the label
/// carries both markers.
function FieldLabel({ field }: { field: ConfigField }) {
  return (
    <span className="gisila-label">
      {field.label}
      {field.required && <span className="gisila-required">*</span>}
      {field.secret && (
        <Tag as="span" type="cool-gray" size="sm">
          secret
        </Tag>
      )}
    </span>
  );
}

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
  const label = <FieldLabel field={field} />;

  if (field.type === "boolean") {
    return (
      <Stack gap={2}>
        <Toggle
          id={field.key}
          labelText={field.label}
          labelA="Disabled"
          labelB="Enabled"
          toggled={value === "true"}
          onToggle={(checked) => onChange(checked ? "true" : "false")}
        />
        {field.hint && <p className="gisila-detail__note">{field.hint}</p>}
      </Stack>
    );
  }

  if (field.type === "select") {
    return (
      <Select
        id={field.key}
        labelText={label}
        helperText={field.hint}
        value={value}
        onChange={(e) => onChange(e.target.value)}
      >
        {field.options?.map((opt) => (
          <SelectItem key={opt} value={opt} text={opt} />
        ))}
      </Select>
    );
  }

  if (field.type === "password") {
    return (
      <PasswordInput
        id={field.key}
        labelText={label}
        helperText={field.hint}
        // The eye toggle stays owned by the page so every secret on the form
        // reveals through the same state.
        type={isVisible ? "text" : "password"}
        onTogglePasswordVisibility={onToggleVisible}
        value={value}
        placeholder={field.placeholder ?? field.default}
        onChange={(e) => onChange(e.target.value)}
      />
    );
  }

  if (field.type === "number") {
    return (
      <NumberInput
        id={field.key}
        label={label}
        helperText={field.hint}
        value={value}
        min={field.min}
        max={field.max}
        allowEmpty
        // Config is serialised as strings, so the numeric value is stringified
        // straight back into the same shape the API expects.
        onChange={(_event, { value: next }) => onChange(String(next))}
      />
    );
  }

  return (
    <TextInput
      id={field.key}
      labelText={label}
      helperText={field.hint}
      value={value}
      placeholder={field.placeholder ?? field.default}
      onChange={(e) => onChange(e.target.value)}
    />
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
  const [confirming, setConfirming] = useState(false);
  const { isSuperuser } = usePermissions();

  // Managed services are node-global infra — only superusers may control them.
  if (!isSuperuser) return null;

  async function act(action: "start" | "stop" | "uninstall" | "retry") {
    setBusy(action);
    try {
      if (action === "uninstall") {
        await api(`/services/${svc.id}`, { method: "DELETE" });
        toast.success("Uninstall queued.");
        onDone();
      } else if (action === "retry") {
        await api(`/services/${svc.id}/retry`, { method: "POST" });
        toast.success("Reinstall queued.");
        mutate(`/services/${svc.id}`);
        mutate("/services/");
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
  const isFailed = svc.status === "failed";
  const removeLabel = isConfigOnly || isFailed ? "Remove" : "Uninstall";

  return (
    <PageSection title="Actions">
      <div style={{ display: "flex", flexWrap: "wrap", gap: "0.5rem" }}>
        {isFailed &&
          (busy === "retry" ? (
            <InlineLoading status="active" description="Retrying…" />
          ) : (
            <Button
              size="md"
              kind="tertiary"
              renderIcon={Renew}
              disabled={isInProgress || !!busy}
              onClick={() => act("retry")}
            >
              Retry install
            </Button>
          ))}

        {!isConfigOnly && !isFailed && (
          <>
            {svc.status !== "running" &&
              (busy === "start" ? (
                <InlineLoading status="active" description="Starting…" />
              ) : (
                <Button
                  size="md"
                  kind="secondary"
                  renderIcon={PlayFilled}
                  disabled={isInProgress || !!busy}
                  onClick={() => act("start")}
                >
                  Start
                </Button>
              ))}
            {svc.status === "running" &&
              (busy === "stop" ? (
                <InlineLoading status="active" description="Stopping…" />
              ) : (
                <Button
                  size="md"
                  kind="secondary"
                  renderIcon={StopFilled}
                  disabled={isInProgress || !!busy}
                  onClick={() => act("stop")}
                >
                  Stop
                </Button>
              ))}
          </>
        )}

        {busy === "uninstall" ? (
          <InlineLoading status="active" description={`${removeLabel}…`} />
        ) : (
          <Button
            size="md"
            kind="danger--tertiary"
            renderIcon={TrashCan}
            disabled={isInProgress || !!busy}
            onClick={() => setConfirming(true)}
          >
            {removeLabel}
          </Button>
        )}
      </div>

      <Modal
        open={confirming}
        danger
        modalHeading={`${removeLabel} ${svc.displayName}?`}
        modalLabel={svc.serviceType}
        primaryButtonText={removeLabel}
        secondaryButtonText="Cancel"
        onRequestClose={() => setConfirming(false)}
        onRequestSubmit={() => {
          setConfirming(false);
          void act("uninstall");
        }}
      >
        <p className="gisila-detail__note">
          {isConfigOnly
            ? "The stored configuration for this service is deleted."
            : "The service is stopped and removed from the host."}
        </p>
      </Modal>
    </PageSection>
  );
}

// ── Loading skeleton ──────────────────────────────────────────────────────────

function PageSkeleton() {
  return (
    <Page>
      <SkeletonText heading width="40%" />
      <Tile>
        <Stack gap={5}>
          {[0, 1, 2, 3].map((i) => (
            <SkeletonText key={i} />
          ))}
        </Stack>
      </Tile>
    </Page>
  );
}
