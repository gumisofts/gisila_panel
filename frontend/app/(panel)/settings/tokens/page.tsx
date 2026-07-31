"use client";

import { useState } from "react";
import useSWR from "swr";
import { toast } from "@/lib/toast";
import { Plus, Trash2, Copy } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { api, fetcher } from "@/lib/api";
import { formatRelative } from "@/lib/utils";
import type { ApiToken, ListResponse } from "@/lib/types";

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
    <div className="container space-y-6 py-8">
      <header>
        <h1 className="text-2xl font-semibold tracking-tight">API tokens</h1>
        <p className="text-sm text-muted-foreground">
          Use these for the CLI, CI, or any programmatic access.
        </p>
      </header>

      {issued && (
        <Card className="border-primary/50">
          <CardContent className="space-y-2 p-5">
            <p className="text-sm font-medium">
              Token issued — copy it now. It won&rsquo;t be shown again.
            </p>
            <div className="flex items-center gap-2 rounded-md border border-border bg-black/40 p-2 font-mono text-sm">
              <code className="flex-1 truncate">{issued}</code>
              <Button
                size="icon"
                variant="ghost"
                onClick={() => {
                  navigator.clipboard.writeText(issued);
                  toast.success("Copied");
                }}
              >
                <Copy className="h-4 w-4" />
              </Button>
            </div>
            <Button
              variant="ghost"
              size="sm"
              onClick={() => setIssued(null)}
            >
              Dismiss
            </Button>
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader>
          <CardTitle>Issue a new token</CardTitle>
        </CardHeader>
        <CardContent>
          <form onSubmit={create} className="flex flex-wrap items-end gap-3">
            <div className="flex-1 space-y-1.5">
              <label className="text-xs font-medium text-muted-foreground">
                Name
              </label>
              <Input
                required
                placeholder="ci/cd"
                value={name}
                onChange={(e) => setName(e.target.value)}
              />
            </div>
            <div className="w-36 space-y-1.5">
              <label className="text-xs font-medium text-muted-foreground">
                Expires (days)
              </label>
              <Input
                type="number"
                min={1}
                value={days}
                onChange={(e) =>
                  setDays(e.target.value === "" ? "" : Number(e.target.value))
                }
                placeholder="never"
              />
            </div>
            <Button type="submit" disabled={busy}>
              <Plus className="h-4 w-4" /> Issue
            </Button>
          </form>
        </CardContent>
      </Card>

      <div className="space-y-2">
        {data?.results.length ? (
          data.results.map((t) => (
            <div
              key={t.id}
              className="flex items-center justify-between rounded-xl border border-border/60 bg-card/60 px-5 py-3 text-sm"
            >
              <div>
                <p className="font-medium">{t.name}</p>
                <p className="text-xs text-muted-foreground">
                  prefix <span className="font-mono">{t.prefix}</span> · last
                  used {formatRelative(t.lastUsedAt)}
                </p>
              </div>
              <div className="flex items-center gap-2">
                {t.expiresAt && (
                  <Badge variant="muted">
                    expires {formatRelative(t.expiresAt)}
                  </Badge>
                )}
                <Button
                  variant="ghost"
                  size="icon"
                  onClick={() => revoke(t.id)}
                >
                  <Trash2 className="h-4 w-4 text-destructive" />
                </Button>
              </div>
            </div>
          ))
        ) : (
          <Card>
            <CardContent className="py-10 text-center text-sm text-muted-foreground">
              No tokens yet.
            </CardContent>
          </Card>
        )}
      </div>
    </div>
  );
}
