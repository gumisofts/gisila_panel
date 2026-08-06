"use client";

import { useState } from "react";
import useSWR from "swr";
import { toast } from "@/lib/toast";
import { Add, TrashCan, UserMultiple } from "@carbon/icons-react";
import {
  Button,
  Column,
  Grid,
  Modal,
  Tag,
  TextInput,
  Tile,
} from "@carbon/react";
import { Page, PageHeader, PageSection } from "@/components/page";
import { api, fetcher } from "@/lib/api";
import { formatRelative } from "@/lib/utils";
import type { ListResponse, Team, User } from "@/lib/types";
import "../_batch-a.scss";

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
    <Page>
      <PageHeader
        title="Teams"
        description="Group projects and collaborators. Billing applies per team."
      />

      <PageSection title="Create a team">
        <Tile>
          <form className="gisila-form-row" onSubmit={create}>
            <div className="gisila-form-row__field">
              <TextInput
                id="team-name"
                labelText="Team name"
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="Indie ops"
                required
              />
            </div>
            <Button type="submit" disabled={busy} renderIcon={Add}>
              Create
            </Button>
          </form>
        </Tile>
      </PageSection>

      <PageSection>
        <Grid condensed className="gisila-cards">
          {data?.results.map((t) => (
            <Column key={t.id} sm={4} md={4} lg={8}>
              <Tile>
                <div className="gisila-row">
                  <div className="gisila-row__main">
                    <span className="gisila-status-icon gisila-status-icon--brand">
                      <UserMultiple size={16} />
                    </span>
                    <div>
                      <p className="gisila-card__title">{t.name}</p>
                      <p className="gisila-card__meta">
                        {t.slug} · created {formatRelative(t.createdAt)}
                      </p>
                    </div>
                  </div>
                  <div className="gisila-row__actions">
                    <Tag type="cool-gray" size="sm">
                      {t.plan}
                    </Tag>
                    {canRemove(t) && (
                      <Button
                        kind="ghost"
                        size="sm"
                        hasIconOnly
                        renderIcon={TrashCan}
                        iconDescription="Remove team"
                        tooltipAlignment="end"
                        onClick={() => setRemoveTarget(t)}
                      />
                    )}
                  </div>
                </div>
              </Tile>
            </Column>
          ))}
        </Grid>
      </PageSection>

      <Modal
        danger
        size="sm"
        open={removeTarget !== null}
        modalHeading={`Remove ${removeTarget?.name ?? ""}?`}
        primaryButtonText={removing ? "Removing…" : "Remove team"}
        secondaryButtonText="Cancel"
        primaryButtonDisabled={removing}
        onRequestClose={() => setRemoveTarget(null)}
        onRequestSubmit={removeTeam}
      >
        <p>
          This permanently deletes the team along with{" "}
          <strong>all of its projects and every app inside them</strong>. Each
          app&apos;s service, files, Linux user, domains and TLS certificates are
          torn down, and team members lose access. This cannot be undone.
        </p>
      </Modal>
    </Page>
  );
}
