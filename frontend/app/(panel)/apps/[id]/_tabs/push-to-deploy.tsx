import { useState } from "react";
import useSWR from "swr";
import {
  Button,
  CodeSnippet,
  InlineNotification,
  Stack,
  Tag,
  TextInput,
  Tile,
} from "@carbon/react";
import { confirmDialog } from "@/components/confirm-dialog";
import { api, fetcher } from "@/lib/api";
import { toast } from "@/lib/toast";
import type { App } from "@/lib/types";
import "../_app-detail.scss";

interface WebhookStatus {
  configured: boolean;
  enabled: boolean;
  path: string;
  branch: string | null;
  lastDeliveryAt: string | null;
  lastDeliveryResult: string | null;
  reportsStatus: boolean;
}

interface WebhookCreated {
  path: string;
  branch: string | null;
  secret: string;
}

/// Push-to-deploy for git apps: a webhook URL and secret to paste into the
/// repository's settings. The secret is only shown right after it is made.
export function PushToDeployCard({
  app,
  canManage,
}: {
  app: App;
  canManage: boolean;
}) {
  const { data, mutate, error } = useSWR<WebhookStatus>(
    `/apps/${app.id}/webhook`,
    fetcher,
  );
  const [busy, setBusy] = useState(false);
  const [created, setCreated] = useState<WebhookCreated | null>(null);
  const [token, setToken] = useState("");

  // The panel and its API share one origin.
  const url = data ? `${window.location.origin}${data.path}` : "";
  const branch = data?.branch ?? "the repository's default branch";

  async function create(rotate: boolean) {
    if (
      rotate &&
      !(await confirmDialog(
        "Make a new secret? Deliveries signed with the old one will be refused until you update the repository's webhook.",
        { confirmLabel: "Rotate secret" },
      ))
    ) {
      return;
    }
    setBusy(true);
    try {
      setCreated(
        await api<WebhookCreated>(`/apps/${app.id}/webhook`, { method: "POST" }),
      );
      await mutate();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed to create the webhook.");
    } finally {
      setBusy(false);
    }
  }

  async function remove() {
    if (!(await confirmDialog("Remove the webhook? Pushes will no longer deploy this app.", { confirmLabel: "Remove" }))) {
      return;
    }
    setBusy(true);
    try {
      await api(`/apps/${app.id}/webhook`, { method: "DELETE" });
      setCreated(null);
      toast.success("Webhook removed.");
      await mutate();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed to remove the webhook.");
    } finally {
      setBusy(false);
    }
  }

  async function saveToken(clear: boolean) {
    setBusy(true);
    try {
      await api(`/apps/${app.id}/webhook/status-token`, {
        method: clear ? "DELETE" : "PUT",
        body: clear ? undefined : JSON.stringify({ token }),
      });
      setToken("");
      toast.success(clear ? "Commit statuses are off." : "Commit statuses will be reported.");
      await mutate();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed to save the token.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <Tile>
      <h3 className="gisila-app__tile-title">
        Push to deploy{" "}
        {data?.enabled ? (
          <Tag type="green" size="sm">On</Tag>
        ) : (
          <Tag type="cool-gray" size="sm">Off</Tag>
        )}
      </h3>
      <Stack gap={5}>
        <p className="gisila-app__hint">
          Deploy automatically when you push to <strong>{branch}</strong>. Add
          a webhook in your repository's settings that sends push events here.
        </p>

        {error && (
          <InlineNotification
            kind="error"
            lowContrast
            hideCloseButton
            title="Could not load the webhook."
            subtitle={error instanceof Error ? error.message : undefined}
          />
        )}

        {data?.enabled && (
          <div>
            <p className="gisila-app__hint">Payload URL</p>
            <CodeSnippet type="single" feedbackTimeout={1500}>
              {url}
            </CodeSnippet>
          </div>
        )}

        {created && (
          <InlineNotification
            kind="warning"
            lowContrast
            hideCloseButton
            title="Copy the secret now"
            subtitle="It won't be shown again. Rotate it to get a new one."
          />
        )}
        {created && (
          <div>
            <p className="gisila-app__hint">Secret</p>
            <CodeSnippet type="single" feedbackTimeout={1500}>
              {created.secret}
            </CodeSnippet>
          </div>
        )}

        {data?.enabled && (
          <ul className="gisila-app__hint">
            <li>
              <strong>GitHub</strong>, <strong>Gitea / Forgejo</strong>:
              content type <code>application/json</code>, paste the secret,
              push events only.
            </li>
            <li>
              <strong>GitLab</strong>: paste the secret as the secret token,
              push events only.
            </li>
          </ul>
        )}

        {data?.enabled && (
          <div>
            <p className="gisila-app__hint">
              <strong>Commit status</strong>{" "}
              {data.reportsStatus ? (
                <Tag type="green" size="sm">reporting</Tag>
              ) : (
                <Tag type="cool-gray" size="sm">off</Tag>
              )}
              <br />
              Show deploying / deployed / failed on each pushed commit. Needs a
              token from the repository host: GitHub — a fine-grained token
              with <em>Commit statuses: write</em>; GitLab — <code>api</code>{" "}
              scope; Gitea / Forgejo — <code>write:repository</code>. Stored
              encrypted and never shown again.
            </p>
            {canManage && (
              <div className="gisila-app__row-actions">
                <TextInput
                  id={`status-token-${app.id}`}
                  type="password"
                  size="sm"
                  labelText="Status token"
                  hideLabel
                  placeholder={data.reportsStatus ? "Replace token" : "Paste a token"}
                  value={token}
                  onChange={(e) => setToken(e.target.value)}
                />
                <Button kind="tertiary" size="sm" disabled={busy || !token.trim()} onClick={() => saveToken(false)}>
                  Save token
                </Button>
                {data.reportsStatus && (
                  <Button kind="danger--ghost" size="sm" disabled={busy} onClick={() => saveToken(true)}>
                    Turn off
                  </Button>
                )}
              </div>
            )}
          </div>
        )}

        {data?.lastDeliveryAt && (
          <p className="gisila-app__hint">
            Last delivery {new Date(data.lastDeliveryAt).toLocaleString()}:{" "}
            {data.lastDeliveryResult}
          </p>
        )}

        {canManage ? (
          <div className="gisila-app__row-actions">
            {data?.enabled ? (
              <>
                <Button kind="tertiary" size="sm" disabled={busy} onClick={() => create(true)}>
                  Rotate secret
                </Button>
                <Button kind="danger--tertiary" size="sm" disabled={busy} onClick={remove}>
                  Remove webhook
                </Button>
              </>
            ) : (
              <Button kind="tertiary" size="sm" disabled={busy || !data} onClick={() => create(false)}>
                Create webhook
              </Button>
            )}
          </div>
        ) : (
          <p className="gisila-app__hint">
            Team admins can create or change the webhook.
          </p>
        )}
      </Stack>
    </Tile>
  );
}
