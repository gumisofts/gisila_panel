"use client";

import { useState } from "react";
import useSWR from "swr";
import {
  Add,
  Edit,
  TrashCan,
  WarningAltFilled,
} from "@carbon/icons-react";
import {
  Button,
  ComposedModal,
  Form,
  InlineLoading,
  InlineNotification,
  ModalBody,
  ModalFooter,
  ModalHeader,
  NumberInput,
  Select,
  SelectItem,
  StructuredListBody,
  StructuredListCell,
  StructuredListRow,
  StructuredListWrapper,
  Tag,
  Tile,
  Toggle,
} from "@carbon/react";
import { toast } from "@/lib/toast";
import { api, fetcher } from "@/lib/api";
import { formatRelative } from "@/lib/utils";
import {
  ALERT_METRIC_LABEL,
  type AlertComparison,
  type AlertEvent,
  type AlertMetric,
  type AlertRule,
  type AlertScope,
  type AlertSeverity,
  type ListResponse,
} from "@/lib/types";

const FORM_ID = "alert-rule-form";

/// Metrics available per scope — mirrors what `AlertEvaluator` actually knows
/// how to sample (see backend/lib/workers/alert_worker.dart): whole-host
/// stats come from /proc + df, app usage from cgroup metric samples relative
/// to its own quota, and database health from a lightweight direct
/// connection (no CPU/memory sampling exists yet for either engine).
const METRICS_BY_SCOPE: Record<AlertScope, AlertMetric[]> = {
  system: ["cpu_percent", "memory_percent", "disk_percent"],
  app: ["cpu_percent", "memory_percent", "status_down"],
  postgres: ["cpu_percent", "connections_percent", "status_down"],
  mongo: ["connections_percent", "status_down"],
};

type RuleForm = {
  metric: AlertMetric;
  comparison: AlertComparison;
  thresholdPercent: number;
  severity: AlertSeverity;
  cooldownMinutes: number;
  enabled: boolean;
  notifyEmail: boolean;
};

function defaultForm(scope: AlertScope): RuleForm {
  return {
    metric: METRICS_BY_SCOPE[scope][0],
    comparison: "gte",
    thresholdPercent: 80,
    severity: "warning",
    cooldownMinutes: 15,
    enabled: true,
    notifyEmail: true,
  };
}

function formFromRule(rule: AlertRule): RuleForm {
  return {
    metric: rule.metric,
    comparison: rule.comparison,
    thresholdPercent: rule.thresholdPercent ?? 80,
    severity: rule.severity,
    cooldownMinutes: rule.cooldownMinutes,
    enabled: rule.enabled,
    notifyEmail: rule.notifyEmail,
  };
}

function severityTag(severity: AlertSeverity) {
  return severity === "critical" ? (
    <Tag type="red" size="sm">Critical</Tag>
  ) : (
    <Tag type="warm-gray" size="sm">Warning</Tag>
  );
}

function query(params: Record<string, string | number | undefined>): string {
  const parts = Object.entries(params)
    .filter(([, v]) => v !== undefined)
    .map(([k, v]) => `${k}=${encodeURIComponent(String(v))}`);
  return parts.length ? `?${parts.join("&")}` : "";
}

/// Threshold-based alert rules attached to a single resource (the whole host,
/// one app, or one database instance). Embedded directly on that resource's
/// own page/tab rather than a separate global list, matching how the rules
/// are scoped on the backend (`AlertRule.scope` + a nullable target FK).
export function AlertRulesManager({
  scope,
  appId,
  postgresInstanceId,
  mongoInstanceId,
  canWrite,
  title = "Alert rules",
  description,
}: {
  scope: AlertScope;
  appId?: number;
  postgresInstanceId?: number;
  mongoInstanceId?: number;
  canWrite: boolean;
  title?: string;
  description?: string;
}) {
  const target = { scope, appId, postgresInstanceId, mongoInstanceId };
  const rulesKey = `/notifications/rules${query(target)}`;
  const eventsKey = `/notifications/events${query({ ...target, limit: 8 })}`;

  const { data: rulesData, isLoading, mutate } = useSWR<ListResponse<AlertRule>>(
    rulesKey,
    fetcher,
  );
  const { data: eventsData } = useSWR<ListResponse<AlertEvent>>(
    eventsKey,
    fetcher,
    { refreshInterval: 30000 },
  );

  const [editing, setEditing] = useState<AlertRule | null>(null);
  const [creating, setCreating] = useState(false);
  const [form, setForm] = useState<RuleForm>(defaultForm(scope));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  const rules = rulesData?.results ?? [];
  const events = eventsData?.results ?? [];
  const metrics = METRICS_BY_SCOPE[scope];

  function openCreate() {
    setForm(defaultForm(scope));
    setError("");
    setCreating(true);
  }

  function openEdit(rule: AlertRule) {
    setForm(formFromRule(rule));
    setError("");
    setEditing(rule);
  }

  function closeModal() {
    setCreating(false);
    setEditing(null);
  }

  function set<K extends keyof RuleForm>(k: K, v: RuleForm[K]) {
    setForm((f) => ({ ...f, [k]: v }));
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    const needsThreshold = form.metric !== "status_down";
    const payload = {
      metric: form.metric,
      comparison: form.comparison,
      thresholdPercent: needsThreshold ? form.thresholdPercent : undefined,
      severity: form.severity,
      cooldownMinutes: form.cooldownMinutes,
      enabled: form.enabled,
      notifyEmail: form.notifyEmail,
    };
    try {
      if (editing) {
        await api(`/notifications/rules/${editing.id}`, {
          method: "PUT",
          body: JSON.stringify(payload),
        });
        toast.success("Alert rule updated");
      } else {
        await api("/notifications/rules", {
          method: "POST",
          body: JSON.stringify({ ...target, ...payload }),
        });
        toast.success("Alert rule created");
      }
      closeModal();
      mutate();
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "Failed to save alert rule.");
    } finally {
      setBusy(false);
    }
  }

  async function handleDelete(rule: AlertRule) {
    if (!confirm(`Delete this alert rule? This cannot be undone.`)) return;
    try {
      await api(`/notifications/rules/${rule.id}`, { method: "DELETE" });
      toast.success("Alert rule deleted");
      mutate();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed to delete alert rule.");
    }
  }

  async function toggleEnabled(rule: AlertRule) {
    try {
      await api(`/notifications/rules/${rule.id}`, {
        method: "PUT",
        body: JSON.stringify({ enabled: !rule.enabled }),
      });
      mutate();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed to update rule.");
    }
  }

  return (
    <Tile>
      <div className="gisila-alerts__header">
        <div>
          <h3 className="gisila-alerts__title">
            <WarningAltFilled size={16} />
            {title}
          </h3>
          {description && <p className="gisila-alerts__description">{description}</p>}
        </div>
        {canWrite && (
          <Button size="sm" kind="tertiary" renderIcon={Add} onClick={openCreate}>
            Add rule
          </Button>
        )}
      </div>

      {isLoading && <InlineLoading description="Loading…" />}

      {!isLoading && rules.length === 0 && (
        <p className="gisila-alerts__empty">
          No alert rules yet.{canWrite ? " Add one to get notified when this resource needs attention." : ""}
        </p>
      )}

      {rules.length > 0 && (
        <div className="gisila-alerts__rules">
          {rules.map((rule) => (
            <div key={rule.id} className="gisila-alerts__rule">
              <div className="gisila-alerts__rule-main">
                <span className="gisila-alerts__rule-metric">
                  {ALERT_METRIC_LABEL[rule.metric]}
                  {rule.metric !== "status_down" && (
                    <span className="gisila-alerts__rule-threshold">
                      {" "}
                      {rule.comparison === "lte" ? "≤" : "≥"} {rule.thresholdPercent}%
                    </span>
                  )}
                </span>
                <div className="gisila-alerts__rule-tags">
                  {severityTag(rule.severity)}
                  {!rule.enabled && <Tag type="gray" size="sm">Disabled</Tag>}
                  {rule.notifyEmail && <Tag type="blue" size="sm">Email</Tag>}
                </div>
                {rule.lastTriggeredAt && (
                  <span className="gisila-alerts__rule-meta">
                    Last triggered {formatRelative(rule.lastTriggeredAt)}
                  </span>
                )}
              </div>
              {canWrite && (
                <div className="gisila-alerts__rule-actions">
                  <Toggle
                    id={`rule-toggle-${rule.id}`}
                    size="sm"
                    hideLabel
                    labelText="Enabled"
                    toggled={rule.enabled}
                    onToggle={() => toggleEnabled(rule)}
                  />
                  <Button
                    kind="ghost"
                    size="sm"
                    hasIconOnly
                    renderIcon={Edit}
                    iconDescription="Edit rule"
                    onClick={() => openEdit(rule)}
                  />
                  <Button
                    kind="danger--ghost"
                    size="sm"
                    hasIconOnly
                    renderIcon={TrashCan}
                    iconDescription="Delete rule"
                    onClick={() => handleDelete(rule)}
                  />
                </div>
              )}
            </div>
          ))}
        </div>
      )}

      {events.length > 0 && (
        <div className="gisila-alerts__history">
          <p className="gisila-alerts__history-title">Recent activity</p>
          <StructuredListWrapper aria-label="Recent alert events" isCondensed>
            <StructuredListBody>
              {events.map((ev) => (
                <StructuredListRow key={ev.id}>
                  <StructuredListCell className="gisila-alerts__event-message">
                    {ev.message}
                  </StructuredListCell>
                  <StructuredListCell>
                    <Tag type={ev.status === "firing" ? "red" : "green"} size="sm">
                      {ev.status === "firing" ? "Firing" : "Resolved"}
                    </Tag>
                  </StructuredListCell>
                  <StructuredListCell className="gisila-alerts__event-time">
                    {formatRelative(ev.createdAt)}
                  </StructuredListCell>
                </StructuredListRow>
              ))}
            </StructuredListBody>
          </StructuredListWrapper>
        </div>
      )}

      <ComposedModal open={creating || !!editing} onClose={closeModal} size="sm">
        <ModalHeader title={editing ? "Edit alert rule" : "Add alert rule"} />
        <ModalBody hasForm>
          <Form id={FORM_ID} onSubmit={handleSubmit}>
            <div className="gisila-alerts__form">
              <Select
                id="rule-metric"
                labelText="Metric"
                value={form.metric}
                disabled={!!editing}
                onChange={(e) => set("metric", e.target.value as AlertMetric)}
              >
                {metrics.map((m) => (
                  <SelectItem key={m} value={m} text={ALERT_METRIC_LABEL[m]} />
                ))}
              </Select>

              {form.metric !== "status_down" && (
                <>
                  <Select
                    id="rule-comparison"
                    labelText="Condition"
                    value={form.comparison}
                    onChange={(e) => set("comparison", e.target.value as AlertComparison)}
                  >
                    <SelectItem value="gte" text="At or above threshold" />
                    <SelectItem value="lte" text="At or below threshold" />
                  </Select>

                  <NumberInput
                    id="rule-threshold"
                    label="Threshold (%)"
                    min={1}
                    max={100}
                    step={1}
                    value={form.thresholdPercent}
                    onChange={(_, { value }) => set("thresholdPercent", Number(value) || 0)}
                  />
                </>
              )}

              <Select
                id="rule-severity"
                labelText="Severity"
                value={form.severity}
                onChange={(e) => set("severity", e.target.value as AlertSeverity)}
              >
                <SelectItem value="warning" text="Warning" />
                <SelectItem value="critical" text="Critical" />
              </Select>

              <NumberInput
                id="rule-cooldown"
                label="Cooldown (minutes)"
                helperText="Minimum time between repeated notifications for the same breach."
                // min must be a multiple of step away from every value the field can
                // hold (including the 15-minute default) — otherwise the browser's
                // native step-mismatch validation silently blocks form submission.
                min={5}
                max={1440}
                step={5}
                value={form.cooldownMinutes}
                onChange={(_, { value }) => set("cooldownMinutes", Number(value) || 15)}
              />

              <Toggle
                id="rule-notify-email"
                labelText="Send email"
                labelA="Off"
                labelB="On"
                toggled={form.notifyEmail}
                onToggle={(checked) => set("notifyEmail", checked)}
              />
              <p className="gisila-alerts__hint">
                In-panel notifications are always sent to affected users; this also
                sends an email if outbound email is configured.
              </p>

              {editing && (
                <Toggle
                  id="rule-enabled"
                  labelText="Rule enabled"
                  labelA="Off"
                  labelB="On"
                  toggled={form.enabled}
                  onToggle={(checked) => set("enabled", checked)}
                />
              )}

              {error && (
                <InlineNotification kind="error" lowContrast hideCloseButton title={error} />
              )}
            </div>
          </Form>
        </ModalBody>
        <ModalFooter>
          <Button kind="secondary" onClick={closeModal}>
            Cancel
          </Button>
          <Button kind="primary" type="submit" form={FORM_ID} disabled={busy}>
            {busy ? "Saving…" : editing ? "Save changes" : "Create rule"}
          </Button>
        </ModalFooter>
      </ComposedModal>
    </Tile>
  );
}
