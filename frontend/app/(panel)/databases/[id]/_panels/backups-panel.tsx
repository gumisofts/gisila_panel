"use client";

import { useEffect, useRef, useState } from "react";
import useSWR, { mutate } from "swr";
import {
  Loader,
  Download,
  Trash2,
  RotateCcw,
  Upload,
  HardDriveDownload,
  Clock,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
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

// Minimal shape shared by Postgres and Mongo database rows — the backups panel
// only needs an id + a display name.
type BackupDb = { id: ID; dbName: string };

const SCOPE_LABEL: Record<PgBackupScope, string> = {
  full: "Full (schema + data)",
  schema: "Schema only",
  data: "Data only",
};

const STATUS_VARIANT: Record<
  PgBackup["status"],
  "default" | "secondary" | "destructive" | "outline"
> = {
  pending: "secondary",
  running: "secondary",
  completed: "outline",
  failed: "destructive",
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
}: {
  instanceId: string;
  db: BackupDb | null;
  onClose: () => void;
  apiBase?: string;
  scopes?: PgBackupScope[];
  uploadAccept?: string;
  uploadNote?: string;
}) {
  const open = !!db;
  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="sm:max-w-2xl">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <HardDriveDownload className="h-4 w-4 text-muted-foreground" />
            Backups — {db?.dbName}
          </DialogTitle>
        </DialogHeader>
        {db && (
          <BackupsBody
            instanceId={instanceId}
            db={db}
            apiBase={apiBase}
            scopes={scopes}
            uploadAccept={uploadAccept}
            uploadNote={uploadNote}
          />
        )}
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>
            Close
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function BackupsBody({
  instanceId,
  db,
  apiBase,
  scopes,
  uploadAccept,
  uploadNote,
}: {
  instanceId: string;
  db: BackupDb;
  apiBase: string;
  scopes: PgBackupScope[];
  uploadAccept: string;
  uploadNote: string;
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
  const fileRef = useRef<HTMLInputElement>(null);
  const [uploading, setUploading] = useState(false);

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

  async function handleRestore(b: PgBackup) {
    if (
      !confirm(
        `Restore ${db.dbName} from this backup?\n\nThis loads the dump into the existing database and may overwrite current data. This cannot be undone.`,
      )
    )
      return;
    try {
      await api(`${apiBase}/${instanceId}/dbs/${db.id}/restore`, {
        method: "POST",
        body: JSON.stringify({ backupId: b.id }),
      });
      alert("Restore queued. It will run in the background.");
    } catch (e: unknown) {
      alert(e instanceof Error ? e.message : "Restore failed.");
    }
  }

  async function handleDelete(b: PgBackup) {
    if (!confirm("Delete this backup file? This cannot be undone.")) return;
    try {
      await api(`${listKey}/${b.id}`, { method: "DELETE" });
      mutate(listKey);
    } catch (e: unknown) {
      alert(e instanceof Error ? e.message : "Delete failed.");
    }
  }

  async function handleUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    if (
      !confirm(
        `Restore ${db.dbName} from "${file.name}"?\n\nThis loads the dump into the existing database and may overwrite current data.`,
      )
    ) {
      if (fileRef.current) fileRef.current.value = "";
      return;
    }
    setUploading(true);
    try {
      await uploadFile(
        `${apiBase}/${instanceId}/dbs/${db.id}/restore-upload`,
        file,
      );
      alert("Upload received. Restore queued in the background.");
    } catch (err: unknown) {
      alert(err instanceof Error ? err.message : "Upload failed.");
    } finally {
      setUploading(false);
      if (fileRef.current) fileRef.current.value = "";
    }
  }

  return (
    <div className="space-y-5 py-1">
      {/* Back up now */}
      <div className="flex items-end gap-2">
        <div className="flex-1 space-y-1.5">
          <Label className="text-xs">Back up now</Label>
          <Select value={scope} onValueChange={(v) => setScope(v as PgBackupScope)}>
            <SelectTrigger>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {scopes.map((s) => (
                <SelectItem key={s} value={s}>{SCOPE_LABEL[s]}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <Button onClick={handleBackup} disabled={backingUp}>
          {backingUp ? (
            <Loader className="mr-1.5 h-3.5 w-3.5 animate-spin" />
          ) : (
            <HardDriveDownload className="mr-1.5 h-3.5 w-3.5" />
          )}
          Back up
        </Button>
      </div>
      {error && <p className="text-sm text-destructive">{error}</p>}

      {/* Schedule */}
      <ScheduleEditor schedKey={schedKey} schedule={schedule} scopes={scopes} />

      {/* Restore from file */}
      <div className="space-y-1.5">
        <Label className="text-xs flex items-center gap-1.5">
          <Upload className="h-3.5 w-3.5 text-muted-foreground" />
          Restore from a file
        </Label>
        <input
          ref={fileRef}
          type="file"
          accept={uploadAccept}
          onChange={handleUpload}
          disabled={uploading}
          className="block w-full text-xs text-muted-foreground file:mr-3 file:rounded-md file:border file:border-input file:bg-background file:px-3 file:py-1.5 file:text-xs file:font-medium hover:file:bg-accent"
        />
        <p className="text-[11px] text-muted-foreground">{uploadNote}</p>
      </div>

      {/* Backups list */}
      <div className="space-y-2">
        <Label className="text-xs">Backups</Label>
        {backups.length === 0 ? (
          <p className="text-sm text-muted-foreground">No backups yet.</p>
        ) : (
          <div className="space-y-1.5 max-h-64 overflow-y-auto">
            {backups.map((b) => (
              <div
                key={b.id}
                className="flex items-center gap-3 rounded-md border px-3 py-2"
              >
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <span className="text-xs font-medium">
                      {formatDate(b.createdAt)}
                    </span>
                    <Badge variant={STATUS_VARIANT[b.status]} className="text-[10px] py-0">
                      {b.status === "running" || b.status === "pending" ? (
                        <Loader className="mr-1 h-2.5 w-2.5 animate-spin" />
                      ) : null}
                      {b.status}
                    </Badge>
                    {b.trigger === "scheduled" && (
                      <Badge variant="secondary" className="text-[10px] py-0">
                        scheduled
                      </Badge>
                    )}
                  </div>
                  <p className="text-[11px] text-muted-foreground">
                    {SCOPE_LABEL[b.scope]} · {formatSize(b.sizeBytes)}
                    {b.errorMessage ? (
                      <span className="text-destructive"> · {b.errorMessage}</span>
                    ) : null}
                  </p>
                </div>
                <div className="flex items-center gap-1 shrink-0">
                  {b.status === "completed" && (
                    <>
                      <Button
                        size="icon"
                        variant="ghost"
                        className="h-7 w-7 text-muted-foreground"
                        title="Download"
                        onClick={() => handleDownload(b)}
                      >
                        <Download className="h-3.5 w-3.5" />
                      </Button>
                      <Button
                        size="icon"
                        variant="ghost"
                        className="h-7 w-7 text-muted-foreground"
                        title="Restore from this backup"
                        onClick={() => handleRestore(b)}
                      >
                        <RotateCcw className="h-3.5 w-3.5" />
                      </Button>
                    </>
                  )}
                  <Button
                    size="icon"
                    variant="ghost"
                    className="h-7 w-7 text-muted-foreground hover:text-destructive"
                    title="Delete backup"
                    onClick={() => handleDelete(b)}
                  >
                    <Trash2 className="h-3.5 w-3.5" />
                  </Button>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
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
    <Card>
      <CardContent className="space-y-3 py-3">
        <div className="flex items-center justify-between">
          <Label className="text-xs flex items-center gap-1.5">
            <Clock className="h-3.5 w-3.5 text-muted-foreground" />
            Scheduled backups
          </Label>
          <Select
            value={enabled ? "on" : "off"}
            onValueChange={(v) => setEnabled(v === "on")}
          >
            <SelectTrigger className="h-7 w-28">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="off">Disabled</SelectItem>
              <SelectItem value="on">Enabled</SelectItem>
            </SelectContent>
          </Select>
        </div>

        {enabled && (
          <>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1">
                <Label className="text-[11px]">Frequency</Label>
                <Select
                  value={frequency}
                  onValueChange={(v) => setFrequency(v as PgBackupFrequency)}
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="hourly">Hourly</SelectItem>
                    <SelectItem value="daily">Daily</SelectItem>
                    <SelectItem value="weekly">Weekly</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1">
                <Label className="text-[11px]">Scope</Label>
                <Select value={scope} onValueChange={(v) => setScope(v as PgBackupScope)}>
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {scopes.map((s) => (
                      <SelectItem key={s} value={s}>{SCOPE_LABEL[s]}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

              {frequency === "weekly" && (
                <div className="space-y-1">
                  <Label className="text-[11px]">Day of week</Label>
                  <Select
                    value={String(weekday)}
                    onValueChange={(v) => setWeekday(Number(v))}
                  >
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {WEEKDAYS.map((d, i) => (
                        <SelectItem key={i} value={String(i)}>
                          {d}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              )}

              {frequency !== "hourly" && (
                <div className="space-y-1">
                  <Label className="text-[11px]">Time (UTC)</Label>
                  <div className="flex items-center gap-1">
                    <Input
                      type="number"
                      min={0}
                      max={23}
                      value={hour}
                      onChange={(e) => setHour(Number(e.target.value))}
                      className="h-9"
                    />
                    <span className="text-muted-foreground">:</span>
                    <Input
                      type="number"
                      min={0}
                      max={59}
                      value={minute}
                      onChange={(e) => setMinute(Number(e.target.value))}
                      className="h-9"
                    />
                  </div>
                </div>
              )}

              {frequency === "hourly" && (
                <div className="space-y-1">
                  <Label className="text-[11px]">Minute past the hour</Label>
                  <Input
                    type="number"
                    min={0}
                    max={59}
                    value={minute}
                    onChange={(e) => setMinute(Number(e.target.value))}
                    className="h-9"
                  />
                </div>
              )}

              <div className="space-y-1">
                <Label className="text-[11px]">Keep last (backups)</Label>
                <Input
                  type="number"
                  min={1}
                  max={365}
                  value={keepCount}
                  onChange={(e) => setKeepCount(Number(e.target.value))}
                  className="h-9"
                />
              </div>
            </div>

            {schedule?.nextRunAt && (
              <p className="text-[11px] text-muted-foreground">
                Next run: {formatDate(schedule.nextRunAt)}
              </p>
            )}
          </>
        )}

        <div className="flex justify-end">
          <Button size="sm" onClick={handleSave} disabled={saving}>
            {saving && <Loader className="mr-1.5 h-3.5 w-3.5 animate-spin" />}
            Save schedule
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
