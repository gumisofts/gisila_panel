"use client";

import { useEffect, useState } from "react";
import useSWR, { mutate } from "swr";
import { toast } from "@/lib/toast";
import { Reset, SettingsAdjust } from "@carbon/icons-react";
import {
  Button,
  InlineLoading,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableHeader,
  TableRow,
  TextInput,
  Tile,
} from "@carbon/react";
import { PageSection } from "@/components/page";
import { api, fetcher } from "@/lib/api";
import "../../_databases.scss";

interface PgSetting {
  name: string;
  value: string;
  unit?: string | null;
  description?: string | null;
  context?: string | null;
  pendingRestart?: boolean;
}

interface ConfigResponse {
  status: "ok" | "initializing" | "not_running";
  settings: PgSetting[];
}

const HEADING = (
  <span className="gisila-db__icon-title">
    <SettingsAdjust size={16} />
    Configuration
  </span>
);

export function ConfigPanel({
  id,
  running,
  apiBase = "/databases",
  note = "Changing these runs ALTER SYSTEM and restarts the cluster. Leave a field blank to reset it to the Postgres default.",
}: {
  id: string;
  running: boolean;
  apiBase?: string;
  note?: string;
}) {
  const key = running ? `${apiBase}/${id}/config` : null;
  const { data } = useSWR<ConfigResponse>(key, fetcher, { refreshInterval: 0 });
  const [edits, setEdits] = useState<Record<string, string>>({});
  const [saving, setSaving] = useState(false);

  // Reset local edits whenever fresh server values arrive.
  useEffect(() => {
    setEdits({});
  }, [data]);

  if (!running) return null;

  if (!data || data.status === "initializing") {
    return (
      <PageSection title={HEADING}>
        <Tile>
          <InlineLoading description="Loading settings…" />
        </Tile>
      </PageSection>
    );
  }

  const dirty = Object.keys(edits).length > 0;

  async function save() {
    setSaving(true);
    try {
      await api(`${apiBase}/${id}/config`, {
        method: "PUT",
        body: JSON.stringify({ settings: edits }),
      });
      toast.success("Settings applied — the instance is restarting.");
      setEdits({});
      mutate(`${apiBase}/${id}`);
      // Give the restart a moment, then refresh the config view.
      setTimeout(() => mutate(key), 4000);
    } catch (e: unknown) {
      toast.error(e instanceof Error ? e.message : "Failed to apply settings");
    } finally {
      setSaving(false);
    }
  }

  return (
    <PageSection
      title={HEADING}
      description={note}
      actions={
        <>
          {saving && <InlineLoading description="Applying…" />}
          {dirty && (
            <Button size="sm" kind="ghost" renderIcon={Reset} onClick={() => setEdits({})}>
              Reset
            </Button>
          )}
          <Button size="sm" onClick={save} disabled={!dirty || saving}>
            Apply &amp; restart
          </Button>
        </>
      }
    >
      <TableContainer>
        <Table size="lg">
          <TableHead>
            <TableRow>
              <TableHeader>Setting</TableHeader>
              <TableHeader>Value</TableHeader>
            </TableRow>
          </TableHead>
          <TableBody>
            {data.settings.map((s) => {
              const current = edits[s.name] ?? s.value ?? "";
              const changed = s.name in edits && edits[s.name] !== s.value;
              return (
                <TableRow key={s.name}>
                  <TableCell>
                    <span className="gisila-db__setting-name">
                      {s.name}
                      {s.unit ? (
                        <span className="gisila-db__hint"> ({s.unit})</span>
                      ) : null}
                    </span>
                    {s.description && (
                      <span className="gisila-db__subnote">{s.description}</span>
                    )}
                  </TableCell>
                  <TableCell>
                    <TextInput
                      id={`config-${id}-${s.name}`}
                      labelText={`${s.name} value`}
                      hideLabel
                      size="sm"
                      value={current}
                      className={changed ? "gisila-db__input--changed" : undefined}
                      onChange={(e) =>
                        setEdits((prev) => ({ ...prev, [s.name]: e.target.value }))
                      }
                    />
                  </TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      </TableContainer>
    </PageSection>
  );
}
