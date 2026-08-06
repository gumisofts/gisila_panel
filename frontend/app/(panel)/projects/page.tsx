"use client";

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
import { Add, Application, FolderOpen, TrashCan } from "@carbon/icons-react";
import { Page, PageHeader, PageSection } from "@/components/page";
import { api, fetcher } from "@/lib/api";
import { usePermissions } from "@/lib/permissions";
import { formatRelative } from "@/lib/utils";
import type { ListResponse, Project, Team } from "@/lib/types";
import "../_batch-a.scss";

export default function ProjectsPage() {
  const { data: projectsData, mutate } = useSWR<ListResponse<Project>>(
    "/projects/",
    fetcher
  );
  const { data: teamsData } = useSWR<ListResponse<Team>>("/teams/", fetcher);

  const [open, setOpen] = useState(false);
  const [teamId, setTeamId] = useState<string>("");
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [saving, setSaving] = useState(false);
  const [removeTarget, setRemoveTarget] = useState<Project | null>(null);
  const [removing, setRemoving] = useState(false);
  const { canForTeam } = usePermissions();

  const teams = teamsData?.results ?? [];
  const projects = projectsData?.results ?? [];

  const removeProject = async () => {
    if (!removeTarget) return;
    setRemoving(true);
    try {
      await api(`/projects/${removeTarget.id}`, { method: "DELETE" });
      toast.success(`Removing "${removeTarget.name}"…`);
      setRemoveTarget(null);
      mutate();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed to remove project");
    } finally {
      setRemoving(false);
    }
  };

  // Group projects by team for display
  const byTeam = teams.map((t) => ({
    team: t,
    projects: projects.filter((p) => p.teamId === t.id),
  }));

  const openDialog = () => {
    setTeamId(teams[0] ? String(teams[0].id) : "");
    setName("");
    setDescription("");
    setOpen(true);
  };

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!teamId) return;
    setSaving(true);
    try {
      await api<Project>("/projects/", {
        method: "POST",
        body: JSON.stringify({
          teamId: Number(teamId),
          name,
          description: description || undefined,
        }),
      });
      mutate();
      setOpen(false);
      toast.success(`Project "${name}" created`);
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed to create project");
    } finally {
      setSaving(false);
    }
  };

  return (
    <Page>
      <PageHeader
        title="Projects"
        description="Organize apps into projects within your teams."
        actions={
          <Button
            onClick={openDialog}
            disabled={teams.length === 0}
            renderIcon={Add}
          >
            New Project
          </Button>
        }
      />

      {teams.length === 0 && (
        <Tile>
          <div className="gisila-empty-state">
            <FolderOpen size={32} />
            <p>You need a team before you can create projects.</p>
            <div>
              <Button as={RouterLink} href="/teams" kind="tertiary" size="sm">
                Go to Teams
              </Button>
            </div>
          </div>
        </Tile>
      )}

      {teams.length > 0 && projects.length === 0 && (
        <Tile>
          <div className="gisila-empty-state">
            <FolderOpen size={32} />
            <p>No projects yet.</p>
            <div>
              <Button kind="tertiary" size="sm" renderIcon={Add} onClick={openDialog}>
                Create your first project
              </Button>
            </div>
          </div>
        </Tile>
      )}

      {byTeam.map(({ team, projects: ps }) =>
        ps.length === 0 ? null : (
          <PageSection key={team.id} title={team.name}>
            <Grid condensed className="gisila-cards">
              {ps.map((p) => (
                <Column key={p.id} sm={4} md={4} lg={5}>
                  <Tile>
                    <div className="gisila-card__head">
                      <div className="gisila-row__main">
                        <span className="gisila-status-icon gisila-status-icon--brand">
                          <FolderOpen size={16} />
                        </span>
                        <div className="gisila-row__text">
                          <p className="gisila-card__title gisila-truncate">
                            {p.name}
                          </p>
                          <p className="gisila-card__mono gisila-truncate">
                            {p.slug}
                          </p>
                        </div>
                      </div>
                      {canForTeam(p.teamId, "admin") && (
                        <Button
                          kind="ghost"
                          size="sm"
                          hasIconOnly
                          renderIcon={TrashCan}
                          iconDescription="Remove project"
                          tooltipAlignment="end"
                          onClick={() => setRemoveTarget(p)}
                        />
                      )}
                    </div>
                    {p.description && (
                      <p className="gisila-card__body gisila-clamp">
                        {p.description}
                      </p>
                    )}
                    <div className="gisila-card__foot">
                      <span>{formatRelative(p.createdAt)}</span>
                      <CarbonLink
                        as={RouterLink}
                        href={`/apps?projectId=${p.id}`}
                        renderIcon={Application}
                        size="sm"
                      >
                        View apps
                      </CarbonLink>
                    </div>
                  </Tile>
                </Column>
              ))}
            </Grid>
          </PageSection>
        )
      )}

      <Modal
        danger
        size="sm"
        open={removeTarget !== null}
        modalHeading={`Remove ${removeTarget?.name ?? ""}?`}
        primaryButtonText={removing ? "Removing…" : "Remove project"}
        secondaryButtonText="Cancel"
        primaryButtonDisabled={removing}
        onRequestClose={() => setRemoveTarget(null)}
        onRequestSubmit={removeProject}
      >
        <p>
          This permanently deletes the project and{" "}
          <strong>every app inside it</strong> — each app&apos;s service, files,
          Linux user, domains and TLS certificates are torn down. This cannot be
          undone.
        </p>
      </Modal>

      <Modal
        size="sm"
        open={open}
        modalHeading="New Project"
        primaryButtonText={saving ? "Creating…" : "Create Project"}
        secondaryButtonText="Cancel"
        primaryButtonDisabled={saving || !name.trim() || !teamId}
        onRequestClose={() => setOpen(false)}
        onRequestSubmit={submit}
      >
        <form onSubmit={submit}>
          <Stack gap={5}>
            <Select
              id="team"
              labelText="Team"
              value={teamId}
              onChange={(e) => setTeamId(e.target.value)}
            >
              <SelectItem disabled hidden value="" text="Select a team" />
              {teams.map((t) => (
                <SelectItem key={t.id} value={String(t.id)} text={t.name} />
              ))}
            </Select>
            <TextInput
              id="proj-name"
              labelText="Project name"
              placeholder="my-backend"
              value={name}
              onChange={(e) => setName(e.target.value)}
              required
            />
            <TextInput
              id="proj-desc"
              labelText="Description (optional)"
              placeholder="Short description…"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
            />
          </Stack>
        </form>
      </Modal>
    </Page>
  );
}
