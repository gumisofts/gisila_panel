"use client";

import useSWR from "swr";
import {
  Activity,
  Pencil,
  Play,
  Plus,
  RotateCw,
  Rocket,
  Square,
  Terminal,
  Trash2,
  Undo2,
  UserPlus,
} from "lucide-react";
import { Card, CardContent } from "@/components/ui/card";
import { fetcher } from "@/lib/api";
import { formatRelative } from "@/lib/utils";
import type { AuditLog, ListResponse } from "@/lib/types";

export default function ActivityPage() {
  const { data, isLoading } = useSWR<ListResponse<AuditLog>>(
    "/audit/?limit=100",
    fetcher,
    { refreshInterval: 10000 },
  );
  const items = data?.results ?? [];

  return (
    <div className="container space-y-6 py-8">
      <header>
        <h1 className="text-2xl font-semibold tracking-tight">Activity</h1>
        <p className="text-sm text-muted-foreground">
          Every action you&apos;ve performed across the panel, most recent first.
        </p>
      </header>

      {!isLoading && items.length === 0 && (
        <Card>
          <CardContent className="py-12 text-center text-sm text-muted-foreground">
            No activity yet.
          </CardContent>
        </Card>
      )}

      {items.length > 0 && (
        <Card>
          <CardContent className="divide-y divide-border/60 p-0">
            {items.map((entry) => (
              <ActivityRow key={entry.id} entry={entry} />
            ))}
          </CardContent>
        </Card>
      )}
    </div>
  );
}

function ActivityRow({ entry }: { entry: AuditLog }) {
  const { icon: Icon, tone } = iconFor(entry.action);
  return (
    <div className="flex items-center gap-3 px-5 py-3">
      <span
        className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-lg ${tone}`}
      >
        <Icon className="h-4 w-4" />
      </span>
      <div className="min-w-0 flex-1">
        <p className="text-sm">{describe(entry)}</p>
        {entry.ipAddress && (
          <p className="font-mono text-[11px] text-muted-foreground">
            {entry.ipAddress}
          </p>
        )}
      </div>
      <span className="shrink-0 text-xs text-muted-foreground">
        {formatRelative(entry.createdAt)}
      </span>
    </div>
  );
}

// action is "<targetType>.<verb>", where verb may itself contain a dot
// (e.g. "app.env.set"). Everything after the first dot is the verb.
function splitAction(action: string): { target: string; verb: string } {
  const i = action.indexOf(".");
  if (i === -1) return { target: action, verb: "" };
  return { target: action.slice(0, i), verb: action.slice(i + 1) };
}

const VERB_LABELS: Record<string, string> = {
  create: "Created",
  update: "Updated",
  delete: "Removed",
  start: "Started",
  stop: "Stopped",
  restart: "Restarted",
  deploy: "Deployed",
  exec: "Ran a command on",
  rollback: "Rolled back",
  invite: "Invited a member to",
  "env.set": "Updated env vars on",
  "env.unset": "Removed an env var from",
};

function describe(entry: AuditLog): string {
  const { target, verb } = splitAction(entry.action);
  const label = VERB_LABELS[verb] ?? prettifyVerb(verb);
  const targetLabel = entry.targetId ? `${target} #${entry.targetId}` : target;
  return `${label} ${targetLabel}`;
}

function prettifyVerb(verb: string): string {
  if (!verb) return "Acted on";
  const words = verb.replace(/\./g, " ");
  return words.charAt(0).toUpperCase() + words.slice(1);
}

function iconFor(action: string): { icon: typeof Activity; tone: string } {
  const { verb } = splitAction(action);
  switch (verb) {
    case "create":
      return { icon: Plus, tone: "bg-emerald-500/15 text-emerald-500" };
    case "delete":
      return { icon: Trash2, tone: "bg-red-500/15 text-red-500" };
    case "update":
    case "env.set":
    case "env.unset":
      return { icon: Pencil, tone: "bg-blue-500/15 text-blue-500" };
    case "start":
      return { icon: Play, tone: "bg-emerald-500/15 text-emerald-500" };
    case "stop":
      return { icon: Square, tone: "bg-zinc-500/15 text-zinc-400" };
    case "restart":
      return { icon: RotateCw, tone: "bg-amber-500/15 text-amber-500" };
    case "deploy":
      return { icon: Rocket, tone: "bg-primary/15 text-primary" };
    case "exec":
      return { icon: Terminal, tone: "bg-violet-500/15 text-violet-500" };
    case "rollback":
      return { icon: Undo2, tone: "bg-amber-500/15 text-amber-500" };
    case "invite":
      return { icon: UserPlus, tone: "bg-blue-500/15 text-blue-500" };
    default:
      return { icon: Activity, tone: "bg-muted text-muted-foreground" };
  }
}
