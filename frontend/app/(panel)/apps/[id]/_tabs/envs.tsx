"use client";

import { useState } from "react";
import useSWR from "swr";
import {
  Button,
  Checkbox,
  Stack,
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
import {
  Add,
  Close,
  Document,
  Edit,
  TrashCan,
  Upload,
  View,
  ViewOff,
} from "@carbon/icons-react";
import { toast } from "@/lib/toast";
import { api, fetcher } from "@/lib/api";
import type { EnvVar, ListResponse } from "@/lib/types";
import "../_app-detail.scss";

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
  const secretCount = parsed.filter((e) => e.isSecret).length;

  return (
    <Stack gap={5}>
      {/* ── Paste .env panel ─────────────────────────────────────────────── */}
      {showPaste ? (
        <Tile>
          <Stack gap={5}>
            <div className="gisila-app__toolbar">
              <span className="gisila-app__inline">
                <Document size={16} />
                Paste .env file
              </span>
              <Button
                kind="ghost"
                size="sm"
                hasIconOnly
                renderIcon={Close}
                iconDescription="Close paste panel"
                onClick={() => { setShowPaste(false); setRawEnv(""); setParsed([]); }}
              />
            </div>

            <TextArea
              id="env-paste"
              labelText="Raw .env contents"
              rows={7}
              placeholder={"DATABASE_URL=postgres://user:pass@localhost/db\nSECRET_KEY=abc123\nDEBUG=false\n# comments are ignored"}
              value={rawEnv}
              onChange={(e) => handlePasteChange(e.target.value)}
              helperText="Comments (#) and blank lines are ignored. Secret detection is automatic — you can override it per row below."
            />

            {/* Parsed editable rows */}
            {parsed.length > 0 && (
              <>
                <TableContainer className="gisila-app__envs">
                  <Table size="sm">
                    <TableHead>
                      <TableRow>
                        <TableHeader>Variable</TableHeader>
                        <TableHeader>Value</TableHeader>
                        <TableHeader>Secret</TableHeader>
                        <TableHeader aria-label="Actions" />
                      </TableRow>
                    </TableHead>
                    <TableBody>
                      {parsed.map((entry, i) => (
                        <TableRow key={i}>
                          <TableCell>
                            <TextInput
                              id={`env-parsed-name-${i}`}
                              labelText="Variable"
                              hideLabel
                              size="sm"
                              value={entry.name}
                              onChange={(e) =>
                                updateParsed(i, "name", e.target.value.toUpperCase())
                              }
                            />
                          </TableCell>
                          <TableCell>
                            <TextInput
                              id={`env-parsed-value-${i}`}
                              labelText="Value"
                              hideLabel
                              size="sm"
                              type={entry.isSecret ? "password" : "text"}
                              value={entry.value}
                              onChange={(e) => updateParsed(i, "value", e.target.value)}
                            />
                          </TableCell>
                          <TableCell>
                            <Checkbox
                              id={`env-parsed-secret-${i}`}
                              labelText="Secret"
                              hideLabel
                              checked={entry.isSecret}
                              onChange={(_, { checked }) =>
                                updateParsed(i, "isSecret", checked)
                              }
                            />
                          </TableCell>
                          <TableCell>
                            <Button
                              kind="ghost"
                              size="sm"
                              hasIconOnly
                              renderIcon={Close}
                              iconDescription="Drop this variable"
                              onClick={() => removeParsed(i)}
                            />
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </TableContainer>

                {/* Import footer */}
                <div className="gisila-app__toolbar">
                  <span className="gisila-app__label">
                    {parsed.length} variable{parsed.length !== 1 ? "s" : ""} ready to import.{" "}
                    {secretCount > 0 && (
                      <>
                        {secretCount} secret{secretCount !== 1 ? "s" : ""}.
                      </>
                    )}
                  </span>
                  <Button
                    size="sm"
                    renderIcon={Upload}
                    onClick={importAll}
                    disabled={importing}
                  >
                    {importing
                      ? "Importing…"
                      : `Import ${parsed.length} variable${parsed.length !== 1 ? "s" : ""}`}
                  </Button>
                </div>
              </>
            )}
          </Stack>
        </Tile>
      ) : null}

      {/* ── Single-add form ───────────────────────────────────────────────── */}
      <Tile>
        <Stack gap={5}>
          <div className="gisila-app__toolbar">
            <span className="gisila-app__label">
              Add a single variable or paste an entire .env file.
            </span>
            <Button
              type="button"
              size="sm"
              kind={showPaste ? "primary" : "tertiary"}
              renderIcon={Document}
              onClick={() => setShowPaste((v) => !v)}
            >
              {showPaste ? "Hide paste panel" : "Paste .env"}
            </Button>
          </div>

          <form onSubmit={addOne} className="gisila-app__form-row">
            <div className="gisila-app__form-field">
              <TextInput
                id="env-new-name"
                labelText="Variable"
                placeholder="VARIABLE_NAME"
                value={name}
                onChange={(e) => setName(e.target.value.toUpperCase())}
                required
              />
            </div>
            <div className="gisila-app__form-field">
              <TextInput
                id="env-new-value"
                labelText="Value"
                placeholder="value"
                value={value}
                onChange={(e) => setValue(e.target.value)}
              />
            </div>
            <div className="gisila-app__form-field--narrow">
              <Checkbox
                id="env-new-secret"
                labelText="Secret"
                checked={isSecret}
                onChange={(_, { checked }) => setIsSecret(checked)}
              />
            </div>
            <Button type="submit" renderIcon={Add} disabled={saving}>
              Add
            </Button>
          </form>

          <p className="gisila-app__hint">
            Changes apply on the next restart or deployment.
          </p>
        </Stack>
      </Tile>

      {/* ── Existing vars ─────────────────────────────────────────────────── */}
      {envs.length > 0 ? (
        <TableContainer className="gisila-app__envs">
          <Table size="sm">
            <TableHead>
              <TableRow>
                <TableHeader>Variable</TableHeader>
                <TableHeader>Value</TableHeader>
                <TableHeader aria-label="Actions" />
              </TableRow>
            </TableHead>
            <TableBody>
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
            </TableBody>
          </Table>
        </TableContainer>
      ) : (
        <Tile className="gisila-empty">
          No env vars yet. Add one above or paste a .env file.
        </Tile>
      )}
    </Stack>
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

  if (editing) {
    /* Edit mode */
    return (
      <TableRow>
        <TableCell>
          <span className="gisila-app__mono gisila-app__env-value">{env.name}</span>
        </TableCell>
        <TableCell>
          <div className="gisila-app__form-row">
            <div className="gisila-app__form-field">
              <TextInput
                id={`env-edit-${env.id}`}
                labelText={`Value for ${env.name}`}
                hideLabel
                size="sm"
                type={draftSecret && !revealed ? "password" : "text"}
                value={draftVal}
                onChange={(e) => setDraftVal(e.target.value)}
                autoFocus
                onKeyDown={(e) => {
                  if (e.key === "Enter") { e.preventDefault(); save(); }
                  if (e.key === "Escape") setEditing(false);
                }}
              />
            </div>
            <div className="gisila-app__form-field--narrow">
              <Checkbox
                id={`env-edit-secret-${env.id}`}
                labelText="Secret"
                checked={draftSecret}
                onChange={(_, { checked }) => setDraftSecret(checked)}
              />
            </div>
          </div>
        </TableCell>
        <TableCell>
          <div className="gisila-app__row-actions">
            <Button size="sm" disabled={saving} onClick={save}>
              {saving ? "…" : "Save"}
            </Button>
            <Button
              size="sm"
              kind="ghost"
              onClick={() => {
                setEditing(false);
                setDraftVal(env.value ?? "");
                setDraftSecret(env.isSecret ?? false);
              }}
            >
              Cancel
            </Button>
          </div>
        </TableCell>
      </TableRow>
    );
  }

  /* Display mode */
  return (
    <TableRow>
      <TableCell>
        <span className="gisila-app__mono gisila-app__env-value">{env.name}</span>
      </TableCell>
      <TableCell>
        <span className="gisila-app__inline">
          <span
            className="gisila-app__mono gisila-app__env-value"
            onClick={() => !env.isSecret && setEditing(true)}
          >
            {env.isSecret && !revealed
              ? "••••••••"
              : (env.value || <em>empty</em>)}
          </span>
          {env.isSecret && (
            <Tag type="warm-gray" size="sm">
              secret
            </Tag>
          )}
        </span>
      </TableCell>
      <TableCell>
        <div className="gisila-app__row-actions">
          {env.isSecret && (
            <Button
              kind="ghost"
              size="sm"
              hasIconOnly
              renderIcon={revealed ? ViewOff : View}
              iconDescription={revealed ? "Hide value" : "Reveal value"}
              onClick={onToggleReveal}
            />
          )}
          <Button
            kind="ghost"
            size="sm"
            hasIconOnly
            renderIcon={Edit}
            iconDescription="Edit"
            onClick={() => {
              setDraftVal(env.value ?? "");
              setDraftSecret(env.isSecret ?? false);
              setEditing(true);
            }}
          />
          <Button
            kind="ghost"
            size="sm"
            hasIconOnly
            renderIcon={TrashCan}
            iconDescription="Delete"
            onClick={onDelete}
          />
        </div>
      </TableCell>
    </TableRow>
  );
}
