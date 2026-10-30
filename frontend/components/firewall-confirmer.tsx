import { useEffect, useRef } from "react";
import useSWR from "swr";
import { api, fetcher } from "@/lib/api";
import type { User } from "@/lib/types";

interface Pending {
  open: { id: number; status: string; requestedBy: number | null } | null;
}

/// Keeps a firewall change once its requester is back on the panel.
///
/// Mounted on every page for superusers. A change made on the Firewall page
/// is rolled back by the server unless the browser of the person who made
/// it confirms it in time; that this request gets through at all proves the
/// new rules didn't cut them off. Polls slowly, and quickly while a change
/// is in flight.
export function FirewallConfirmer() {
  const { data: me } = useSWR<User>("/auth/me", fetcher);
  const { data, mutate } = useSWR<Pending>(
    me?.isSuperuser ? "/firewall/pending" : null,
    fetcher,
    { refreshInterval: (d) => (d?.open ? 2000 : 20000), shouldRetryOnError: true },
  );
  const sent = useRef(new Set<number>());
  const open = data?.open;

  useEffect(() => {
    if (!open || !me || open.status !== "awaiting_confirmation") return;
    if (open.requestedBy !== Number(me.id) || sent.current.has(open.id)) return;
    sent.current.add(open.id);
    api(`/firewall/changes/${open.id}/confirm`, { method: "POST" })
      .then(() => mutate())
      .catch(() => sent.current.delete(open.id));
  }, [open, me, mutate]);

  return null;
}
