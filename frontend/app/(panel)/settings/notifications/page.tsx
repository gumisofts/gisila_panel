"use client";

import { useEffect, useState } from "react";
import useSWR from "swr";
import { Email, SecurityServices, Send } from "@carbon/icons-react";
import {
  Button,
  Form,
  InlineNotification,
  NumberInput,
  PasswordInput,
  Select,
  SelectItem,
  Stack,
  TextInput,
  Tile,
  Toggle,
} from "@carbon/react";
import { Page, PageHeader, PageSection } from "@/components/page";
import { AlertRulesManager } from "@/components/alert-rules-manager";
import { toast } from "@/lib/toast";
import { api, fetcher } from "@/lib/api";
import { usePermissions } from "@/lib/permissions";
import type { SmtpConfig, SmtpSecurity } from "@/lib/types";
import "../_settings.scss";

type SmtpForm = {
  smtpHost: string;
  smtpPort: number;
  smtpUsername: string;
  smtpPassword: string;
  smtpSecurity: SmtpSecurity;
  fromEmail: string;
  fromName: string;
  emailEnabled: boolean;
};

function formFromConfig(cfg: SmtpConfig): SmtpForm {
  return {
    smtpHost: cfg.smtpHost ?? "",
    smtpPort: cfg.smtpPort,
    smtpUsername: cfg.smtpUsername ?? "",
    // The API never returns the stored password (write-only) — leaving this
    // blank on save means "keep the existing one" (see NotificationCore).
    smtpPassword: "",
    smtpSecurity: cfg.smtpSecurity,
    fromEmail: cfg.fromEmail ?? "",
    fromName: cfg.fromName,
    emailEnabled: cfg.emailEnabled,
  };
}

export default function NotificationSettingsPage() {
  const { isSuperuser } = usePermissions();
  const { data: cfg, isLoading, mutate } = useSWR<SmtpConfig>(
    isSuperuser ? "/notifications/settings/smtp" : null,
    fetcher,
  );

  const [form, setForm] = useState<SmtpForm | null>(null);
  const [saving, setSaving] = useState(false);
  const [testEmail, setTestEmail] = useState("");
  const [sendingTest, setSendingTest] = useState(false);

  useEffect(() => {
    if (cfg) setForm(formFromConfig(cfg));
  }, [cfg]);

  if (!isSuperuser) {
    return (
      <Page>
        <Tile className="gisila-empty">
          <div className="gisila-settings__empty">
            <SecurityServices size={32} />
            <div>
              <h2 className="gisila-settings__empty-title">
                Superuser access required
              </h2>
              <p>Only superusers can manage alerting and outbound email.</p>
            </div>
          </div>
        </Tile>
      </Page>
    );
  }

  function set<K extends keyof SmtpForm>(k: K, v: SmtpForm[K]) {
    setForm((f) => (f ? { ...f, [k]: v } : f));
  }

  async function save(e: React.FormEvent) {
    e.preventDefault();
    if (!form) return;
    setSaving(true);
    try {
      await api("/notifications/settings/smtp", {
        method: "PUT",
        body: JSON.stringify({
          smtpHost: form.smtpHost || undefined,
          smtpPort: form.smtpPort,
          smtpUsername: form.smtpUsername || undefined,
          // Omit entirely rather than send "" so the backend's "blank means
          // unchanged" rule has something consistent to key off.
          smtpPassword: form.smtpPassword || undefined,
          smtpSecurity: form.smtpSecurity,
          fromEmail: form.fromEmail || undefined,
          fromName: form.fromName || undefined,
          emailEnabled: form.emailEnabled,
        }),
      });
      toast.success("SMTP settings saved");
      mutate();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed to save SMTP settings");
    } finally {
      setSaving(false);
    }
  }

  async function sendTest() {
    if (!testEmail.trim()) return;
    setSendingTest(true);
    try {
      await api("/notifications/settings/smtp/test", {
        method: "POST",
        body: JSON.stringify({ toEmail: testEmail.trim() }),
      });
      toast.success(`Test email sent to ${testEmail.trim()}`);
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed to send test email");
    } finally {
      setSendingTest(false);
    }
  }

  return (
    <Page>
      <PageHeader
        title="Alerts & Email"
        description="Outbound SMTP for alert emails, and server-wide alert thresholds."
      />

      <PageSection title="Outbound email (SMTP)">
        {isLoading || !form ? (
          <p className="gisila-settings__hint">Loading…</p>
        ) : (
          <Form onSubmit={save}>
            <Stack gap={6}>
              <Toggle
                id="smtp-enabled"
                labelText="Send alert emails"
                labelA="Off"
                labelB="On"
                toggled={form.emailEnabled}
                onToggle={(checked) => set("emailEnabled", checked)}
              />

              <div className="gisila-settings__form-row">
                <div className="gisila-settings__form-field">
                  <TextInput
                    id="smtp-host"
                    labelText="SMTP host"
                    placeholder="smtp.example.com"
                    value={form.smtpHost}
                    onChange={(e) => set("smtpHost", e.target.value)}
                  />
                </div>
                <div className="gisila-settings__form-field gisila-settings__form-field--narrow">
                  <NumberInput
                    id="smtp-port"
                    label="Port"
                    min={1}
                    max={65535}
                    value={form.smtpPort}
                    onChange={(_, { value }) => set("smtpPort", Number(value) || 587)}
                  />
                </div>
                <div className="gisila-settings__form-field gisila-settings__form-field--narrow">
                  <Select
                    id="smtp-security"
                    labelText="Security"
                    value={form.smtpSecurity}
                    onChange={(e) => set("smtpSecurity", e.target.value as SmtpSecurity)}
                  >
                    <SelectItem value="none" text="None" />
                    <SelectItem value="starttls" text="STARTTLS" />
                    <SelectItem value="ssl" text="SSL/TLS" />
                  </Select>
                </div>
              </div>

              <div className="gisila-settings__form-row">
                <div className="gisila-settings__form-field">
                  <TextInput
                    id="smtp-username"
                    labelText="SMTP username"
                    value={form.smtpUsername}
                    onChange={(e) => set("smtpUsername", e.target.value)}
                  />
                </div>
                <div className="gisila-settings__form-field">
                  <PasswordInput
                    id="smtp-password"
                    labelText="SMTP password"
                    placeholder={
                      cfg?.smtpHost ? "Leave blank to keep the current password" : ""
                    }
                    value={form.smtpPassword}
                    onChange={(e) => set("smtpPassword", e.target.value)}
                  />
                </div>
              </div>

              <div className="gisila-settings__form-row">
                <div className="gisila-settings__form-field">
                  <TextInput
                    id="smtp-from-email"
                    labelText="From address"
                    placeholder="alerts@example.com"
                    type="email"
                    value={form.fromEmail}
                    onChange={(e) => set("fromEmail", e.target.value)}
                  />
                </div>
                <div className="gisila-settings__form-field">
                  <TextInput
                    id="smtp-from-name"
                    labelText="From name"
                    placeholder="Gisila Panel"
                    value={form.fromName}
                    onChange={(e) => set("fromName", e.target.value)}
                  />
                </div>
              </div>

              <div className="gisila-settings__row-actions" style={{ justifyContent: "flex-start" }}>
                <Button type="submit" disabled={saving} renderIcon={Email}>
                  {saving ? "Saving…" : "Save SMTP settings"}
                </Button>
              </div>
            </Stack>
          </Form>
        )}
      </PageSection>

      {cfg?.emailEnabled && (
        <PageSection title="Send a test email">
          <div className="gisila-settings__form-row">
            <div className="gisila-settings__form-field">
              <TextInput
                id="smtp-test-email"
                labelText="Recipient"
                placeholder="you@example.com"
                type="email"
                value={testEmail}
                onChange={(e) => setTestEmail(e.target.value)}
              />
            </div>
            <div>
              <Button
                kind="tertiary"
                renderIcon={Send}
                disabled={sendingTest || !testEmail.trim()}
                onClick={sendTest}
              >
                {sendingTest ? "Sending…" : "Send test email"}
              </Button>
            </div>
          </div>
        </PageSection>
      )}

      {!cfg?.smtpHost && !isLoading && (
        <InlineNotification
          kind="info"
          lowContrast
          hideCloseButton
          title="No SMTP host configured"
          subtitle="In-panel notifications still work without SMTP — only alert emails require it."
        />
      )}

      <PageSection
        title="Server-wide alerts"
        description="Fires when the whole host — not a specific app or database — crosses a threshold. Delivered to every superuser."
      >
        <AlertRulesManager scope="system" canWrite />
      </PageSection>

      <PageSection
        title="Mail stack alerts"
        description="Fires when the mail stack (Postfix / Dovecot / OpenDKIM) is found unhealthy by the periodic health monitor. Delivered to every superuser."
      >
        <AlertRulesManager scope="mail" canWrite />
      </PageSection>
    </Page>
  );
}
