import { useMemo, useState } from "react";
import useSWR from "swr";
import qrcode from "qrcode-generator";
import { Copy, Download, Locked, Logout } from "@carbon/icons-react";
import {
  Button,
  ComposedModal,
  Form,
  InlineNotification,
  ModalBody,
  ModalFooter,
  ModalHeader,
  PasswordInput,
  Stack,
  Tag,
  TextInput,
} from "@carbon/react";
import { PageSection } from "@/components/page";
import { toast } from "@/lib/toast";
import { api, fetcher, setToken } from "@/lib/api";
import type { TotpStatus } from "@/lib/types";
import { confirmDialog } from "@/components/confirm-dialog";

function errorMessage(err: unknown) {
  return err instanceof Error ? err.message : "Failed";
}

// ── Password ─────────────────────────────────────────────────────────────────

function ChangePassword() {
  const [oldPassword, setOldPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [busy, setBusy] = useState(false);
  const mismatch = confirm !== "" && confirm !== newPassword;

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (mismatch) return;
    setBusy(true);
    try {
      const res = await api<{ access: string }>("/auth/change-password", {
        method: "POST",
        body: JSON.stringify({ oldPassword, newPassword }),
      });
      // The old token was revoked with every other session; keep this one.
      setToken(res.access);
      setOldPassword("");
      setNewPassword("");
      setConfirm("");
      toast.success("Password changed. Other sessions were signed out.");
    } catch (err: unknown) {
      toast.error(errorMessage(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Form onSubmit={submit}>
      <Stack gap={5}>
        <PasswordInput
          id="current-password"
          labelText="Current password"
          autoComplete="current-password"
          required
          value={oldPassword}
          onChange={(e) => setOldPassword(e.target.value)}
        />
        <div className="gisila-settings__form-row">
          <div className="gisila-settings__form-field">
            <PasswordInput
              id="new-password"
              labelText="New password"
              autoComplete="new-password"
              helperText="At least 8 characters."
              minLength={8}
              required
              value={newPassword}
              onChange={(e) => setNewPassword(e.target.value)}
            />
          </div>
          <div className="gisila-settings__form-field">
            <PasswordInput
              id="confirm-password"
              labelText="Confirm new password"
              autoComplete="new-password"
              required
              invalid={mismatch}
              invalidText="Passwords don't match."
              value={confirm}
              onChange={(e) => setConfirm(e.target.value)}
            />
          </div>
        </div>
        <div>
          <Button type="submit" disabled={busy || mismatch}>
            Change password
          </Button>
        </div>
      </Stack>
    </Form>
  );
}

// ── Recovery codes ───────────────────────────────────────────────────────────

function RecoveryCodeList({ codes }: { codes: string[] }) {
  const text = codes.join("\n");
  return (
    <Stack gap={4}>
      <InlineNotification
        kind="warning"
        lowContrast
        hideCloseButton
        title="Save these recovery codes now."
        subtitle="Each one signs you in once if you lose your authenticator. They won't be shown again."
      />
      <pre className="gisila-settings__codes">{text}</pre>
      <div className="gisila-settings__row-actions gisila-settings__row-actions--start">
        <Button
          kind="tertiary"
          size="sm"
          renderIcon={Copy}
          onClick={() => {
            navigator.clipboard.writeText(text);
            toast.success("Copied");
          }}
        >
          Copy
        </Button>
        <Button
          kind="tertiary"
          size="sm"
          renderIcon={Download}
          onClick={() => {
            const url = URL.createObjectURL(
              new Blob([text + "\n"], { type: "text/plain" }),
            );
            const a = document.createElement("a");
            a.href = url;
            a.download = "gisila-recovery-codes.txt";
            a.click();
            URL.revokeObjectURL(url);
          }}
        >
          Download
        </Button>
      </div>
    </Stack>
  );
}

// ── Two-factor setup ─────────────────────────────────────────────────────────

type SetupStep =
  | { step: "password" }
  | { step: "scan"; secret: string; otpauthUri: string }
  | { step: "codes"; recoveryCodes: string[] };

function QrCode({ value }: { value: string }) {
  // Error correction "M" with automatic sizing (type 0) fits any otpauth URI.
  const svg = useMemo(() => {
    const qr = qrcode(0, "M");
    qr.addData(value);
    qr.make();
    return qr.createSvgTag({ cellSize: 4, margin: 4, scalable: true });
  }, [value]);
  return (
    <div
      className="gisila-settings__qr"
      role="img"
      aria-label="QR code for your authenticator app"
      dangerouslySetInnerHTML={{ __html: svg }}
    />
  );
}

function TotpSetupModal({
  open,
  onClose,
}: {
  open: boolean;
  onClose: (enabled: boolean) => void;
}) {
  const [state, setState] = useState<SetupStep>({ step: "password" });
  const [password, setPassword] = useState("");
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);

  // No state reset here: the parent remounts this modal (new `key`) each
  // time it opens, so the closing animation keeps showing the last step.
  function close() {
    onClose(state.step === "codes");
  }

  async function submitPassword(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    try {
      const res = await api<{ secret: string; otpauthUri: string }>(
        "/auth/totp/setup",
        { method: "POST", body: JSON.stringify({ password }) },
      );
      setPassword("");
      setState({ step: "scan", ...res });
    } catch (err: unknown) {
      toast.error(errorMessage(err));
    } finally {
      setBusy(false);
    }
  }

  async function submitCode(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    try {
      const res = await api<{ recoveryCodes: string[]; access: string }>(
        "/auth/totp/enable",
        { method: "POST", body: JSON.stringify({ code }) },
      );
      // Turning 2FA on signed out every session, this one included.
      setToken(res.access);
      setState({ step: "codes", recoveryCodes: res.recoveryCodes });
    } catch (err: unknown) {
      toast.error(errorMessage(err));
      setCode("");
    } finally {
      setBusy(false);
    }
  }

  const formId = `totp-setup-${state.step}`;

  return (
    <ComposedModal open={open} onClose={close} size="sm" preventCloseOnClickOutside>
      <ModalHeader title="Set up two-factor authentication" />
      <ModalBody hasForm>
        {state.step === "password" && (
          <Form id={formId} onSubmit={submitPassword}>
            <PasswordInput
              id="totp-password"
              labelText="Confirm your password"
              autoComplete="current-password"
              required
              autoFocus
              value={password}
              onChange={(e) => setPassword(e.target.value)}
            />
          </Form>
        )}
        {state.step === "scan" && (
          <Form id={formId} onSubmit={submitCode}>
            <Stack gap={5}>
              <p>
                Scan this code with an authenticator app (1Password, Google
                Authenticator, Aegis, …), then enter the 6-digit code it shows.
              </p>
              <QrCode value={state.otpauthUri} />
              <div>
                <span className="gisila-settings__label">
                  Or enter this key manually
                </span>
                <div className="gisila-settings__secret">
                  <code className="gisila-settings__secret-value">
                    {state.secret.match(/.{1,4}/g)?.join(" ")}
                  </code>
                  <Button
                    kind="ghost"
                    size="sm"
                    hasIconOnly
                    renderIcon={Copy}
                    iconDescription="Copy key"
                    onClick={() => {
                      navigator.clipboard.writeText(state.secret);
                      toast.success("Copied");
                    }}
                  />
                </div>
              </div>
              <TextInput
                id="totp-code"
                labelText="Code from the app"
                autoComplete="one-time-code"
                inputMode="numeric"
                required
                value={code}
                onChange={(e) => setCode(e.target.value)}
                placeholder="123456"
              />
            </Stack>
          </Form>
        )}
        {state.step === "codes" && (
          <RecoveryCodeList codes={state.recoveryCodes} />
        )}
      </ModalBody>
      <ModalFooter>
        {state.step === "codes" ? (
          <Button kind="primary" onClick={close}>
            I saved my recovery codes
          </Button>
        ) : (
          <>
            <Button kind="secondary" onClick={close}>
              Cancel
            </Button>
            <Button kind="primary" type="submit" form={formId} disabled={busy}>
              {state.step === "password" ? "Continue" : "Turn on"}
            </Button>
          </>
        )}
      </ModalFooter>
    </ComposedModal>
  );
}

// ── Two-factor management ────────────────────────────────────────────────────

/// Asks for a code (and optionally the password) before a sensitive 2FA change.
function TotpConfirmModal({
  open,
  title,
  description,
  needsPassword,
  allowRecovery,
  danger,
  submitLabel,
  onSubmit,
  onClose,
}: {
  open: boolean;
  title: string;
  description: string;
  needsPassword: boolean;
  allowRecovery: boolean;
  danger?: boolean;
  submitLabel: string;
  onSubmit: (values: { password: string; code: string }) => Promise<void>;
  onClose: () => void;
}) {
  const [password, setPassword] = useState("");
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const formId = `totp-confirm-${submitLabel.replace(/\W+/g, "-")}`;

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    try {
      await onSubmit({ password, code });
      setPassword("");
      setCode("");
    } catch (err: unknown) {
      toast.error(errorMessage(err));
      setCode("");
    } finally {
      setBusy(false);
    }
  }

  return (
    <ComposedModal open={open} onClose={onClose} size="sm">
      <ModalHeader title={title} />
      <ModalBody hasForm>
        <Form id={formId} onSubmit={submit}>
          <Stack gap={5}>
            <p>{description}</p>
            {needsPassword && (
              <PasswordInput
                id={`${formId}-password`}
                labelText="Password"
                autoComplete="current-password"
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
              />
            )}
            <TextInput
              id={`${formId}-code`}
              labelText={
                allowRecovery
                  ? "Authentication code or recovery code"
                  : "Authentication code"
              }
              autoComplete="one-time-code"
              required
              value={code}
              onChange={(e) => setCode(e.target.value)}
            />
          </Stack>
        </Form>
      </ModalBody>
      <ModalFooter>
        <Button kind="secondary" onClick={onClose}>
          Cancel
        </Button>
        <Button
          kind={danger ? "danger" : "primary"}
          type="submit"
          form={formId}
          disabled={busy}
        >
          {submitLabel}
        </Button>
      </ModalFooter>
    </ComposedModal>
  );
}

function TwoFactor() {
  const { data, mutate } = useSWR<TotpStatus>("/auth/totp", fetcher);
  const [setupOpen, setSetupOpen] = useState(false);
  const [disableOpen, setDisableOpen] = useState(false);
  const [regenOpen, setRegenOpen] = useState(false);
  const [newCodes, setNewCodes] = useState<string[] | null>(null);
  // Bumped on every open so each modal starts from a clean slate.
  const [modalKey, setModalKey] = useState(0);
  function openModal(open: (value: boolean) => void) {
    setModalKey((k) => k + 1);
    open(true);
  }

  if (!data) return null;

  return (
    <Stack gap={5}>
      <div className="gisila-settings__name">
        <span>Authenticator app</span>
        {data.enabled ? (
          <Tag type="green" size="sm" renderIcon={Locked}>
            On
          </Tag>
        ) : (
          <Tag type="gray" size="sm">
            Off
          </Tag>
        )}
      </div>
      <p className="gisila-settings__hint">
        {data.enabled
          ? `Signing in asks for a code from your authenticator app. ${data.recoveryCodesRemaining} recovery code${data.recoveryCodesRemaining === 1 ? "" : "s"} left.`
          : "Require a code from an authenticator app, as well as your password, to sign in."}
      </p>

      {data.enabled && data.recoveryCodesRemaining <= 2 && !newCodes && (
        <InlineNotification
          kind="warning"
          lowContrast
          hideCloseButton
          title="You're running out of recovery codes."
          subtitle="Generate a new set so you can still get in if you lose your device."
        />
      )}

      {newCodes && (
        <Stack gap={4}>
          <RecoveryCodeList codes={newCodes} />
          <div>
            <Button kind="ghost" size="sm" onClick={() => setNewCodes(null)}>
              Done
            </Button>
          </div>
        </Stack>
      )}

      <div className="gisila-settings__row-actions gisila-settings__row-actions--start">
        {data.enabled ? (
          <>
            <Button kind="tertiary" size="sm" onClick={() => openModal(setRegenOpen)}>
              New recovery codes
            </Button>
            <Button
              kind="danger--tertiary"
              size="sm"
              onClick={() => openModal(setDisableOpen)}
            >
              Turn off
            </Button>
          </>
        ) : (
          <Button size="sm" renderIcon={Locked} onClick={() => openModal(setSetupOpen)}>
            Set up two-factor authentication
          </Button>
        )}
      </div>

      <TotpSetupModal
        key={`setup-${modalKey}`}
        open={setupOpen}
        onClose={(enabled) => {
          setSetupOpen(false);
          if (enabled) toast.success("Two-factor authentication is on");
          mutate();
        }}
      />
      <TotpConfirmModal
        key={`disable-${modalKey}`}
        open={disableOpen}
        title="Turn off two-factor authentication"
        description="Your account will be protected by your password alone."
        needsPassword
        allowRecovery
        danger
        submitLabel="Turn off"
        onClose={() => setDisableOpen(false)}
        onSubmit={async ({ password, code }) => {
          await api("/auth/totp/disable", {
            method: "POST",
            body: JSON.stringify({ password, code }),
          });
          setDisableOpen(false);
          toast.success("Two-factor authentication is off");
          mutate();
        }}
      />
      <TotpConfirmModal
        key={`regen-${modalKey}`}
        open={regenOpen}
        title="New recovery codes"
        description="Your current recovery codes will stop working."
        needsPassword={false}
        allowRecovery={false}
        submitLabel="Generate"
        onClose={() => setRegenOpen(false)}
        onSubmit={async ({ code }) => {
          const res = await api<{ recoveryCodes: string[] }>(
            "/auth/totp/recovery-codes",
            { method: "POST", body: JSON.stringify({ code }) },
          );
          setRegenOpen(false);
          setNewCodes(res.recoveryCodes);
          mutate();
        }}
      />
    </Stack>
  );
}

// ── Sessions ─────────────────────────────────────────────────────────────────

function Sessions() {
  const [busy, setBusy] = useState(false);

  async function revoke() {
    if (!(await confirmDialog("Sign out of the panel everywhere except this browser?"))) return;
    setBusy(true);
    try {
      const res = await api<{ access: string }>("/auth/sessions/revoke", {
        method: "POST",
      });
      setToken(res.access);
      toast.success("Signed out of all other sessions");
    } catch (err: unknown) {
      toast.error(errorMessage(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Stack gap={4}>
      <p className="gisila-settings__hint">
        Signs out every other browser where you are signed in. API tokens are
        not affected; revoke those under API tokens.
      </p>
      <div>
        <Button
          kind="tertiary"
          size="sm"
          renderIcon={Logout}
          disabled={busy}
          onClick={revoke}
        >
          Sign out other sessions
        </Button>
      </div>
    </Stack>
  );
}

export function SecuritySections() {
  return (
    <>
      <PageSection title="Password">
        <ChangePassword />
      </PageSection>
      <PageSection title="Two-factor authentication">
        <TwoFactor />
      </PageSection>
      <PageSection title="Sessions">
        <Sessions />
      </PageSection>
    </>
  );
}
