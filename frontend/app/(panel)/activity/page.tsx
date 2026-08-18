"use client";

import { useState } from "react";
import useSWR from "swr";
import {
  Activity,
  Add,
  Edit,
  PlayFilled,
  Renew,
  Rocket,
  StopFilled,
  Terminal,
  TrashCan,
  Undo,
  UserFollow,
} from "@carbon/icons-react";
import {
  Pagination,
  StructuredListBody,
  StructuredListCell,
  StructuredListRow,
  StructuredListSkeleton,
  StructuredListWrapper,
  Tile,
} from "@carbon/react";
import { Page, PageHeader } from "@/components/page";
import { fetcher } from "@/lib/api";
import { formatRelative } from "@/lib/utils";
import type { AuditLog, ListResponse } from "@/lib/types";

const PAGE_SIZES = [10, 25, 50, 100];

export default function ActivityPage() {
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(25);
  const offset = (page - 1) * pageSize;

  const { data, isLoading } = useSWR<ListResponse<AuditLog>>(
    `/audit/?limit=${pageSize}&offset=${offset}`,
    fetcher,
    // Auto-refresh only the first page — polling while offset > 0 would
    // shift older entries out from under whatever the user is reading as
    // newer activity pushes the page boundaries around.
    { refreshInterval: page === 1 ? 10000 : 0 },
  );
  const items = data?.results ?? [];
  const totalItems = data?.count ?? items.length;

  return (
    <Page>
      <PageHeader
        title="Activity"
        description="Every action you've performed across the panel, most recent first."
      />

      {isLoading && <StructuredListSkeleton rowCount={8} />}

      {!isLoading && items.length === 0 && (
        <Tile className="gisila-empty">No activity yet.</Tile>
      )}

      {items.length > 0 && (
        <>
          <StructuredListWrapper aria-label="Activity log" isCondensed>
            <StructuredListBody>
              {items.map((entry) => (
                <ActivityRow key={entry.id} entry={entry} />
              ))}
            </StructuredListBody>
          </StructuredListWrapper>

          <Pagination
            page={page}
            pageSize={pageSize}
            pageSizes={PAGE_SIZES}
            totalItems={totalItems}
            onChange={({ page: nextPage, pageSize: nextPageSize }) => {
              // Changing page size makes the old page number meaningless —
              // land back on page 1 instead of an arbitrary offset into it.
              if (nextPageSize !== pageSize) {
                setPageSize(nextPageSize);
                setPage(1);
              } else {
                setPage(nextPage);
              }
            }}
          />
        </>
      )}
    </Page>
  );
}

function ActivityRow({ entry }: { entry: AuditLog }) {
  const { icon: Icon, tone } = iconFor(entry.action);
  return (
    <StructuredListRow>
      <StructuredListCell className="gisila-activity__icon-cell">
        <span className={`gisila-status-icon gisila-status-icon--${tone}`}>
          <Icon size={16} />
        </span>
      </StructuredListCell>
      <StructuredListCell className="gisila-activity__detail">
        <span>{describe(entry)}</span>
        {entry.ipAddress && (
          <span className="gisila-activity__meta">{entry.ipAddress}</span>
        )}
      </StructuredListCell>
      <StructuredListCell className="gisila-activity__time">
        {formatRelative(entry.createdAt)}
      </StructuredListCell>
    </StructuredListRow>
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
      return { icon: Add, tone: "success" };
    case "delete":
      return { icon: TrashCan, tone: "danger" };
    case "update":
    case "env.set":
    case "env.unset":
      return { icon: Edit, tone: "info" };
    case "start":
      return { icon: PlayFilled, tone: "success" };
    case "stop":
      return { icon: StopFilled, tone: "neutral" };
    case "restart":
      return { icon: Renew, tone: "warning" };
    case "deploy":
      return { icon: Rocket, tone: "brand" };
    case "exec":
      return { icon: Terminal, tone: "info" };
    case "rollback":
      return { icon: Undo, tone: "warning" };
    case "invite":
      return { icon: UserFollow, tone: "info" };
    default:
      return { icon: Activity, tone: "neutral" };
  }
}
