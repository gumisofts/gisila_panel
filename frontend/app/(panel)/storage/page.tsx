"use client";

import { useState } from "react";
import useSWR, { mutate } from "swr";
import { toast } from "sonner";
import {
  HardDrive,
  Plus,
  Trash2,
  CheckCircle,
  AlertCircle,
  Loader,
  Play,
  Square,
  Cloud,
  Server,
  Copy,
  Eye,
} from "lucide-react";
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
import { api, fetcher } from "@/lib/api";
import { cn } from "@/lib/utils";
import type {
  ListResponse,
  StorageProvider,
  StorageProviderStatus,
  StorageBucket,
} from "@/lib/types";

const STATUS: Record<
  StorageProviderStatus,
  { icon: React.ReactNode; label: string; variant: "outline" | "secondary" | "destructive" }
> = {
  running:      { icon: <CheckCircle className="h-3.5 w-3.5 text-emerald-500" />, label: "Running", variant: "outline" },
  config_only:  { icon: <CheckCircle className="h-3.5 w-3.5 text-emerald-500" />, label: "Ready", variant: "outline" },
  stopped:      { icon: <AlertCircle className="h-3.5 w-3.5 text-amber-500" />,   label: "Stopped", variant: "secondary" },
  failed:       { icon: <AlertCircle className="h-3.5 w-3.5 text-red-500" />,     label: "Failed", variant: "destructive" },
  pending:      { icon: <Loader className="h-3.5 w-3.5 animate-spin text-blue-500" />, label: "Pending", variant: "secondary" },
  installing:   { icon: <Loader className="h-3.5 w-3.5 animate-spin text-blue-500" />, label: "Installing", variant: "secondary" },
  uninstalling: { icon: <Loader className="h-3.5 w-3.5 animate-spin text-amber-500" />, label: "Removing", variant: "secondary" },
};

function copy(text: string) {
  navigator.clipboard.writeText(text);
  toast.success("Copied");
}

export default function StoragePage() {
  const { data, isLoading } = useSWR<ListResponse<StorageProvider>>(
    "/storage/providers",
    fetcher,
  );
  const [minioOpen, setMinioOpen] = useState(false);
  const [connectorOpen, setConnectorOpen] = useState(false);

  const providers = data?.results ?? [];
  const hasMinio = providers.some((p) => p.kind === "minio");

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-lg font-semibold tracking-tight">Object storage</h1>
          <p className="text-sm text-muted-foreground">
            S3-compatible buckets — self-hosted MinIO or an external provider.
          </p>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" size="sm" onClick={() => setConnectorOpen(true)}>
            <Cloud className="mr-1.5 h-4 w-4" /> Add connector
          </Button>
          {!hasMinio && (
            <Button size="sm" onClick={() => setMinioOpen(true)}>
              <Server className="mr-1.5 h-4 w-4" /> Install MinIO
            </Button>
          )}
        </div>
      </div>

      {isLoading ? (
        <p className="text-sm text-muted-foreground">Loading…</p>
      ) : providers.length === 0 ? (
        <Card>
          <CardContent className="py-16 text-center">
            <HardDrive className="mx-auto mb-3 h-10 w-10 opacity-40" />
            <p className="text-sm text-muted-foreground">
              No storage providers yet. Install MinIO for self-hosted buckets, or
              connect an external S3/R2 endpoint.
            </p>
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-4">
          {providers.map((p) => (
            <ProviderCard key={p.id} provider={p} />
          ))}
        </div>
      )}

      <InstallMinioDialog open={minioOpen} onOpenChange={setMinioOpen} />
      <AddConnectorDialog open={connectorOpen} onOpenChange={setConnectorOpen} />
    </div>
  );
}

function ProviderCard({ provider: p }: { provider: StorageProvider }) {
  const s = STATUS[p.status] ?? STATUS.pending;
  const bucketsKey = `/storage/providers/${p.id}/buckets`;
  const { data } = useSWR<ListResponse<StorageBucket>>(bucketsKey, fetcher, {
    refreshInterval: p.status === "running" || p.kind === "external" ? 0 : 4000,
  });
  const [createOpen, setCreateOpen] = useState(false);
  const buckets = data?.results ?? [];

  async function lifecycle(action: "start" | "stop") {
    try {
      await api(`/storage/providers/${p.id}/${action}`, { method: "POST" });
      mutate("/storage/providers");
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : `Failed to ${action}`);
    }
  }

  async function remove() {
    if (!confirm(`Remove "${p.displayName}"? Buckets and any app links are removed too.`))
      return;
    try {
      await api(`/storage/providers/${p.id}`, { method: "DELETE" });
      toast.success("Provider removal queued.");
      mutate("/storage/providers");
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed to remove");
    }
  }

  const canHaveBuckets = p.status === "running" || p.kind === "external";

  return (
    <Card>
      <CardHeader className="flex flex-row items-start justify-between space-y-0">
        <div className="space-y-1">
          <CardTitle className="flex items-center gap-2 text-base">
            {p.kind === "minio" ? (
              <Server className="h-4 w-4 text-violet-500" />
            ) : (
              <Cloud className="h-4 w-4 text-sky-500" />
            )}
            {p.displayName}
            <Badge variant={s.variant} className="ml-1 gap-1 text-[10px]">
              {s.icon} {s.label}
            </Badge>
          </CardTitle>
          <p className="font-mono text-xs text-muted-foreground">{p.endpoint}</p>
          {p.errorMessage && (
            <p className="text-xs text-red-500">{p.errorMessage}</p>
          )}
        </div>
        <div className="flex gap-1">
          {p.kind === "minio" && p.status === "stopped" && (
            <Button size="icon" variant="ghost" className="h-7 w-7" onClick={() => lifecycle("start")}>
              <Play className="h-4 w-4" />
            </Button>
          )}
          {p.kind === "minio" && p.status === "running" && (
            <Button size="icon" variant="ghost" className="h-7 w-7" onClick={() => lifecycle("stop")}>
              <Square className="h-4 w-4" />
            </Button>
          )}
          <Button
            size="icon"
            variant="ghost"
            className="h-7 w-7 text-muted-foreground hover:text-red-500"
            onClick={remove}
          >
            <Trash2 className="h-4 w-4" />
          </Button>
        </div>
      </CardHeader>
      <CardContent className="space-y-3">
        <div className="flex items-center justify-between">
          <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
            Buckets
          </p>
          {canHaveBuckets && (
            <Button size="sm" variant="outline" onClick={() => setCreateOpen(true)}>
              <Plus className="mr-1.5 h-3.5 w-3.5" /> New bucket
            </Button>
          )}
        </div>
        {buckets.length === 0 ? (
          <p className="text-xs text-muted-foreground">No buckets yet.</p>
        ) : (
          <div className="divide-y divide-border rounded-md border border-border">
            {buckets.map((b) => (
              <BucketRow key={b.id} providerId={p.id} bucket={b} />
            ))}
          </div>
        )}
      </CardContent>

      <CreateBucketDialog
        open={createOpen}
        onOpenChange={setCreateOpen}
        providerId={p.id}
        bucketsKey={bucketsKey}
      />
    </Card>
  );
}

function BucketRow({
  providerId,
  bucket: b,
}: {
  providerId: number;
  bucket: StorageBucket;
}) {
  const [creds, setCreds] = useState<StorageBucket["connection"] | null>(null);

  async function reveal() {
    try {
      const full = await api<StorageBucket>(
        `/storage/providers/${providerId}/buckets/${b.id}`,
      );
      setCreds(full.connection ?? null);
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed to load credentials");
    }
  }

  async function remove() {
    if (!confirm(`Delete bucket "${b.bucketName}" and all its objects?`)) return;
    try {
      await api(`/storage/providers/${providerId}/buckets/${b.id}`, {
        method: "DELETE",
      });
      toast.success("Bucket deletion queued.");
      mutate(`/storage/providers/${providerId}/buckets`);
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed to delete");
    }
  }

  return (
    <div className="px-3 py-2.5 text-sm">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <span className="font-mono">{b.bucketName}</span>
          {b.isPublic && (
            <Badge variant="secondary" className="text-[10px]">public</Badge>
          )}
          <Badge
            variant={
              b.status === "active"
                ? "outline"
                : b.status === "failed"
                  ? "destructive"
                  : "secondary"
            }
            className="text-[10px]"
          >
            {b.status}
          </Badge>
        </div>
        <div className="flex gap-1">
          <Button size="icon" variant="ghost" className="h-7 w-7" onClick={reveal}>
            <Eye className="h-4 w-4" />
          </Button>
          <Button
            size="icon"
            variant="ghost"
            className="h-7 w-7 text-muted-foreground hover:text-red-500"
            onClick={remove}
          >
            <Trash2 className="h-4 w-4" />
          </Button>
        </div>
      </div>
      {b.errorMessage && (
        <p className="mt-1 text-xs text-red-500">{b.errorMessage}</p>
      )}
      {creds && (
        <div className="mt-2 space-y-1 rounded bg-muted/50 p-2 font-mono text-[11px]">
          {[
            ["Endpoint", creds.endpoint],
            ["Region", creds.region],
            ["Bucket", creds.bucket],
            ["Access key", creds.accessKey],
            ["Secret key", creds.secretKey],
            ...(creds.publicUrl ? [["Public URL", creds.publicUrl]] : []),
          ].map(([k, v]) => (
            <div key={k} className="flex items-center justify-between gap-2">
              <span className="text-muted-foreground">{k}</span>
              <button
                className="flex items-center gap-1 truncate hover:text-foreground"
                onClick={() => copy(String(v))}
                title="Copy"
              >
                <span className="truncate max-w-[18rem]">{v}</span>
                <Copy className="h-3 w-3 shrink-0" />
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function InstallMinioDialog({
  open,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (v: boolean) => void;
}) {
  const [form, setForm] = useState({
    displayName: "MinIO",
    port: "9000",
    consolePort: "9001",
    publicUrl: "",
  });
  const [saving, setSaving] = useState(false);

  async function submit() {
    setSaving(true);
    try {
      await api("/storage/providers/minio", {
        method: "POST",
        body: JSON.stringify({
          displayName: form.displayName,
          port: Number(form.port),
          consolePort: Number(form.consolePort),
          publicUrl: form.publicUrl || undefined,
        }),
      });
      toast.success("MinIO installation queued.");
      onOpenChange(false);
      mutate("/storage/providers");
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed to install MinIO");
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Install MinIO</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          <div>
            <Label>Display name</Label>
            <Input
              className="mt-1"
              value={form.displayName}
              onChange={(e) => setForm({ ...form, displayName: e.target.value })}
            />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label>API port</Label>
              <Input
                className="mt-1"
                type="number"
                value={form.port}
                onChange={(e) => setForm({ ...form, port: e.target.value })}
              />
            </div>
            <div>
              <Label>Console port</Label>
              <Input
                className="mt-1"
                type="number"
                value={form.consolePort}
                onChange={(e) => setForm({ ...form, consolePort: e.target.value })}
              />
            </div>
          </div>
          <div>
            <Label>
              Public URL
              <span className="ml-1 text-[10px] text-muted-foreground">(optional)</span>
            </Label>
            <Input
              className="mt-1 font-mono text-sm"
              placeholder="https://cdn.example.com"
              value={form.publicUrl}
              onChange={(e) => setForm({ ...form, publicUrl: e.target.value })}
            />
            <p className="mt-1 text-xs text-muted-foreground">
              Base URL for public object reads (front MinIO with nginx or a CDN).
              The server listens on 127.0.0.1 only.
            </p>
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button onClick={submit} disabled={saving}>
            {saving ? "Installing…" : "Install"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function AddConnectorDialog({
  open,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (v: boolean) => void;
}) {
  const [form, setForm] = useState({
    displayName: "",
    endpoint: "",
    region: "auto",
    accessKey: "",
    secretKey: "",
    publicUrl: "",
    forcePathStyle: true,
  });
  const [saving, setSaving] = useState(false);

  async function submit() {
    setSaving(true);
    try {
      await api("/storage/providers/external", {
        method: "POST",
        body: JSON.stringify({
          displayName: form.displayName,
          endpoint: form.endpoint,
          region: form.region || "us-east-1",
          accessKey: form.accessKey,
          secretKey: form.secretKey,
          publicUrl: form.publicUrl || undefined,
          forcePathStyle: form.forcePathStyle,
        }),
      });
      toast.success("Connector added.");
      onOpenChange(false);
      mutate("/storage/providers");
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed to add connector");
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Add external S3 connector</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          <div>
            <Label>Display name</Label>
            <Input
              className="mt-1"
              placeholder="Cloudflare R2"
              value={form.displayName}
              onChange={(e) => setForm({ ...form, displayName: e.target.value })}
            />
          </div>
          <div>
            <Label>Endpoint</Label>
            <Input
              className="mt-1 font-mono text-sm"
              placeholder="https://<account>.r2.cloudflarestorage.com"
              value={form.endpoint}
              onChange={(e) => setForm({ ...form, endpoint: e.target.value })}
            />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label>Region</Label>
              <Input
                className="mt-1"
                value={form.region}
                onChange={(e) => setForm({ ...form, region: e.target.value })}
              />
            </div>
            <label className="mt-6 flex items-center gap-2 text-sm">
              <input
                type="checkbox"
                className="h-4 w-4 rounded border-border"
                checked={form.forcePathStyle}
                onChange={(e) => setForm({ ...form, forcePathStyle: e.target.checked })}
              />
              Path-style addressing
            </label>
          </div>
          <div>
            <Label>Access key ID</Label>
            <Input
              className="mt-1 font-mono text-sm"
              value={form.accessKey}
              onChange={(e) => setForm({ ...form, accessKey: e.target.value })}
            />
          </div>
          <div>
            <Label>Secret access key</Label>
            <Input
              className="mt-1 font-mono text-sm"
              type="password"
              value={form.secretKey}
              onChange={(e) => setForm({ ...form, secretKey: e.target.value })}
            />
          </div>
          <div>
            <Label>
              Public URL
              <span className="ml-1 text-[10px] text-muted-foreground">(optional)</span>
            </Label>
            <Input
              className="mt-1 font-mono text-sm"
              placeholder="https://cdn.example.com"
              value={form.publicUrl}
              onChange={(e) => setForm({ ...form, publicUrl: e.target.value })}
            />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button onClick={submit} disabled={saving}>
            {saving ? "Adding…" : "Add connector"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function CreateBucketDialog({
  open,
  onOpenChange,
  providerId,
  bucketsKey,
}: {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  providerId: number;
  bucketsKey: string;
}) {
  const [bucketName, setBucketName] = useState("");
  const [isPublic, setIsPublic] = useState(false);
  const [saving, setSaving] = useState(false);
  const [created, setCreated] = useState<StorageBucket["connection"] | null>(null);

  async function submit() {
    setSaving(true);
    try {
      const bucket = await api<StorageBucket>(
        `/storage/providers/${providerId}/buckets`,
        {
          method: "POST",
          body: JSON.stringify({ bucketName, isPublic }),
        },
      );
      toast.success("Bucket creation queued.");
      mutate(bucketsKey);
      setCreated(bucket.connection ?? null);
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed to create bucket");
    } finally {
      setSaving(false);
    }
  }

  function close() {
    onOpenChange(false);
    setBucketName("");
    setIsPublic(false);
    setCreated(null);
  }

  return (
    <Dialog open={open} onOpenChange={(v) => (v ? onOpenChange(v) : close())}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{created ? "Bucket created" : "New bucket"}</DialogTitle>
        </DialogHeader>
        {created ? (
          <div className="space-y-2">
            <p className="text-xs text-muted-foreground">
              Save the secret key now — it is shown only once. Or link this bucket
              to an app to inject these automatically.
            </p>
            <div className="space-y-1 rounded bg-muted/50 p-3 font-mono text-[11px]">
              {[
                ["Endpoint", created.endpoint],
                ["Region", created.region],
                ["Bucket", created.bucket],
                ["Access key", created.accessKey],
                ["Secret key", created.secretKey],
              ].map(([k, v]) => (
                <div key={k} className="flex items-center justify-between gap-2">
                  <span className="text-muted-foreground">{k}</span>
                  <button
                    className="flex items-center gap-1 truncate hover:text-foreground"
                    onClick={() => copy(String(v))}
                  >
                    <span className="truncate max-w-[16rem]">{v}</span>
                    <Copy className="h-3 w-3 shrink-0" />
                  </button>
                </div>
              ))}
            </div>
            <DialogFooter>
              <Button onClick={close}>Done</Button>
            </DialogFooter>
          </div>
        ) : (
          <>
            <div className="space-y-3">
              <div>
                <Label>Bucket name</Label>
                <Input
                  className="mt-1 font-mono text-sm"
                  placeholder="my-app-uploads"
                  value={bucketName}
                  onChange={(e) => setBucketName(e.target.value.toLowerCase())}
                />
                <p className="mt-1 text-xs text-muted-foreground">
                  3–63 lowercase letters, digits and hyphens.
                </p>
              </div>
              <label className="flex items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  className="h-4 w-4 rounded border-border"
                  checked={isPublic}
                  onChange={(e) => setIsPublic(e.target.checked)}
                />
                Public read (anonymous downloads)
              </label>
            </div>
            <DialogFooter>
              <Button variant="outline" onClick={close}>Cancel</Button>
              <Button onClick={submit} disabled={saving || !bucketName}>
                {saving ? "Creating…" : "Create bucket"}
              </Button>
            </DialogFooter>
          </>
        )}
      </DialogContent>
    </Dialog>
  );
}
