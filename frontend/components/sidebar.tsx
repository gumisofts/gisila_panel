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
  FirewallClassic,
  FolderOpen,
  Layers,
  Notification,
  ObjectStorage,
  Password,
  Security,
  Settings,
  UserMultiple,
} from "@carbon/icons-react";
import useSWR from "swr";
import { fetcher } from "@/lib/api";
import type { User } from "@/lib/types";
import { VersionFooter } from "@/components/version-info";

// Flat links rather than Carbon's collapsible SideNavMenu groups: the panel has
// sixteen destinations that are switched between constantly, and SideNavMenu
// drops the per-item icon and puts a disclosure click in front of every jump.
// The section labels are kept as plain list headings so the grouping survives.
const NAV_SECTIONS = [
  {
    label: "Overview",
    items: [
      { href: "/dashboard", label: "Dashboard", icon: Dashboard },
      { href: "/notifications", label: "Notifications", icon: Notification },
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
      { href: "/runtimes", label: "Runtimes", icon: Catalog },
      { href: "/services", label: "Services", icon: Layers, superuser: true },
      { href: "/databases", label: "Databases", icon: DataBase, superuser: true },
      { href: "/storage", label: "Storage", icon: ObjectStorage, superuser: true },
      { href: "/mail", label: "Mail", icon: Email, superuser: true },
      { href: "/firewall", label: "Firewall", icon: FirewallClassic, superuser: true },
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
          items: [
            { href: "/settings/users", label: "Users", icon: Security },
            {
              href: "/settings/notifications",
              label: "Alerts & Email",
              icon: Notification,
            },
          ],
        },
      ]
    : // Node-global infra is superuser-only on the backend; hide it rather
      // than link to pages that would only 403.
      NAV_SECTIONS.map((section) => ({
        ...section,
        items: section.items.filter((item) => !("superuser" in item)),
      }));

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
        <SideNavDivider />
        <li className="gisila-side-nav__version">
          <VersionFooter />
        </li>
      </SideNavItems>
    </SideNav>
  );
}
