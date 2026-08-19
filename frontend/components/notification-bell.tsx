"use client";

import useSWR from "swr";
import { HeaderGlobalAction } from "@carbon/react";
import { Notification as NotificationIcon } from "@carbon/icons-react";
import { useRouter } from "@/compat/navigation";
import { fetcher } from "@/lib/api";

const UNREAD_COUNT_PATH = "/notifications/inbox/unread-count";

/// Bell in the header global bar: an unread badge and a link to the inbox.
///
/// It opens nothing in place, on purpose. The earlier version hung a Popover
/// panel off this button and popped it open by itself whenever the unread
/// count rose, which parked a 22rem panel over the header actions next to it
/// while the user was mid-task. The full list already lives at
/// `/notifications`, so the bell just points there and the badge carries the
/// only thing worth glancing at.
export function NotificationBell() {
  const router = useRouter();
  const { data } = useSWR<{ count: number }>(UNREAD_COUNT_PATH, fetcher, {
    refreshInterval: 15000,
  });
  const count = data?.count ?? 0;

  return (
    <HeaderGlobalAction
      aria-label={
        count > 0 ? `Notifications (${count} unread)` : "Notifications"
      }
      tooltipAlignment="center"
      className="gisila-bell"
      onClick={() => router.push("/notifications")}
    >
      <NotificationIcon size={20} />
      {count > 0 && (
        <span className="gisila-bell__badge">{count > 9 ? "9+" : count}</span>
      )}
    </HeaderGlobalAction>
  );
}
