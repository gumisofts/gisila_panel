"use client";

import { useState } from "react";
import useSWR from "swr";
import { toast } from "@/lib/toast";
import { Add, Copy, TrashCan } from "@carbon/icons-react";
import {
  Button,
  Form,
  InlineNotification,
  NumberInput,
  Stack,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableHeader,
  TableRow,
  Tag,
  TextInput,
  Tile,
} from "@carbon/react";
import { Page, PageHeader, PageSection } from "@/components/page";
import { api, fetcher } from "@/lib/api";
import { formatRelative } from "@/lib/utils";
import type { ApiToken, ListResponse } from "@/lib/types";
import "../_settings.scss";

export default function TokensPage() {
  const { data, mutate } = useSWR<ListResponse<ApiToken>>(
    "/me/security/tokens",
    fetcher,
  );
  const [name, setName] = useState("");
  const [days, setDays] = useState<number | "">("");
  const [issued, setIssued] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function create(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    try {
      const res = await api<{ plain: string; token: ApiToken }>(
        "/me/security/tokens",
        {
          method: "POST",
          body: JSON.stringify({
            name,
            expiresInDays: days === "" ? undefined : days,
          }),
        },
      );
      setIssued(res.plain);
      setName("");
      setDays("");
      mutate();
      toast.success("Token issued — copy it now");
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed");
    } finally {
      setBusy(false);
    }
  }

  async function revoke(id: number) {
    if (!confirm("Revoke this token?")) return;
    await api(`/me/security/tokens/${id}`, { method: "DELETE" });
    mutate();
  }

  return (
    <Page>
      <PageHeader
        title="API tokens"
        description="Use these for the CLI, CI, or any programmatic access."
      />

      {issued && (
        <PageSection>
          <Stack gap={4}>
            <InlineNotification
              kind="warning"
              lowContrast
              hideCloseButton
              title="Token issued — copy it now."
              subtitle="It won’t be shown again."
            />
            <div className="gisila-settings__secret">
              <code className="gisila-settings__secret-value">{issued}</code>
              <Button
                kind="ghost"
                size="sm"
                hasIconOnly
                renderIcon={Copy}
                iconDescription="Copy token"
                onClick={() => {
                  navigator.clipboard.writeText(issued);
                  toast.success("Copied");
                }}
              />
            </div>
            <div>
              <Button kind="ghost" size="sm" onClick={() => setIssued(null)}>
                Dismiss
              </Button>
            </div>
          </Stack>
        </PageSection>
      )}

      <PageSection title="Issue a new token">
        <Form onSubmit={create}>
          <div className="gisila-settings__form-row">
            <div className="gisila-settings__form-field">
              <TextInput
                id="token-name"
                labelText="Name"
                required
                placeholder="ci/cd"
                value={name}
                onChange={(e) => setName(e.target.value)}
              />
            </div>
            <div className="gisila-settings__form-field gisila-settings__form-field--narrow">
              <NumberInput
                id="token-expires-in-days"
                label="Expires (days)"
                min={1}
                allowEmpty
                hideSteppers
                value={days}
                placeholder="never"
                onChange={(_event, { value }) =>
                  setDays(value === "" ? "" : Number(value))
                }
              />
            </div>
            <Button type="submit" disabled={busy} renderIcon={Add}>
              Issue
            </Button>
          </div>
        </Form>
      </PageSection>

      <PageSection>
        {data?.results.length ? (
          <TableContainer>
            <Table size="sm">
              <TableHead>
                <TableRow>
                  <TableHeader>Name</TableHeader>
                  <TableHeader>Prefix</TableHeader>
                  <TableHeader>Last used</TableHeader>
                  <TableHeader>Expires</TableHeader>
                  <TableHeader />
                </TableRow>
              </TableHead>
              <TableBody>
                {data.results.map((t) => (
                  <TableRow key={t.id}>
                    <TableCell>{t.name}</TableCell>
                    <TableCell>
                      <span className="gisila-settings__mono">{t.prefix}</span>
                    </TableCell>
                    <TableCell>{formatRelative(t.lastUsedAt)}</TableCell>
                    <TableCell>
                      {t.expiresAt && (
                        <Tag type="cool-gray" size="sm">
                          expires {formatRelative(t.expiresAt)}
                        </Tag>
                      )}
                    </TableCell>
                    <TableCell>
                      <div className="gisila-settings__row-actions">
                        <Button
                          kind="danger--ghost"
                          size="sm"
                          hasIconOnly
                          renderIcon={TrashCan}
                          iconDescription="Revoke token"
                          onClick={() => revoke(t.id)}
                        />
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </TableContainer>
        ) : (
          <Tile className="gisila-empty">No tokens yet.</Tile>
        )}
      </PageSection>
    </Page>
  );
}
