import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { formatRelative } from "@/lib/utils";
import { DEPLOY_MODE_LABEL, type App } from "@/lib/types";

export function OverviewTab({ app }: { app: App }) {
  return (
    <div className="grid gap-4 md:grid-cols-2">
      <Card>
        <CardHeader><CardTitle>Runtime</CardTitle></CardHeader>
        <CardContent className="space-y-3">
          <Row label="Application" value={app.runtime} mono />
          <Row
            label="Deployment mode"
            value={
              app.deploymentMode
                ? DEPLOY_MODE_LABEL[app.deploymentMode] ?? app.deploymentMode
                : "—"
            }
          />
          <Row label="Source" value={app.sourceType} />
          <Row label="Git URL" value={app.gitUrl ?? "—"} mono />
          <Row label="Branch" value={app.gitBranch ?? "—"} mono />
          <Row label="Build" value={app.buildCommand ?? "—"} mono />
          <Row label="Start" value={app.startCommand ?? "—"} mono />
        </CardContent>
      </Card>
      <Card>
        <CardHeader><CardTitle>Sandbox</CardTitle></CardHeader>
        <CardContent className="space-y-3">
          <Row label="Linux user" value={app.linuxUser} mono />
          <Row label="Work dir" value={app.workDir} mono />
          <Row label="Internal port" value={`127.0.0.1:${app.internalPort}`} mono />
          <Row label="Memory limit" value={`${app.memoryMbLimit} MB`} />
          <Row label="CPU quota" value={`${app.cpuQuotaPercent}%`} />
          <Row label="Tasks max" value={app.tasksLimit} />
        </CardContent>
      </Card>
      <Card className="md:col-span-2">
        <CardHeader><CardTitle>Activity</CardTitle></CardHeader>
        <CardContent>
          <Row label="Status" value={app.status} />
          <Row label="Created" value={formatRelative(app.createdAt)} />
          <Row label="Last deployed" value={formatRelative(app.lastDeployedAt)} />
          <Row label="Updated" value={formatRelative(app.updatedAt)} />
        </CardContent>
      </Card>
    </div>
  );
}

function Row({
  label,
  value,
  mono,
}: {
  label: string;
  value: React.ReactNode;
  mono?: boolean;
}) {
  return (
    <div className="flex items-center justify-between py-1.5 text-sm">
      <span className="text-muted-foreground">{label}</span>
      <span className={mono ? "font-mono text-xs" : "font-medium"}>{value}</span>
    </div>
  );
}
