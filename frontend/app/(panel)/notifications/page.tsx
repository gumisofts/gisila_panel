"use client";

import { useState } from "react";
import useSWR from "swr";
import {
  CheckmarkFilled,
  ErrorFilled,
  Notification as NotificationIcon,
  WarningAltFilled,
} from "@carbon/icons-react";
import { Button, Tile, Toggle } from "@carbon/react";
import { Page, PageHeader } from "@/components/page";
import { api, fetcher } from "@/lib/api";
import { formatRelative } from "@/lib/utils";
import type { AppNotification, ListResponse, NotificationLevel } from "@/lib/types";
import "./_notifications.scss";

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
  const key = `/notifications/inbox?limit=100${unreadOnly ? "&unreadOnly=true" : ""}`;

  const { data, isLoading, mutate } = useSWR<ListResponse<AppNotification>>(
    key,
    fetcher,
    { refreshInterval: 15000 },
  );
  const items = data?.results ?? [];
  const hasUnread = items.some((n) => !n.readAt);

  async function markRead(item: AppNotification) {
    if (item.readAt) return;
    await api(`/notifications/inbox/${item.id}/read`, { method: "POST" });
    mutate();
  }

  async function markAllRead() {
    await api("/notifications/inbox/read-all", { method: "POST" });
    mutate();
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
          onToggle={setUnreadOnly}
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
      )}
    </Page>
  );
}
