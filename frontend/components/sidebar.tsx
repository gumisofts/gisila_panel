"use client";

import { Fragment } from "react";
import Link from "@/compat/link";
import { usePathname } from "@/compat/navigation";
import { SideNav, SideNavItems, SideNavDivider, SideNavLink } from "@carbon/react";
import {
  Activity,
  Api,
  Application,
  Catalog,
  Dashboard,
  DataBase,
  Earth,
  Email,
  FolderOpen,
  Layers,
  ObjectStorage,
  Password,
  Security,
  Settings,
  UserMultiple,
} from "@carbon/icons-react";
import useSWR from "swr";
import { fetcher } from "@/lib/api";
import type { User } from "@/lib/types";

// Flat links rather than Carbon's collapsible SideNavMenu groups: the panel has
// sixteen destinations that are switched between constantly, and SideNavMenu
// drops the per-item icon and puts a disclosure click in front of every jump.
// The section labels are kept as plain list headings so the grouping survives.
const NAV_SECTIONS = [
  {
    label: "Overview",
    items: [
      { href: "/dashboard", label: "Dashboard", icon: Dashboard },
      { href: "/activity", label: "Activity", icon: Activity },
    ],
  },
  {
    label: "Deploy",
    items: [
      { href: "/projects", label: "Projects", icon: FolderOpen },
      { href: "/apps", label: "Apps", icon: Application },
      { href: "/domains", label: "Domains", icon: Earth },
    ],
  },
  {
    label: "Infrastructure",
    items: [
      { href: "/applications", label: "Applications", icon: Catalog },
      { href: "/services", label: "Services", icon: Layers },
      { href: "/databases", label: "Databases", icon: DataBase },
      { href: "/storage", label: "Storage", icon: ObjectStorage },
      { href: "/mail", label: "Mail", icon: Email },
    ],
  },
  {
    label: "Team",
    items: [{ href: "/teams", label: "Teams", icon: UserMultiple }],
  },
  {
    label: "Account",
    items: [
      { href: "/settings/tokens", label: "API Tokens", icon: Api },
      { href: "/settings/ssh-keys", label: "SSH Keys", icon: Password },
      { href: "/settings", label: "Settings", icon: Settings },
    ],
  },
];

export function PanelSideNav({
  expanded,
  onOverlayClick,
}: {
  expanded: boolean;
  onOverlayClick?: () => void;
}) {
  const pathname = usePathname();
  const { data: me } = useSWR<User>("/auth/me", fetcher);

  function isActive(href: string) {
    if (href === "/dashboard") return pathname === href;
    // /settings must not match /settings/tokens or /settings/ssh-keys
    if (href === "/settings") return pathname === "/settings";
    return pathname === href || pathname?.startsWith(href + "/");
  }

  const sections = me?.isSuperuser
    ? [
        ...NAV_SECTIONS,
        {
          label: "Administration",
          items: [{ href: "/settings/users", label: "Users", icon: Security }],
        },
      ]
    : NAV_SECTIONS;

  return (
    <SideNav
      aria-label="Side navigation"
      expanded={expanded}
      onOverlayClick={onOverlayClick}
      isPersistent
    >
      <SideNavItems>
        {sections.map((section, index) => (
          <Fragment key={section.label}>
            {index > 0 && <SideNavDivider />}
            <li className="gisila-side-nav__section" aria-hidden="true">
              {section.label}
            </li>
            {section.items.map(({ href, label, icon }) => (
              <SideNavLink
                key={href}
                as={Link}
                href={href}
                renderIcon={icon}
                isActive={isActive(href)}
                isSideNavExpanded={expanded}
              >
                {label}
              </SideNavLink>
            ))}
          </Fragment>
        ))}
      </SideNavItems>
    </SideNav>
  );
}
