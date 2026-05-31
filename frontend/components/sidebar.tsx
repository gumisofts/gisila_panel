"use client";

import Link from "@/compat/link";
import { usePathname, useRouter } from "@/compat/navigation";
import {
  LayoutDashboard,
  Boxes,
  FolderOpen,
  Globe,
  Activity,
  Key,
  LogOut,
  Rocket,
  Settings,
  Users,
  Layers,
  Database,
  KeySquare,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { setToken } from "@/lib/api";

const NAV_SECTIONS = [
  {
    label: "Overview",
    items: [
      { href: "/dashboard", label: "Dashboard", icon: LayoutDashboard },
      { href: "/activity",  label: "Activity",  icon: Activity },
    ],
  },
  {
    label: "Deploy",
    items: [
      { href: "/projects",  label: "Projects",  icon: FolderOpen },
      { href: "/apps",      label: "Apps",      icon: Boxes },
      { href: "/domains",   label: "Domains",   icon: Globe },
    ],
  },
  {
    label: "Infrastructure",
    items: [
      { href: "/services",  label: "Services",  icon: Layers },
      { href: "/databases", label: "Databases", icon: Database },
    ],
  },
  {
    label: "Team",
    items: [
      { href: "/teams", label: "Teams", icon: Users },
    ],
  },
  {
    label: "Account",
    items: [
      { href: "/settings/tokens",   label: "API Tokens", icon: Key },
      { href: "/settings/ssh-keys", label: "SSH Keys",   icon: KeySquare },
      { href: "/settings",          label: "Settings",   icon: Settings },
    ],
  },
];

export function Sidebar() {
  const pathname = usePathname();
  const router = useRouter();

  function signOut() {
    setToken(null);
    router.push("/login");
  }

  function isActive(href: string) {
    if (href === "/dashboard") return pathname === href;
    // /settings must not match /settings/tokens or /settings/ssh-keys
    if (href === "/settings")
      return pathname === "/settings";
    return pathname === href || pathname?.startsWith(href + "/");
  }

  return (
    <aside className="hidden w-56 shrink-0 flex-col border-r border-border bg-card md:flex">
      {/* Logo */}
      <Link
        href="/dashboard"
        className="flex h-12 items-center gap-2.5 border-b border-border px-4 text-sm font-semibold tracking-tight"
      >
        <Rocket className="h-4 w-4 text-primary" />
        Gisila Panel
      </Link>

      {/* Nav sections */}
      <nav className="flex-1 overflow-y-auto p-2 space-y-4">
        {NAV_SECTIONS.map((section) => (
          <div key={section.label}>
            <p className="mb-1 px-2.5 text-[10px] font-semibold uppercase tracking-widest text-muted-foreground/60">
              {section.label}
            </p>
            <div className="space-y-0.5">
              {section.items.map(({ href, label, icon: Icon }) => (
                <Link
                  key={href}
                  href={href}
                  className={cn(
                    "flex items-center gap-2.5 rounded px-2.5 py-1.5 text-sm text-muted-foreground transition-colors hover:bg-accent hover:text-foreground",
                    isActive(href) && "bg-accent text-foreground font-medium",
                  )}
                >
                  <Icon className="h-4 w-4 shrink-0" />
                  {label}
                </Link>
              ))}
            </div>
          </div>
        ))}
      </nav>

      {/* Sign out */}
      <div className="border-t border-border p-2">
        <button
          onClick={signOut}
          className="flex w-full items-center gap-2.5 rounded px-2.5 py-1.5 text-sm text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
        >
          <LogOut className="h-4 w-4 shrink-0" />
          Sign out
        </button>
      </div>
    </aside>
  );
}
