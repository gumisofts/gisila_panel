"use client";

import { WarningAltFilled } from "@carbon/icons-react";
import { PageSection } from "@/components/page";
import { AlertRulesManager } from "@/components/alert-rules-manager";

const HEADING = (
  <span className="gisila-db__icon-title">
    <WarningAltFilled size={16} />
    Alerts
  </span>
);

/// Database-scoped alert rules live only on the instance's own page (shared
/// by both the Postgres and Mongo instance pages) — this scope has no team to
/// fall back to, so the read/write check is a flat superuser gate (see
/// `NotificationsApi._requireReadAccess`).
export function AlertsPanel({
  engine,
  instanceId,
  isSuperuser,
}: {
  engine: "postgres" | "mongo";
  instanceId: number;
  isSuperuser: boolean;
}) {
  if (!isSuperuser) return null;

  return (
    <PageSection title={HEADING}>
      <AlertRulesManager
        scope={engine}
        postgresInstanceId={engine === "postgres" ? instanceId : undefined}
        mongoInstanceId={engine === "mongo" ? instanceId : undefined}
        canWrite
        title="Alert rules"
        description={
          engine === "postgres"
            ? "Get notified when this instance's CPU or connection usage crosses a threshold, or when it goes down. CPU is measured as percent of one core, so a multi-core host can go well above 100%."
            : "Get notified when this instance's connection usage crosses a threshold, or when it goes down."
        }
      />
    </PageSection>
  );
}
