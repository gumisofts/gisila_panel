"use client";

import { useState } from "react";
import useSWR from "swr";
import { toast } from "sonner";
import { Plus, Trash2 } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { api, fetcher } from "@/lib/api";
import { formatRelative } from "@/lib/utils";
import type { ListResponse, SshKey, User } from "@/lib/types";

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
    <div className="container space-y-6 py-8">
      <header>
        <h1 className="text-2xl font-semibold tracking-tight">Settings</h1>
        <p className="text-sm text-muted-foreground">Profile, security and SSH keys.</p>
      </header>

      <Card>
        <CardHeader><CardTitle>Profile</CardTitle></CardHeader>
        <CardContent className="space-y-2 text-sm">
          <p>
            <span className="text-muted-foreground">Email:</span>{" "}
            <span className="font-medium">{me.data?.email}</span>
          </p>
          <p>
            <span className="text-muted-foreground">Member since:</span>{" "}
            {me.data ? formatRelative(me.data.createdAt) : "—"}
          </p>
        </CardContent>
      </Card>

      <Card>
        <CardHeader><CardTitle>SSH keys</CardTitle></CardHeader>
        <CardContent className="space-y-4">
          <form onSubmit={addKey} className="space-y-3">
            <div className="space-y-1.5">
              <label className="text-xs font-medium text-muted-foreground">
                Name
              </label>
              <Input
                value={keyName}
                onChange={(e) => setKeyName(e.target.value)}
                placeholder="My laptop"
                required
              />
            </div>
            <div className="space-y-1.5">
              <label className="text-xs font-medium text-muted-foreground">
                Public key
              </label>
              <Textarea
                value={publicKey}
                onChange={(e) => setPublicKey(e.target.value)}
                rows={4}
                placeholder="ssh-ed25519 AAAA…"
                required
              />
            </div>
            <Button type="submit" disabled={busy}>
              <Plus className="h-4 w-4" /> Add key
            </Button>
          </form>

          <div className="space-y-2">
            {keys.data?.results.length ? (
              keys.data.results.map((k) => (
                <div
                  key={k.id}
                  className="flex items-center justify-between rounded-md border border-border/60 px-3 py-2 text-sm"
                >
                  <div>
                    <p className="font-medium">{k.name}</p>
                    <p className="font-mono text-xs text-muted-foreground">
                      {k.fingerprint}
                    </p>
                  </div>
                  <Button
                    size="icon"
                    variant="ghost"
                    onClick={() => removeKey(k.id)}
                  >
                    <Trash2 className="h-4 w-4 text-destructive" />
                  </Button>
                </div>
              ))
            ) : (
              <p className="text-xs text-muted-foreground">
                No SSH keys uploaded.
              </p>
            )}
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
