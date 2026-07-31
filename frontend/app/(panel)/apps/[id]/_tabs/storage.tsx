"use client";

import { useState } from "react";
import useSWR, { mutate } from "swr";
import {
  Button,
  Modal,
  Select,
  SelectItem,
  SkeletonText,
  Stack,
  Tag,
  TextInput,
  Tile,
} from "@carbon/react";
import { Add, Link, ObjectStorage, TrashCan } from "@carbon/icons-react";
import { toast } from "@/lib/toast";
import { api, fetcher } from "@/lib/api";
import { PageSection } from "@/components/page";
import type {
  AppStorageLink,
  ListResponse,
  StorageBucket,
  StorageProvider,
} from "@/lib/types";
import "../_app-detail.scss";

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
    <div className="gisila-app__narrow">
      <PageSection
        title="Object storage buckets"
        description="Linking a bucket injects its S3 credentials into this app's environment (live on the next deploy)."
        actions={
          <Button size="sm" renderIcon={Add} onClick={() => setOpen(true)}>
            Link bucket
          </Button>
        }
      >
        {isLoading ? (
          <SkeletonText paragraph lineCount={3} />
        ) : links.length === 0 ? (
          <Tile className="gisila-empty">
            <span className="gisila-app__empty">
              <ObjectStorage size={32} />
              No buckets linked yet.
            </span>
          </Tile>
        ) : (
          <Stack gap={5}>
            {links.map((l) => (
              <Tile key={l.id}>
                <div className="gisila-app__toolbar">
                  <span className="gisila-app__inline">
                    <Link size={16} />
                    {l.bucketName}
                    <Tag type="outline" size="sm">
                      {l.providerName}
                    </Tag>
                    <Tag type="cool-gray" size="sm">
                      {l.providerKind}
                    </Tag>
                  </span>
                  <Button
                    size="sm"
                    kind="danger--ghost"
                    hasIconOnly
                    renderIcon={TrashCan}
                    iconDescription={`Unlink ${l.bucketName}`}
                    onClick={() => unlink(l.id)}
                  />
                </div>
                <p className="gisila-app__hint">
                  Injected env vars (prefix{" "}
                  <span className="gisila-app__chip">{l.envPrefix}</span>):
                </p>
                <div className="gisila-app__inline">
                  {l.envVars.map((v) => (
                    <span key={v} className="gisila-app__chip">
                      {v}
                    </span>
                  ))}
                </div>
              </Tile>
            ))}
          </Stack>
        )}
      </PageSection>

      <Modal
        open={open}
        size="sm"
        modalHeading="Link a bucket"
        primaryButtonText={saving ? "Linking…" : "Link bucket"}
        primaryButtonDisabled={saving || !bucketId}
        secondaryButtonText="Cancel"
        onRequestClose={() => setOpen(false)}
        onRequestSubmit={link}
      >
        <Stack gap={5}>
          <Select
            id="storage-provider"
            labelText="Provider"
            value={providerId}
            onChange={(e) => {
              setProviderId(e.target.value);
              setBucketId("");
            }}
          >
            <SelectItem value="" text="Select a storage provider" />
            {(providers.data?.results ?? []).map((p) => (
              <SelectItem
                key={p.id}
                value={String(p.id)}
                text={`${p.displayName} (${p.kind})`}
              />
            ))}
          </Select>

          <Select
            id="storage-bucket"
            labelText="Bucket"
            value={bucketId}
            disabled={!providerId}
            onChange={(e) => setBucketId(e.target.value)}
          >
            <SelectItem
              value=""
              text={providerId ? "Select a bucket" : "Pick a provider first"}
            />
            {(buckets.data?.results ?? [])
              .filter((b) => b.status === "active")
              .map((b) => (
                <SelectItem key={b.id} value={String(b.id)} text={b.bucketName} />
              ))}
          </Select>

          <div>
            <TextInput
              id="env-prefix"
              labelText="Env var prefix"
              value={envPrefix}
              onChange={(e) => setEnvPrefix(e.target.value.toUpperCase())}
              placeholder="S3"
            />
            <p className="gisila-app__hint">
              Variables are named{" "}
              <span className="gisila-app__chip">
                {envPrefix || "S3"}_ENDPOINT
              </span>
              ,{" "}
              <span className="gisila-app__chip">{envPrefix || "S3"}_BUCKET</span>
              ,{" "}
              <span className="gisila-app__chip">
                {envPrefix || "S3"}_ACCESS_KEY
              </span>
              , … Use a distinct prefix to attach more than one bucket.
            </p>
          </div>
        </Stack>
      </Modal>
    </div>
  );
}
