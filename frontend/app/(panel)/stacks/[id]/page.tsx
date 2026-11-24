import { useState } from "react";
import useSWR from "swr";
import {
  Button,
  Link as CarbonLink,
  Select,
  SelectItem,
  Stack,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableHeader,
  TableRow,
  Tag,
  Tile,
} from "@carbon/react";
import { Add, Close, TrashCan } from "@carbon/icons-react";
import RouterLink from "@/compat/link";
import { useParams, useRouter } from "@/compat/navigation";
import { confirmDialog } from "@/components/confirm-dialog";
import { ErrorState } from "@/components/error-state";
import { Page, PageHeader, PageSection } from "@/components/page";
import { api, fetcher } from "@/lib/api";
import { usePermissions } from "@/lib/permissions";
import { toast } from "@/lib/toast";
import type {
  App,
  ListResponse,
  Project,
  Stack as StackModel,
} from "@/lib/types";
import { EnvEditor } from "../../apps/[id]/_tabs/envs";
import "../../apps/[id]/_app-detail.scss";

export default function StackDetailPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const stack = useSWR<StackModel>(`/stacks/${id}`, fetcher);
  const projects = useSWR<ListResponse<Project>>("/projects/", fetcher);
  const projectId = stack.data?.projectId;
  // Every app of the project: the stack's members plus the ones that could join.
  const apps = useSWR<ListResponse<App>>(
    projectId != null ? `/apps/?projectId=${projectId}` : null,
    fetcher,
  );
  const { canForProject } = usePermissions();
  const canEdit = canForProject(projectId, "developer");
  const [adding, setAdding] = useState("");
  const [busy, setBusy] = useState(false);

  if (stack.error && !stack.data) {
    return (
      <Page>
        <ErrorState error={stack.error} onRetry={() => stack.mutate()} />
      </Page>
    );
  }
  if (!stack.data) return <Page>{null}</Page>;

  const s = stack.data;
  const all = apps.data?.results ?? [];
  const members = all
    .filter((a) => a.stackId === s.id)
    .sort((a, b) => a.name.localeCompare(b.name));
  const candidates = all.filter((a) => a.stackId !== s.id);
  const projectName = projects.data?.results.find(
    (p) => p.id === s.projectId,
  )?.name;

  async function setStack(app: App, stackId: number) {
    setBusy(true);
    try {
      // 0 takes the app out of its stack.
      await api(`/apps/${app.id}`, {
        method: "PATCH",
        body: JSON.stringify({ stackId }),
      });
      await apps.mutate();
      toast.success(
        stackId
          ? `${app.name} added. It gets the stack's variables on its next deployment.`
          : `${app.name} removed. It keeps the stack's variables until its next deployment.`,
      );
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed");
    } finally {
      setBusy(false);
    }
  }

  async function addSelected() {
    const app = candidates.find((a) => String(a.id) === adding);
    if (!app) return;
    if (
      app.stackId != null &&
      !(await confirmDialog(
        `${app.name} is in another stack. Move it to ${s.name}?`,
        { danger: false, confirmLabel: "Move" },
      ))
    ) {
      return;
    }
    await setStack(app, s.id);
    setAdding("");
  }

  async function remove() {
    if (
      !(await confirmDialog(
        `Delete the ${s.name} stack and its shared variables? Its apps are kept. They keep running as they are and lose these variables on their next deployment.`,
        { confirmLabel: "Delete stack" },
      ))
    ) {
      return;
    }
    try {
      await api(`/stacks/${s.id}`, { method: "DELETE" });
      toast.success(`Stack "${s.name}" deleted`);
      router.push("/stacks");
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed to delete stack");
    }
  }

  return (
    <Page>
      <PageHeader
        title={s.name}
        description={
          s.description ||
          `Stack${projectName ? ` in ${projectName}` : ""}. Its variables are shared by every app in it.`
        }
        actions={
          canEdit ? (
            <Button kind="danger--tertiary" renderIcon={TrashCan} onClick={remove}>
              Delete stack
            </Button>
          ) : undefined
        }
      />

      <PageSection title="Apps">
        <Stack gap={5}>
          {canEdit && candidates.length > 0 && (
            <div className="gisila-app__form-row">
              <div className="gisila-app__form-field">
                <Select
                  id="stack-add-app"
                  labelText="Add an app from this project"
                  value={adding}
                  onChange={(e) => setAdding(e.target.value)}
                >
                  <SelectItem value="" text="Choose an app" />
                  {candidates.map((a) => (
                    <SelectItem
                      key={a.id}
                      value={String(a.id)}
                      text={a.stackId != null ? `${a.name} (in another stack)` : a.name}
                    />
                  ))}
                </Select>
              </div>
              <Button renderIcon={Add} disabled={!adding || busy} onClick={addSelected}>
                Add
              </Button>
            </div>
          )}

          {members.length > 0 ? (
            <TableContainer>
              <Table size="sm">
                <TableHead>
                  <TableRow>
                    <TableHeader>App</TableHeader>
                    <TableHeader>Runtime</TableHeader>
                    <TableHeader>Status</TableHeader>
                    <TableHeader aria-label="Actions" />
                  </TableRow>
                </TableHead>
                <TableBody>
                  {members.map((a) => (
                    <TableRow key={a.id}>
                      <TableCell>
                        <CarbonLink as={RouterLink} href={`/apps/${a.id}`}>
                          {a.name}
                        </CarbonLink>
                      </TableCell>
                      <TableCell>{a.runtime}</TableCell>
                      <TableCell>
                        <Tag size="sm" type={a.status === "running" ? "green" : "gray"}>
                          {a.status}
                        </Tag>
                      </TableCell>
                      <TableCell>
                        {canEdit && (
                          <Button
                            kind="ghost"
                            size="sm"
                            hasIconOnly
                            renderIcon={Close}
                            iconDescription="Remove from stack"
                            tooltipAlignment="end"
                            disabled={busy}
                            onClick={() => setStack(a, 0)}
                          />
                        )}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </TableContainer>
          ) : (
            <Tile className="gisila-empty">
              No apps in this stack yet.
              {candidates.length === 0 && apps.data
                ? " This project has no apps to add."
                : ""}
            </Tile>
          )}
        </Stack>
      </PageSection>

      <PageSection title="Shared variables">
        <EnvEditor
          basePath={`/stacks/${s.id}`}
          hint="Every app in this stack gets these on its next restart or deployment. An app's own variable with the same name overrides the one here."
        />
      </PageSection>
    </Page>
  );
}
