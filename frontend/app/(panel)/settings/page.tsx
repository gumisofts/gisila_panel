"use client";

import { useState } from "react";
import useSWR from "swr";
import { toast } from "@/lib/toast";
import { Add, TrashCan } from "@carbon/icons-react";
import {
  Button,
  Form,
  Stack,
  StructuredListBody,
  StructuredListCell,
  StructuredListRow,
  StructuredListWrapper,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableHeader,
  TableRow,
  TextArea,
  TextInput,
  Tile,
} from "@carbon/react";
import { Page, PageHeader, PageSection } from "@/components/page";
import { api, fetcher } from "@/lib/api";
import { formatRelative } from "@/lib/utils";
import type { ListResponse, SshKey, User } from "@/lib/types";
import "./_settings.scss";

export default function SettingsPage() {
  const me = useSWR<User>("/auth/me", fetcher);
  const keys = useSWR<ListResponse<SshKey>>("/me/security/ssh-keys", fetcher);

  const [keyName, setKeyName] = useState("");
  const [publicKey, setPublicKey] = useState("");
  const [busy, setBusy] = useState(false);

  async function addKey(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    try {
      await api("/me/security/ssh-keys", {
        method: "POST",
        body: JSON.stringify({ name: keyName, publicKey }),
      });
      setKeyName("");
      setPublicKey("");
      keys.mutate();
      toast.success("SSH key added");
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed");
    } finally {
      setBusy(false);
    }
  }

  async function removeKey(id: number) {
    if (!confirm("Remove this SSH key?")) return;
    await api(`/me/security/ssh-keys/${id}`, { method: "DELETE" });
    keys.mutate();
  }

  return (
    <Page>
      <PageHeader
        title="Settings"
        description="Profile, security and SSH keys."
      />

      <PageSection title="Profile">
        <StructuredListWrapper aria-label="Profile" isCondensed>
          <StructuredListBody>
            <StructuredListRow>
              <StructuredListCell className="gisila-settings__term">
                Email
              </StructuredListCell>
              <StructuredListCell>{me.data?.email}</StructuredListCell>
            </StructuredListRow>
            <StructuredListRow>
              <StructuredListCell className="gisila-settings__term">
                Member since
              </StructuredListCell>
              <StructuredListCell>
                {me.data ? formatRelative(me.data.createdAt) : "—"}
              </StructuredListCell>
            </StructuredListRow>
          </StructuredListBody>
        </StructuredListWrapper>
      </PageSection>

      <PageSection title="SSH keys">
        <Stack gap={6}>
          <Form onSubmit={addKey}>
            <Stack gap={5}>
              <TextInput
                id="ssh-key-name"
                labelText="Name"
                value={keyName}
                onChange={(e) => setKeyName(e.target.value)}
                placeholder="My laptop"
                required
              />
              <TextArea
                id="ssh-key-public"
                labelText="Public key"
                value={publicKey}
                onChange={(e) => setPublicKey(e.target.value)}
                rows={4}
                placeholder="ssh-ed25519 AAAA…"
                required
              />
              <div>
                <Button type="submit" disabled={busy} renderIcon={Add}>
                  Add key
                </Button>
              </div>
            </Stack>
          </Form>

          {keys.data?.results.length ? (
            <TableContainer>
              <Table size="sm">
                <TableHead>
                  <TableRow>
                    <TableHeader>Name</TableHeader>
                    <TableHeader>Fingerprint</TableHeader>
                    <TableHeader />
                  </TableRow>
                </TableHead>
                <TableBody>
                  {keys.data.results.map((k) => (
                    <TableRow key={k.id}>
                      <TableCell>{k.name}</TableCell>
                      <TableCell>
                        <span className="gisila-settings__mono">
                          {k.fingerprint}
                        </span>
                      </TableCell>
                      <TableCell>
                        <div className="gisila-settings__row-actions">
                          <Button
                            kind="danger--ghost"
                            size="sm"
                            hasIconOnly
                            renderIcon={TrashCan}
                            iconDescription="Remove key"
                            onClick={() => removeKey(k.id)}
                          />
                        </div>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </TableContainer>
          ) : (
            <Tile className="gisila-empty">No SSH keys uploaded.</Tile>
          )}
        </Stack>
      </PageSection>
    </Page>
  );
}
