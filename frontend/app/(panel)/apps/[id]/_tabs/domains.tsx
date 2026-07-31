"use client";

import { useState } from "react";
import useSWR from "swr";
import { toast } from "@/lib/toast";
import { Globe, Plus, Trash2, ShieldCheck } from "lucide-react";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { api, fetcher } from "@/lib/api";
import { formatRelative } from "@/lib/utils";
import type { Domain, ListResponse } from "@/lib/types";

export function DomainsTab({ appId }: { appId: number }) {
  const { data, mutate } = useSWR<ListResponse<Domain>>(
    `/apps/${appId}/domains/`,
    fetcher,
    { refreshInterval: 5000 },
  );
  const [hostname, setHostname] = useState("");
  const [busy, setBusy] = useState(false);

  async function add(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    try {
      await api(`/apps/${appId}/domains/`, {
        method: "POST",
        body: JSON.stringify({ hostname }),
      });
      setHostname("");
      mutate();
      toast.success("Domain attached");
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed");
    } finally {
      setBusy(false);
    }
  }

  async function issue(id: number) {
    try {
      await api(`/apps/${appId}/domains/${id}/ssl`, { method: "POST" });
      toast.success("Certificate issuance queued");
      mutate();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed");
    }
  }

  async function remove(id: number) {
    if (!confirm("Remove this domain?")) return;
    await api(`/apps/${appId}/domains/${id}`, { method: "DELETE" });
    mutate();
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardContent className="p-5">
          <form onSubmit={add} className="flex flex-wrap items-end gap-3">
            <div className="flex-1 space-y-1.5">
              <label className="text-xs font-medium text-muted-foreground">
                Custom domain
              </label>
              <Input
                value={hostname}
                onChange={(e) => setHostname(e.target.value)}
                placeholder="api.example.com"
                required
              />
            </div>
            <Button type="submit" disabled={busy}>
              <Plus className="h-4 w-4" /> Attach
            </Button>
          </form>
        </CardContent>
      </Card>

      <div className="space-y-2">
        {data?.results.length ? (
          data.results.map((d) => (
            <div
              key={d.id}
              className="flex items-center justify-between rounded-xl border border-border/60 bg-card/60 px-5 py-3 text-sm"
            >
              <div className="flex items-center gap-3">
                <Globe className="h-4 w-4 text-muted-foreground" />
                <div>
                  <p className="font-medium">{d.hostname}</p>
                  <p className="text-xs text-muted-foreground">
                    SSL: {d.sslStatus}
                    {d.sslExpiresAt
                      ? ` · expires ${formatRelative(d.sslExpiresAt)}`
                      : ""}
                  </p>
                </div>
              </div>
              <div className="flex items-center gap-2">
                {d.sslStatus === "issued" ? (
                  <Badge variant="success">https</Badge>
                ) : (
                  <Button size="sm" variant="outline" onClick={() => issue(d.id)}>
                    <ShieldCheck className="h-4 w-4" /> Issue cert
                  </Button>
                )}
                <Button
                  size="icon"
                  variant="ghost"
                  onClick={() => remove(d.id)}
                >
                  <Trash2 className="h-4 w-4 text-destructive" />
                </Button>
              </div>
            </div>
          ))
        ) : (
          <Card>
            <CardContent className="py-10 text-center text-sm text-muted-foreground">
              No domains attached yet.
            </CardContent>
          </Card>
        )}
      </div>
    </div>
  );
}
