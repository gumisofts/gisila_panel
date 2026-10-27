import { useState, type ElementType } from "react";
import useSWR, { mutate } from "swr";
import { toast } from "@/lib/toast";
import {
  Add,
  BareMetalServer,
  CheckmarkFilled,
  Cloud,
  Earth,
  ObjectStorage,
  PlayFilled,
  StopFilled,
  TrashCan,
  View,
  WarningAlt,
} from "@carbon/icons-react";
import {
  Button,
  Checkbox,
  CodeSnippet,
  InlineLoading,
  Link as CarbonLink,
  Modal,
  NumberInput,
  PasswordInput,
  SkeletonText,
  Stack,
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
  StorageProvider,
  StorageProviderStatus,
  StorageBucket,
} from "@/lib/types";
import "../_storage-mail.scss";
import { confirmDialog } from "@/components/confirm-dialog";

type StatusTone = "green" | "gray" | "red" | "blue";

const STATUS: Record<
  StorageProviderStatus,
  { label: string; tone: StatusTone; icon?: ElementType; busy?: boolean }
> = {
  running:      { label: "Running", tone: "green", icon: CheckmarkFilled },
  config_only:  { label: "Ready", tone: "green", icon: CheckmarkFilled },
  stopped:      { label: "Stopped", tone: "gray", icon: WarningAlt },
  failed:       { label: "Failed", tone: "red", icon: WarningAlt },
  pending:      { label: "Pending", tone: "blue", busy: true },
  installing:   { label: "Installing", tone: "blue", busy: true },
  uninstalling: { label: "Removing", tone: "gray", busy: true },
};

function ProviderStatusTag({ status }: { status: StorageProviderStatus }) {
  const s = STATUS[status] ?? STATUS.pending;
  if (s.busy) return <InlineLoading status="active" description={s.label} />;
  return (
    <Tag size="sm" type={s.tone} renderIcon={s.icon}>
      {s.label}
    </Tag>
  );
}

/// CodeSnippet copies its own contents; this only keeps the toast the panel
/// has always shown on copy.
function copied() {
  toast.success("Copied");
}

/** A server the panel installs and runs on this host. */
const isLocal = (kind: string) => kind === "garage" || kind === "minio";

export default function StoragePage() {
  const { data, isLoading } = useSWR<ListResponse<StorageProvider>>(
    "/storage/providers",
    fetcher,
  );
  const [installOpen, setInstallOpen] = useState(false);
  const [connectorOpen, setConnectorOpen] = useState(false);

  const providers = data?.results ?? [];
  const hasLocal = providers.some((p) => isLocal(p.kind));

  return (
    <Page>
      <PageHeader
        title="Object storage"
        description="S3-compatible buckets — self-hosted Garage or an external provider."
        actions={
          <>
            <Button
              kind="tertiary"
              size="sm"
              renderIcon={Cloud}
              onClick={() => setConnectorOpen(true)}
            >
              Add connector
            </Button>
            {!hasLocal && (
              <Button
                size="sm"
                renderIcon={BareMetalServer}
                onClick={() => setInstallOpen(true)}
              >
                Install Garage
              </Button>
            )}
          </>
        }
      />

      {isLoading ? (
        <SkeletonText paragraph lineCount={3} />
      ) : providers.length === 0 ? (
        <Tile className="gisila-empty">
          <ObjectStorage size={32} style={{ opacity: 0.4 }} />
          <p>
            No storage providers yet. Install Garage for self-hosted buckets, or
            connect an external S3/R2 endpoint.
          </p>
        </Tile>
      ) : (
        <Stack gap={5}>
          {providers.map((p) => (
            <ProviderCard key={p.id} provider={p} />
          ))}
        </Stack>
      )}

      <InstallGarageDialog open={installOpen} onOpenChange={setInstallOpen} />
      <AddConnectorDialog open={connectorOpen} onOpenChange={setConnectorOpen} />
    </Page>
  );
}

function ProviderCard({ provider: p }: { provider: StorageProvider }) {
  const bucketsKey = `/storage/providers/${p.id}/buckets`;
  const { data } = useSWR<ListResponse<StorageBucket>>(bucketsKey, fetcher, {
    refreshInterval: p.status === "running" || p.kind === "external" ? 0 : 4000,
  });
  const [createOpen, setCreateOpen] = useState(false);
  const [exposeOpen, setExposeOpen] = useState(false);
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
    if (!(await confirmDialog(`Remove "${p.displayName}"? Buckets and any app links are removed too.`)))
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
    <Tile>
      <div className="gisila-sm__tile-head">
        <Stack gap={2}>
          <div className="gisila-sm__title-row">
            {isLocal(p.kind) ? (
              <BareMetalServer size={16} />
            ) : (
              <Cloud size={16} />
            )}
            <span className="gisila-sm__title">{p.displayName}</span>
            <ProviderStatusTag status={p.status} />
          </div>
          <p className="gisila-sm__meta">{p.endpoint}</p>
          {p.publicUrl ? (
            <p className="gisila-sm__meta">
              public:{" "}
              <CarbonLink href={p.publicUrl} target="_blank" rel="noreferrer">
                {p.publicUrl}
              </CarbonLink>
            </p>
          ) : (
            isLocal(p.kind) && (
              <p className="gisila-sm__warning">
                Not publicly exposed — only reachable from apps on this host.
              </p>
            )
          )}
          {p.consoleUrl && (
            <p className="gisila-sm__meta">
              console:{" "}
              <CarbonLink href={p.consoleUrl} target="_blank" rel="noreferrer">
                {p.consoleUrl}
              </CarbonLink>
            </p>
          )}
          {p.errorMessage && (
            <p className="gisila-sm__error">{p.errorMessage}</p>
          )}
        </Stack>
        <div className="gisila-sm__actions">
          {isLocal(p.kind) && (
            <Button
              kind="ghost"
              size="sm"
              hasIconOnly
              renderIcon={Earth}
              iconDescription="Public URL"
              onClick={() => setExposeOpen(true)}
            />
          )}
          {isLocal(p.kind) && p.status === "stopped" && (
            <Button
              kind="ghost"
              size="sm"
              hasIconOnly
              renderIcon={PlayFilled}
              iconDescription="Start"
              onClick={() => lifecycle("start")}
            />
          )}
          {isLocal(p.kind) && p.status === "running" && (
            <Button
              kind="ghost"
              size="sm"
              hasIconOnly
              renderIcon={StopFilled}
              iconDescription="Stop"
              onClick={() => lifecycle("stop")}
            />
          )}
          <Button
            kind="danger--ghost"
            size="sm"
            hasIconOnly
            renderIcon={TrashCan}
            iconDescription="Remove provider"
            onClick={remove}
          />
        </div>
      </div>

      <div className="gisila-sm__bar" style={{ marginBlock: "1.5rem 0.5rem" }}>
        <p className="gisila-sm__label">Buckets</p>
        {canHaveBuckets && (
          <Button
            kind="tertiary"
            size="sm"
            renderIcon={Add}
            onClick={() => setCreateOpen(true)}
          >
            New bucket
          </Button>
        )}
      </div>
      {buckets.length === 0 ? (
        <p className="gisila-sm__note">No buckets yet.</p>
      ) : (
        <Table size="sm">
          <TableHead>
            <TableRow>
              <TableHeader>Bucket</TableHeader>
              <TableHeader>Status</TableHeader>
              <TableHeader aria-label="Actions" />
            </TableRow>
          </TableHead>
          <TableBody>
            {buckets.map((b) => (
              <BucketRow key={b.id} providerId={p.id} bucket={b} />
            ))}
          </TableBody>
        </Table>
      )}

      <CreateBucketDialog
        open={createOpen}
        onOpenChange={setCreateOpen}
        providerId={p.id}
        bucketsKey={bucketsKey}
      />
      <ExposeDialog
        open={exposeOpen}
        onOpenChange={setExposeOpen}
        provider={p}
      />
    </Tile>
  );
}

function ExposeDialog({
  open,
  onOpenChange,
  provider: p,
}: {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  provider: StorageProvider;
}) {
  const [publicUrl, setPublicUrl] = useState(p.publicUrl ?? "");
  const [consoleUrl, setConsoleUrl] = useState(p.consoleUrl ?? "");
  const [issueCert, setIssueCert] = useState(true);
  const [saving, setSaving] = useState(false);

  // Certbot only applies to https URLs; http (or upstream-terminated TLS) skips it.
  const anyHttps =
    publicUrl.trim().startsWith("https://") ||
    consoleUrl.trim().startsWith("https://");

  async function submit() {
    setSaving(true);
    try {
      await api(`/storage/providers/${p.id}/expose`, {
        method: "POST",
        body: JSON.stringify({
          publicUrl: publicUrl.trim(),
          consoleUrl: consoleUrl.trim(),
          issueCert,
        }),
      });
      toast.success(
        publicUrl.trim()
          ? "Public URL set — nginx vhost is being configured."
          : "Public URL cleared.",
      );
      onOpenChange(false);
      mutate("/storage/providers");
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed to update");
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal
      open={open}
      onRequestClose={() => onOpenChange(false)}
      modalHeading={`Public URL for ${p.displayName}`}
      primaryButtonText={saving ? "Saving…" : "Save"}
      primaryButtonDisabled={saving}
      secondaryButtonText="Cancel"
      onRequestSubmit={submit}
      size="md"
    >
      <Stack gap={5}>
        <TextInput
          id={`expose-public-${p.id}`}
          labelText="S3 API URL"
          placeholder="https://s3.example.com"
          value={publicUrl}
          onChange={(e) => setPublicUrl(e.target.value)}
        />
        {p.kind === "minio" && (
          <TextInput
            id={`expose-console-${p.id}`}
            labelText={
              <>
                Console URL{" "}
                <span className="gisila-sm__optional">(optional)</span>
              </>
            }
            placeholder="https://minio.example.com"
            value={consoleUrl}
            onChange={(e) => setConsoleUrl(e.target.value)}
          />
        )}
        <Checkbox
          id={`expose-cert-${p.id}`}
          labelText="Obtain a Let's Encrypt certificate"
          checked={issueCert}
          disabled={!anyHttps}
          onChange={(_, { checked }) => setIssueCert(checked)}
        />
        <div className="gisila-sm__callout gisila-sm__note">
          {p.kind === "minio" ? (
            <p>
              MinIO listens on <code className="gisila-sm__code">127.0.0.1</code>{" "}
              only. Each URL creates an nginx reverse-proxy vhost — the S3 API
              (unlimited upload size) and the web console (websockets) get their
              own hostnames, since they can&apos;t share one.
            </p>
          ) : (
            <p>
              Garage listens on <code className="gisila-sm__code">127.0.0.1</code>{" "}
              only. The URL gets an nginx vhost for the S3 API (unlimited upload
              size); objects in public buckets are also readable there without
              credentials, at{" "}
              <code className="gisila-sm__code">/&lt;bucket&gt;/&lt;key&gt;</code>.
            </p>
          )}
          <p>
            Leave the certificate box unchecked if TLS is terminated upstream
            (e.g. a Cloudflare proxy or external load balancer) — nginx then
            serves plain HTTP on port 80 and no certbot runs.
          </p>
          <p>
            Point a DNS <code className="gisila-sm__code">A</code> record at this
            server for each hostname first. An{" "}
            <code className="gisila-sm__code">https://</code> URL triggers a
            Let&apos;s Encrypt certificate automatically.
          </p>
          <p>Leave a field blank to remove its vhost.</p>
        </div>
      </Stack>
    </Modal>
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
    if (!(await confirmDialog(`Delete bucket "${b.bucketName}" and all its objects?`))) return;
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
    <>
      <TableRow>
        <TableCell>
          <div className="gisila-sm__title-row">
            <span className="gisila-sm__code">{b.bucketName}</span>
            {b.isPublic && (
              <Tag size="sm" type="cool-gray">
                public
              </Tag>
            )}
          </div>
        </TableCell>
        <TableCell>
          <Tag
            size="sm"
            type={
              b.status === "active"
                ? "green"
                : b.status === "failed"
                  ? "red"
                  : "gray"
            }
          >
            {b.status}
          </Tag>
        </TableCell>
        <TableCell>
          <div className="gisila-sm__actions" style={{ justifyContent: "flex-end" }}>
            <Button
              kind="ghost"
              size="sm"
              hasIconOnly
              renderIcon={View}
              iconDescription="Show credentials"
              onClick={reveal}
            />
            <Button
              kind="danger--ghost"
              size="sm"
              hasIconOnly
              renderIcon={TrashCan}
              iconDescription="Delete bucket"
              onClick={remove}
            />
          </div>
        </TableCell>
      </TableRow>
      {(b.errorMessage || creds) && (
        <TableRow>
          <TableCell colSpan={3}>
            <Stack gap={3}>
              {b.errorMessage && (
                <p className="gisila-sm__error">{b.errorMessage}</p>
              )}
              {creds && (
                <CredentialList
                  rows={[
                    ["Endpoint", creds.endpoint],
                    ["Region", creds.region],
                    ["Bucket", creds.bucket],
                    ["Access key", creds.accessKey],
                    ["Secret key", creds.secretKey],
                    ...(creds.publicUrl ? [["Public URL", creds.publicUrl]] : []),
                  ]}
                />
              )}
            </Stack>
          </TableCell>
        </TableRow>
      )}
    </>
  );
}

/// Key/value list of S3 credentials. Every value is copied verbatim into an
/// SDK config, so each one gets its own copy button.
function CredentialList({ rows }: { rows: (string | null | undefined)[][] }) {
  return (
    <div className="gisila-sm__kv">
      {rows.map(([k, v]) => (
        <div key={k} className="gisila-sm__kv-row">
          <span className="gisila-sm__kv-key">{k}</span>
          <CodeSnippet
            type="single"
            copyText={String(v)}
            feedback="Copied"
            aria-label={`Copy ${k}`}
            onClick={copied}
          >
            {String(v)}
          </CodeSnippet>
        </div>
      ))}
    </div>
  );
}

function InstallGarageDialog({
  open,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (v: boolean) => void;
}) {
  const [form, setForm] = useState({
    displayName: "Garage",
    port: "3900",
    publicUrl: "",
  });
  const [saving, setSaving] = useState(false);
  const port = Number(form.port) || 3900;

  async function submit() {
    setSaving(true);
    try {
      await api("/storage/providers/garage", {
        method: "POST",
        body: JSON.stringify({
          displayName: form.displayName,
          port: Number(form.port),
          publicUrl: form.publicUrl || undefined,
        }),
      });
      toast.success("Garage installation queued.");
      onOpenChange(false);
      mutate("/storage/providers");
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed to install Garage");
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal
      open={open}
      onRequestClose={() => onOpenChange(false)}
      modalHeading="Install Garage"
      primaryButtonText={saving ? "Installing…" : "Install"}
      primaryButtonDisabled={saving}
      secondaryButtonText="Cancel"
      onRequestSubmit={submit}
      size="sm"
    >
      <Stack gap={5}>
        <TextInput
          id="garage-display-name"
          labelText="Display name"
          value={form.displayName}
          onChange={(e) => setForm({ ...form, displayName: e.target.value })}
        />
        <NumberInput
          id="garage-port"
          label="S3 API port"
          helperText={`Garage also uses ${port + 1} (internal RPC) and ${port + 2} (public reads), all on 127.0.0.1.`}
          allowEmpty
          hideSteppers
          value={form.port}
          onChange={(_, { value }) => setForm({ ...form, port: String(value) })}
        />
        <TextInput
          id="garage-public-url"
          labelText={
            <>
              Public URL <span className="gisila-sm__optional">(optional)</span>
            </>
          }
          placeholder="https://s3.example.com"
          helperText="Publishes the S3 API through nginx at this URL. Without it, buckets are reachable only from apps on this host."
          value={form.publicUrl}
          onChange={(e) => setForm({ ...form, publicUrl: e.target.value })}
        />
      </Stack>
    </Modal>
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
    <Modal
      open={open}
      onRequestClose={() => onOpenChange(false)}
      modalHeading="Add external S3 connector"
      primaryButtonText={saving ? "Adding…" : "Add connector"}
      primaryButtonDisabled={saving}
      secondaryButtonText="Cancel"
      onRequestSubmit={submit}
      size="md"
    >
      <Stack gap={5}>
        <TextInput
          id="connector-display-name"
          labelText="Display name"
          placeholder="Cloudflare R2"
          value={form.displayName}
          onChange={(e) => setForm({ ...form, displayName: e.target.value })}
        />
        <TextInput
          id="connector-endpoint"
          labelText="Endpoint"
          placeholder="https://<account>.r2.cloudflarestorage.com"
          value={form.endpoint}
          onChange={(e) => setForm({ ...form, endpoint: e.target.value })}
        />
        <div
          style={{
            display: "grid",
            gridTemplateColumns: "1fr 1fr",
            alignItems: "end",
            gap: "1rem",
          }}
        >
          <TextInput
            id="connector-region"
            labelText="Region"
            value={form.region}
            onChange={(e) => setForm({ ...form, region: e.target.value })}
          />
          <Checkbox
            id="connector-path-style"
            labelText="Path-style addressing"
            checked={form.forcePathStyle}
            onChange={(_, { checked }) =>
              setForm({ ...form, forcePathStyle: checked })
            }
          />
        </div>
        <TextInput
          id="connector-access-key"
          labelText="Access key ID"
          value={form.accessKey}
          onChange={(e) => setForm({ ...form, accessKey: e.target.value })}
        />
        <PasswordInput
          id="connector-secret-key"
          labelText="Secret access key"
          value={form.secretKey}
          onChange={(e) => setForm({ ...form, secretKey: e.target.value })}
        />
        <TextInput
          id="connector-public-url"
          labelText={
            <>
              Public URL <span className="gisila-sm__optional">(optional)</span>
            </>
          }
          placeholder="https://cdn.example.com"
          value={form.publicUrl}
          onChange={(e) => setForm({ ...form, publicUrl: e.target.value })}
        />
      </Stack>
    </Modal>
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
    <Modal
      open={open}
      onRequestClose={close}
      modalHeading={created ? "Bucket created" : "New bucket"}
      primaryButtonText={
        created ? "Done" : saving ? "Creating…" : "Create bucket"
      }
      primaryButtonDisabled={!created && (saving || !bucketName)}
      secondaryButtonText={created ? undefined : "Cancel"}
      onRequestSubmit={created ? close : submit}
      size="sm"
    >
      {created ? (
        <Stack gap={5}>
          <p className="gisila-sm__note">
            Save the secret key now — it is shown only once. Or link this bucket
            to an app to inject these automatically.
          </p>
          <CredentialList
            rows={[
              ["Endpoint", created.endpoint],
              ["Region", created.region],
              ["Bucket", created.bucket],
              ["Access key", created.accessKey],
              ["Secret key", created.secretKey],
            ]}
          />
        </Stack>
      ) : (
        <Stack gap={5}>
          <TextInput
            id={`bucket-name-${providerId}`}
            labelText="Bucket name"
            placeholder="my-app-uploads"
            helperText="3–63 lowercase letters, digits and hyphens."
            value={bucketName}
            onChange={(e) => setBucketName(e.target.value.toLowerCase())}
          />
          <Checkbox
            id={`bucket-public-${providerId}`}
            labelText="Public read (anonymous downloads)"
            checked={isPublic}
            onChange={(_, { checked }) => setIsPublic(checked)}
          />
        </Stack>
      )}
    </Modal>
  );
}
