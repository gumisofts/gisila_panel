"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
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

const NAV = [
  { href: "/dashboard", label: "Dashboard", icon: LayoutDashboard },
  { href: "/projects", label: "Projects", icon: FolderOpen },
  { href: "/apps", label: "Apps", icon: Boxes },
  { href: "/domains", label: "Domains", icon: Globe },
  { href: "/services", label: "Services", icon: Layers },
  { href: "/databases", label: "Databases", icon: Database },
  { href: "/activity", label: "Activity", icon: Activity },
  { href: "/teams", label: "Teams", icon: Users },
  { href: "/settings/tokens", label: "API Tokens", icon: Key },
  { href: "/settings/ssh-keys", label: "SSH Keys", icon: KeySquare },
  { href: "/settings", label: "Settings", icon: Settings },
];

export function Sidebar() {
  const pathname = usePathname();
  const router = useRouter();

  function signOut() {
    setToken(null);
    router.push("/login");
  }

  return (
    <aside className="hidden w-56 shrink-0 flex-col border-r border-border bg-card md:flex">
      <Link
        href="/dashboard"
        className="flex h-12 items-center gap-2.5 border-b border-border px-4 text-sm font-semibold tracking-tight"
      >
        <Rocket className="h-4 w-4 text-primary" />
        Gisila Panel
      </Link>

      <nav className="flex-1 p-2">
        {NAV.map(({ href, label, icon: Icon }) => {
          const active =
            pathname === href ||
            (href !== "/dashboard" && pathname?.startsWith(href));
          return (
            <Link
              key={href}
              href={href}
              className={cn(
                "flex items-center gap-2.5 rounded px-2.5 py-1.5 text-sm text-muted-foreground transition-colors hover:bg-accent hover:text-foreground",
                active && "bg-accent text-foreground font-medium",
              )}
            >
              <Icon className="h-4 w-4 shrink-0" />
              {label}
            </Link>
          );
        })}
      </nav>

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
