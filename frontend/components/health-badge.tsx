"use client";

import { CheckmarkFilled, Renew, WarningAltFilled } from "@carbon/icons-react";
import { Button, InlineLoading, Tag } from "@carbon/react";
import { formatRelative } from "@/lib/utils";
import type { HealthStatus } from "@/lib/types";

/// Small live-health indicator shared by Mail / Services / Runtimes, all of
/// which read the same `{healthy, checkedAt, detail?}` shape cached by
/// `HealthMonitorWorker` (see `GET /mail/health`, `/services/{id}/health`,
/// `/applications/{id}/versions/{versionId}/health`). `healthy` is `null`
/// until the first probe lands, so the badge renders nothing until then
/// rather than guessing.
export function HealthBadge({ health }: { health?: HealthStatus | null }) {
  if (!health || health.healthy === null || health.healthy === undefined) {
    return null;
  }
  const title =
    (health.checkedAt
      ? `Checked ${formatRelative(health.checkedAt)}${health.detail ? ` — ${health.detail}` : ""}`
      : health.detail) ?? undefined;
  return health.healthy ? (
    <Tag type="green" size="sm" renderIcon={CheckmarkFilled} title={title}>
      Healthy
    </Tag>
  ) : (
    <Tag type="red" size="sm" renderIcon={WarningAltFilled} title={title}>
      Unhealthy
    </Tag>
  );
}

/// Superuser-only "Repair now" action for the mail stack / a managed
/// service — manually triggers the same auto-repair path
/// `HealthMonitorWorker` takes when it finds the resource down past its
/// cooldown.
export function RepairButton({
  onRepair,
  busy,
  disabled,
}: {
  onRepair: () => void;
  busy: boolean;
  disabled?: boolean;
}) {
  if (busy) {
    return <InlineLoading status="active" description="Repairing…" />;
  }
  return (
    <Button
      kind="tertiary"
      size="sm"
      renderIcon={Renew}
      disabled={disabled}
      onClick={onRepair}
    >
      Repair now
    </Button>
  );
}
