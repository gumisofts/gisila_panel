"use client";

import { useEffect, useState } from "react";
import { useTheme } from "next-themes";
import { HeaderGlobalAction } from "@carbon/react";
import { Asleep, Light, Screen } from "@carbon/icons-react";

const ORDER = ["light", "dark", "system"] as const;
type ThemeKey = (typeof ORDER)[number];

const ICONS = {
  light: Light,
  dark: Asleep,
  system: Screen,
} as const;

const LABELS = {
  light: "Light",
  dark: "Dark",
  system: "System",
} as const;

/// Cycles light → dark → system. A single header action is more reliable in the
/// Carbon shell than an OverflowMenu (v11/v12 menu variants disagree on
/// children), and still exposes all three modes.
export function ThemeToggle() {
  const { theme, setTheme, resolvedTheme } = useTheme();
  const [mounted, setMounted] = useState(false);

  useEffect(() => setMounted(true), []);

  const current: ThemeKey = ORDER.includes(theme as ThemeKey)
    ? (theme as ThemeKey)
    : "system";

  function cycle() {
    const next = ORDER[(ORDER.indexOf(current) + 1) % ORDER.length];
    setTheme(next);
  }

  // Show the active mode. For "system", use the Screen icon and mention what
  // the OS is currently resolving to in the accessible label.
  const Icon = !mounted ? Screen : ICONS[current];
  const detail =
    current === "system" && mounted && resolvedTheme
      ? `${LABELS.system} (${LABELS[resolvedTheme as "light" | "dark"]})`
      : LABELS[current];

  return (
    <HeaderGlobalAction
      aria-label={`Theme: ${detail}. Click to change.`}
      tooltipAlignment="end"
      onClick={cycle}
    >
      <Icon size={20} />
    </HeaderGlobalAction>
  );
}
