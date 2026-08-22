"use client";

import { useState } from "react";
import useSWR, { mutate as mutateCache } from "swr";
import {
  CheckmarkFilled,
  ErrorFilled,
  Notification as NotificationIcon,
  WarningAltFilled,
} from "@carbon/icons-react";
import { Button, Pagination, Tile, Toggle } from "@carbon/react";
import { Page, PageHeader } from "@/components/page";
import { api, fetcher } from "@/lib/api";
import { formatRelative } from "@/lib/utils";
import type { AppNotification, ListResponse, NotificationLevel } from "@/lib/types";
import "./_notifications.scss";

const PAGE_SIZES = [10, 25, 50, 100];
const UNREAD_COUNT_PATH = "/notifications/inbox/unread-count";

function levelIcon(level: NotificationLevel) {
  switch (level) {
    case "critical":
      return <ErrorFilled size={20} className="gisila-inbox__icon gisila-inbox__icon--critical" />;
    case "warning":
      return <WarningAltFilled size={20} className="gisila-inbox__icon gisila-inbox__icon--warning" />;
    default:
      return <CheckmarkFilled size={20} className="gisila-inbox__icon gisila-inbox__icon--info" />;
  }
}

export default function NotificationsPage() {
  const [unreadOnly, setUnreadOnly] = useState(false);
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(25);
  const offset = (page - 1) * pageSize;
  const key = `/notifications/inbox?limit=${pageSize}&offset=${offset}${unreadOnly ? "&unreadOnly=true" : ""}`;

  const { data, isLoading, mutate } = useSWR<ListResponse<AppNotification>>(
    key,
    fetcher,
    // Auto-refresh only the first page — polling while offset > 0 would
    // shift older entries out from under whatever the user is reading as
    // newer alerts push the page boundaries around.
    { refreshInterval: page === 1 ? 15000 : 0 },
  );
  const { data: unread } = useSWR<{ count: number }>(UNREAD_COUNT_PATH, fetcher, {
    refreshInterval: 15000,
  });
  const items = data?.results ?? [];
  const totalItems = data?.count ?? items.length;
  const hasUnread = (unread?.count ?? 0) > 0;

  async function refreshInbox() {
    await Promise.all([mutate(), mutateCache(UNREAD_COUNT_PATH)]);
  }

  async function markRead(item: AppNotification) {
    if (item.readAt) return;
    await api(`/notifications/inbox/${item.id}/read`, { method: "POST" });
    await refreshInbox();
  }

  async function markAllRead() {
    await api("/notifications/inbox/read-all", { method: "POST" });
    await refreshInbox();
  }

  return (
    <Page>
      <PageHeader
        title="Notifications"
        description="Alerts fired by your apps, databases and the host itself."
        actions={
          hasUnread && (
            <Button kind="tertiary" size="sm" onClick={markAllRead}>
              Mark all read
            </Button>
          )
        }
      />

      <div className="gisila-inbox__filter">
        <Toggle
          id="unread-only"
          size="sm"
          labelText="Unread only"
          labelA="All"
          labelB="Unread"
          toggled={unreadOnly}
          onToggle={(value) => {
            setUnreadOnly(value);
            setPage(1);
          }}
        />
      </div>

      {!isLoading && items.length === 0 && (
        <Tile className="gisila-empty">
          <div className="gisila-inbox__empty">
            <NotificationIcon size={32} />
            <p>{unreadOnly ? "No unread notifications." : "No notifications yet."}</p>
          </div>
        </Tile>
      )}

      {items.length > 0 && (
        <>
          <div className="gisila-inbox__list">
            {items.map((item) => (
              <button
                key={item.id}
                type="button"
                className={
                  item.readAt
                    ? "gisila-inbox__item"
                    : "gisila-inbox__item gisila-inbox__item--unread"
                }
                onClick={() => markRead(item)}
              >
                {levelIcon(item.level)}
                <span className="gisila-inbox__item-body">
                  <span className="gisila-inbox__item-title">{item.title}</span>
                  {item.body && <span className="gisila-inbox__item-text">{item.body}</span>}
                </span>
                <span className="gisila-inbox__item-time">
                  {formatRelative(item.createdAt)}
                </span>
              </button>
            ))}
          </div>

          <Pagination
            className="gisila-inbox__pagination"
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
