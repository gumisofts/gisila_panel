"use client";

import { useEffect, useState } from "react";
import {
  Button,
  CodeSnippet,
  ContentSwitcher,
  InlineLoading,
  InlineNotification,
  Modal,
  Select,
  SelectItem,
  Stack,
  Switch,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableHeader,
  TableRow,
  Tag,
  TextArea,
  TextInput,
  Tile,
} from "@carbon/react";
import { Page, PageHeader } from "@/components/page";
import { api } from "@/lib/api";
import { SshKey, SshKeyAlgorithm } from "@/lib/types";
import { Add, Checkmark, Copy, Password, TrashCan } from "@carbon/icons-react";
import "../_settings.scss";

const ALGORITHMS: { value: SshKeyAlgorithm; label: string; badge: string }[] = [
  { value: "ed25519",   label: "Ed25519",   badge: "Recommended" },
  { value: "rsa-4096",  label: "RSA 4096",  badge: ""            },
  { value: "rsa-2048",  label: "RSA 2048",  badge: ""            },
  { value: "ecdsa-p256",label: "ECDSA P-256",badge: ""           },
  { value: "ecdsa-p384",label: "ECDSA P-384",badge: ""           },
];

type Mode = "generate" | "paste";

export default function SshKeysPage() {
  const [keys, setKeys] = useState<SshKey[]>([]);
  const [loading, setLoading] = useState(true);

  const [dialogOpen, setDialogOpen] = useState(false);
  const [mode, setMode] = useState<Mode>("generate");
  const [name, setName] = useState("");
  const [algorithm, setAlgorithm] = useState<SshKeyAlgorithm>("ed25519");
  const [publicKey, setPublicKey] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // After generate: show the keypair once.
  const [generatedPrivateKey, setGeneratedPrivateKey] = useState<string | null>(null);
  const [generatedPublicKey, setGeneratedPublicKey] = useState<string | null>(null);
  const [copiedId, setCopiedId] = useState<number | null>(null);
  const [copiedPrivate, setCopiedPrivate] = useState(false);

  const load = () =>
    api<{ results: SshKey[] }>("/me/security/ssh-keys")
      .then((d) => setKeys(d.results))
      .finally(() => setLoading(false));

  useEffect(() => { load(); }, []);

  const openNew = () => {
    setName("");
    setAlgorithm("ed25519");
    setPublicKey("");
    setError(null);
    setGeneratedPrivateKey(null);
    setGeneratedPublicKey(null);
    setMode("generate");
    setDialogOpen(true);
  };

  // Dismissing the dialog itself (close button, escape, click outside) drops the
  // one-time keypair; the explicit footer buttons below only close it.
  const onDialogOpenChange = (o: boolean) => {
    if (!o) {
      setGeneratedPrivateKey(null);
      setGeneratedPublicKey(null);
    }
    setDialogOpen(o);
  };

  const submit = async () => {
    setSaving(true);
    setError(null);
    try {
      if (mode === "generate") {
        const res = await api<{ key: SshKey; privateKey: string }>(
          "/me/security/ssh-keys/generate",
          {
            method: "POST",
            body: JSON.stringify({ name, algorithm }),
          }
        );
        setKeys((prev) => [res.key, ...prev]);
        setGeneratedPrivateKey(res.privateKey);
        setGeneratedPublicKey(res.key.publicKey);
      } else {
        const res = await api<SshKey>("/me/security/ssh-keys", {
          method: "POST",
          body: JSON.stringify({ name, publicKey }),
        });
        setKeys((prev) => [res, ...prev]);
        setDialogOpen(false);
      }
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "An error occurred.");
    } finally {
      setSaving(false);
    }
  };

  const deleteKey = async (id: number) => {
    if (!confirm("Delete this SSH key? This action cannot be undone.")) return;
    await api(`/me/security/ssh-keys/${id}`, { method: "DELETE" });
    setKeys((prev) => prev.filter((k) => k.id !== id));
  };

  const copyPub = (key: SshKey) => {
    navigator.clipboard.writeText(key.publicKey);
    setCopiedId(key.id as number);
    setTimeout(() => setCopiedId(null), 2000);
  };

  const copyPrivate = () => {
    if (!generatedPrivateKey) return;
    navigator.clipboard.writeText(generatedPrivateKey);
    setCopiedPrivate(true);
    setTimeout(() => setCopiedPrivate(false), 2000);
  };

  return (
    <Page>
      <PageHeader
        title="SSH Keys"
        description="Generate deploy keys or add existing public keys for server access."
        actions={
          <Button renderIcon={Add} onClick={openNew}>
            Add Key
          </Button>
        }
      />

      {loading ? (
        <InlineLoading description="Loading…" />
      ) : keys.length === 0 ? (
        <Tile className="gisila-empty">
          <div className="gisila-settings__empty">
            <Password size={32} />
            <p>No SSH keys yet.</p>
            <Button kind="tertiary" size="sm" renderIcon={Add} onClick={openNew}>
              Add your first key
            </Button>
          </div>
        </Tile>
      ) : (
        <TableContainer>
          <Table size="sm">
            <TableHead>
              <TableRow>
                <TableHeader>Name</TableHeader>
                <TableHeader>Fingerprint</TableHeader>
                <TableHeader>Public key</TableHeader>
                <TableHeader />
              </TableRow>
            </TableHead>
            <TableBody>
              {keys.map((key) => (
                <TableRow key={key.id}>
                  <TableCell>
                    <div className="gisila-settings__name">
                      <span>{key.name}</span>
                      {key.algorithm && (
                        <Tag type="cool-gray" size="sm">
                          {ALGORITHMS.find((a) => a.value === key.algorithm)?.label ?? key.algorithm}
                        </Tag>
                      )}
                      {key.isDeployKey && (
                        <Tag type="blue" size="sm">
                          Deploy key
                        </Tag>
                      )}
                    </div>
                  </TableCell>
                  <TableCell>
                    <span className="gisila-settings__mono gisila-settings__truncate">
                      {key.fingerprint}
                    </span>
                  </TableCell>
                  <TableCell>
                    <span className="gisila-settings__mono gisila-settings__truncate">
                      {key.publicKey}
                    </span>
                  </TableCell>
                  <TableCell>
                    <div className="gisila-settings__row-actions">
                      <Button
                        kind="ghost"
                        size="sm"
                        hasIconOnly
                        renderIcon={copiedId === key.id ? Checkmark : Copy}
                        iconDescription="Copy public key"
                        onClick={() => copyPub(key)}
                      />
                      <Button
                        kind="danger--ghost"
                        size="sm"
                        hasIconOnly
                        renderIcon={TrashCan}
                        iconDescription="Delete key"
                        onClick={() => deleteKey(key.id as number)}
                      />
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </TableContainer>
      )}

      {/* Add / Generate dialog */}
      <Modal
        open={dialogOpen}
        onRequestClose={() => onDialogOpenChange(false)}
        size="md"
        hasScrollingContent={Boolean(generatedPrivateKey)}
        modalHeading={
          generatedPrivateKey ? "Key generated — save your private key" : "Add SSH Key"
        }
        primaryButtonText={
          generatedPrivateKey
            ? "Done"
            : saving
            ? "…"
            : mode === "generate"
            ? "Generate Key"
            : "Add Key"
        }
        primaryButtonDisabled={
          generatedPrivateKey ? false : saving || !name.trim()
        }
        secondaryButtonText={generatedPrivateKey ? undefined : "Cancel"}
        onRequestSubmit={
          generatedPrivateKey ? () => setDialogOpen(false) : submit
        }
      >
        {generatedPrivateKey ? (
          <Stack gap={5}>
            <InlineNotification
              kind="warning"
              lowContrast
              hideCloseButton
              title="This private key will not be shown again."
              subtitle="Copy it now if you need external access to this key."
            />
            <div>
              <span className="gisila-settings__label">Private Key (PEM)</span>
              <CodeSnippet type="multi" hideCopyButton wrapText>
                {generatedPrivateKey}
              </CodeSnippet>
            </div>
            <div>
              <span className="gisila-settings__label">Public Key</span>
              <CodeSnippet type="multi" hideCopyButton wrapText>
                {generatedPublicKey}
              </CodeSnippet>
              <p className="gisila-settings__hint">
                Add this to your Git hosting provider as a deploy key with read access.
              </p>
            </div>
            <Button
              kind="tertiary"
              renderIcon={copiedPrivate ? Checkmark : Copy}
              onClick={copyPrivate}
            >
              {copiedPrivate ? "Copied!" : "Copy private key"}
            </Button>
          </Stack>
        ) : (
          <Stack gap={5}>
            <ContentSwitcher
              selectedIndex={mode === "generate" ? 0 : 1}
              onChange={({ name: selected }) => setMode(selected as Mode)}
            >
              <Switch name="generate" text="Generate" />
              <Switch name="paste" text="Paste public key" />
            </ContentSwitcher>

            <TextInput
              id="key-name"
              labelText="Name"
              placeholder="e.g. my-repo deploy key"
              value={name}
              onChange={(e) => setName(e.target.value)}
            />

            {mode === "generate" ? (
              <Select
                id="key-algo"
                labelText="Algorithm"
                value={algorithm}
                onChange={(e) => setAlgorithm(e.target.value as SshKeyAlgorithm)}
              >
                {ALGORITHMS.map((a) => (
                  <SelectItem
                    key={a.value}
                    value={a.value}
                    text={a.badge ? `${a.label} (${a.badge})` : a.label}
                  />
                ))}
              </Select>
            ) : (
              <TextArea
                id="pub-key"
                labelText="Public Key"
                rows={4}
                placeholder="ssh-ed25519 AAAAC3Nz…"
                value={publicKey}
                onChange={(e) => setPublicKey(e.target.value)}
              />
            )}

            {error && (
              <InlineNotification
                kind="error"
                lowContrast
                hideCloseButton
                title={error}
              />
            )}
          </Stack>
        )}
      </Modal>
    </Page>
  );
}
