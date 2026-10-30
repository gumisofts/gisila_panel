import { useEffect, useState } from "react";
import useSWR from "swr";
import {
  Button,
  InlineNotification,
  NumberInput,
  Stack,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableHeader,
  TableRow,
  Tag,
  TextInput,
  Tile,
  Toggle,
} from "@carbon/react";
import { Add, Edit, PlayFilled, Time, TrashCan } from "@carbon/icons-react";
import { confirmDialog } from "@/components/confirm-dialog";
import { api, fetcher } from "@/lib/api";
import { usePermissions } from "@/lib/permissions";
import { toast } from "@/lib/toast";
import type { App } from "@/lib/types";
import "../_app-detail.scss";

interface CronJob {
  id: number;
  name: string;
  schedule: string;
  command: string;
  timeoutSeconds: number;
  enabled: boolean;
  nextRunAt: string | null;
  lastRunAt: string | null;
  lastStatus: string | null;
}

interface CronRun {
  id: number;
  trigger: string;
  status: string;
  exitCode: number | null;
  output: string | null;
  startedAt: string;
  finishedAt: string | null;
}

const STATUS_TAG: Record<string, "green" | "red" | "blue" | "magenta" | "cool-gray"> = {
  succeeded: "green",
  failed: "red",
  timed_out: "magenta",
  running: "blue",
  skipped: "cool-gray",
};

function StatusTag({ status }: { status: string | null }) {
  if (!status) return <span className="gisila-app__hint">never run</span>;
  return (
    <Tag type={STATUS_TAG[status] ?? "cool-gray"} size="sm">
      {status.replace("_", " ")}
    </Tag>
  );
}

function when(iso: string | null): string {
  return iso ? new Date(iso).toLocaleString() : "—";
}

interface Draft {
  name: string;
  schedule: string;
  command: string;
  timeoutSeconds: number;
}

const EMPTY: Draft = { name: "", schedule: "0 3 * * *", command: "", timeoutSeconds: 300 };

/// Create or edit one job, with a live preview of the next runs.
function JobForm({
  appId,
  initial,
  jobId,
  onDone,
}: {
  appId: number;
  initial: Draft;
  jobId?: number;
  onDone: () => void;
}) {
  const [draft, setDraft] = useState(initial);
  const [saving, setSaving] = useState(false);
  const [preview, setPreview] = useState<{ next?: string[]; error?: string }>({});

  useEffect(() => {
    const schedule = draft.schedule.trim();
    if (!schedule) return setPreview({});
    const t = setTimeout(async () => {
      try {
        const res = await api<{ next: string[] }>(
          `/apps/${appId}/cron/preview?schedule=${encodeURIComponent(schedule)}`,
        );
        setPreview({ next: res.next });
      } catch (err: unknown) {
        setPreview({ error: err instanceof Error ? err.message : "Invalid schedule." });
      }
    }, 300);
    return () => clearTimeout(t);
  }, [appId, draft.schedule]);

  async function save() {
    setSaving(true);
    try {
      await api(jobId ? `/apps/${appId}/cron/${jobId}` : `/apps/${appId}/cron`, {
        method: jobId ? "PATCH" : "POST",
        body: JSON.stringify(draft),
      });
      toast.success(jobId ? "Cron job saved." : "Cron job created.");
      onDone();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed to save.");
    } finally {
      setSaving(false);
    }
  }

  const set = <K extends keyof Draft>(k: K, v: Draft[K]) =>
    setDraft((d) => ({ ...d, [k]: v }));

  return (
    <Tile>
      <Stack gap={5}>
        <h3 className="gisila-app__tile-title">{jobId ? "Edit cron job" : "New cron job"}</h3>
        <TextInput
          id="cron-name"
          labelText="Name"
          placeholder="Nightly cleanup"
          value={draft.name}
          onChange={(e) => set("name", e.target.value)}
        />
        <TextInput
          id="cron-schedule"
          labelText="Schedule (UTC)"
          helperText={
            preview.next?.length
              ? `Next: ${preview.next.slice(0, 3).map((t) => new Date(t).toLocaleString()).join(" · ")}`
              : "minute hour day-of-month month day-of-week, e.g. */15 * * * * or @daily"
          }
          invalid={!!preview.error}
          invalidText={preview.error}
          value={draft.schedule}
          onChange={(e) => set("schedule", e.target.value)}
        />
        <TextInput
          id="cron-command"
          labelText="Command"
          helperText="Runs like a Console command: as the app's user, in its directory, with its environment variables."
          placeholder="./bin/cleanup --older-than 30d"
          value={draft.command}
          onChange={(e) => set("command", e.target.value)}
        />
        <NumberInput
          id="cron-timeout"
          label="Timeout (seconds)"
          min={1}
          max={3600}
          value={draft.timeoutSeconds}
          onChange={(_e, { value }) => set("timeoutSeconds", Number(value) || 300)}
        />
        <div className="gisila-app__row-actions">
          <Button
            size="sm"
            disabled={saving || !draft.name.trim() || !draft.command.trim() || !!preview.error}
            onClick={save}
          >
            {saving ? "Saving…" : "Save"}
          </Button>
          <Button size="sm" kind="ghost" onClick={onDone}>
            Cancel
          </Button>
        </div>
      </Stack>
    </Tile>
  );
}

/// Recent runs of one job; refreshes while one is running.
function RunHistory({ appId, jobId }: { appId: number; jobId: number }) {
  const { data } = useSWR<{ results: CronRun[] }>(`/apps/${appId}/cron/${jobId}/runs`, fetcher, {
    refreshInterval: (latest) =>
      latest?.results.some((r) => r.status === "running") ? 3000 : 0,
  });
  const [open, setOpen] = useState<number | null>(null);
  const runs = data?.results ?? [];
  if (!data) return <p className="gisila-app__hint">Loading runs…</p>;
  if (runs.length === 0) return <p className="gisila-app__hint">No runs yet.</p>;
  return (
    <Stack gap={3}>
      {runs.map((r) => (
        <div key={r.id}>
          <Button kind="ghost" size="sm" onClick={() => setOpen(open === r.id ? null : r.id)}>
            <StatusTag status={r.status} /> {when(r.startedAt)} · {r.trigger}
            {r.exitCode != null ? ` · exit ${r.exitCode}` : ""}
          </Button>
          {open === r.id && (
            <div className="gisila-term">
              <pre className="gisila-term__body">{r.output || "(no output)"}</pre>
            </div>
          )}
        </div>
      ))}
    </Stack>
  );
}

export function CronTab({ app }: { app: App }) {
  const appId = app.id;
  const { canForProject } = usePermissions();
  const canManage = canForProject(app.projectId, "developer");
  const { data, mutate, error } = useSWR<{ results: CronJob[] }>(`/apps/${appId}/cron`, fetcher, {
    refreshInterval: 15000,
  });
  const [editing, setEditing] = useState<CronJob | "new" | null>(null);
  const [history, setHistory] = useState<number | null>(null);
  const jobs = data?.results ?? [];

  async function toggle(job: CronJob, enabled: boolean) {
    try {
      await api(`/apps/${appId}/cron/${job.id}`, {
        method: "PATCH",
        body: JSON.stringify({ enabled }),
      });
      await mutate();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed to update.");
    }
  }

  async function runNow(job: CronJob) {
    try {
      await api(`/apps/${appId}/cron/${job.id}/run`, { method: "POST" });
      toast.success(`Started "${job.name}".`);
      setHistory(job.id);
      await mutate();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed to start the run.");
    }
  }

  async function remove(job: CronJob) {
    if (!(await confirmDialog(`Delete the cron job "${job.name}" and its run history?`, { confirmLabel: "Delete" }))) {
      return;
    }
    try {
      await api(`/apps/${appId}/cron/${job.id}`, { method: "DELETE" });
      toast.success("Cron job deleted.");
      await mutate();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed to delete.");
    }
  }

  return (
    <Stack gap={6}>
      <Tile>
        <Stack gap={4}>
          <h3 className="gisila-app__tile-title">
            <Time /> Cron jobs
          </h3>
          <p className="gisila-app__hint">
            Run commands on a schedule (UTC), as the app's own user with its environment variables —
            the same way the Console runs them. A run is skipped while the previous one is still going.
          </p>
          {error && (
            <InlineNotification
              kind="error"
              lowContrast
              hideCloseButton
              title="Could not load cron jobs."
              subtitle={error instanceof Error ? error.message : undefined}
            />
          )}
          {canManage && !editing && (
            <div>
              <Button size="sm" kind="tertiary" renderIcon={Add} onClick={() => setEditing("new")}>
                New cron job
              </Button>
            </div>
          )}
        </Stack>
      </Tile>

      {editing && (
        <JobForm
          appId={appId}
          jobId={editing === "new" ? undefined : editing.id}
          initial={
            editing === "new"
              ? EMPTY
              : {
                  name: editing.name,
                  schedule: editing.schedule,
                  command: editing.command,
                  timeoutSeconds: editing.timeoutSeconds,
                }
          }
          onDone={() => {
            setEditing(null);
            void mutate();
          }}
        />
      )}

      {jobs.length > 0 && (
        <TableContainer>
          <Table size="md">
            <TableHead>
              <TableRow>
                <TableHeader>Job</TableHeader>
                <TableHeader>Schedule</TableHeader>
                <TableHeader>Next run</TableHeader>
                <TableHeader>Last run</TableHeader>
                <TableHeader>On</TableHeader>
                <TableHeader />
              </TableRow>
            </TableHead>
            <TableBody>
              {jobs.map((job) => (
                <TableRow key={job.id}>
                  <TableCell>
                    <strong>{job.name}</strong>
                    <br />
                    <code>{job.command}</code>
                  </TableCell>
                  <TableCell>
                    <code>{job.schedule}</code>
                  </TableCell>
                  <TableCell>{job.enabled ? when(job.nextRunAt) : "paused"}</TableCell>
                  <TableCell>
                    <StatusTag status={job.lastStatus} /> {job.lastRunAt ? when(job.lastRunAt) : ""}
                  </TableCell>
                  <TableCell>
                    <Toggle
                      id={`cron-on-${job.id}`}
                      size="sm"
                      hideLabel
                      labelText="Enabled"
                      toggled={job.enabled}
                      disabled={!canManage}
                      onToggle={(on) => toggle(job, on)}
                    />
                  </TableCell>
                  <TableCell>
                    {canManage && (
                      <div className="gisila-app__row-actions">
                        <Button kind="ghost" size="sm" hasIconOnly iconDescription="Run now" renderIcon={PlayFilled} onClick={() => runNow(job)} />
                        <Button kind="ghost" size="sm" onClick={() => setHistory(history === job.id ? null : job.id)}>
                          Runs
                        </Button>
                        <Button kind="ghost" size="sm" hasIconOnly iconDescription="Edit" renderIcon={Edit} onClick={() => setEditing(job)} />
                        <Button kind="ghost" size="sm" hasIconOnly iconDescription="Delete" renderIcon={TrashCan} onClick={() => remove(job)} />
                      </div>
                    )}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </TableContainer>
      )}

      {history != null && canManage && (
        <Tile>
          <h3 className="gisila-app__tile-title">
            Runs of {jobs.find((j) => j.id === history)?.name ?? "job"}
          </h3>
          <RunHistory appId={appId} jobId={history} />
        </Tile>
      )}

      {data && jobs.length === 0 && !editing && (
        <p className="gisila-app__hint">No cron jobs yet.</p>
      )}
    </Stack>
  );
}
