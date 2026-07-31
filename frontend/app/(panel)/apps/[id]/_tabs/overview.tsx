import {
  Column,
  Grid,
  StructuredListBody,
  StructuredListCell,
  StructuredListRow,
  StructuredListWrapper,
  Tile,
} from "@carbon/react";
import { formatRelative } from "@/lib/utils";
import { DEPLOY_MODE_LABEL, type App } from "@/lib/types";
import "../_app-detail.scss";

export function OverviewTab({ app }: { app: App }) {
  return (
    <Grid condensed>
      <Column sm={4} md={4} lg={8} className="gisila-app__col">
        <Tile>
          <h3 className="gisila-app__tile-title">Runtime</h3>
          <StructuredListWrapper aria-label="Runtime" isCondensed>
            <StructuredListBody>
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
            </StructuredListBody>
          </StructuredListWrapper>
        </Tile>
      </Column>

      <Column sm={4} md={4} lg={8} className="gisila-app__col">
        <Tile>
          <h3 className="gisila-app__tile-title">Sandbox</h3>
          <StructuredListWrapper aria-label="Sandbox" isCondensed>
            <StructuredListBody>
              <Row label="Linux user" value={app.linuxUser} mono />
              <Row label="Work dir" value={app.workDir} mono />
              <Row
                label="Internal port"
                value={`127.0.0.1:${app.internalPort}`}
                mono
              />
              <Row label="Memory limit" value={`${app.memoryMbLimit} MB`} />
              <Row label="CPU quota" value={`${app.cpuQuotaPercent}%`} />
              <Row label="Tasks max" value={app.tasksLimit} />
            </StructuredListBody>
          </StructuredListWrapper>
        </Tile>
      </Column>

      <Column sm={4} md={8} lg={16} className="gisila-app__col">
        <Tile>
          <h3 className="gisila-app__tile-title">Activity</h3>
          <StructuredListWrapper aria-label="Activity" isCondensed>
            <StructuredListBody>
              <Row label="Status" value={app.status} />
              <Row label="Created" value={formatRelative(app.createdAt)} />
              <Row
                label="Last deployed"
                value={formatRelative(app.lastDeployedAt)}
              />
              <Row label="Updated" value={formatRelative(app.updatedAt)} />
            </StructuredListBody>
          </StructuredListWrapper>
        </Tile>
      </Column>
    </Grid>
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
    <StructuredListRow>
      <StructuredListCell noWrap>{label}</StructuredListCell>
      <StructuredListCell
        className={
          mono ? "gisila-app__value gisila-app__mono" : "gisila-app__value"
        }
      >
        {value}
      </StructuredListCell>
    </StructuredListRow>
  );
}
