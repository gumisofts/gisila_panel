"use client";

import { useState } from "react";
import useSWR from "swr";
import {
  Button,
  Stack,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableHeader,
  TableRow,
  Tag,
  TextInput,
  Tile,
} from "@carbon/react";
import { Add, Earth, Security, TrashCan } from "@carbon/icons-react";
import { toast } from "@/lib/toast";
import { api, fetcher } from "@/lib/api";
import { formatRelative } from "@/lib/utils";
import type { Domain, ListResponse } from "@/lib/types";
import "../_app-detail.scss";

export function DomainsTab({ appId }: { appId: number }) {
  const { data, mutate } = useSWR<ListResponse<Domain>>(
    `/apps/${appId}/domains/`,
    fetcher,
    { refreshInterval: 5000 },
  );
  const [hostname, setHostname] = useState("");
  const [busy, setBusy] = useState(false);

  async function add(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    try {
      await api(`/apps/${appId}/domains/`, {
        method: "POST",
        body: JSON.stringify({ hostname }),
      });
      setHostname("");
      mutate();
      toast.success("Domain attached");
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed");
    } finally {
      setBusy(false);
    }
  }

  async function issue(id: number) {
    try {
      await api(`/apps/${appId}/domains/${id}/ssl`, { method: "POST" });
      toast.success("Certificate issuance queued");
      mutate();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed");
    }
  }

  async function remove(id: number) {
    if (!confirm("Remove this domain?")) return;
    await api(`/apps/${appId}/domains/${id}`, { method: "DELETE" });
    mutate();
  }

  return (
    <Stack gap={5}>
      <Tile>
        <form onSubmit={add} className="gisila-app__form-row">
          <div className="gisila-app__form-field">
            <TextInput
              id="domain-hostname"
              labelText="Custom domain"
              value={hostname}
              onChange={(e) => setHostname(e.target.value)}
              placeholder="api.example.com"
              required
            />
          </div>
          <Button type="submit" renderIcon={Add} disabled={busy}>
            Attach
          </Button>
        </form>
      </Tile>

      {data?.results.length ? (
        <TableContainer>
          <Table size="md">
            <TableHead>
              <TableRow>
                <TableHeader>Hostname</TableHeader>
                <TableHeader>TLS</TableHeader>
                <TableHeader aria-label="Actions" />
              </TableRow>
            </TableHead>
            <TableBody>
              {data.results.map((d) => (
                <TableRow key={d.id}>
                  <TableCell>
                    <span className="gisila-app__inline">
                      <Earth size={16} />
                      {d.hostname}
                    </span>
                  </TableCell>
                  <TableCell>
                    <span className="gisila-app__label">
                      SSL: {d.sslStatus}
                      {d.sslExpiresAt
                        ? ` · expires ${formatRelative(d.sslExpiresAt)}`
                        : ""}
                    </span>
                  </TableCell>
                  <TableCell>
                    <div className="gisila-app__row-actions">
                      {d.sslStatus === "issued" ? (
                        <Tag type="green" size="sm">
                          https
                        </Tag>
                      ) : (
                        <Button
                          size="sm"
                          kind="tertiary"
                          renderIcon={Security}
                          onClick={() => issue(d.id)}
                        >
                          Issue cert
                        </Button>
                      )}
                      <Button
                        size="sm"
                        kind="danger--ghost"
                        hasIconOnly
                        renderIcon={TrashCan}
                        iconDescription={`Remove ${d.hostname}`}
                        onClick={() => remove(d.id)}
                      />
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </TableContainer>
      ) : (
        <Tile className="gisila-empty">No domains attached yet.</Tile>
      )}
    </Stack>
  );
}
