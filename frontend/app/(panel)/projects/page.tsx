"use client";

import { useState } from "react";
import Link from "@/compat/link";
import useSWR from "swr";
import { toast } from "@/lib/toast";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { api, fetcher } from "@/lib/api";
import { usePermissions } from "@/lib/permissions";
import { formatRelative } from "@/lib/utils";
import type { ListResponse, Project, Team } from "@/lib/types";
import { Boxes, FolderOpen, Plus, Trash2 } from "lucide-react";

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
    <div className="max-w-4xl mx-auto space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold">Projects</h1>
          <p className="text-sm text-muted-foreground mt-1">
            Organize apps into projects within your teams.
          </p>
        </div>
        <Button onClick={openDialog} disabled={teams.length === 0}>
          <Plus className="w-4 h-4 mr-2" /> New Project
        </Button>
      </div>

      {teams.length === 0 && (
        <Card>
          <CardContent className="flex flex-col items-center justify-center py-14 gap-3 text-center">
            <FolderOpen className="w-10 h-10 text-muted-foreground/50" />
            <p className="text-sm text-muted-foreground">
              You need a team before you can create projects.
            </p>
            <Button variant="outline" size="sm" asChild>
              <Link href="/teams">Go to Teams</Link>
            </Button>
          </CardContent>
        </Card>
      )}

      {teams.length > 0 && projects.length === 0 && (
        <Card>
          <CardContent className="flex flex-col items-center justify-center py-14 gap-3 text-center">
            <FolderOpen className="w-10 h-10 text-muted-foreground/50" />
            <p className="text-sm text-muted-foreground">No projects yet.</p>
            <Button variant="outline" size="sm" onClick={openDialog}>
              <Plus className="w-4 h-4 mr-1" /> Create your first project
            </Button>
          </CardContent>
        </Card>
      )}

      {byTeam.map(({ team, projects: ps }) =>
        ps.length === 0 ? null : (
          <section key={team.id}>
            <h2 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-3 px-0.5">
              {team.name}
            </h2>
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
              {ps.map((p) => (
                <Card
                  key={p.id}
                  className="hover:border-primary/40 transition-colors"
                >
                  <CardContent className="p-5">
                    <div className="flex items-start justify-between gap-2">
                      <div className="flex items-center gap-3 min-w-0">
                        <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">
                          <FolderOpen className="h-4 w-4" />
                        </div>
                        <div className="min-w-0">
                          <p className="font-medium text-sm truncate">{p.name}</p>
                          <p className="text-xs text-muted-foreground font-mono">
                            {p.slug}
                          </p>
                        </div>
                      </div>
                      {canForTeam(p.teamId, "admin") && (
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-8 w-8 shrink-0 text-muted-foreground hover:text-destructive"
                          title="Remove project"
                          onClick={() => setRemoveTarget(p)}
                        >
                          <Trash2 className="h-4 w-4" />
                        </Button>
                      )}
                    </div>
                    {p.description && (
                      <p className="mt-3 text-xs text-muted-foreground line-clamp-2">
                        {p.description}
                      </p>
                    )}
                    <div className="mt-4 flex items-center justify-between">
                      <span className="text-xs text-muted-foreground">
                        {formatRelative(p.createdAt)}
                      </span>
                      <Link
                        href={`/apps?projectId=${p.id}`}
                        className="flex items-center gap-1 text-xs text-primary hover:underline"
                      >
                        <Boxes className="w-3.5 h-3.5" />
                        View apps
                      </Link>
                    </div>
                  </CardContent>
                </Card>
              ))}
            </div>
          </section>
        )
      )}

      <Dialog
        open={removeTarget !== null}
        onOpenChange={(o) => !o && setRemoveTarget(null)}
      >
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Remove {removeTarget?.name}?</DialogTitle>
          </DialogHeader>
          <p className="text-sm text-muted-foreground">
            This permanently deletes the project and{" "}
            <span className="font-medium text-foreground">every app inside it</span>{" "}
            — each app&apos;s service, files, Linux user, domains and TLS
            certificates are torn down. This cannot be undone.
          </p>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setRemoveTarget(null)}
              disabled={removing}
            >
              Cancel
            </Button>
            <Button
              variant="destructive"
              onClick={removeProject}
              disabled={removing}
            >
              {removing ? "Removing…" : "Remove project"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>New Project</DialogTitle>
          </DialogHeader>
          <form onSubmit={submit} className="space-y-4">
            <div>
              <Label htmlFor="team">Team</Label>
              <Select value={teamId} onValueChange={setTeamId}>
                <SelectTrigger id="team" className="mt-1">
                  <SelectValue placeholder="Select a team" />
                </SelectTrigger>
                <SelectContent>
                  {teams.map((t) => (
                    <SelectItem key={t.id} value={String(t.id)}>
                      {t.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label htmlFor="proj-name">Project name</Label>
              <Input
                id="proj-name"
                className="mt-1"
                placeholder="my-backend"
                value={name}
                onChange={(e) => setName(e.target.value)}
                required
              />
            </div>
            <div>
              <Label htmlFor="proj-desc">
                Description
                <span className="ml-1.5 text-[10px] font-normal text-muted-foreground">
                  (optional)
                </span>
              </Label>
              <Input
                id="proj-desc"
                className="mt-1"
                placeholder="Short description…"
                value={description}
                onChange={(e) => setDescription(e.target.value)}
              />
            </div>
            <DialogFooter>
              <Button
                type="button"
                variant="outline"
                onClick={() => setOpen(false)}
              >
                Cancel
              </Button>
              <Button type="submit" disabled={saving || !name.trim() || !teamId}>
                {saving ? "Creating…" : "Create Project"}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  );
}
