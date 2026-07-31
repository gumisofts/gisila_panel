"use client";

import { useState } from "react";
import useSWR from "swr";
import { toast } from "@/lib/toast";
import {
  Eye, EyeOff, Plus, Trash2, FileText, Upload, X, Lock, Unlock,
} from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { api, fetcher } from "@/lib/api";
import { cn } from "@/lib/utils";
import type { EnvVar, ListResponse } from "@/lib/types";

// ── .env parser ───────────────────────────────────────────────────────────────

interface ParsedEntry {
  name: string;
  value: string;
  isSecret: boolean;
}

function parseDotEnv(raw: string): ParsedEntry[] {
  const entries: ParsedEntry[] = [];
  for (const line of raw.split(/\r?\n/)) {
    const trimmed = line.trim();
    // Skip blank lines and comments.
    if (!trimmed || trimmed.startsWith("#")) continue;

    const eqIdx = trimmed.indexOf("=");
    if (eqIdx === -1) continue;

    const key = trimmed.slice(0, eqIdx).trim();
    let val   = trimmed.slice(eqIdx + 1).trim();

    // Strip surrounding quotes (single or double).
    if (
      (val.startsWith('"') && val.endsWith('"')) ||
      (val.startsWith("'") && val.endsWith("'"))
    ) {
      val = val.slice(1, -1);
    }

    if (!key) continue;

    // Heuristic: treat anything that looks like a secret as such.
    const lk = key.toLowerCase();
    const isSecret =
      lk.includes("secret") ||
      lk.includes("password") ||
      lk.includes("passwd") ||
      lk.includes("token") ||
      lk.includes("api_key") ||
      lk.includes("private_key") ||
      lk.includes("credential") ||
      lk === "database_url" ||
      lk === "db_url";

    entries.push({ name: key, value: val, isSecret });
  }
  return entries;
}

// ── Main component ────────────────────────────────────────────────────────────

export function EnvsTab({ appId }: { appId: number }) {
  const { data, mutate } = useSWR<ListResponse<EnvVar>>(
    `/apps/${appId}/envs`,
    fetcher,
  );

  // Single-add form.
  const [name, setName]       = useState("");
  const [value, setValue]     = useState("");
  const [isSecret, setIsSecret] = useState(false);
  const [saving, setSaving]   = useState(false);

  // Reveal state for existing secrets.
  const [revealed, setRevealed] = useState<Record<number, boolean>>({});

  // Paste-and-edit panel.
  const [showPaste, setShowPaste]     = useState(false);
  const [rawEnv, setRawEnv]           = useState("");
  const [parsed, setParsed]           = useState<ParsedEntry[]>([]);
  const [importing, setImporting]     = useState(false);

  // ── Handlers ────────────────────────────────────────────────────────────────

  async function addOne(e: React.FormEvent) {
    e.preventDefault();
    setSaving(true);
    try {
      await api(`/apps/${appId}/envs`, {
        method: "POST",
        body: JSON.stringify({ name, value, isSecret }),
      });
      setName(""); setValue(""); setIsSecret(false);
      mutate();
      toast.success("Env var saved.");
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed");
    } finally {
      setSaving(false);
    }
  }

  async function remove(envId: number) {
    if (!confirm("Delete this env var?")) return;
    await api(`/apps/${appId}/envs/${envId}`, { method: "DELETE" });
    mutate();
  }

  function handlePasteChange(text: string) {
    setRawEnv(text);
    setParsed(parseDotEnv(text));
  }

  function updateParsed(idx: number, field: keyof ParsedEntry, val: string | boolean) {
    setParsed((p) => p.map((e, i) => (i === idx ? { ...e, [field]: val } : e)));
  }

  function removeParsed(idx: number) {
    setParsed((p) => p.filter((_, i) => i !== idx));
  }

  async function importAll() {
    if (parsed.length === 0) return;
    setImporting(true);
    try {
      const res = await api<{ imported: number }>(`/apps/${appId}/envs/bulk`, {
        method: "POST",
        body: JSON.stringify({ entries: parsed }),
      });
      mutate();
      toast.success(`Imported ${res.imported} variable${res.imported !== 1 ? "s" : ""}.`);
      setShowPaste(false);
      setRawEnv("");
      setParsed([]);
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Import failed");
    } finally {
      setImporting(false);
    }
  }

  const envs = data?.results ?? [];

  return (
    <div className="space-y-4">
      {/* ── Paste .env panel ─────────────────────────────────────────────── */}
      {showPaste ? (
        <Card className="border-primary/30 bg-primary/5">
          <CardHeader className="flex flex-row items-center justify-between pb-2 pt-4">
            <CardTitle className="text-sm font-medium flex items-center gap-2">
              <FileText className="h-4 w-4 text-muted-foreground" />
              Paste .env file
            </CardTitle>
            <Button
              variant="ghost"
              size="icon"
              className="h-7 w-7"
              onClick={() => { setShowPaste(false); setRawEnv(""); setParsed([]); }}
            >
              <X className="h-4 w-4" />
            </Button>
          </CardHeader>
          <CardContent className="space-y-4">
            {/* Raw textarea */}
            <div className="space-y-1.5">
              <Textarea
                className="font-mono text-xs leading-relaxed min-h-[140px] resize-y"
                placeholder={"DATABASE_URL=postgres://user:pass@localhost/db\nSECRET_KEY=abc123\nDEBUG=false\n# comments are ignored"}
                value={rawEnv}
                onChange={(e) => handlePasteChange(e.target.value)}
              />
              <p className="text-xs text-muted-foreground">
                Paste your <code className="font-mono">.env</code> file above. Comments (#) and blank lines are ignored.
                Secret detection is automatic — you can override it per-row below.
              </p>
            </div>

            {/* Parsed editable rows */}
            {parsed.length > 0 && (
              <div className="space-y-2">
                <div className="grid grid-cols-[1fr_1fr_auto_auto] gap-2 pb-1 text-[10px] uppercase tracking-wider text-muted-foreground px-1">
                  <span>Variable</span>
                  <span>Value</span>
                  <span>Secret</span>
                  <span />
                </div>
                {parsed.map((entry, i) => (
                  <div key={i} className="grid grid-cols-[1fr_1fr_auto_auto] items-center gap-2">
                    <Input
                      className="h-8 font-mono text-xs"
                      value={entry.name}
                      onChange={(e) =>
                        updateParsed(i, "name", e.target.value.toUpperCase())
                      }
                    />
                    <Input
                      className="h-8 font-mono text-xs"
                      type={entry.isSecret ? "password" : "text"}
                      value={entry.value}
                      onChange={(e) => updateParsed(i, "value", e.target.value)}
                    />
                    <button
                      type="button"
                      title={entry.isSecret ? "Mark as plain" : "Mark as secret"}
                      onClick={() => updateParsed(i, "isSecret", !entry.isSecret)}
                      className={cn(
                        "flex h-8 w-8 items-center justify-center rounded-md border transition-colors",
                        entry.isSecret
                          ? "border-amber-500/40 bg-amber-500/10 text-amber-500"
                          : "border-border bg-card text-muted-foreground hover:border-primary/30",
                      )}
                    >
                      {entry.isSecret ? (
                        <Lock className="h-3.5 w-3.5" />
                      ) : (
                        <Unlock className="h-3.5 w-3.5" />
                      )}
                    </button>
                    <button
                      type="button"
                      onClick={() => removeParsed(i)}
                      className="flex h-8 w-8 items-center justify-center rounded-md text-muted-foreground hover:text-destructive"
                    >
                      <X className="h-3.5 w-3.5" />
                    </button>
                  </div>
                ))}

                {/* Import footer */}
                <div className="flex items-center justify-between pt-2">
                  <span className="text-xs text-muted-foreground">
                    {parsed.length} variable{parsed.length !== 1 ? "s" : ""} ready to import.{" "}
                    {parsed.filter((e) => e.isSecret).length > 0 && (
                      <span className="text-amber-500">
                        {parsed.filter((e) => e.isSecret).length} secret
                        {parsed.filter((e) => e.isSecret).length !== 1 ? "s" : ""}.
                      </span>
                    )}
                  </span>
                  <Button size="sm" onClick={importAll} disabled={importing}>
                    {importing ? (
                      "Importing…"
                    ) : (
                      <>
                        <Upload className="mr-1.5 h-3.5 w-3.5" />
                        Import {parsed.length} variable{parsed.length !== 1 ? "s" : ""}
                      </>
                    )}
                  </Button>
                </div>
              </div>
            )}
          </CardContent>
        </Card>
      ) : null}

      {/* ── Single-add form ───────────────────────────────────────────────── */}
      <Card>
        <CardContent className="p-5">
          <div className="mb-3 flex items-center justify-between">
            <p className="text-xs text-muted-foreground">Add a single variable or paste an entire .env file.</p>
            <Button
              type="button"
              size="sm"
              variant={showPaste ? "default" : "outline"}
              className="h-7 text-xs gap-1.5"
              onClick={() => setShowPaste((v) => !v)}
            >
              <FileText className="h-3.5 w-3.5" />
              {showPaste ? "Hide paste panel" : "Paste .env"}
            </Button>
          </div>
          <form
            onSubmit={addOne}
            className="grid gap-3 md:grid-cols-[1fr_1fr_auto_auto]"
          >
            <Input
              placeholder="VARIABLE_NAME"
              className="font-mono text-sm"
              value={name}
              onChange={(e) => setName(e.target.value.toUpperCase())}
              required
            />
            <Input
              placeholder="value"
              className="font-mono text-sm"
              value={value}
              onChange={(e) => setValue(e.target.value)}
            />
            <label className="inline-flex items-center gap-2 text-xs text-muted-foreground whitespace-nowrap">
              <input
                type="checkbox"
                checked={isSecret}
                onChange={(e) => setIsSecret(e.target.checked)}
                className="rounded"
              />
              Secret
            </label>
            <Button type="submit" size="sm" disabled={saving}>
              <Plus className="h-3.5 w-3.5" /> Add
            </Button>
          </form>
          <p className="mt-2.5 text-xs text-muted-foreground">
            Changes apply on the next restart or deployment.
          </p>
        </CardContent>
      </Card>

      {/* ── Existing vars ─────────────────────────────────────────────────── */}
      <Card>
        <CardContent className="p-0">
          {envs.length > 0 ? (
            <ul className="divide-y divide-border/60">
              {envs.map((env) => (
                <EnvRow
                  key={env.id}
                  env={env}
                  appId={appId}
                  revealed={!!revealed[env.id]}
                  onToggleReveal={() =>
                    setRevealed((m) => ({ ...m, [env.id]: !m[env.id] }))
                  }
                  onDelete={() => remove(env.id)}
                  onSaved={() => mutate()}
                />
              ))}
            </ul>
          ) : (
            <div className="py-10 text-center text-sm text-muted-foreground">
              No env vars yet. Add one above or paste a .env file.
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

// ── Individual env var row (inline edit) ──────────────────────────────────────

function EnvRow({
  env,
  appId,
  revealed,
  onToggleReveal,
  onDelete,
  onSaved,
}: {
  env: EnvVar;
  appId: number;
  revealed: boolean;
  onToggleReveal: () => void;
  onDelete: () => void;
  onSaved: () => void;
}) {
  const [editing, setEditing]   = useState(false);
  const [draftVal, setDraftVal] = useState(env.value ?? "");
  const [draftSecret, setDraftSecret] = useState(env.isSecret ?? false);
  const [saving, setSaving]     = useState(false);

  async function save() {
    setSaving(true);
    try {
      await api(`/apps/${appId}/envs`, {
        method: "POST",
        body: JSON.stringify({
          name: env.name,
          value: draftVal,
          isSecret: draftSecret,
        }),
      });
      onSaved();
      setEditing(false);
      toast.success(`${env.name} updated.`);
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed");
    } finally {
      setSaving(false);
    }
  }

  return (
    <li className="px-4 py-3 text-sm">
      {editing ? (
        /* Edit mode */
        <div className="flex items-center gap-2">
          <code className="w-44 shrink-0 font-mono text-xs font-medium">{env.name}</code>
          <Input
            className="h-7 flex-1 font-mono text-xs"
            type={draftSecret && !revealed ? "password" : "text"}
            value={draftVal}
            onChange={(e) => setDraftVal(e.target.value)}
            autoFocus
            onKeyDown={(e) => {
              if (e.key === "Enter") { e.preventDefault(); save(); }
              if (e.key === "Escape") setEditing(false);
            }}
          />
          <label className="flex items-center gap-1.5 text-xs text-muted-foreground whitespace-nowrap">
            <input
              type="checkbox"
              checked={draftSecret}
              onChange={(e) => setDraftSecret(e.target.checked)}
            />
            Secret
          </label>
          <Button size="sm" className="h-7 text-xs px-2" disabled={saving} onClick={save}>
            {saving ? "…" : "Save"}
          </Button>
          <Button
            size="sm"
            variant="ghost"
            className="h-7 px-2 text-xs"
            onClick={() => { setEditing(false); setDraftVal(env.value ?? ""); setDraftSecret(env.isSecret ?? false); }}
          >
            Cancel
          </Button>
        </div>
      ) : (
        /* Display mode */
        <div className="flex items-center gap-3">
          <div className="flex min-w-0 flex-1 items-center gap-3">
            <code className="w-44 shrink-0 font-mono text-xs font-medium truncate">
              {env.name}
            </code>
            <span
              className={cn(
                "flex-1 min-w-0 truncate font-mono text-xs text-muted-foreground",
                !env.isSecret && "cursor-pointer hover:text-foreground",
              )}
              onClick={() => !env.isSecret && setEditing(true)}
            >
              {env.isSecret && !revealed
                ? <span className="tracking-widest">••••••••</span>
                : (env.value || <span className="italic opacity-50">empty</span>)}
            </span>
            {env.isSecret && (
              <Badge variant="secondary" className="shrink-0 gap-1 text-[9px] font-normal py-0">
                <Lock className="h-2.5 w-2.5" />
                secret
              </Badge>
            )}
          </div>

          <div className="flex items-center gap-1 shrink-0">
            {env.isSecret && (
              <Button variant="ghost" size="icon" className="h-7 w-7" onClick={onToggleReveal}>
                {revealed ? <EyeOff className="h-3.5 w-3.5" /> : <Eye className="h-3.5 w-3.5" />}
              </Button>
            )}
            <Button
              variant="ghost"
              size="icon"
              className="h-7 w-7 text-muted-foreground hover:text-foreground"
              onClick={() => { setDraftVal(env.value ?? ""); setDraftSecret(env.isSecret ?? false); setEditing(true); }}
              title="Edit"
            >
              <svg className="h-3.5 w-3.5" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" d="M15.232 5.232l3.536 3.536M9 11l6.364-6.364a2 2 0 112.828 2.828L11.828 13.828A2 2 0 0110 14H8v-2a2 2 0 01.586-1.414z" />
              </svg>
            </Button>
            <Button
              variant="ghost"
              size="icon"
              className="h-7 w-7 text-muted-foreground hover:text-destructive"
              onClick={onDelete}
            >
              <Trash2 className="h-3.5 w-3.5" />
            </Button>
          </div>
        </div>
      )}
    </li>
  );
}
