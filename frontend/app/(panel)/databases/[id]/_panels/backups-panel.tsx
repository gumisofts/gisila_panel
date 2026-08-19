"use client";

import { useEffect, useState } from "react";
import useSWR, { mutate } from "swr";
import { Download, Reset, TrashCan } from "@carbon/icons-react";
import {
  Button,
  FileUploaderButton,
  FormGroup,
  InlineLoading,
  InlineNotification,
  Modal,
  NumberInput,
  Select,
  SelectItem,
  Stack,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableHeader,
  TableRow,
  Tag,
  Tile,
  Toggle,
} from "@carbon/react";
import {
  api,
  fetcher,
  downloadFile,
  uploadFile,
} from "@/lib/api";
import type {
  ID,
  PgBackup,
  PgBackupSchedule,
  PgBackupScope,
  PgBackupFrequency,
  ListResponse,
} from "@/lib/types";
import "../../_databases.scss";

// Minimal shape shared by Postgres and Mongo database rows — the backups panel
// only needs an id + a display name.
type BackupDb = { id: ID; dbName: string };

// Destructive actions are confirmed in a sibling Modal rather than inside the
// backups Modal: Carbon's open modal container carries a transform, which would
// become the containing block for a nested fixed-position modal.
type PendingAction =
  | { kind: "restore"; backup: PgBackup }
  | { kind: "delete"; backup: PgBackup }
  | { kind: "upload"; file: File };

const SCOPE_LABEL: Record<PgBackupScope, string> = {
  full: "Full (schema + data)",
  schema: "Schema only",
  data: "Data only",
};

const STATUS_TAG: Record<
  PgBackup["status"],
  "red" | "green" | "blue" | "gray"
> = {
  pending: "blue",
  running: "blue",
  completed: "green",
  failed: "red",
};

const WEEKDAYS = [
  "Sunday",
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
];

function formatSize(bytes?: number | null): string {
  if (bytes == null) return "—";
  if (bytes < 1024) return `${bytes} B`;
  const units = ["KB", "MB", "GB", "TB"];
  let v = bytes / 1024;
  let i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return `${v.toFixed(1)} ${units[i]}`;
}

function formatDate(iso?: string | null): string {
  if (!iso) return "—";
  try {
    return new Date(iso).toLocaleString();
  } catch {
    return iso;
  }
}

export function BackupsDialog({
  instanceId,
  db,
  onClose,
  apiBase = "/databases",
  scopes = ["full", "schema", "data"],
  uploadAccept = ".sql,.gz,.sql.gz",
  uploadNote = "Upload a .sql or .sql.gz dump to restore into this database. Restoring may overwrite existing data.",
  canRestore = true,
  exportOnlyNote = "The panel can dump this database but will not write back into it. Download a backup and load it with psql instead.",
}: {
  instanceId: string;
  db: BackupDb | null;
  onClose: () => void;
  apiBase?: string;
  scopes?: PgBackupScope[];
  uploadAccept?: string;
  uploadNote?: string;
  /** When false the database is export-only: backups can be taken, downloaded
   *  and deleted, but not replayed into the cluster. */
  canRestore?: boolean;
  /** Shown in place of the restore controls when [canRestore] is false. */
  exportOnlyNote?: string;
}) {
  const open = !!db;
  const [pending, setPending] = useState<PendingAction | null>(null);
  const [uploading, setUploading] = useState(false);

  const listKey = db ? `${apiBase}/${instanceId}/dbs/${db.id}/backups` : "";

  async function runPending() {
    if (!db || !pending) return;
    const action = pending;
    setPending(null);

    if (action.kind === "restore") {
      try {
        await api(`${apiBase}/${instanceId}/dbs/${db.id}/restore`, {
          method: "POST",
          body: JSON.stringify({ backupId: action.backup.id }),
        });
        alert("Restore queued. It will run in the background.");
      } catch (e: unknown) {
        alert(e instanceof Error ? e.message : "Restore failed.");
      }
      return;
    }

    if (action.kind === "delete") {
      try {
        await api(`${listKey}/${action.backup.id}`, { method: "DELETE" });
        mutate(listKey);
      } catch (e: unknown) {
        alert(e instanceof Error ? e.message : "Delete failed.");
      }
      return;
    }

    setUploading(true);
    try {
      await uploadFile(
        `${apiBase}/${instanceId}/dbs/${db.id}/restore-upload`,
        action.file,
      );
      alert("Upload received. Restore queued in the background.");
    } catch (err: unknown) {
      alert(err instanceof Error ? err.message : "Upload failed.");
    } finally {
      setUploading(false);
    }
  }

  function confirmCopy(action: PendingAction): {
    heading: string;
    primary: string;
    body: string;
  } {
    const name = db?.dbName ?? "";
    switch (action.kind) {
      case "restore":
        return {
          heading: "Restore from backup",
          primary: "Restore",
          body: `Restore ${name} from this backup? This loads the dump into the existing database and may overwrite current data. This cannot be undone.`,
        };
      case "delete":
        return {
          heading: "Delete backup",
          primary: "Delete",
          body: "Delete this backup file? This cannot be undone.",
        };
      case "upload":
        return {
          heading: "Restore from file",
          primary: "Restore",
          body: `Restore ${name} from "${action.file.name}"? This loads the dump into the existing database and may overwrite current data.`,
        };
    }
  }

  const copy = pending ? confirmCopy(pending) : null;

  return (
    <>
      <Modal
        open={open}
        onRequestClose={() => {
          setPending(null);
          onClose();
        }}
        onRequestSubmit={onClose}
        modalHeading={`Backups — ${db?.dbName ?? ""}`}
        primaryButtonText="Close"
        size="lg"
        hasScrollingContent
      >
        {db && (
          <BackupsBody
            instanceId={instanceId}
            db={db}
            apiBase={apiBase}
            scopes={scopes}
            uploadAccept={uploadAccept}
            uploadNote={uploadNote}
            uploading={uploading}
            canRestore={canRestore}
            exportOnlyNote={exportOnlyNote}
            onRequest={setPending}
          />
        )}
      </Modal>

      <Modal
        danger
        open={!!pending}
        onRequestClose={() => setPending(null)}
        onRequestSubmit={runPending}
        modalHeading={copy?.heading ?? ""}
        primaryButtonText={copy?.primary ?? ""}
        secondaryButtonText="Cancel"
        size="sm"
      >
        <p className="gisila-db__note">{copy?.body}</p>
      </Modal>
    </>
  );
}

function BackupsBody({
  instanceId,
  db,
  apiBase,
  scopes,
  uploadAccept,
  uploadNote,
  uploading,
  canRestore,
  exportOnlyNote,
  onRequest,
}: {
  instanceId: string;
  db: BackupDb;
  apiBase: string;
  scopes: PgBackupScope[];
  uploadAccept: string;
  uploadNote: string;
  uploading: boolean;
  canRestore: boolean;
  exportOnlyNote: string;
  onRequest: (action: PendingAction) => void;
}) {
  const listKey = `${apiBase}/${instanceId}/dbs/${db.id}/backups`;
  const schedKey = `${apiBase}/${instanceId}/dbs/${db.id}/backup-schedule`;

  const { data: listData } = useSWR<ListResponse<PgBackup>>(listKey, fetcher, {
    refreshInterval(d) {
      const pending = d?.results.some(
        (b) => b.status === "pending" || b.status === "running",
      );
      return pending ? 3000 : 0;
    },
  });
  const backups = listData?.results ?? [];

  const { data: schedule } = useSWR<PgBackupSchedule>(schedKey, fetcher);

  const [scope, setScope] = useState<PgBackupScope>("full");
  const [backingUp, setBackingUp] = useState(false);
  const [error, setError] = useState("");

  async function handleBackup() {
    setError("");
    setBackingUp(true);
    try {
      await api(listKey, { method: "POST", body: JSON.stringify({ scope }) });
      mutate(listKey);
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Failed to start backup.");
    } finally {
      setBackingUp(false);
    }
  }

  async function handleDownload(b: PgBackup) {
    try {
      await downloadFile(
        `${listKey}/${b.id}/download`,
        b.fileName ?? `${db.dbName}-backup.sql.gz`,
      );
    } catch (e: unknown) {
      alert(e instanceof Error ? e.message : "Download failed.");
    }
  }

  function handleUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    onRequest({ kind: "upload", file });
  }

  return (
    <Stack gap={6}>
      {/* Back up now */}
      <div style={{ display: "flex", alignItems: "flex-end", gap: "0.5rem" }}>
        <div style={{ flex: 1, minWidth: 0 }}>
          <Select
            id="backup-scope"
            labelText="Back up now"
            value={scope}
            onChange={(e) => setScope(e.target.value as PgBackupScope)}
          >
            {scopes.map((s) => (
              <SelectItem key={s} value={s} text={SCOPE_LABEL[s]} />
            ))}
          </Select>
        </div>
        <Button renderIcon={Download} onClick={handleBackup} disabled={backingUp}>
          Back up
        </Button>
      </div>
      {backingUp && <InlineLoading description="Starting backup…" />}
      {error && (
        <InlineNotification kind="error" lowContrast hideCloseButton title={error} />
      )}

      {/* Schedule */}
      <ScheduleEditor schedKey={schedKey} schedule={schedule} scopes={scopes} />

      {/* Restore from file */}
      {canRestore ? (
        <FormGroup legendText="Restore from a file">
          <Stack gap={3}>
            <FileUploaderButton
              accept={uploadAccept.split(",")}
              buttonKind="tertiary"
              labelText="Choose a dump file"
              disabled={uploading}
              onChange={handleUpload}
            />
            {uploading && <InlineLoading description="Uploading…" />}
            <p className="gisila-db__hint">{uploadNote}</p>
          </Stack>
        </FormGroup>
      ) : (
        <InlineNotification
          kind="info"
          lowContrast
          hideCloseButton
          title="Export only"
          subtitle={exportOnlyNote}
        />
      )}

      {/* Backups list */}
      {backups.length === 0 ? (
        <div>
          <p className="gisila-db__stat-label">Backups</p>
          <p className="gisila-db__note">No backups yet.</p>
        </div>
      ) : (
        <TableContainer title="Backups">
          <Table size="sm">
            <TableHead>
              <TableRow>
                <TableHeader>Created</TableHeader>
                <TableHeader>Scope</TableHeader>
                <TableHeader>Size</TableHeader>
                <TableHeader>Status</TableHeader>
                <TableHeader>Actions</TableHeader>
              </TableRow>
            </TableHead>
            <TableBody>
              {backups.map((b) => (
                <TableRow key={b.id}>
                  <TableCell>{formatDate(b.createdAt)}</TableCell>
                  <TableCell>{SCOPE_LABEL[b.scope]}</TableCell>
                  <TableCell>{formatSize(b.sizeBytes)}</TableCell>
                  <TableCell>
                    <div className="gisila-db__tags">
                      <Tag type={STATUS_TAG[b.status]} size="sm">
                        {b.status}
                      </Tag>
                      {b.trigger === "scheduled" && (
                        <Tag type="cool-gray" size="sm">scheduled</Tag>
                      )}
                    </div>
                    {b.errorMessage && (
                      <span className="gisila-db__suberror">
                        {b.errorMessage}
                      </span>
                    )}
                  </TableCell>
                  <TableCell>
                    <div className="gisila-db__row-actions">
                      {b.status === "completed" && (
                        <>
                          <Button
                            kind="ghost"
                            size="sm"
                            hasIconOnly
                            renderIcon={Download}
                            iconDescription="Download"
                            onClick={() => handleDownload(b)}
                          />
                          {canRestore && (
                            <Button
                              kind="ghost"
                              size="sm"
                              hasIconOnly
                              renderIcon={Reset}
                              iconDescription="Restore from this backup"
                              onClick={() => onRequest({ kind: "restore", backup: b })}
                            />
                          )}
                        </>
                      )}
                      <Button
                        kind="danger--ghost"
                        size="sm"
                        hasIconOnly
                        renderIcon={TrashCan}
                        iconDescription="Delete backup"
                        onClick={() => onRequest({ kind: "delete", backup: b })}
                      />
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </TableContainer>
      )}
    </Stack>
  );
}

function ScheduleEditor({
  schedKey,
  schedule,
  scopes,
}: {
  schedKey: string;
  schedule?: PgBackupSchedule;
  scopes: PgBackupScope[];
}) {
  const [enabled, setEnabled] = useState(false);
  const [frequency, setFrequency] = useState<PgBackupFrequency>("daily");
  const [hour, setHour] = useState(2);
  const [minute, setMinute] = useState(0);
  const [weekday, setWeekday] = useState(0);
  const [scope, setScope] = useState<PgBackupScope>("full");
  const [keepCount, setKeepCount] = useState(7);
  const [saving, setSaving] = useState(false);

  // Seed local state whenever the fetched schedule changes.
  useEffect(() => {
    if (!schedule) return;
    setEnabled(schedule.enabled);
    setFrequency(schedule.frequency);
    setHour(schedule.hour);
    setMinute(schedule.minute);
    setWeekday(schedule.weekday ?? 0);
    setScope(schedule.scope);
    setKeepCount(schedule.keepCount);
  }, [schedule]);

  async function handleSave() {
    setSaving(true);
    try {
      await api(schedKey, {
        method: "PUT",
        body: JSON.stringify({
          enabled,
          frequency,
          hour,
          minute,
          weekday,
          scope,
          keepCount,
        }),
      });
      mutate(schedKey);
    } catch (e: unknown) {
      alert(e instanceof Error ? e.message : "Failed to save schedule.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <Tile>
      <Stack gap={5}>
        <Toggle
          id="backup-schedule-enabled"
          labelText="Scheduled backups"
          labelA="Disabled"
          labelB="Enabled"
          toggled={enabled}
          onToggle={setEnabled}
        />

        {enabled && (
          <>
            <div className="gisila-db__form-grid">
              <Select
                id="backup-frequency"
                labelText="Frequency"
                value={frequency}
                onChange={(e) => setFrequency(e.target.value as PgBackupFrequency)}
              >
                <SelectItem value="hourly" text="Hourly" />
                <SelectItem value="daily" text="Daily" />
                <SelectItem value="weekly" text="Weekly" />
              </Select>

              <Select
                id="backup-schedule-scope"
                labelText="Scope"
                value={scope}
                onChange={(e) => setScope(e.target.value as PgBackupScope)}
              >
                {scopes.map((s) => (
                  <SelectItem key={s} value={s} text={SCOPE_LABEL[s]} />
                ))}
              </Select>

              {frequency === "weekly" && (
                <Select
                  id="backup-weekday"
                  labelText="Day of week"
                  value={String(weekday)}
                  onChange={(e) => setWeekday(Number(e.target.value))}
                >
                  {WEEKDAYS.map((d, i) => (
                    <SelectItem key={i} value={String(i)} text={d} />
                  ))}
                </Select>
              )}

              {frequency !== "hourly" && (
                <div style={{ display: "flex", alignItems: "flex-end", gap: "0.5rem" }}>
                  <NumberInput
                    id="backup-hour"
                    label="Time (UTC)"
                    min={0}
                    max={23}
                    value={hour}
                    onChange={(_evt, { value }) => setHour(Number(value))}
                  />
                  <NumberInput
                    id="backup-minute"
                    label="Minute"
                    min={0}
                    max={59}
                    value={minute}
                    onChange={(_evt, { value }) => setMinute(Number(value))}
                  />
                </div>
              )}

              {frequency === "hourly" && (
                <NumberInput
                  id="backup-minute-hourly"
                  label="Minute past the hour"
                  min={0}
                  max={59}
                  value={minute}
                  onChange={(_evt, { value }) => setMinute(Number(value))}
                />
              )}

              <NumberInput
                id="backup-keep-count"
                label="Keep last (backups)"
                min={1}
                max={365}
                value={keepCount}
                onChange={(_evt, { value }) => setKeepCount(Number(value))}
              />
            </div>

            {schedule?.nextRunAt && (
              <p className="gisila-db__hint">
                Next run: {formatDate(schedule.nextRunAt)}
              </p>
            )}
          </>
        )}

        <div
          style={{
            display: "flex",
            alignItems: "center",
            justifyContent: "flex-end",
            gap: "0.5rem",
          }}
        >
          {saving && <InlineLoading description="Saving…" />}
          <Button size="sm" onClick={handleSave} disabled={saving}>
            Save schedule
          </Button>
        </div>
      </Stack>
    </Tile>
  );
}
