"use client";

import { useState } from "react";
import useSWR, { mutate } from "swr";
import { toast } from "sonner";
import { HardDrive, Plus, Trash2, Link2, Loader } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { api, fetcher } from "@/lib/api";
import type {
  AppStorageLink,
  ListResponse,
  StorageBucket,
  StorageProvider,
} from "@/lib/types";

export function StorageTab({ appId }: { appId: number }) {
  const linksKey = `/storage/apps/${appId}/links`;
  const { data, isLoading } = useSWR<ListResponse<AppStorageLink>>(linksKey, fetcher);
  const providers = useSWR<ListResponse<StorageProvider>>(
    "/storage/providers",
    fetcher,
  );

  const [open, setOpen] = useState(false);
  const [providerId, setProviderId] = useState<string>("");
  const [bucketId, setBucketId] = useState<string>("");
  const [envPrefix, setEnvPrefix] = useState("S3");
  const [saving, setSaving] = useState(false);

  // Buckets for the chosen provider (only fetched once a provider is picked).
  const buckets = useSWR<ListResponse<StorageBucket>>(
    providerId ? `/storage/providers/${providerId}/buckets` : null,
    fetcher,
  );

  const links = data?.results ?? [];

  async function link() {
    if (!bucketId) {
      toast.error("Pick a bucket to link.");
      return;
    }
    setSaving(true);
    try {
      await api(linksKey, {
        method: "POST",
        body: JSON.stringify({ bucketId: Number(bucketId), envPrefix }),
      });
      toast.success("Bucket linked — credentials injected as env vars.");
      setOpen(false);
      setProviderId("");
      setBucketId("");
      setEnvPrefix("S3");
      mutate(linksKey);
      mutate(`/apps/${appId}/envs`);
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed to link bucket");
    } finally {
      setSaving(false);
    }
  }

  async function unlink(linkId: number) {
    if (!confirm("Unlink this bucket? Its injected env vars will be removed.")) return;
    try {
      await api(`${linksKey}/${linkId}`, { method: "DELETE" });
      toast.success("Bucket unlinked.");
      mutate(linksKey);
      mutate(`/apps/${appId}/envs`);
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed to unlink");
    }
  }

  return (
    <div className="space-y-4 max-w-3xl">
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-sm font-medium">Object storage buckets</h3>
          <p className="text-xs text-muted-foreground">
            Linking a bucket injects its S3 credentials into this app&apos;s
            environment (live on the next deploy).
          </p>
        </div>
        {(
          <Button size="sm" onClick={() => setOpen(true)}>
            <Plus className="mr-1.5 h-4 w-4" /> Link bucket
          </Button>
        )}
      </div>

      {isLoading ? (
        <p className="text-sm text-muted-foreground">Loading…</p>
      ) : links.length === 0 ? (
        <Card>
          <CardContent className="py-10 text-center text-sm text-muted-foreground">
            <HardDrive className="mx-auto mb-3 h-8 w-8 opacity-40" />
            No buckets linked yet.
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-3">
          {links.map((l) => (
            <Card key={l.id}>
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="flex items-center gap-2 text-sm">
                  <Link2 className="h-4 w-4 text-violet-500" />
                  {l.bucketName}
                  <Badge variant="outline" className="ml-1 text-[10px]">
                    {l.providerName}
                  </Badge>
                  <Badge variant="secondary" className="text-[10px]">
                    {l.providerKind}
                  </Badge>
                </CardTitle>
                {(
                  <Button
                    size="icon"
                    variant="ghost"
                    className="h-7 w-7 text-muted-foreground hover:text-red-500"
                    onClick={() => unlink(l.id)}
                  >
                    <Trash2 className="h-4 w-4" />
                  </Button>
                )}
              </CardHeader>
              <CardContent className="pb-3">
                <p className="mb-1.5 text-xs text-muted-foreground">
                  Injected env vars (prefix{" "}
                  <code className="font-mono">{l.envPrefix}</code>):
                </p>
                <div className="flex flex-wrap gap-1">
                  {l.envVars.map((v) => (
                    <code
                      key={v}
                      className="rounded bg-muted px-1.5 py-0.5 font-mono text-[11px]"
                    >
                      {v}
                    </code>
                  ))}
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Link a bucket</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div>
              <Label>Provider</Label>
              <Select
                value={providerId}
                onValueChange={(v) => {
                  setProviderId(v);
                  setBucketId("");
                }}
              >
                <SelectTrigger className="mt-1">
                  <SelectValue placeholder="Select a storage provider" />
                </SelectTrigger>
                <SelectContent>
                  {(providers.data?.results ?? []).map((p) => (
                    <SelectItem key={p.id} value={String(p.id)}>
                      {p.displayName} ({p.kind})
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label>Bucket</Label>
              <Select
                value={bucketId}
                onValueChange={setBucketId}
                disabled={!providerId}
              >
                <SelectTrigger className="mt-1">
                  <SelectValue
                    placeholder={
                      providerId ? "Select a bucket" : "Pick a provider first"
                    }
                  />
                </SelectTrigger>
                <SelectContent>
                  {(buckets.data?.results ?? [])
                    .filter((b) => b.status === "active")
                    .map((b) => (
                      <SelectItem key={b.id} value={String(b.id)}>
                        {b.bucketName}
                      </SelectItem>
                    ))}
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label htmlFor="env-prefix">Env var prefix</Label>
              <Input
                id="env-prefix"
                className="mt-1 font-mono"
                value={envPrefix}
                onChange={(e) => setEnvPrefix(e.target.value.toUpperCase())}
                placeholder="S3"
              />
              <p className="mt-1 text-xs text-muted-foreground">
                Variables are named{" "}
                <code className="font-mono">{envPrefix || "S3"}_ENDPOINT</code>,{" "}
                <code className="font-mono">{envPrefix || "S3"}_BUCKET</code>,{" "}
                <code className="font-mono">{envPrefix || "S3"}_ACCESS_KEY</code>, …
                Use a distinct prefix to attach more than one bucket.
              </p>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setOpen(false)}>
              Cancel
            </Button>
            <Button onClick={link} disabled={saving || !bucketId}>
              {saving ? <Loader className="h-4 w-4 animate-spin" /> : "Link bucket"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
