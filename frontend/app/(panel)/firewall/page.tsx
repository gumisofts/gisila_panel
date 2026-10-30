import { useEffect, useState } from "react";
import useSWR from "swr";
import { Add, Renew } from "@carbon/icons-react";
import {
  Button,
  InlineLoading,
  InlineNotification,
  Modal,
  Select,
  SelectItem,
  SkeletonText,
  Stack,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableHeader,
  TableRow,
  Tag,
  TextArea,
  TextInput,
  Tile,
} from "@carbon/react";
import { confirmDialog } from "@/components/confirm-dialog";
import { Page, PageHeader, PageSection } from "@/components/page";
import { api, fetcher } from "@/lib/api";
import { toast } from "@/lib/toast";
import type { User } from "@/lib/types";
import "./_firewall.scss";

type Action = "allow" | "deny" | "reject" | "limit";

interface FirewallRule {
  action: Action;
  proto: "tcp" | "udp" | "any";
  port: string | null;
  from: string;
  comment: string;
  families: string[];
  origin: "panel" | "base" | "web" | "other";
  raw?: string;
}

interface RuleSpec {
  action: Action;
  proto: string;
  port: string | null;
  from: string;
  note?: string;
}

interface FirewallChange {
  id: number;
  op: "add" | "delete" | "enable" | "disable" | "web-sources";
  // A rule for add / delete; the sources for web-sources.
  rule: RuleSpec | { sources: string[]; preset?: string } | null;
  status:
    | "queued"
    | "applying"
    | "awaiting_confirmation"
    | "confirm_requested"
    | "revert_requested"
    | "applied"
    | "rolled_back"
    | "failed";
  error: string | null;
  requestedBy: number | null;
  requestedByEmail: string | null;
  confirmBy: string | null;
  createdAt: string;
}

interface FirewallOverview {
  available?: boolean;
  reason?: string;
  active?: boolean;
  version?: string;
  defaultIncoming?: "allow" | "deny" | "reject" | null;
  sshPorts?: number[];
  rules?: FirewallRule[];
  // What 80 and 443 are limited to; empty when open to everyone.
  webSources?: string[];
  refreshedAt: string | null;
  confirmWindow: number;
  open: FirewallChange | null;
  recent: FirewallChange[];
}

const ACTION_TAG: Record<Action, "green" | "red" | "magenta" | "purple"> = {
  allow: "green",
  deny: "red",
  reject: "magenta",
  limit: "purple",
};

const STATUS: Record<FirewallChange["status"], { label: string; tag: "green" | "red" | "gray" | "blue" | "warm-gray" }> = {
  queued: { label: "Queued", tag: "blue" },
  applying: { label: "Applying", tag: "blue" },
  awaiting_confirmation: { label: "Checking", tag: "blue" },
  confirm_requested: { label: "Confirming", tag: "blue" },
  revert_requested: { label: "Reverting", tag: "blue" },
  applied: { label: "Applied", tag: "green" },
  rolled_back: { label: "Rolled back", tag: "warm-gray" },
  failed: { label: "Refused", tag: "red" },
};

function describeRule(r: { action: string; proto: string; port: string | null; from: string }) {
  const port = r.port ? `port ${r.port}${r.proto !== "any" ? `/${r.proto}` : ""}` : r.proto !== "any" ? `all ${r.proto}` : "all ports";
  const from = r.from === "any" ? "anywhere" : r.from;
  return `${r.action} ${port} from ${from}`;
}

function isRuleSpec(r: FirewallChange["rule"]): r is RuleSpec {
  return !!r && "action" in r;
}

function describeChange(c: FirewallChange) {
  switch (c.op) {
    case "enable":
      return "Turn the firewall on";
    case "disable":
      return "Turn the firewall off";
    case "add":
      return isRuleSpec(c.rule) ? `Add: ${describeRule(c.rule)}` : "Add a rule";
    case "delete":
      return isRuleSpec(c.rule) ? `Remove: ${describeRule(c.rule)}` : "Remove a rule";
    case "web-sources": {
      const r = c.rule && "sources" in c.rule ? c.rule : null;
      if (!r?.sources.length) return "Open ports 80 and 443 to everyone";
      if (r.preset === "cloudflare") return "Limit ports 80 and 443 to Cloudflare";
      return `Limit ports 80 and 443 to ${r.sources.length} source${r.sources.length === 1 ? "" : "s"}`;
    }
  }
}

function ruleNote(r: FirewallRule) {
  if (r.origin === "base") return "Kept open by the panel";
  if (r.origin === "web") return "Web ports limited from the panel";
  if (r.origin === "panel") {
    const note = r.comment.replace(/^gisila-panel:?\s*/, "");
    return note || "Added from the panel";
  }
  return r.raw ? `Other: ${r.raw}` : r.comment || "Added outside this page";
}

export default function FirewallPage() {
  const { data: me } = useSWR<User>("/auth/me", fetcher);
  const [watching, setWatching] = useState<number | null>(null);
  const { data, error, mutate } = useSWR<FirewallOverview>("/firewall", fetcher, {
    // Fast while a change is in flight. FirewallConfirmer, on every page,
    // confirms it once applied.
    refreshInterval: (d) => (d?.open || watching ? 1500 : 15000),
  });
  const [adding, setAdding] = useState(false);
  const [limiting, setLimiting] = useState(false);
  const [busy, setBusy] = useState(false);

  const open = data?.open ?? null;

  // Report how a change this browser made ended.
  useEffect(() => {
    if (watching == null || !data) return;
    const c = data.recent.find((r) => r.id === watching);
    if (!c || data.open?.id === watching) return;
    setWatching(null);
    if (c.status === "applied") toast.success(`${describeChange(c)}: done.`);
    else toast.error(c.error ?? `${describeChange(c)}: ${STATUS[c.status].label.toLowerCase()}.`);
  }, [data, watching]);

  async function submit(path: string, body?: object) {
    setBusy(true);
    try {
      const change = await api<FirewallChange>(path, {
        method: "POST",
        body: body ? JSON.stringify(body) : undefined,
      });
      setWatching(change.id);
      await mutate();
      return true;
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "The change was not accepted.");
      return false;
    } finally {
      setBusy(false);
    }
  }

  async function toggle() {
    if (data?.active) {
      if (!(await confirmDialog("Turn the firewall off? Every port that a service listens on publicly becomes reachable.", { confirmLabel: "Turn off" }))) return;
      await submit("/firewall/disable");
    } else {
      if (!(await confirmDialog(`Turn the firewall on? Incoming connections are then ${data?.defaultIncoming === "allow" ? "allowed" : "blocked"} by default, except on the ports the rules below allow. SSH (${(data?.sshPorts ?? [22]).join(", ")}), 80 and 443 are kept open.`, { danger: false, confirmLabel: "Turn on" }))) return;
      await submit("/firewall/enable");
    }
  }

  async function remove(r: FirewallRule) {
    if (!(await confirmDialog(`Remove the rule "${describeRule(r)}"?`, { confirmLabel: "Remove" }))) return;
    await submit("/firewall/rules/remove", { action: r.action, proto: r.proto, port: r.port, from: r.from });
  }

  async function webSources(body: { preset?: string; sources?: string }, question: string) {
    if (!(await confirmDialog(question, { danger: false, confirmLabel: "Apply" }))) return false;
    return submit("/firewall/web-sources", body);
  }

  async function refresh() {
    await api("/firewall/refresh", { method: "POST" });
    toast.success("Reading the firewall again…");
    setTimeout(() => void mutate(), 2500);
  }

  const unavailable = data && data.available === false;
  // Nothing can be changed before the worker has read the firewall once.
  const busyChange = busy || !!open || data?.available !== true;

  return (
    <Page>
      <PageHeader
        title="Firewall"
        description="Allow or block incoming connections to this server (ufw)."
        actions={
          <>
            <Button kind="ghost" size="md" renderIcon={Renew} onClick={refresh}>
              Refresh
            </Button>
            {data?.available && (
              <Button kind={data.active ? "danger--tertiary" : "primary"} size="md" disabled={busyChange} onClick={toggle}>
                {data.active ? "Turn off" : "Turn on"}
              </Button>
            )}
          </>
        }
      />

      {error && (
        <InlineNotification kind="error" lowContrast hideCloseButton title="Could not load the firewall." subtitle={error instanceof Error ? error.message : undefined} />
      )}
      {!data && !error && <SkeletonText paragraph lineCount={4} />}

      {unavailable && (
        <InlineNotification kind="warning" lowContrast hideCloseButton title="Firewall not available" subtitle={data.reason ?? "ufw is not installed on this server."} />
      )}

      {data && !unavailable && (
        <>
          {open && <OpenChange change={open} mine={!!me && open.requestedBy === Number(me.id)} onRevert={async () => {
            await api(`/firewall/changes/${open.id}/revert`, { method: "POST" }).catch((e: unknown) => toast.error(e instanceof Error ? e.message : "Could not revert."));
            await mutate();
          }} />}

          <PageSection>
            <Tile className="gisila-firewall__status">
              <div>
                <p className="gisila-firewall__label">Status</p>
                {data.available === undefined ? (
                  <Tag type="gray">Not read yet</Tag>
                ) : data.active ? (
                  <Tag type="green">Active</Tag>
                ) : (
                  <Tag type="cool-gray">Inactive</Tag>
                )}
              </div>
              <div>
                <p className="gisila-firewall__label">Incoming by default</p>
                <p>{data.defaultIncoming ?? "—"}</p>
              </div>
              <div>
                <p className="gisila-firewall__label">SSH ports (always open)</p>
                <p>{data.sshPorts?.join(", ") ?? "—"}</p>
              </div>
              <div>
                <p className="gisila-firewall__label">Last read</p>
                <p>{data.refreshedAt ? new Date(data.refreshedAt).toLocaleTimeString() : "—"}</p>
              </div>
            </Tile>
            <p className="gisila-firewall__hint">
              You can't lock yourself out from here. After a change is
              applied, your browser confirms it as soon as it reaches the
              panel again, from any page. If you don't get back to the panel
              within {Math.round(data.confirmWindow / 60)} minutes, the old
              rules come back on their own. Rules that would block SSH or
              the panel for everyone, or block your own IP address, are
              refused. Docker's published ports bypass ufw.
            </p>
          </PageSection>

          <WebPorts
            sources={data.webSources ?? []}
            disabled={busyChange}
            onCloudflare={() =>
              webSources(
                { preset: "cloudflare" },
                "Let only Cloudflare reach ports 80 and 443? Sites whose DNS record is not proxied through Cloudflare (grey cloud) stop loading, and their HTTP certificate renewals fail.",
              )
            }
            onCustom={() => setLimiting(true)}
            onOpen={() => webSources({ sources: "" }, "Open ports 80 and 443 to everyone again?")}
          />

          <PageSection
            title="Rules"
            description="ufw checks rules from the top and stops at the first match. Blocks are put above allows."
            actions={
              <Button size="sm" renderIcon={Add} disabled={busyChange} onClick={() => setAdding(true)}>
                Add rule
              </Button>
            }
          >
            <TableContainer>
              <Table size="sm">
                <TableHead>
                  <TableRow>
                    <TableHeader>Action</TableHeader>
                    <TableHeader>Port</TableHeader>
                    <TableHeader>Protocol</TableHeader>
                    <TableHeader>From</TableHeader>
                    <TableHeader>Note</TableHeader>
                    <TableHeader>IP</TableHeader>
                    <TableHeader />
                  </TableRow>
                </TableHead>
                <TableBody>
                  {(data.rules ?? []).length === 0 && (
                    <TableRow>
                      <TableCell colSpan={7}>No rules yet.</TableCell>
                    </TableRow>
                  )}
                  {(data.rules ?? []).map((r, i) => (
                    <TableRow key={`${i}-${r.action}-${r.port}-${r.from}-${r.proto}`}>
                      <TableCell>
                        <Tag type={ACTION_TAG[r.action] ?? "gray"} size="sm">{r.action}</Tag>
                      </TableCell>
                      <TableCell>{r.port ?? "all"}</TableCell>
                      <TableCell>{r.proto}</TableCell>
                      <TableCell>{r.from === "any" ? "Anywhere" : r.from}</TableCell>
                      <TableCell className="gisila-firewall__note">{ruleNote(r)}</TableCell>
                      <TableCell>{r.families.map((f) => (f === "v4" ? "IPv4" : "IPv6")).join(", ")}</TableCell>
                      <TableCell>
                        {r.origin === "panel" && (
                          <Button kind="danger--ghost" size="sm" disabled={busyChange} onClick={() => remove(r)}>
                            Remove
                          </Button>
                        )}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </TableContainer>
          </PageSection>

          <PageSection title="Recent changes">
            <TableContainer>
              <Table size="sm">
                <TableHead>
                  <TableRow>
                    <TableHeader>When</TableHeader>
                    <TableHeader>Change</TableHeader>
                    <TableHeader>By</TableHeader>
                    <TableHeader>Result</TableHeader>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {data.recent.length === 0 && (
                    <TableRow>
                      <TableCell colSpan={4}>No changes yet.</TableCell>
                    </TableRow>
                  )}
                  {data.recent.map((c) => (
                    <TableRow key={c.id}>
                      <TableCell>{new Date(c.createdAt).toLocaleString()}</TableCell>
                      <TableCell>{describeChange(c)}</TableCell>
                      <TableCell>{c.requestedByEmail ?? "—"}</TableCell>
                      <TableCell>
                        <Tag type={STATUS[c.status].tag} size="sm">{STATUS[c.status].label}</Tag>
                        {c.error && <span className="gisila-firewall__error">{c.error}</span>}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </TableContainer>
          </PageSection>
        </>
      )}

      <WebSourcesModal
        open={limiting}
        busy={busy}
        initial={data?.webSources ?? []}
        onClose={() => setLimiting(false)}
        onSubmit={async (sources) => {
          if (await webSources({ sources }, "Limit ports 80 and 443 to these sources? Anything else, including sites not reached through them, is cut off.")) setLimiting(false);
        }}
      />

      <AddRuleModal
        open={adding}
        busy={busy}
        onClose={() => setAdding(false)}
        onSubmit={async (rule) => {
          if (await submit("/firewall/rules", rule)) setAdding(false);
        }}
      />
    </Page>
  );
}

function WebPorts({
  sources,
  disabled,
  onCloudflare,
  onCustom,
  onOpen,
}: {
  sources: string[];
  disabled: boolean;
  onCloudflare: () => void;
  onCustom: () => void;
  onOpen: () => void;
}) {
  const limited = sources.length > 0;
  return (
    <PageSection
      title="Web ports (80, 443)"
      description="Who can reach the sites and the panel. When every domain is proxied through Cloudflare, letting only Cloudflare in stops anyone from going around it to this server."
      actions={
        <>
          <Button kind="tertiary" size="sm" disabled={disabled} onClick={onCloudflare}>
            Only Cloudflare
          </Button>
          <Button kind="ghost" size="sm" disabled={disabled} onClick={onCustom}>
            Custom…
          </Button>
          {limited && (
            <Button kind="danger--ghost" size="sm" disabled={disabled} onClick={onOpen}>
              Open to everyone
            </Button>
          )}
        </>
      }
    >
      <Tile>
        {limited ? (
          <>
            <Tag type="purple">Limited</Tag> Only {sources.length} source{sources.length === 1 ? "" : "s"} can connect:{" "}
            <span className="gisila-firewall__note">{sources.join(", ")}</span>
          </>
        ) : (
          <>
            <Tag type="green">Open</Tag> Anyone can connect.
          </>
        )}
      </Tile>
    </PageSection>
  );
}

function WebSourcesModal({
  open,
  busy,
  initial,
  onClose,
  onSubmit,
}: {
  open: boolean;
  busy: boolean;
  initial: string[];
  onClose: () => void;
  onSubmit: (sources: string) => void;
}) {
  const [text, setText] = useState("");
  useEffect(() => {
    if (open) setText(initial.join("\n"));
    // Only when it opens: the list refreshes in the background.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);
  const empty = text.trim() === "";
  return (
    <Modal
      open={open}
      modalHeading="Limit ports 80 and 443"
      primaryButtonText={busy ? "Applying…" : "Limit"}
      secondaryButtonText="Cancel"
      primaryButtonDisabled={busy || empty}
      onRequestClose={onClose}
      onRequestSubmit={() => onSubmit(text)}
      size="sm"
    >
      <TextArea
        id="fw-web-sources"
        labelText="Sources"
        helperText="IP addresses or ranges, one per line. The address you reach the panel from has to be among them, or the change is refused."
        rows={8}
        value={text}
        onChange={(e) => setText(e.target.value)}
      />
    </Modal>
  );
}

function OpenChange({ change, mine, onRevert }: { change: FirewallChange; mine: boolean; onRevert: () => void }) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, []);
  const left = change.confirmBy ? Math.max(0, Math.round((Date.parse(change.confirmBy) - now) / 1000)) : null;
  const text =
    change.status === "awaiting_confirmation"
      ? mine
        ? "Applied. Confirming that you can still reach the panel…"
        : `Applied by ${change.requestedByEmail ?? "another admin"}, waiting for them to reach the panel${left != null ? ` (rolls back in ${Math.floor(left / 60)}:${String(left % 60).padStart(2, "0")})` : ""}.`
      : change.status === "confirm_requested"
        ? "Reached the panel through the new rules. Keeping the change…"
        : change.status === "revert_requested"
          ? "Putting the old rules back…"
          : "Applying…";
  return (
    <Tile className="gisila-firewall__open">
      <InlineLoading description={`${describeChange(change)}: ${text}`} />
      {change.status === "awaiting_confirmation" && (
        <Button kind="danger--ghost" size="sm" onClick={onRevert}>
          Revert now
        </Button>
      )}
    </Tile>
  );
}

function AddRuleModal({
  open,
  busy,
  onClose,
  onSubmit,
}: {
  open: boolean;
  busy: boolean;
  onClose: () => void;
  onSubmit: (rule: { action: Action; proto: string; port: string; from: string; note: string }) => void;
}) {
  const [action, setAction] = useState<Action>("allow");
  const [proto, setProto] = useState("tcp");
  const [port, setPort] = useState("");
  const [from, setFrom] = useState("");
  const [note, setNote] = useState("");

  useEffect(() => {
    if (open) {
      setAction("allow");
      setProto("tcp");
      setPort("");
      setFrom("");
      setNote("");
    }
  }, [open]);

  const portOk = port === "" || /^\d{1,5}(:\d{1,5})?$/.test(port.trim());
  const needsPort = action === "limit" || (action === "allow" && from.trim() === "");

  return (
    <Modal
      open={open}
      modalHeading="Add a firewall rule"
      primaryButtonText={busy ? "Adding…" : "Add rule"}
      secondaryButtonText="Cancel"
      primaryButtonDisabled={busy || !portOk || (needsPort && port.trim() === "")}
      onRequestClose={onClose}
      onRequestSubmit={() => onSubmit({ action, proto, port: port.trim(), from: from.trim() || "any", note: note.trim() })}
      size="sm"
    >
      <Stack gap={5}>
        <Select id="fw-action" labelText="Action" value={action} onChange={(e) => setAction(e.target.value as Action)}>
          <SelectItem value="allow" text="Allow" />
          <SelectItem value="deny" text="Block (drop silently)" />
          <SelectItem value="reject" text="Reject (refuse with an error)" />
          <SelectItem value="limit" text="Rate limit (6 connections in 30s per IP)" />
        </Select>
        <TextInput
          id="fw-port"
          labelText="Port"
          placeholder={action === "deny" || action === "reject" ? "Empty for every port" : "e.g. 8080 or 6000:6010"}
          helperText="A port, or a range like 6000:6010 (ranges need TCP or UDP)."
          invalid={!portOk}
          invalidText="Use a port number or a range like 6000:6010."
          value={port}
          onChange={(e) => setPort(e.target.value)}
        />
        <Select id="fw-proto" labelText="Protocol" value={proto} onChange={(e) => setProto(e.target.value)}>
          <SelectItem value="tcp" text="TCP" />
          <SelectItem value="udp" text="UDP" />
          <SelectItem value="any" text="TCP and UDP" />
        </Select>
        <TextInput
          id="fw-from"
          labelText="From"
          placeholder="Anywhere"
          helperText="An IP address or range, like 203.0.113.7 or 203.0.113.0/24. Empty means anywhere."
          value={from}
          onChange={(e) => setFrom(e.target.value)}
        />
        <TextInput
          id="fw-note"
          labelText="Note (optional)"
          maxLength={60}
          placeholder="e.g. office VPN"
          value={note}
          onChange={(e) => setNote(e.target.value)}
        />
      </Stack>
    </Modal>
  );
}
