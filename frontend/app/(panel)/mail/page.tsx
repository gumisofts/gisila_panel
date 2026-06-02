"use client";

import { useState } from "react";
import useSWR, { mutate } from "swr";
import {
  Mail,
  Plus,
  Globe,
  Trash2,
  Loader,
  AtSign,
  KeyRound,
  ChevronDown,
  ChevronRight,
  ShieldCheck,
  Server,
  Copy,
  Check,
  Settings2,
  RefreshCw,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { api, fetcher } from "@/lib/api";
import type {
  ListResponse,
  MailDomain,
  MailAccount,
  MailDnsResponse,
  MailConnectionSettings,
} from "@/lib/types";

// ── Copy-to-clipboard button ─────────────────────────────────────────────────

function CopyButton({ value, className }: { value: string; className?: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <button
      type="button"
      className={
        "shrink-0 text-muted-foreground transition-colors hover:text-foreground " +
        (className ?? "")
      }
      title="Copy"
      onClick={async () => {
        try {
          await navigator.clipboard.writeText(value);
          setCopied(true);
          setTimeout(() => setCopied(false), 1500);
        } catch {
          /* clipboard unavailable */
        }
      }}
    >
      {copied ? (
        <Check className="h-3.5 w-3.5 text-emerald-500" />
      ) : (
        <Copy className="h-3.5 w-3.5" />
      )}
    </button>
  );
}

export default function MailPage() {
  const { data, isLoading } = useSWR<ListResponse<MailDomain>>(
    "/mail/domains",
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
    <div className="mx-auto max-w-4xl space-y-6 p-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold">Mail</h1>
          <p className="mt-0.5 text-sm text-muted-foreground">
            Host email for your domains. Each domain can have multiple mailboxes
            (Postfix&nbsp;+&nbsp;Dovecot).
          </p>
        </div>
        <Button size="sm" onClick={() => setShowAdd(true)}>
          <Plus className="mr-1.5 h-3.5 w-3.5" />
          Add domain
        </Button>
      </div>

      {isLoading ? (
        <p className="text-sm text-muted-foreground">Loading…</p>
      ) : domains.length === 0 ? (
        <Card>
          <CardContent className="flex flex-col items-center gap-3 py-16 text-center">
            <Mail className="h-10 w-10 text-muted-foreground/40" />
            <div>
              <p className="font-medium">No mail domains yet</p>
              <p className="mt-1 text-sm text-muted-foreground">
                Add a domain to start hosting mailboxes. Point its MX record at
                this server once configured.
              </p>
            </div>
            <Button size="sm" onClick={() => setShowAdd(true)}>
              <Plus className="mr-1.5 h-3.5 w-3.5" />
              Add domain
            </Button>
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-3">
          {domains.map((d) => (
            <DomainCard key={d.id} domain={d} />
          ))}
        </div>
      )}

      <Dialog open={showAdd} onOpenChange={setShowAdd}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Add mail domain</DialogTitle>
          </DialogHeader>
          <div className="space-y-4 py-2">
            <div className="space-y-1.5">
              <Label>Domain</Label>
              <Input
                placeholder="example.com"
                value={domain}
                onChange={(e) => setDomain(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && handleAddDomain()}
              />
              <p className="text-xs text-muted-foreground">
                Set an MX record pointing at this host and a matching A record so
                mail can be delivered.
              </p>
            </div>
            {error && <p className="text-sm text-destructive">{error}</p>}
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowAdd(false)}>
              Cancel
            </Button>
            <Button onClick={handleAddDomain} disabled={busy || !domain.trim()}>
              {busy ? (
                <Loader className="mr-1.5 h-3.5 w-3.5 animate-spin" />
              ) : (
                <Plus className="mr-1.5 h-3.5 w-3.5" />
              )}
              Add
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
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
    <Card>
      <CardContent className="py-0">
        <div className="flex items-center gap-4 py-4">
          <button
            className="flex flex-1 items-center gap-4 text-left min-w-0"
            onClick={() => setOpen((o) => !o)}
          >
            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-indigo-500/10">
              <Globe className="h-5 w-5 text-indigo-500" />
            </div>
            <div className="flex-1 min-w-0">
              <span className="font-medium truncate">{domain.domain}</span>
              <p className="text-sm text-muted-foreground">
                {open
                  ? `${accounts.length} mailbox${accounts.length === 1 ? "" : "es"}`
                  : "Click to manage mailboxes"}
              </p>
            </div>
            {open ? (
              <ChevronDown className="h-4 w-4 text-muted-foreground" />
            ) : (
              <ChevronRight className="h-4 w-4 text-muted-foreground" />
            )}
          </button>
          <Button
            variant="ghost"
            size="icon"
            className="text-muted-foreground hover:text-destructive"
            onClick={handleRemoveDomain}
            disabled={removing}
          >
            {removing ? (
              <Loader className="h-4 w-4 animate-spin" />
            ) : (
              <Trash2 className="h-4 w-4" />
            )}
          </Button>
        </div>

        {open && (
          <div className="border-t py-4 space-y-6">
            {/* ── Settings: hostname + DMARC ─────────────────────────────── */}
            <div className="space-y-3">
              <p className="flex items-center gap-1.5 text-sm font-medium">
                <Settings2 className="h-3.5 w-3.5 text-muted-foreground" />
                Settings
              </p>
              <div className="grid gap-3 sm:grid-cols-2">
                <div className="space-y-1.5">
                  <Label className="text-xs">Mail hostname</Label>
                  <Input
                    value={hostname}
                    placeholder={`mail.${domain.domain}`}
                    onChange={(e) => setHostname(e.target.value)}
                  />
                  <p className="text-[11px] text-muted-foreground">
                    The host MX / A records point at. Needs a real or self-signed
                    TLS cert for clients to connect securely.
                  </p>
                </div>
                <div className="space-y-1.5">
                  <Label className="text-xs">DMARC policy</Label>
                  <Select
                    value={dmarc}
                    onValueChange={(v) =>
                      setDmarc(v as MailDomain["dmarcPolicy"])
                    }
                  >
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="none">none — monitor only</SelectItem>
                      <SelectItem value="quarantine">
                        quarantine — send failures to spam
                      </SelectItem>
                      <SelectItem value="reject">
                        reject — block failures
                      </SelectItem>
                    </SelectContent>
                  </Select>
                  <p className="text-[11px] text-muted-foreground">
                    How receivers treat mail that fails SPF/DKIM.
                  </p>
                </div>
              </div>
              {settingsDirty && (
                <div className="flex justify-end">
                  <Button
                    size="sm"
                    onClick={handleSaveSettings}
                    disabled={savingSettings}
                  >
                    {savingSettings ? (
                      <Loader className="mr-1.5 h-3.5 w-3.5 animate-spin" />
                    ) : (
                      <Check className="mr-1.5 h-3.5 w-3.5" />
                    )}
                    Save settings
                  </Button>
                </div>
              )}
            </div>

            {/* ── DNS records ────────────────────────────────────────────── */}
            <DnsPanel domain={domain} />

            {/* ── Mailboxes ──────────────────────────────────────────────── */}
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <p className="text-sm font-medium">Mailboxes</p>
                <Button size="sm" variant="outline" onClick={() => setShowAdd(true)}>
                  <Plus className="mr-1.5 h-3.5 w-3.5" />
                  New mailbox
                </Button>
              </div>

            {isLoading ? (
              <p className="text-sm text-muted-foreground">Loading…</p>
            ) : accounts.length === 0 ? (
              <p className="text-sm text-muted-foreground">
                No mailboxes yet for this domain.
              </p>
            ) : (
              <div className="space-y-2">
                {accounts.map((acc) => (
                  <div
                    key={acc.id}
                    className="flex items-center gap-3 rounded-md border px-3 py-2"
                  >
                    <AtSign className="h-4 w-4 text-muted-foreground shrink-0" />
                    <div className="flex-1 min-w-0">
                      <span className="text-sm font-medium truncate">
                        {acc.address}
                      </span>
                      <p className="text-xs text-muted-foreground">
                        {acc.quotaMb ? `${acc.quotaMb} MB quota` : "Unlimited"}
                      </p>
                    </div>
                    {!acc.isActive && (
                      <Badge variant="secondary" className="text-xs">
                        Disabled
                      </Badge>
                    )}
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-8 w-8 text-muted-foreground"
                      title="Connection settings (SMTP / IMAP / POP3)"
                      onClick={() => setConnAccount(acc)}
                    >
                      <Server className="h-4 w-4" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-8 w-8 text-muted-foreground"
                      title="Reset password"
                      onClick={() => {
                        setPwAccount(acc);
                        setNewPw("");
                        setError("");
                      }}
                    >
                      <KeyRound className="h-4 w-4" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon"
                      className="h-8 w-8 text-muted-foreground hover:text-destructive"
                      title="Delete mailbox"
                      onClick={() => handleDeleteAccount(acc)}
                    >
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  </div>
                ))}
              </div>
            )}
            </div>
          </div>
        )}
      </CardContent>

      {/* New mailbox dialog */}
      <Dialog open={showAdd} onOpenChange={setShowAdd}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>New mailbox</DialogTitle>
          </DialogHeader>
          <div className="space-y-4 py-2">
            <div className="space-y-1.5">
              <Label>Address</Label>
              <div className="flex items-center gap-2">
                <Input
                  placeholder="info"
                  value={localPart}
                  onChange={(e) => setLocalPart(e.target.value)}
                />
                <span className="text-sm text-muted-foreground whitespace-nowrap">
                  @{domain.domain}
                </span>
              </div>
            </div>
            <div className="space-y-1.5">
              <Label>Password</Label>
              <Input
                type="password"
                placeholder="At least 6 characters"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
              />
            </div>
            <div className="space-y-1.5">
              <Label>Quota (MB)</Label>
              <Input
                type="number"
                placeholder="Leave empty for unlimited"
                value={quota}
                onChange={(e) => setQuota(e.target.value)}
              />
            </div>
            {error && <p className="text-sm text-destructive">{error}</p>}
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowAdd(false)}>
              Cancel
            </Button>
            <Button
              onClick={handleAddAccount}
              disabled={busy || !localPart.trim() || password.length < 6}
            >
              {busy ? (
                <Loader className="mr-1.5 h-3.5 w-3.5 animate-spin" />
              ) : (
                <Plus className="mr-1.5 h-3.5 w-3.5" />
              )}
              Create
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Reset password dialog */}
      <Dialog open={!!pwAccount} onOpenChange={(o) => !o && setPwAccount(null)}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Reset password</DialogTitle>
          </DialogHeader>
          <div className="space-y-4 py-2">
            <p className="text-sm text-muted-foreground">
              Set a new password for{" "}
              <span className="font-medium text-foreground">
                {pwAccount?.address}
              </span>
              .
            </p>
            <div className="space-y-1.5">
              <Label>New password</Label>
              <Input
                type="password"
                placeholder="At least 6 characters"
                value={newPw}
                onChange={(e) => setNewPw(e.target.value)}
              />
            </div>
            {error && <p className="text-sm text-destructive">{error}</p>}
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setPwAccount(null)}>
              Cancel
            </Button>
            <Button onClick={handleSetPassword} disabled={busy || newPw.length < 6}>
              {busy ? (
                <Loader className="mr-1.5 h-3.5 w-3.5 animate-spin" />
              ) : (
                <KeyRound className="mr-1.5 h-3.5 w-3.5" />
              )}
              Save
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Connection settings dialog */}
      <ConnectionDialog
        account={connAccount}
        onClose={() => setConnAccount(null)}
      />
    </Card>
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
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <p className="flex items-center gap-1.5 text-sm font-medium">
          <ShieldCheck className="h-3.5 w-3.5 text-muted-foreground" />
          DNS records
        </p>
        <div className="flex items-center gap-2">
          {dkimReady ? (
            <Badge variant="secondary" className="text-[10px] text-emerald-600">
              <Check className="mr-1 h-3 w-3" />
              DKIM configured
            </Badge>
          ) : (
            <Badge variant="secondary" className="text-[10px]">
              <Loader className="mr-1 h-3 w-3 animate-spin" />
              Waiting for DKIM key…
            </Badge>
          )}
          <button
            type="button"
            title="Trigger sync now"
            className="text-muted-foreground hover:text-foreground transition-colors"
            onClick={handleSync}
            disabled={syncing}
          >
            <RefreshCw
              className={"h-3.5 w-3.5" + (syncing ? " animate-spin" : "")}
            />
          </button>
        </div>
      </div>

      {!dkimReady && (
        <div className="rounded-md border border-amber-500/30 bg-amber-500/5 px-3 py-2 text-[11px] text-amber-700 dark:text-amber-400">
          The DKIM signing key is generated on the first sync after the agent
          provisions OpenDKIM. Click the refresh icon to trigger one now, or
          wait — this panel polls automatically every 5 s.
        </div>
      )}

      <p className="text-[11px] text-muted-foreground">
        Publish these records at your DNS provider so mail delivers and passes
        SPF, DKIM, and DMARC. Also set reverse DNS (PTR) for the server IP.
      </p>

      {isLoading && records.length === 0 ? (
        <p className="text-sm text-muted-foreground">Loading…</p>
      ) : (
        <div className="space-y-2">
          {records.map((r, i) => (
            <div key={i} className="rounded-md border bg-muted/30 px-3 py-2">
              <div className="flex items-center gap-2">
                <Badge
                  variant="outline"
                  className="font-mono text-[10px] uppercase shrink-0"
                >
                  {r.label ?? r.type}
                </Badge>
                <code className="text-xs text-muted-foreground truncate">
                  {r.host}
                </code>
                {typeof r.priority === "number" && (
                  <span className="text-[10px] text-muted-foreground shrink-0">
                    pri {r.priority}
                  </span>
                )}
              </div>
              <div className="mt-1.5 flex items-start gap-2">
                <code
                  className={
                    "flex-1 break-all text-xs font-mono" +
                    (r.value.startsWith("<") ? " text-muted-foreground italic" : "")
                  }
                >
                  {r.value}
                </code>
                {!r.value.startsWith("<") && (
                  <CopyButton value={r.value} className="mt-0.5" />
                )}
              </div>
              {r.note && (
                <p className="mt-1 text-[11px] text-muted-foreground">{r.note}</p>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
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
    <div className="flex items-center gap-2 rounded-md border px-3 py-2">
      <span className="w-28 shrink-0 text-xs font-medium">{label}</span>
      <code className="flex-1 truncate text-xs font-mono text-muted-foreground">
        {summary}
      </code>
      <CopyButton value={`${host}:${port}`} />
    </div>
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
    <Dialog open={!!account} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Connection settings</DialogTitle>
        </DialogHeader>
        {c && account && (
          <div className="space-y-4 py-2">
            <div className="rounded-md bg-muted/50 px-3 py-2 text-sm">
              <div className="flex items-center justify-between gap-2">
                <span className="text-muted-foreground">Username</span>
                <span className="flex items-center gap-2 font-mono text-xs">
                  {account.address}
                  <CopyButton value={account.address} />
                </span>
              </div>
              <p className="mt-1 text-[11px] text-muted-foreground">
                Password is the mailbox password you set. Use STARTTLS or SSL/TLS
                depending on your client; both ports are open.
              </p>
            </div>

            <div className="space-y-1.5">
              <p className="text-xs font-medium text-muted-foreground uppercase tracking-wider">
                Outgoing (SMTP)
              </p>
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
            </div>

            <div className="space-y-1.5">
              <p className="text-xs font-medium text-muted-foreground uppercase tracking-wider">
                Incoming (IMAP)
              </p>
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
            </div>

            <div className="space-y-1.5">
              <p className="text-xs font-medium text-muted-foreground uppercase tracking-wider">
                Incoming (POP3)
              </p>
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
            </div>
          </div>
        )}
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>
            Close
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
