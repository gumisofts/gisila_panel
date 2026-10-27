import { useEffect, useState } from "react";
import { Modal } from "@carbon/react";

interface Pending {
  message: string;
  danger: boolean;
  confirmLabel: string;
  resolve: (ok: boolean) => void;
}

let show: ((p: Pending) => void) | null = null;

/// Asks [message] in a Carbon modal and resolves to whether the user
/// confirmed. A drop-in for `window.confirm`, which is unstyled, blocks the
/// page and can't be themed: `if (!(await confirmDialog("Delete it?"))) return;`
export function confirmDialog(
  message: string,
  { danger = true, confirmLabel = "Confirm" }: {
    danger?: boolean;
    confirmLabel?: string;
  } = {},
): Promise<boolean> {
  return new Promise((resolve) => {
    if (!show) {
      // Host not mounted (shouldn't happen): fall back rather than hang.
      resolve(window.confirm(message));
      return;
    }
    show({ message, danger, confirmLabel, resolve });
  });
}

/// Mounted once at the app root; renders whatever [confirmDialog] asks.
export function ConfirmDialogHost() {
  const [pending, setPending] = useState<Pending | null>(null);

  useEffect(() => {
    show = setPending;
    return () => {
      show = null;
    };
  }, []);

  function close(ok: boolean) {
    pending?.resolve(ok);
    setPending(null);
  }

  return (
    <Modal
      open={pending !== null}
      danger={pending?.danger}
      size="xs"
      modalHeading="Are you sure?"
      primaryButtonText={pending?.confirmLabel ?? "Confirm"}
      secondaryButtonText="Cancel"
      onRequestClose={() => close(false)}
      onRequestSubmit={() => close(true)}
    >
      <p>{pending?.message}</p>
    </Modal>
  );
}
