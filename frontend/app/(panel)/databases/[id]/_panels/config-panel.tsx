"use client";

import { useEffect, useState } from "react";
import useSWR, { mutate } from "swr";
import { toast } from "sonner";
import { Settings2, Loader, RotateCcw } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { api, fetcher } from "@/lib/api";

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

export function ConfigPanel({ id, running }: { id: string; running: boolean }) {
  const key = running ? `/databases/${id}/config` : null;
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
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-sm">
            <Settings2 className="h-4 w-4 text-muted-foreground" /> Configuration
          </CardTitle>
        </CardHeader>
        <CardContent className="flex items-center gap-2 py-6 text-sm text-muted-foreground">
          <Loader className="h-4 w-4 animate-spin" /> Loading settings…
        </CardContent>
      </Card>
    );
  }

  const dirty = Object.keys(edits).length > 0;

  async function save() {
    setSaving(true);
    try {
      await api(`/databases/${id}/config`, {
        method: "PUT",
        body: JSON.stringify({ settings: edits }),
      });
      toast.success("Settings applied — the instance is restarting.");
      setEdits({});
      mutate(`/databases/${id}`);
      // Give the restart a moment, then refresh the config view.
      setTimeout(() => mutate(key), 4000);
    } catch (e: unknown) {
      toast.error(e instanceof Error ? e.message : "Failed to apply settings");
    } finally {
      setSaving(false);
    }
  }

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0">
        <CardTitle className="flex items-center gap-2 text-sm">
          <Settings2 className="h-4 w-4 text-muted-foreground" /> Configuration
        </CardTitle>
        <div className="flex items-center gap-2">
          {dirty && (
            <Button size="sm" variant="ghost" onClick={() => setEdits({})}>
              <RotateCcw className="mr-1.5 h-3.5 w-3.5" /> Reset
            </Button>
          )}
          <Button size="sm" onClick={save} disabled={!dirty || saving}>
            {saving && <Loader className="mr-1.5 h-3.5 w-3.5 animate-spin" />}
            Apply &amp; restart
          </Button>
        </div>
      </CardHeader>
      <CardContent className="space-y-3">
        <p className="text-xs text-muted-foreground">
          Changing these runs <code>ALTER SYSTEM</code> and restarts the cluster.
          Leave a field blank to reset it to the Postgres default.
        </p>
        <div className="divide-y divide-border/60">
          {data.settings.map((s) => {
            const current = edits[s.name] ?? s.value ?? "";
            const changed = s.name in edits && edits[s.name] !== s.value;
            return (
              <div key={s.name} className="grid grid-cols-1 gap-2 py-3 sm:grid-cols-2 sm:items-center">
                <div className="min-w-0">
                  <p className="font-mono text-sm">
                    {s.name}
                    {s.unit ? (
                      <span className="ml-1 text-xs text-muted-foreground">({s.unit})</span>
                    ) : null}
                  </p>
                  {s.description && (
                    <p className="truncate text-xs text-muted-foreground">{s.description}</p>
                  )}
                </div>
                <Input
                  value={current}
                  className={changed ? "border-primary" : ""}
                  onChange={(e) =>
                    setEdits((prev) => ({ ...prev, [s.name]: e.target.value }))
                  }
                />
              </div>
            );
          })}
        </div>
      </CardContent>
    </Card>
  );
}
