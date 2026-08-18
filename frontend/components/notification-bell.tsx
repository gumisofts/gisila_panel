"use client";

import { useState } from "react";
import useSWR, { mutate as globalMutate } from "swr";
import { Popover, PopoverContent, Button, SkeletonText } from "@carbon/react";
import {
  CheckmarkFilled,
  ErrorFilled,
  Notification as NotificationIcon,
  WarningAltFilled,
} from "@carbon/icons-react";
import { useRouter } from "@/compat/navigation";
import { api, fetcher } from "@/lib/api";
import { formatRelative } from "@/lib/utils";
import type { AppNotification, ListResponse, NotificationLevel } from "@/lib/types";

const INBOX_PATH = "/notifications/inbox?limit=8";
const UNREAD_COUNT_PATH = "/notifications/inbox/unread-count";

function levelIcon(level: NotificationLevel) {
  switch (level) {
    case "critical":
      return <ErrorFilled className="gisila-bell__icon gisila-bell__icon--critical" />;
    case "warning":
      return <WarningAltFilled className="gisila-bell__icon gisila-bell__icon--warning" />;
    default:
      return <CheckmarkFilled className="gisila-bell__icon gisila-bell__icon--info" />;
  }
}

/// Bell icon in the header global bar. Polls the unread count continuously so
/// the badge stays fresh even while the panel is idle; the recent-items list
/// is only fetched while the dropdown is open.
export function NotificationBell() {
  const [open, setOpen] = useState(false);
  const router = useRouter();

  const { data: unread } = useSWR<{ count: number }>(
    UNREAD_COUNT_PATH,
    fetcher,
    { refreshInterval: 15000 },
  );
  const { data, isLoading } = useSWR<ListResponse<AppNotification>>(
    open ? INBOX_PATH : null,
    fetcher,
    { refreshInterval: open ? 10000 : 0 },
  );

  const count = unread?.count ?? 0;
  const items = data?.results ?? [];

  async function markRead(item: AppNotification) {
    if (item.readAt) return;
    try {
      await api(`/notifications/inbox/${item.id}/read`, { method: "POST" });
      globalMutate(INBOX_PATH);
      globalMutate(UNREAD_COUNT_PATH);
    } catch {
      /* non-critical — badge will settle on next poll */
    }
  }

  async function markAllRead() {
    try {
      await api("/notifications/inbox/read-all", { method: "POST" });
      globalMutate(INBOX_PATH);
      globalMutate(UNREAD_COUNT_PATH);
    } catch {
      /* non-critical */
    }
  }

  function viewAll() {
    setOpen(false);
    router.push("/notifications");
  }

  return (
    <Popover
      open={open}
      onRequestClose={() => setOpen(false)}
      align="bottom-right"
      dropShadow
      caret={false}
    >
      <button
        type="button"
        className="gisila-bell"
        aria-label={count > 0 ? `${count} unread notifications` : "Notifications"}
        onClick={() => setOpen((v) => !v)}
      >
        <NotificationIcon size={20} />
        {count > 0 && (
          <span className="gisila-bell__badge">{count > 9 ? "9+" : count}</span>
        )}
      </button>
      <PopoverContent className="gisila-bell__panel">
        <div className="gisila-bell__header">
          <span className="gisila-bell__title">Notifications</span>
          {count > 0 && (
            <Button kind="ghost" size="sm" onClick={markAllRead}>
              Mark all read
            </Button>
          )}
        </div>

        <div className="gisila-bell__list">
          {isLoading && (
            <div className="gisila-bell__loading">
              <SkeletonText paragraph lineCount={3} />
            </div>
          )}

          {!isLoading && items.length === 0 && (
            <p className="gisila-bell__empty">You&apos;re all caught up.</p>
          )}

          {items.map((item) => (
            <button
              key={item.id}
              type="button"
              className={
                item.readAt
                  ? "gisila-bell__item"
                  : "gisila-bell__item gisila-bell__item--unread"
              }
              onClick={() => markRead(item)}
            >
              {levelIcon(item.level)}
              <span className="gisila-bell__item-body">
                <span className="gisila-bell__item-title">{item.title}</span>
                {item.body && (
                  <span className="gisila-bell__item-text">{item.body}</span>
                )}
                <span className="gisila-bell__item-time">
                  {formatRelative(item.createdAt)}
                </span>
              </span>
            </button>
          ))}
        </div>

        <div className="gisila-bell__footer">
          <Button kind="ghost" size="sm" onClick={viewAll}>
            View all notifications
          </Button>
        </div>
      </PopoverContent>
    </Popover>
  );
}
