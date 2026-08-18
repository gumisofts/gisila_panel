"use client";

import { useEffect, useRef, useState } from "react";
import useSWR, { mutate as globalMutate } from "swr";
import { Popover, PopoverContent, Button, SkeletonText } from "@carbon/react";
import {
  CheckmarkFilled,
  ChevronDown,
  ChevronUp,
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

// How long an auto-opened (new-notification) popover stays up before it
// quietly closes itself again — long enough to notice, short enough to not
// linger and get in the way of whatever the user was doing.
const AUTO_OPEN_DURATION_MS = 8000;

// Whether the notification list is collapsed to just the header is a display
// preference, not session state — remembered across reloads so a user who
// finds the full list "annoying" only has to collapse it once.
const COLLAPSED_STORAGE_KEY = "gisila:notifications:collapsed";

function loadCollapsedPreference(): boolean {
  if (typeof window === "undefined") return false;
  return window.localStorage.getItem(COLLAPSED_STORAGE_KEY) === "1";
}

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
///
/// The panel opens two ways: a manual click always shows whatever the user's
/// collapsed/expanded preference is, while a rising unread count while the
/// user is already on the platform pops it open briefly in collapsed form —
/// just enough to notice a new alert without the full list shoving itself in
/// front of whatever they were doing.
export function NotificationBell() {
  const [open, setOpen] = useState(false);
  const [collapsed, setCollapsed] = useState(loadCollapsedPreference);
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

  // A new-notification pop-open always shows the collapsed, low-key form
  // regardless of the user's stored preference — `autoCollapsed` overlays
  // that until the user opens (or the auto-open times out and closes) the
  // panel again.
  const [autoCollapsed, setAutoCollapsed] = useState(false);
  const effectiveCollapsed = open && autoCollapsed ? true : collapsed;

  // Detect a rising unread count (a new notification landed) and pop the
  // panel open — but skip the very first load, where "previous" is unknown,
  // so simply opening the app doesn't look like a fresh notification.
  const prevCountRef = useRef<number | null>(null);
  const autoCloseTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    if (unread === undefined) return;
    const prev = prevCountRef.current;
    prevCountRef.current = unread.count;
    if (prev === null || unread.count <= prev) return;

    setOpen(true);
    setAutoCollapsed(true);
    if (autoCloseTimerRef.current) clearTimeout(autoCloseTimerRef.current);
    autoCloseTimerRef.current = setTimeout(() => {
      setOpen(false);
      setAutoCollapsed(false);
    }, AUTO_OPEN_DURATION_MS);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [unread?.count]);

  useEffect(() => {
    return () => {
      if (autoCloseTimerRef.current) clearTimeout(autoCloseTimerRef.current);
    };
  }, []);

  function toggleCollapsed() {
    setAutoCollapsed(false);
    setCollapsed((c) => {
      const next = !c;
      window.localStorage.setItem(COLLAPSED_STORAGE_KEY, next ? "1" : "0");
      return next;
    });
  }

  function handleBellClick() {
    setAutoCollapsed(false);
    if (autoCloseTimerRef.current) {
      clearTimeout(autoCloseTimerRef.current);
      autoCloseTimerRef.current = null;
    }
    setOpen((v) => !v);
  }

  function handleRequestClose() {
    setOpen(false);
    setAutoCollapsed(false);
    if (autoCloseTimerRef.current) {
      clearTimeout(autoCloseTimerRef.current);
      autoCloseTimerRef.current = null;
    }
  }

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
      onRequestClose={handleRequestClose}
      align="bottom-right"
      dropShadow
      caret={false}
    >
      <button
        type="button"
        className="gisila-bell"
        aria-label={count > 0 ? `${count} unread notifications` : "Notifications"}
        onClick={handleBellClick}
      >
        <NotificationIcon size={20} />
        {count > 0 && (
          <span className="gisila-bell__badge">{count > 9 ? "9+" : count}</span>
        )}
      </button>
      <PopoverContent
        className={
          effectiveCollapsed
            ? "gisila-bell__panel gisila-bell__panel--collapsed"
            : "gisila-bell__panel"
        }
      >
        <div className="gisila-bell__header">
          <span className="gisila-bell__title">
            Notifications
            {count > 0 && (
              <span className="gisila-bell__title-count">{count}</span>
            )}
          </span>
          <div className="gisila-bell__header-actions">
            {count > 0 && !effectiveCollapsed && (
              <Button kind="ghost" size="sm" onClick={markAllRead}>
                Mark all read
              </Button>
            )}
            <button
              type="button"
              className="gisila-bell__collapse-toggle"
              aria-label={effectiveCollapsed ? "Expand notifications" : "Collapse notifications"}
              onClick={toggleCollapsed}
            >
              {effectiveCollapsed ? <ChevronDown size={16} /> : <ChevronUp size={16} />}
            </button>
          </div>
        </div>

        {effectiveCollapsed ? (
          <button
            type="button"
            className="gisila-bell__summary"
            onClick={toggleCollapsed}
          >
            {count > 0
              ? `${count} unread notification${count === 1 ? "" : "s"} — click to view`
              : "You're all caught up."}
          </button>
        ) : (
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
        )}

        {!effectiveCollapsed && (
          <div className="gisila-bell__footer">
            <Button kind="ghost" size="sm" onClick={viewAll}>
              View all notifications
            </Button>
          </div>
        )}
      </PopoverContent>
    </Popover>
  );
}
