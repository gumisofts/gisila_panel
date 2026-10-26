"use client";

import { useState } from "react";
import {
  FileUploaderDropContainer,
  FileUploaderItem,
  InlineNotification,
  Modal,
  Stack,
} from "@carbon/react";
import { api, uploadFile } from "@/lib/api";
import type { App } from "@/lib/types";

// Matches the server's cap (and nginx's client_max_body_size).
const MAX_MB = 50;

/// "Deploy now" for binary and zip apps: pick the file, upload it, then
/// trigger a deployment of that upload.
export function DeployUploadModal({
  app,
  open,
  onClose,
  onDeployed,
}: {
  app: App;
  open: boolean;
  onClose: () => void;
  onDeployed: () => void;
}) {
  const isZip = app.sourceType === "zip";
  const [file, setFile] = useState<File | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function close() {
    if (busy) return;
    setFile(null);
    setError(null);
    onClose();
  }

  async function submit() {
    if (!file) return;
    setBusy(true);
    setError(null);
    try {
      const { artifactId } = await uploadFile<{ artifactId: string }>(
        `/apps/${app.id}/deployments/artifacts`,
        file,
      );
      await api(`/apps/${app.id}/deployments/`, {
        method: "POST",
        body: JSON.stringify({ sourceType: app.sourceType, artifactId }),
      });
      setFile(null);
      onDeployed();
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "Upload failed");
    } finally {
      setBusy(false);
    }
  }

  const tooBig = file != null && file.size > MAX_MB * 1024 * 1024;

  return (
    <Modal
      open={open}
      size="sm"
      modalHeading={`Deploy ${app.name}`}
      modalLabel={isZip ? "ZIP upload" : "Binary upload"}
      primaryButtonText={busy ? "Uploading…" : "Upload and deploy"}
      primaryButtonDisabled={!file || tooBig || busy}
      secondaryButtonText="Cancel"
      onRequestClose={close}
      onRequestSubmit={submit}
    >
      <Stack gap={5}>
        <p>
          {isZip
            ? "Upload a .zip of the project source. It is unpacked and built the same way as a git checkout."
            : "Upload a compiled Linux executable (ELF) or #! script. It runs directly as the app's start command."}{" "}
          Up to {MAX_MB} MB.
        </p>
        {file ? (
          <FileUploaderItem
            name={file.name}
            status={busy ? "uploading" : "edit"}
            invalid={tooBig}
            errorSubject={tooBig ? `Larger than ${MAX_MB} MB` : undefined}
            onDelete={() => !busy && setFile(null)}
          />
        ) : (
          <FileUploaderDropContainer
            labelText={
              isZip
                ? "Drag a .zip here or click to choose"
                : "Drag the binary here or click to choose"
            }
            accept={isZip ? [".zip", "application/zip"] : []}
            multiple={false}
            onAddFiles={(_e, { addedFiles }) => {
              setError(null);
              setFile(addedFiles[0] ?? null);
            }}
          />
        )}
        {error && (
          <InlineNotification
            kind="error"
            lowContrast
            hideCloseButton
            title="Deploy failed"
            subtitle={error}
          />
        )}
      </Stack>
    </Modal>
  );
}
