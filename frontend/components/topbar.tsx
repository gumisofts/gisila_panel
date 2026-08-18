"use client";

import useSWR from "swr";
import { useRouter } from "@/compat/navigation";
import {
  HeaderGlobalAction,
  HeaderGlobalBar,
  OverflowMenu,
  OverflowMenuItem,
} from "@carbon/react";
import { Add, UserAvatar } from "@carbon/icons-react";
import { NotificationBell } from "@/components/notification-bell";
import { ThemeToggle } from "@/components/theme-toggle";
import { fetcher, setToken } from "@/lib/api";
import type { User } from "@/lib/types";

/// Right-hand side of the Carbon header: create action, theme picker and the
/// account menu. Sign out moved here from the bottom of the sidebar, which is
/// where Carbon's shell puts account actions.
export function PanelHeaderActions() {
  const { data } = useSWR<User>("/auth/me", fetcher);
  const router = useRouter();

  function signOut() {
    setToken(null);
    router.push("/login");
  }

  return (
    <HeaderGlobalBar>
      <HeaderGlobalAction
        aria-label="New app"
        tooltipAlignment="center"
        onClick={() => router.push("/apps/new")}
      >
        <Add size={20} />
      </HeaderGlobalAction>

      <NotificationBell />

      <ThemeToggle />

      <OverflowMenu
        aria-label={data?.email ? `Account: ${data.email}` : "Account"}
        className="gisila-header__menu"
        renderIcon={UserAvatar}
        size="lg"
        flipped
        menuOptionsClass="gisila-header__menu-options"
      >
        <OverflowMenuItem
          itemText={data?.email ?? "Signed in"}
          disabled
          requireTitle={false}
        />
        <OverflowMenuItem
          itemText="Sign out"
          onClick={signOut}
          hasDivider
          isDelete
          requireTitle={false}
        />
      </OverflowMenu>
    </HeaderGlobalBar>
  );
}
