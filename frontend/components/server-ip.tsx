import useSWR from "swr";
import { Copy } from "@carbon/icons-react";
import { fetcher } from "@/lib/api";
import { toast } from "@/lib/toast";

export interface BuildStamp {
  version: string;
  commit: string;
  builtAt: string;
}

export interface ServerInfo {
  hostname: string;
  publicIp: string | null;
  privateIps: string[];
  // Absent from panels older than the version display.
  version?: {
    panel: BuildStamp;
    // Null when the agent can't be asked (missing, or too old to say).
    agent: BuildStamp | null;
  };
}

/// Addresses and build versions of the host the panel runs on. They
/// practically never change, so fetch once per session rather than on every
/// focus.
export function useServerInfo() {
  return useSWR<ServerInfo>("/system/info", fetcher, {
    revalidateOnFocus: false,
    dedupingInterval: 10 * 60_000,
  });
}

/// Header chip showing the server's public IP; clicking copies it — the usual
/// reason to look it up is pasting it into a DNS A record.
export function ServerIpChip() {
  const { data } = useServerInfo();
  const ip = data?.publicIp;
  if (!ip) return null;

  const detail = [
    data.hostname,
    data.privateIps.length ? `private: ${data.privateIps.join(", ")}` : "",
  ]
    .filter(Boolean)
    .join(" · ");

  return (
    <button
      type="button"
      className="gisila-server-ip"
      title={`${detail} — click to copy`}
      onClick={() => {
        void navigator.clipboard.writeText(ip);
        toast.success(`Copied ${ip}`);
      }}
    >
      <span className="gisila-server-ip__label">Server IP</span>
      <span className="gisila-server-ip__value">{ip}</span>
      <Copy size={16} />
    </button>
  );
}
