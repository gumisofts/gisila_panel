import { useSyncExternalStore } from "react";
import { ToastNotification } from "@carbon/react";

// Carbon models notifications declaratively — you render a <ToastNotification>
// where you want one — while the panel calls `toast.error(...)` imperatively
// from 22 modules, several of them outside the React tree (lib/api.ts raises
// the session-expiry toast from a plain fetch wrapper). This module keeps that
// imperative surface and backs it with a Carbon notification stack, so the
// call sites only had to change which module they import from.
//
// Only `success` and `error` exist because those are the only two the panel
// ever used, and always with a bare message string.

type ToastKind = "success" | "error";

interface ToastItem {
  id: number;
  kind: ToastKind;
  message: string;
}

let items: ToastItem[] = [];
let nextId = 1;
const listeners = new Set<() => void>();

function emit() {
  for (const listener of listeners) listener();
}

function push(kind: ToastKind, message: string) {
  items = [...items, { id: nextId++, kind, message }];
  emit();
}

function dismiss(id: number) {
  items = items.filter((item) => item.id !== id);
  emit();
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

function getSnapshot() {
  return items;
}

export const toast = {
  success: (message: string) => push("success", message),
  error: (message: string) => push("error", message),
};

/// Mount once, near the root. Renders the active notifications bottom-right,
/// matching where Sonner used to put them.
export function Toaster() {
  const active = useSyncExternalStore(subscribe, getSnapshot, getSnapshot);

  return (
    <div
      aria-live="polite"
      style={{
        position: "fixed",
        insetBlockEnd: "1rem",
        insetInlineEnd: "1rem",
        zIndex: 9000,
        display: "flex",
        flexDirection: "column",
        gap: "0.5rem",
      }}
    >
      {active.map((item) => (
        <ToastNotification
          key={item.id}
          kind={item.kind}
          title={item.kind === "success" ? "Success" : "Error"}
          subtitle={item.message}
          lowContrast
          // Fires for both the close button and the timeout, so this is the
          // single place the item leaves the stack.
          onClose={() => dismiss(item.id)}
          timeout={6000}
        />
      ))}
    </div>
  );
}
