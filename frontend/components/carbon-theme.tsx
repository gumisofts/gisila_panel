"use client";

import { useEffect, useState, type ReactNode } from "react";
import { Theme } from "@carbon/react";
import { useTheme } from "next-themes";

/// Keeps Carbon's React theme context in sync with next-themes. next-themes
/// still owns the `class` on <html> (so document background / CSS variables
/// flip); this wrapper ensures Carbon components that read ThemeContext update
/// too.
export function CarbonTheme({ children }: { children: ReactNode }) {
  const { resolvedTheme } = useTheme();
  const [mounted, setMounted] = useState(false);

  useEffect(() => setMounted(true), []);

  const theme =
    mounted && resolvedTheme === "dark" ? ("g100" as const) : ("white" as const);

  return (
    <Theme theme={theme} className="gisila-theme-root">
      {children}
    </Theme>
  );
}
