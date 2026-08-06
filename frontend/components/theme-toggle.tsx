"use client";

import { useEffect, useState } from "react";
import { useTheme } from "next-themes";
import { OverflowMenu, OverflowMenuItem } from "@carbon/react";
import { Asleep, Light, Screen } from "@carbon/icons-react";

const OPTIONS = [
  { key: "light", label: "Light", icon: Light },
  { key: "system", label: "System", icon: Screen },
  { key: "dark", label: "Dark", icon: Asleep },
] as const;

/// Theme picker for the header. A menu rather than a plain toggle because the
/// panel offers three states, and cycling a single button through them gives no
/// indication of what the next press will do.
export function ThemeToggle() {
  const { theme, setTheme } = useTheme();
  const [mounted, setMounted] = useState(false);

  // next-themes cannot know the resolved theme until it has read the DOM, so
  // the trigger icon would otherwise differ between the server-rendered markup
  // and the first client render.
  useEffect(() => setMounted(true), []);

  const current = OPTIONS.find((option) => option.key === theme) ?? OPTIONS[1];

  return (
    <OverflowMenu
      aria-label="Change theme"
      className="gisila-header__menu"
      renderIcon={mounted ? current.icon : Screen}
      size="lg"
      flipped
      menuOptionsClass="gisila-header__menu-options"
    >
      {OPTIONS.map((option) => (
        <OverflowMenuItem
          key={option.key}
          itemText={option.label}
          onClick={() => setTheme(option.key)}
          requireTitle={false}
        />
      ))}
    </OverflowMenu>
  );
}
