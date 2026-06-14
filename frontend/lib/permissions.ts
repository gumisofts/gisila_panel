"use client";

import useSWR from "swr";
import { fetcher } from "./api";
import type { ListResponse, Project, Role, Team, User } from "./types";

const RANK: Record<Role, number> = {
  viewer: 0,
  developer: 1,
  admin: 2,
  owner: 3,
};

/** True when [role] meets or exceeds [min] in the privilege hierarchy. */
export function roleAtLeast(role: Role | undefined | null, min: Role): boolean {
  if (!role) return false;
  return RANK[role] >= RANK[min];
}

/**
 * Resolve what the current user is allowed to do. Mirrors the backend policy:
 *   - superusers can do anything;
 *   - team resources follow the viewer<developer<admin<owner hierarchy;
 *   - node-global infra (services, databases, mail) is superuser-only.
 *
 * The backend enforces all of this with 403s — these helpers only drive whether
 * the UI shows a control, so the experience matches the user's actual rights.
 */
export function usePermissions() {
  const { data: me } = useSWR<User>("/auth/me", fetcher);
  const { data: teams } = useSWR<ListResponse<Team>>("/teams/", fetcher);
  const { data: projects } = useSWR<ListResponse<Project>>("/projects/", fetcher);

  const isSuperuser = me?.isSuperuser ?? false;

  const roleByTeam = new Map<number, Role>();
  for (const t of teams?.results ?? []) {
    if (t.myRole) roleByTeam.set(t.id, t.myRole);
  }
  const teamByProject = new Map<number, number>();
  for (const p of projects?.results ?? []) teamByProject.set(p.id, p.teamId);

  function teamRole(teamId?: number | null): Role | undefined {
    if (teamId == null) return undefined;
    return roleByTeam.get(teamId);
  }

  function canForTeam(teamId: number | null | undefined, min: Role): boolean {
    if (isSuperuser) return true;
    return roleAtLeast(teamRole(teamId), min);
  }

  function canForProject(
    projectId: number | null | undefined,
    min: Role,
  ): boolean {
    if (isSuperuser) return true;
    if (projectId == null) return false;
    return canForTeam(teamByProject.get(projectId), min);
  }

  return { isSuperuser, teamRole, canForTeam, canForProject };
}
