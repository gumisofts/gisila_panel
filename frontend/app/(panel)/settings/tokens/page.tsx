import { useState } from "react";
import useSWR from "swr";
import { toast } from "@/lib/toast";
import { Add, Copy, TrashCan } from "@carbon/icons-react";
import {
  Button,
  CodeSnippet,
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
import { confirmDialog } from "@/components/confirm-dialog";

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
    if (!(await confirmDialog("Revoke this token?"))) return;
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

      <AiAssistantSection token={issued} />

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

/// How to connect an AI assistant to the panel's MCP endpoint (`/mcp`).
/// Fills in the token just issued, if any.
function AiAssistantSection({ token }: { token: string | null }) {
  const url = `${window.location.origin}/mcp`;
  const bearer = token ?? "<token>";
  const config = JSON.stringify(
    { mcpServers: { gisila: { url, headers: { Authorization: `Bearer ${bearer}` } } } },
    null,
    2,
  );
  return (
    <PageSection
      title="Connect an AI assistant"
      description="AI assistants that speak MCP (Claude Code, Cursor and others) can work with the panel through a token: read status and logs, deploy, restart, change settings. They act as you, with your permissions, and their changes appear in Activity. Issue a separate token for each assistant so you can revoke it on its own."
    >
      <Stack gap={5}>
        <div>
          <p className="gisila-settings__hint">Claude Code</p>
          <CodeSnippet type="multi" feedback="Copied">
            {`claude mcp add --transport http gisila ${url} --header "Authorization: Bearer ${bearer}"`}
          </CodeSnippet>
        </div>
        <div>
          <p className="gisila-settings__hint">Cursor and other clients (mcp.json)</p>
          <CodeSnippet type="multi" feedback="Copied">
            {config}
          </CodeSnippet>
        </div>
      </Stack>
    </PageSection>
  );
}
