"use client";

import { useState } from "react";
import useSWR from "swr";
import { toast } from "@/lib/toast";
import { Plus, Trash2, Users } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { api, fetcher } from "@/lib/api";
import { formatRelative } from "@/lib/utils";
import type { ListResponse, Team, User } from "@/lib/types";

export default function TeamsPage() {
  const { data, mutate } = useSWR<ListResponse<Team>>("/teams/", fetcher);
  const { data: me } = useSWR<User>("/auth/me", fetcher);
  const [name, setName] = useState("");
  const [busy, setBusy] = useState(false);
  const [removeTarget, setRemoveTarget] = useState<Team | null>(null);
  const [removing, setRemoving] = useState(false);

  // Only a team's owner (or a superuser) may delete it.
  const canRemove = (t: Team) =>
    me != null && (me.id === t.ownerId || me.isSuperuser);

  async function removeTeam() {
    if (!removeTarget) return;
    setRemoving(true);
    try {
      await api(`/teams/${removeTarget.id}`, { method: "DELETE" });
      toast.success(`Removing "${removeTarget.name}"…`);
      setRemoveTarget(null);
      mutate();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed to remove team");
    } finally {
      setRemoving(false);
    }
  }

  async function create(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    try {
      await api("/teams/", {
        method: "POST",
        body: JSON.stringify({ name }),
      });
      setName("");
      mutate();
      toast.success("Team created");
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="container space-y-6 py-8">
      <header>
        <h1 className="text-2xl font-semibold tracking-tight">Teams</h1>
        <p className="text-sm text-muted-foreground">
          Group projects and collaborators. Billing applies per team.
        </p>
      </header>

      <Card>
        <CardHeader>
          <CardTitle>Create a team</CardTitle>
        </CardHeader>
        <CardContent>
          <form className="flex items-end gap-3" onSubmit={create}>
            <div className="flex-1 space-y-1.5">
              <label className="text-xs font-medium text-muted-foreground">
                Team name
              </label>
              <Input
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="Indie ops"
                required
              />
            </div>
            <Button type="submit" disabled={busy}>
              <Plus className="h-4 w-4" /> Create
            </Button>
          </form>
        </CardContent>
      </Card>

      <div className="grid gap-3 md:grid-cols-2">
        {data?.results.map((t) => (
          <Card key={t.id}>
            <CardContent className="flex items-center justify-between p-5">
              <div className="flex items-center gap-3">
                <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/15 text-primary">
                  <Users className="h-5 w-5" />
                </div>
                <div>
                  <p className="font-medium">{t.name}</p>
                  <p className="text-xs text-muted-foreground">
                    {t.slug} · created {formatRelative(t.createdAt)}
                  </p>
                </div>
              </div>
              <div className="flex items-center gap-2">
                <Badge variant="muted">{t.plan}</Badge>
                {canRemove(t) && (
                  <Button
                    variant="ghost"
                    size="icon"
                    className="h-8 w-8 text-muted-foreground hover:text-destructive"
                    title="Remove team"
                    onClick={() => setRemoveTarget(t)}
                  >
                    <Trash2 className="h-4 w-4" />
                  </Button>
                )}
              </div>
            </CardContent>
          </Card>
        ))}
      </div>

      <Dialog
        open={removeTarget !== null}
        onOpenChange={(o) => !o && setRemoveTarget(null)}
      >
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Remove {removeTarget?.name}?</DialogTitle>
          </DialogHeader>
          <p className="text-sm text-muted-foreground">
            This permanently deletes the team along with{" "}
            <span className="font-medium text-foreground">
              all of its projects and every app inside them
            </span>
            . Each app&apos;s service, files, Linux user, domains and TLS
            certificates are torn down, and team members lose access. This cannot
            be undone.
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
              onClick={removeTeam}
              disabled={removing}
            >
              {removing ? "Removing…" : "Remove team"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
