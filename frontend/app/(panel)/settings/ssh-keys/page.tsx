"use client";

import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
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
import { api } from "@/lib/api";
import { SshKey, SshKeyAlgorithm } from "@/lib/types";
import {
  Check,
  Clipboard,
  Key,
  Plus,
  Sparkles,
  Trash2,
} from "lucide-react";

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
    <div className="max-w-3xl mx-auto space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold">SSH Keys</h1>
          <p className="text-sm text-muted-foreground mt-1">
            Generate deploy keys or add existing public keys for server access.
          </p>
        </div>
        <Button onClick={openNew}>
          <Plus className="w-4 h-4 mr-2" /> Add Key
        </Button>
      </div>

      {loading ? (
        <p className="text-sm text-muted-foreground">Loading…</p>
      ) : keys.length === 0 ? (
        <Card>
          <CardContent className="flex flex-col items-center justify-center py-14 gap-3 text-center">
            <Key className="w-10 h-10 text-muted-foreground/50" />
            <p className="text-sm text-muted-foreground">No SSH keys yet.</p>
            <Button variant="outline" size="sm" onClick={openNew}>
              <Plus className="w-4 h-4 mr-1" /> Add your first key
            </Button>
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-3">
          {keys.map((key) => (
            <Card key={key.id}>
              <CardContent className="flex items-start gap-4 py-4">
                <div className="mt-0.5 text-muted-foreground">
                  <Key className="w-5 h-5" />
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="font-medium text-sm">{key.name}</span>
                    {key.algorithm && (
                      <span className="text-xs bg-muted text-muted-foreground px-2 py-0.5 rounded-full">
                        {ALGORITHMS.find((a) => a.value === key.algorithm)?.label ?? key.algorithm}
                      </span>
                    )}
                    {key.isDeployKey && (
                      <span className="text-xs bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400 px-2 py-0.5 rounded-full">
                        Deploy key
                      </span>
                    )}
                  </div>
                  <p className="text-xs text-muted-foreground font-mono mt-1 truncate">
                    {key.fingerprint}
                  </p>
                  <p className="text-xs text-muted-foreground font-mono mt-1 truncate opacity-60">
                    {key.publicKey}
                  </p>
                </div>
                <div className="flex items-center gap-2 shrink-0">
                  <Button
                    variant="ghost"
                    size="icon"
                    title="Copy public key"
                    onClick={() => copyPub(key)}
                  >
                    {copiedId === key.id ? (
                      <Check className="w-4 h-4 text-green-500" />
                    ) : (
                      <Clipboard className="w-4 h-4" />
                    )}
                  </Button>
                  <Button
                    variant="ghost"
                    size="icon"
                    className="text-destructive hover:text-destructive"
                    onClick={() => deleteKey(key.id as number)}
                  >
                    <Trash2 className="w-4 h-4" />
                  </Button>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {/* Add / Generate dialog */}
        <Dialog
        open={dialogOpen}
        onOpenChange={(o) => {
          if (!o) {
            setGeneratedPrivateKey(null);
            setGeneratedPublicKey(null);
          }
          setDialogOpen(o);
        }}
      >
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>
              {generatedPrivateKey ? "Key generated — save your private key" : "Add SSH Key"}
            </DialogTitle>
          </DialogHeader>

          {generatedPrivateKey ? (
            <div className="space-y-4">
              <div className="rounded-md bg-amber-50 border border-amber-200 dark:bg-amber-950/20 dark:border-amber-800 px-4 py-3 text-sm text-amber-800 dark:text-amber-400">
                This private key will <strong>not</strong> be shown again. Copy
                it now if you need external access to this key.
              </div>
              <div>
                <Label className="text-xs text-muted-foreground mb-1 block">Private Key (PEM)</Label>
                <pre className="text-xs font-mono bg-muted rounded-md p-3 overflow-auto max-h-48 whitespace-pre-wrap break-all">
                  {generatedPrivateKey}
                </pre>
              </div>
              <div>
                <Label className="text-xs text-muted-foreground mb-1 block">Public Key</Label>
                <pre className="text-xs font-mono bg-muted rounded-md p-3 overflow-auto max-h-24 whitespace-pre-wrap break-all">
                  {generatedPublicKey}
                </pre>
                <p className="text-xs text-muted-foreground mt-1">
                  Add this to your Git hosting provider as a deploy key with read access.
                </p>
              </div>
              <Button variant="outline" className="w-full" onClick={copyPrivate}>
                {copiedPrivate ? (
                  <><Check className="w-4 h-4 mr-2 text-green-500" /> Copied!</>
                ) : (
                  <><Clipboard className="w-4 h-4 mr-2" /> Copy private key</>
                )}
              </Button>
            </div>
          ) : (
            <div className="space-y-4">
              {/* Mode tabs */}
              <div className="flex rounded-md border overflow-hidden text-sm">
                {(["generate", "paste"] as Mode[]).map((m) => (
                  <button
                    key={m}
                    className={`flex-1 px-4 py-2 flex items-center justify-center gap-1.5 transition-colors ${
                      mode === m
                        ? "bg-primary text-primary-foreground"
                        : "hover:bg-muted text-muted-foreground"
                    }`}
                    onClick={() => setMode(m)}
                  >
                    {m === "generate" ? (
                      <><Sparkles className="w-3.5 h-3.5" /> Generate</>
                    ) : (
                      <><Clipboard className="w-3.5 h-3.5" /> Paste public key</>
                    )}
                  </button>
                ))}
              </div>

              <div>
                <Label htmlFor="key-name">Name</Label>
                <Input
                  id="key-name"
                  placeholder="e.g. my-repo deploy key"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  className="mt-1"
                />
              </div>

              {mode === "generate" ? (
                <div>
                  <Label htmlFor="key-algo">Algorithm</Label>
                  <Select
                    value={algorithm}
                    onValueChange={(v) => setAlgorithm(v as SshKeyAlgorithm)}
                  >
                    <SelectTrigger id="key-algo" className="mt-1">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {ALGORITHMS.map((a) => (
                        <SelectItem key={a.value} value={a.value}>
                          {a.label}
                          {a.badge && (
                            <span className="ml-2 text-xs text-muted-foreground">
                              ({a.badge})
                            </span>
                          )}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              ) : (
                <div>
                  <Label htmlFor="pub-key">Public Key</Label>
                  <textarea
                    id="pub-key"
                    rows={4}
                    className="mt-1 w-full rounded-md border border-input bg-background px-3 py-2 text-sm font-mono placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring resize-none"
                    placeholder="ssh-ed25519 AAAAC3Nz…"
                    value={publicKey}
                    onChange={(e) => setPublicKey(e.target.value)}
                  />
                </div>
              )}

              {error && <p className="text-sm text-destructive">{error}</p>}
            </div>
          )}

          <DialogFooter>
            {generatedPrivateKey ? (
              <Button onClick={() => setDialogOpen(false)}>Done</Button>
            ) : (
              <>
                <Button variant="outline" onClick={() => setDialogOpen(false)}>
                  Cancel
                </Button>
                <Button onClick={submit} disabled={saving || !name.trim()}>
                  {saving
                    ? "…"
                    : mode === "generate"
                    ? "Generate Key"
                    : "Add Key"}
                </Button>
              </>
            )}
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
