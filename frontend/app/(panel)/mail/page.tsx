"use client";

import { useState } from "react";
import useSWR, { mutate } from "swr";
import {
  Add,
  At,
  BareMetalServer,
  Checkmark,
  ChevronDown,
  ChevronRight,
  Download,
  Earth,
  Email,
  Password,
  Renew,
  Security,
  SettingsAdjust,
  TrashCan,
} from "@carbon/icons-react";
import {
  Button,
  CodeSnippet,
  DataTableSkeleton,
  InlineLoading,
  InlineNotification,
  Modal,
  NumberInput,
  PasswordInput,
  Select,
  SelectItem,
  SkeletonText,
  Stack,
  StructuredListBody,
  StructuredListCell,
  StructuredListRow,
  StructuredListWrapper,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
  Tag,
  TextInput,
  Tile,
} from "@carbon/react";
import { Page, PageHeader } from "@/components/page";
import { api, fetcher } from "@/lib/api";
import type {
  ListResponse,
  MailDomain,
  MailAccount,
  MailDnsResponse,
  MailConnectionSettings,
  MailStatus,
} from "@/lib/types";
import "../_storage-mail.scss";

export default function MailPage() {
  // Gate the whole mail UI behind the tooling install check. While the tooling
  // is absent we poll so the page flips to the normal UI as soon as the
  // operator's install finishes (or someone installs it out of band).
  const { data: status, isLoading: statusLoading } = useSWR<MailStatus>(
    "/mail/status",
    fetcher,
    { refreshInterval: (d) => (d?.installed ? 0 : 4_000) }
  );
  const installed = status?.installed ?? false;

  const { data, isLoading } = useSWR<ListResponse<MailDomain>>(
    installed ? "/mail/domains" : null,
    fetcher,
    {
      // Poll faster while any domain is still waiting for its DKIM key.
      refreshInterval(latestData) {
        const anyPending = latestData?.results.some((d) => !d.dkimConfigured);
        return anyPending ? 5_000 : 15_000;
      },
    }
  );

  const [showAdd, setShowAdd] = useState(false);
  const [domain, setDomain] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [installing, setInstalling] = useState(false);

  async function handleInstall() {
    setError("");
    setInstalling(true);
    try {
      await api("/mail/install", { method: "POST" });
      // Keep `installing` true and let the status poll flip the UI to the
      // normal mail view once the worker finishes provisioning.
      mutate("/mail/status");
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Failed to start installation.");
      setInstalling(false);
    }
  }

  async function handleAddDomain() {
    setError("");
    setBusy(true);
    try {
      await api("/mail/domains", {
        method: "POST",
        body: JSON.stringify({ domain }),
      });
      mutate("/mail/domains");
      setShowAdd(false);
      setDomain("");
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Failed to add domain.");
    } finally {
      setBusy(false);
    }
  }

  const domains = data?.results ?? [];

  return (
    <Page>
      <PageHeader
        title="Mail"
        description={
          <>
            Host email for your domains. Each domain can have multiple mailboxes
            (Postfix&nbsp;+&nbsp;Dovecot).
          </>
        }
        actions={
          installed && (
            <Button size="sm" renderIcon={Add} onClick={() => setShowAdd(true)}>
              Add domain
            </Button>
          )
        }
      />

      {statusLoading ? (
        <SkeletonText paragraph lineCount={3} />
      ) : !installed ? (
        <Tile className="gisila-empty">
          <Stack gap={4}>
            <Email size={32} style={{ opacity: 0.4 }} />
            <div>
              <p className="gisila-sm__title">Email tools not installed</p>
              <p className="gisila-sm__note" style={{ marginBlockStart: "0.25rem" }}>
                Installs Postfix, Dovecot and OpenDKIM on this server so you can
                host mailboxes for your domains. This runs once and may take a
                minute.
              </p>
            </div>
            <div style={{ display: "flex", justifyContent: "center" }}>
              {installing ? (
                <InlineLoading
                  status="active"
                  description="Installing email tools…"
                />
              ) : (
                <Button size="sm" renderIcon={Download} onClick={handleInstall}>
                  Install email tools
                </Button>
              )}
            </div>
            {error && (
              <InlineNotification
                kind="error"
                lowContrast
                hideCloseButton
                title={error}
              />
            )}
          </Stack>
        </Tile>
      ) : isLoading ? (
        <SkeletonText paragraph lineCount={3} />
      ) : domains.length === 0 ? (
        <Tile className="gisila-empty">
          <Stack gap={4}>
            <Email size={32} style={{ opacity: 0.4 }} />
            <div>
              <p className="gisila-sm__title">No mail domains yet</p>
              <p className="gisila-sm__note" style={{ marginBlockStart: "0.25rem" }}>
                Add a domain to start hosting mailboxes. Point its MX record at
                this server once configured.
              </p>
            </div>
            <div style={{ display: "flex", justifyContent: "center" }}>
              <Button size="sm" renderIcon={Add} onClick={() => setShowAdd(true)}>
                Add domain
              </Button>
            </div>
          </Stack>
        </Tile>
      ) : (
        <Stack gap={4}>
          {domains.map((d) => (
            <DomainCard key={d.id} domain={d} />
          ))}
        </Stack>
      )}

      <Modal
        open={showAdd}
        onRequestClose={() => setShowAdd(false)}
        modalHeading="Add mail domain"
        primaryButtonText="Add"
        primaryButtonDisabled={busy || !domain.trim()}
        secondaryButtonText="Cancel"
        loadingStatus={busy ? "active" : "inactive"}
        loadingDescription="Adding domain…"
        onRequestSubmit={handleAddDomain}
        size="sm"
      >
        <Stack gap={5}>
          <TextInput
            id="mail-new-domain"
            labelText="Domain"
            placeholder="example.com"
            helperText="Set an MX record pointing at this host and a matching A record so mail can be delivered."
            value={domain}
            onChange={(e) => setDomain(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && handleAddDomain()}
          />
          {error && (
            <InlineNotification
              kind="error"
              lowContrast
              hideCloseButton
              title={error}
            />
          )}
        </Stack>
      </Modal>
    </Page>
  );
}

function DomainCard({ domain }: { domain: MailDomain }) {
  const [open, setOpen] = useState(false);
  const [removing, setRemoving] = useState(false);

  const accountsKey = open ? `/mail/domains/${domain.id}/accounts` : null;
  const { data, isLoading } = useSWR<ListResponse<MailAccount>>(
    accountsKey,
    fetcher
  );
  const accounts = data?.results ?? [];

  const [showAdd, setShowAdd] = useState(false);
  const [localPart, setLocalPart] = useState("");
  const [password, setPassword] = useState("");
  const [quota, setQuota] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  const [pwAccount, setPwAccount] = useState<MailAccount | null>(null);
  const [newPw, setNewPw] = useState("");

  // DNS-facing settings (hostname + DMARC policy).
  const [hostname, setHostname] = useState(domain.mailHostname);
  const [dmarc, setDmarc] = useState(domain.dmarcPolicy);
  const [savingSettings, setSavingSettings] = useState(false);
  const settingsDirty =
    hostname.trim() !== domain.mailHostname || dmarc !== domain.dmarcPolicy;

  // Connection settings dialog for a specific mailbox.
  const [connAccount, setConnAccount] = useState<MailAccount | null>(null);

  function reloadAccounts() {
    mutate(`/mail/domains/${domain.id}/accounts`);
  }

  async function handleSaveSettings() {
    setSavingSettings(true);
    try {
      await api(`/mail/domains/${domain.id}`, {
        method: "PATCH",
        body: JSON.stringify({ mailHostname: hostname.trim(), dmarcPolicy: dmarc }),
      });
      mutate("/mail/domains");
      mutate(`/mail/domains/${domain.id}/dns`);
    } catch (e: unknown) {
      alert(e instanceof Error ? e.message : "Failed to save settings.");
    } finally {
      setSavingSettings(false);
    }
  }

  async function handleRemoveDomain() {
    if (!confirm(`Remove ${domain.domain} and all its mailboxes?`)) return;
    setRemoving(true);
    try {
      await api(`/mail/domains/${domain.id}`, { method: "DELETE" });
      mutate("/mail/domains");
    } catch (e: unknown) {
      alert(e instanceof Error ? e.message : "Failed to remove domain.");
    } finally {
      setRemoving(false);
    }
  }

  async function handleAddAccount() {
    setError("");
    setBusy(true);
    try {
      await api(`/mail/domains/${domain.id}/accounts`, {
        method: "POST",
        body: JSON.stringify({
          localPart,
          password,
          quotaMb: quota ? Number(quota) : undefined,
        }),
      });
      reloadAccounts();
      setShowAdd(false);
      setLocalPart("");
      setPassword("");
      setQuota("");
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Failed to create mailbox.");
    } finally {
      setBusy(false);
    }
  }

  async function handleSetPassword() {
    if (!pwAccount) return;
    setBusy(true);
    setError("");
    try {
      await api(`/mail/accounts/${pwAccount.id}/password`, {
        method: "PUT",
        body: JSON.stringify({ password: newPw }),
      });
      setPwAccount(null);
      setNewPw("");
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Failed to set password.");
    } finally {
      setBusy(false);
    }
  }

  async function handleDeleteAccount(acc: MailAccount) {
    if (!confirm(`Delete mailbox ${acc.address}?`)) return;
    try {
      await api(`/mail/accounts/${acc.id}`, { method: "DELETE" });
      reloadAccounts();
    } catch (e: unknown) {
      alert(e instanceof Error ? e.message : "Failed to delete mailbox.");
    }
  }

  return (
    <Tile>
      <div style={{ display: "flex", alignItems: "center", gap: "1rem" }}>
        <button
          type="button"
          className="gisila-mail__toggle"
          onClick={() => setOpen((o) => !o)}
        >
          <span className="gisila-status-icon gisila-status-icon--brand">
            <Earth size={20} />
          </span>
          <span style={{ flex: 1, minWidth: 0 }}>
            <span className="gisila-mail__domain">{domain.domain}</span>
            <span className="gisila-sm__note" style={{ display: "block" }}>
              {open
                ? `${accounts.length} mailbox${accounts.length === 1 ? "" : "es"}`
                : "Click to manage mailboxes"}
            </span>
          </span>
          {open ? <ChevronDown size={16} /> : <ChevronRight size={16} />}
        </button>
        {removing ? (
          <InlineLoading status="active" description="Removing…" />
        ) : (
          <Button
            kind="danger--ghost"
            size="sm"
            hasIconOnly
            renderIcon={TrashCan}
            iconDescription="Remove domain"
            onClick={handleRemoveDomain}
          />
        )}
      </div>

      {open && (
        <div className="gisila-mail__panel">
          <Stack gap={7}>
            {/* ── Settings: hostname + DMARC ─────────────────────────────── */}
            <Stack gap={5}>
              <p className="gisila-sm__title gisila-sm__title-row">
                <SettingsAdjust size={16} />
                Settings
              </p>
              <div
                style={{
                  display: "grid",
                  gap: "1rem",
                  gridTemplateColumns: "repeat(auto-fit, minmax(16rem, 1fr))",
                }}
              >
                <TextInput
                  id={`mail-hostname-${domain.id}`}
                  labelText="Mail hostname"
                  value={hostname}
                  placeholder={`mail.${domain.domain}`}
                  helperText="The host MX / A records point at. Needs a real or self-signed TLS cert for clients to connect securely."
                  onChange={(e) => setHostname(e.target.value)}
                />
                <Select
                  id={`mail-dmarc-${domain.id}`}
                  labelText="DMARC policy"
                  helperText="How receivers treat mail that fails SPF/DKIM."
                  value={dmarc}
                  onChange={(e) =>
                    setDmarc(e.target.value as MailDomain["dmarcPolicy"])
                  }
                >
                  <SelectItem value="none" text="none — monitor only" />
                  <SelectItem
                    value="quarantine"
                    text="quarantine — send failures to spam"
                  />
                  <SelectItem value="reject" text="reject — block failures" />
                </Select>
              </div>
              {settingsDirty && (
                <div style={{ display: "flex", justifyContent: "flex-end" }}>
                  {savingSettings ? (
                    <InlineLoading status="active" description="Saving…" />
                  ) : (
                    <Button
                      size="sm"
                      renderIcon={Checkmark}
                      onClick={handleSaveSettings}
                    >
                      Save settings
                    </Button>
                  )}
                </div>
              )}
            </Stack>

            {/* ── DNS records ────────────────────────────────────────────── */}
            <DnsPanel domain={domain} />

            {/* ── Mailboxes ──────────────────────────────────────────────── */}
            <Stack gap={5}>
              <div className="gisila-sm__bar">
                <p className="gisila-sm__title">Mailboxes</p>
                <Button
                  kind="tertiary"
                  size="sm"
                  renderIcon={Add}
                  onClick={() => setShowAdd(true)}
                >
                  New mailbox
                </Button>
              </div>

              {isLoading ? (
                <DataTableSkeleton
                  columnCount={3}
                  rowCount={3}
                  showHeader={false}
                  showToolbar={false}
                />
              ) : accounts.length === 0 ? (
                <p className="gisila-sm__note">
                  No mailboxes yet for this domain.
                </p>
              ) : (
                <Table size="sm">
                  <TableHead>
                    <TableRow>
                      <TableHeader>Mailbox</TableHeader>
                      <TableHeader>Quota</TableHeader>
                      <TableHeader aria-label="Actions" />
                    </TableRow>
                  </TableHead>
                  <TableBody>
                    {accounts.map((acc) => (
                      <TableRow key={acc.id}>
                        <TableCell>
                          <span className="gisila-sm__title-row">
                            <At size={16} />
                            <span className="gisila-sm__code">
                              {acc.address}
                            </span>
                            {!acc.isActive && (
                              <Tag size="sm" type="gray">
                                Disabled
                              </Tag>
                            )}
                          </span>
                        </TableCell>
                        <TableCell>
                          {acc.quotaMb ? `${acc.quotaMb} MB quota` : "Unlimited"}
                        </TableCell>
                        <TableCell>
                          <div
                            className="gisila-sm__actions"
                            style={{ justifyContent: "flex-end" }}
                          >
                            <Button
                              kind="ghost"
                              size="sm"
                              hasIconOnly
                              renderIcon={BareMetalServer}
                              iconDescription="Connection settings (SMTP / IMAP / POP3)"
                              onClick={() => setConnAccount(acc)}
                            />
                            <Button
                              kind="ghost"
                              size="sm"
                              hasIconOnly
                              renderIcon={Password}
                              iconDescription="Reset password"
                              onClick={() => {
                                setPwAccount(acc);
                                setNewPw("");
                                setError("");
                              }}
                            />
                            <Button
                              kind="danger--ghost"
                              size="sm"
                              hasIconOnly
                              renderIcon={TrashCan}
                              iconDescription="Delete mailbox"
                              onClick={() => handleDeleteAccount(acc)}
                            />
                          </div>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </Stack>
          </Stack>
        </div>
      )}

      {/* New mailbox dialog */}
      <Modal
        open={showAdd}
        onRequestClose={() => setShowAdd(false)}
        modalHeading="New mailbox"
        primaryButtonText="Create"
        primaryButtonDisabled={busy || !localPart.trim() || password.length < 6}
        secondaryButtonText="Cancel"
        loadingStatus={busy ? "active" : "inactive"}
        loadingDescription="Creating mailbox…"
        onRequestSubmit={handleAddAccount}
        size="sm"
      >
        <Stack gap={5}>
          <div
            style={{ display: "flex", alignItems: "flex-end", gap: "0.5rem" }}
          >
            <div style={{ flex: 1, minWidth: 0 }}>
              <TextInput
                id={`mailbox-local-part-${domain.id}`}
                labelText="Address"
                placeholder="info"
                value={localPart}
                onChange={(e) => setLocalPart(e.target.value)}
              />
            </div>
            <span
              className="gisila-sm__note"
              style={{ whiteSpace: "nowrap", paddingBlockEnd: "0.5rem" }}
            >
              @{domain.domain}
            </span>
          </div>
          <PasswordInput
            id={`mailbox-password-${domain.id}`}
            labelText="Password"
            placeholder="At least 6 characters"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />
          <NumberInput
            id={`mailbox-quota-${domain.id}`}
            label="Quota (MB)"
            placeholder="Leave empty for unlimited"
            allowEmpty
            hideSteppers
            value={quota}
            onChange={(_, { value }) => setQuota(String(value))}
          />
          {error && (
            <InlineNotification
              kind="error"
              lowContrast
              hideCloseButton
              title={error}
            />
          )}
        </Stack>
      </Modal>

      {/* Reset password dialog */}
      <Modal
        open={!!pwAccount}
        onRequestClose={() => setPwAccount(null)}
        modalHeading="Reset password"
        primaryButtonText="Save"
        primaryButtonDisabled={busy || newPw.length < 6}
        secondaryButtonText="Cancel"
        loadingStatus={busy ? "active" : "inactive"}
        loadingDescription="Saving password…"
        onRequestSubmit={handleSetPassword}
        size="sm"
      >
        <Stack gap={5}>
          <p className="gisila-sm__note">
            Set a new password for{" "}
            <span className="gisila-sm__code">{pwAccount?.address}</span>.
          </p>
          <PasswordInput
            id={`mailbox-new-password-${domain.id}`}
            labelText="New password"
            placeholder="At least 6 characters"
            value={newPw}
            onChange={(e) => setNewPw(e.target.value)}
          />
          {error && (
            <InlineNotification
              kind="error"
              lowContrast
              hideCloseButton
              title={error}
            />
          )}
        </Stack>
      </Modal>

      {/* Connection settings dialog */}
      <ConnectionDialog
        account={connAccount}
        onClose={() => setConnAccount(null)}
      />
    </Tile>
  );
}

// ── DNS records panel ─────────────────────────────────────────────────────────

function DnsPanel({ domain }: { domain: MailDomain }) {
  const dnsKey = `/mail/domains/${domain.id}/dns`;

  // Poll every 5 s while DKIM is not yet configured; back off to 30 s once ready.
  const { data, isLoading } = useSWR<MailDnsResponse>(dnsKey, fetcher, {
    refreshInterval: domain.dkimConfigured ? 30_000 : 5_000,
    revalidateOnFocus: true,
  });

  const dkimReady = data?.dkimConfigured ?? domain.dkimConfigured;
  const records = data?.records ?? [];

  const [syncing, setSyncing] = useState(false);

  async function handleSync() {
    setSyncing(true);
    try {
      await api(`/mail/domains/${domain.id}/sync`, { method: "POST" });
      // Optimistically start polling; the badge will update once the worker responds.
      mutate(dnsKey);
      mutate("/mail/domains");
    } catch {
      // ignore — worker will retry
    } finally {
      setSyncing(false);
    }
  }

  return (
    <Stack gap={5}>
      <div className="gisila-sm__bar">
        <p className="gisila-sm__title gisila-sm__title-row">
          <Security size={16} />
          DNS records
        </p>
        <div className="gisila-sm__actions">
          {dkimReady ? (
            <Tag size="sm" type="green" renderIcon={Checkmark}>
              DKIM configured
            </Tag>
          ) : (
            <InlineLoading status="active" description="Waiting for DKIM key…" />
          )}
          {syncing ? (
            <InlineLoading status="active" description="Syncing…" />
          ) : (
            <Button
              kind="ghost"
              size="sm"
              hasIconOnly
              renderIcon={Renew}
              iconDescription="Trigger sync now"
              onClick={handleSync}
            />
          )}
        </div>
      </div>

      {!dkimReady && (
        <InlineNotification
          kind="warning"
          lowContrast
          hideCloseButton
          title=""
          subtitle="The DKIM signing key is generated on the first sync after the agent provisions OpenDKIM. Click the refresh icon to trigger one now, or wait — this panel polls automatically every 5 s."
        />
      )}

      <p className="gisila-sm__note">
        Publish these records at your DNS provider so mail delivers and passes
        SPF, DKIM, and DMARC. Also set reverse DNS (PTR) for the server IP.
      </p>

      {isLoading && records.length === 0 ? (
        <DataTableSkeleton
          columnCount={3}
          rowCount={4}
          showHeader={false}
          showToolbar={false}
        />
      ) : (
        <Table size="sm">
          <TableHead>
            <TableRow>
              <TableHeader>Type</TableHeader>
              <TableHeader>Host</TableHeader>
              <TableHeader>Value</TableHeader>
            </TableRow>
          </TableHead>
          <TableBody>
            {records.map((r, i) => {
              // Values the backend could not resolve yet come back as a
              // "<placeholder>" hint rather than something copyable.
              const isPlaceholder = r.value.startsWith("<");
              return (
                <TableRow key={i}>
                  <TableCell>
                    <div className="gisila-sm__title-row">
                      <Tag size="sm" type="outline">
                        {r.label ?? r.type}
                      </Tag>
                      {typeof r.priority === "number" && (
                        <span className="gisila-sm__note">
                          pri {r.priority}
                        </span>
                      )}
                    </div>
                  </TableCell>
                  <TableCell>
                    <code className="gisila-sm__meta">{r.host}</code>
                  </TableCell>
                  <TableCell>
                    <Stack gap={2}>
                      <CodeSnippet
                        type="multi"
                        wrapText
                        // No collapse threshold and a one-row floor: the
                        // snippet grows to the full record, so a ~400-character
                        // DKIM key is never truncated behind a "show more".
                        maxCollapsedNumberOfRows={0}
                        minCollapsedNumberOfRows={1}
                        // Copy the record straight from the API payload rather
                        // than from the rendered text.
                        copyText={r.value}
                        hideCopyButton={isPlaceholder}
                        className={
                          isPlaceholder
                            ? "gisila-dns__value gisila-dns__value--placeholder"
                            : "gisila-dns__value"
                        }
                        feedback="Copied"
                        aria-label={`${r.label ?? r.type} record value`}
                      >
                        {r.value}
                      </CodeSnippet>
                      {r.note && <p className="gisila-sm__note">{r.note}</p>}
                    </Stack>
                  </TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      )}
    </Stack>
  );
}

// ── Connection settings dialog ────────────────────────────────────────────────

function ConnectionRow({
  label,
  host,
  port,
  security,
}: {
  label: string;
  host: string;
  port: number;
  security: string;
}) {
  const summary = `${host}:${port} (${security})`;
  return (
    <StructuredListRow>
      <StructuredListCell noWrap>{label}</StructuredListCell>
      <StructuredListCell>
        {/* The row shows the security mode too, but only host:port is worth
            pasting into a mail client, so that is what the copy button takes. */}
        <CodeSnippet
          type="single"
          copyText={`${host}:${port}`}
          feedback="Copied"
          aria-label={`Copy ${label} host and port`}
        >
          {summary}
        </CodeSnippet>
      </StructuredListCell>
    </StructuredListRow>
  );
}

function ConnectionDialog({
  account,
  onClose,
}: {
  account: MailAccount | null;
  onClose: () => void;
}) {
  const c: MailConnectionSettings | undefined = account?.connection;
  return (
    <Modal
      open={!!account}
      onRequestClose={onClose}
      modalHeading="Connection settings"
      primaryButtonText="Close"
      onRequestSubmit={onClose}
      size="md"
    >
      {c && account && (
        <Stack gap={6}>
          <Stack gap={3}>
            <div className="gisila-sm__kv-row">
              <span className="gisila-sm__kv-key">Username</span>
              <CodeSnippet
                type="single"
                copyText={account.address}
                feedback="Copied"
                aria-label="Copy username"
              >
                {account.address}
              </CodeSnippet>
            </div>
            <p className="gisila-sm__note">
              Password is the mailbox password you set. Use STARTTLS or SSL/TLS
              depending on your client; both ports are open.
            </p>
          </Stack>

          <Stack gap={3}>
            <p className="gisila-sm__label">Outgoing (SMTP)</p>
            <StructuredListWrapper aria-label="Outgoing (SMTP)" isCondensed>
              <StructuredListBody>
                <ConnectionRow
                  label="STARTTLS"
                  host={c.smtp.host}
                  port={c.smtp.starttls.port}
                  security={c.smtp.starttls.security}
                />
                <ConnectionRow
                  label="SSL/TLS"
                  host={c.smtp.host}
                  port={c.smtp.ssl.port}
                  security={c.smtp.ssl.security}
                />
              </StructuredListBody>
            </StructuredListWrapper>
          </Stack>

          <Stack gap={3}>
            <p className="gisila-sm__label">Incoming (IMAP)</p>
            <StructuredListWrapper aria-label="Incoming (IMAP)" isCondensed>
              <StructuredListBody>
                <ConnectionRow
                  label="SSL/TLS"
                  host={c.imap.host}
                  port={c.imap.ssl.port}
                  security={c.imap.ssl.security}
                />
                <ConnectionRow
                  label="STARTTLS"
                  host={c.imap.host}
                  port={c.imap.starttls.port}
                  security={c.imap.starttls.security}
                />
              </StructuredListBody>
            </StructuredListWrapper>
          </Stack>

          <Stack gap={3}>
            <p className="gisila-sm__label">Incoming (POP3)</p>
            <StructuredListWrapper aria-label="Incoming (POP3)" isCondensed>
              <StructuredListBody>
                <ConnectionRow
                  label="SSL/TLS"
                  host={c.pop3.host}
                  port={c.pop3.ssl.port}
                  security={c.pop3.ssl.security}
                />
                <ConnectionRow
                  label="STARTTLS"
                  host={c.pop3.host}
                  port={c.pop3.starttls.port}
                  security={c.pop3.starttls.security}
                />
              </StructuredListBody>
            </StructuredListWrapper>
          </Stack>
        </Stack>
      )}
    </Modal>
  );
}
