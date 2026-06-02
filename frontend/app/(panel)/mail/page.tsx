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
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { api, fetcher } from "@/lib/api";
import type { ListResponse, MailDomain, MailAccount } from "@/lib/types";

export default function MailPage() {
  const { data, isLoading } = useSWR<ListResponse<MailDomain>>(
    "/mail/domains",
    fetcher,
    { refreshInterval: 15000 }
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

  function reloadAccounts() {
    mutate(`/mail/domains/${domain.id}/accounts`);
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
          <div className="border-t py-4 space-y-3">
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
    </Card>
  );
}
