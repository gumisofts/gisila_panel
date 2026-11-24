import { useState } from "react";
import RouterLink from "@/compat/link";
import useSWR from "swr";
import { toast } from "@/lib/toast";
import {
  Button,
  Column,
  Grid,
  Link as CarbonLink,
  Modal,
  Select,
  SelectItem,
  Stack,
  TextInput,
  Tile,
} from "@carbon/react";
import { Add, ArrowRight, Category } from "@carbon/icons-react";
import { Page, PageHeader, PageSection } from "@/components/page";
import { api, fetcher } from "@/lib/api";
import { usePermissions } from "@/lib/permissions";
import type {
  App,
  ListResponse,
  Project,
  Stack as StackModel,
} from "@/lib/types";
import "../_batch-a.scss";

export default function StacksPage() {
  const { data, mutate } = useSWR<ListResponse<StackModel>>("/stacks/", fetcher);
  const projectsData = useSWR<ListResponse<Project>>("/projects/", fetcher);
  const appsData = useSWR<ListResponse<App>>("/apps/", fetcher);
  const { canForProject } = usePermissions();

  const [open, setOpen] = useState(false);
  const [projectId, setProjectId] = useState("");
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [saving, setSaving] = useState(false);

  const stacks = data?.results ?? [];
  const projects = projectsData.data?.results ?? [];
  // Stacks can only be created where the user could also edit an app's env.
  const writable = projects.filter((p) => canForProject(p.id, "developer"));
  const appCount = new Map<number, number>();
  for (const a of appsData.data?.results ?? []) {
    if (a.stackId != null) {
      appCount.set(a.stackId, (appCount.get(a.stackId) ?? 0) + 1);
    }
  }

  const openDialog = () => {
    setProjectId(writable[0] ? String(writable[0].id) : "");
    setName("");
    setDescription("");
    setOpen(true);
  };

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!projectId || !name.trim()) return;
    setSaving(true);
    try {
      await api<StackModel>("/stacks/", {
        method: "POST",
        body: JSON.stringify({
          projectId: Number(projectId),
          name: name.trim(),
          description: description || undefined,
        }),
      });
      mutate();
      setOpen(false);
      toast.success(`Stack "${name.trim()}" created`);
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed to create stack");
    } finally {
      setSaving(false);
    }
  };

  return (
    <Page>
      <PageHeader
        title="Stacks"
        description="Group the apps that belong together and give them one shared set of environment variables."
        actions={
          <Button
            onClick={openDialog}
            disabled={writable.length === 0}
            renderIcon={Add}
          >
            New stack
          </Button>
        }
      />

      {data && stacks.length === 0 && (
        <Tile>
          <div className="gisila-empty-state">
            <Category size={32} />
            <p>
              No stacks yet. A stack holds variables such as DATABASE_URL once,
              and every app in it gets them. An app&apos;s own variable still
              wins when both set the same name.
            </p>
            {writable.length > 0 ? (
              <div>
                <Button kind="tertiary" size="sm" renderIcon={Add} onClick={openDialog}>
                  Create your first stack
                </Button>
              </div>
            ) : (
              <p>
                You need a project first.{" "}
                <CarbonLink as={RouterLink} href="/projects">
                  Go to Projects
                </CarbonLink>
              </p>
            )}
          </div>
        </Tile>
      )}

      {projects.map((project) => {
        const own = stacks.filter((s) => s.projectId === project.id);
        if (own.length === 0) return null;
        return (
          <PageSection key={project.id} title={project.name}>
            <Grid condensed className="gisila-cards">
              {own.map((s) => {
                const n = appCount.get(s.id) ?? 0;
                return (
                  <Column key={s.id} sm={4} md={4} lg={5}>
                    <Tile>
                      <div className="gisila-card__head">
                        <div className="gisila-row__main">
                          <span className="gisila-status-icon gisila-status-icon--brand">
                            <Category size={16} />
                          </span>
                          <div className="gisila-row__text">
                            <p className="gisila-card__title gisila-truncate">
                              {s.name}
                            </p>
                            <p className="gisila-card__mono gisila-truncate">
                              {n} app{n === 1 ? "" : "s"}
                            </p>
                          </div>
                        </div>
                      </div>
                      {s.description && (
                        <p className="gisila-card__body gisila-clamp">
                          {s.description}
                        </p>
                      )}
                      <div className="gisila-card__foot">
                        <span />
                        <CarbonLink
                          as={RouterLink}
                          href={`/stacks/${s.id}`}
                          renderIcon={ArrowRight}
                          size="sm"
                        >
                          Apps and variables
                        </CarbonLink>
                      </div>
                    </Tile>
                  </Column>
                );
              })}
            </Grid>
          </PageSection>
        );
      })}

      <Modal
        size="sm"
        open={open}
        modalHeading="New stack"
        primaryButtonText={saving ? "Creating…" : "Create stack"}
        secondaryButtonText="Cancel"
        primaryButtonDisabled={saving || !name.trim() || !projectId}
        onRequestClose={() => setOpen(false)}
        onRequestSubmit={submit}
      >
        <form onSubmit={submit}>
          <Stack gap={5}>
            <Select
              id="stack-project"
              labelText="Project"
              helperText="A stack can hold apps from this project only."
              value={projectId}
              onChange={(e) => setProjectId(e.target.value)}
            >
              <SelectItem disabled hidden value="" text="Select a project" />
              {writable.map((p) => (
                <SelectItem key={p.id} value={String(p.id)} text={p.name} />
              ))}
            </Select>
            <TextInput
              id="stack-name"
              labelText="Stack name"
              placeholder="production"
              value={name}
              onChange={(e) => setName(e.target.value)}
              required
            />
            <TextInput
              id="stack-desc"
              labelText="Description (optional)"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
            />
          </Stack>
        </form>
      </Modal>
    </Page>
  );
}
