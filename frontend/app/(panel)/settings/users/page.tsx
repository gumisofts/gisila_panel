"use client";

import { useState } from "react";
import useSWR from "swr";
import { toast } from "@/lib/toast";
import {
  Add,
  Security,
  SecurityServices,
  TrashCan,
  UserFollow,
  UserMinus,
  UserMultiple,
} from "@carbon/icons-react";
import {
  Button,
  ComposedModal,
  Form,
  InlineLoading,
  ModalBody,
  ModalFooter,
  ModalHeader,
  PasswordInput,
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
  Toggle,
} from "@carbon/react";
import { Page, PageHeader } from "@/components/page";
import { api, fetcher } from "@/lib/api";
import type { ListResponse, User } from "@/lib/types";
import "../_settings.scss";

const CREATE_FORM_ID = "new-user-form";

export default function UsersPage() {
  const { data: me } = useSWR<User>("/auth/me", fetcher);
  const { data, mutate, isLoading } = useSWR<ListResponse<User>>(
    "/auth/users",
    fetcher,
  );

  const [showCreate, setShowCreate] = useState(false);
  const [form, setForm] = useState({
    email: "",
    password: "",
    firstName: "",
    lastName: "",
    isSuperuser: false,
  });
  const [creating, setCreating] = useState(false);
  const [busyId, setBusyId] = useState<number | null>(null);

  if (me && !me.isSuperuser) {
    return (
      <Page>
        <Tile className="gisila-empty">
          <div className="gisila-settings__empty">
            <SecurityServices size={32} />
            <div>
              <h2 className="gisila-settings__empty-title">
                Superuser access required
              </h2>
              <p>Only superusers can manage user accounts.</p>
            </div>
          </div>
        </Tile>
      </Page>
    );
  }

  async function handleCreate(e: React.FormEvent) {
    e.preventDefault();
    setCreating(true);
    try {
      await api("/auth/users", {
        method: "POST",
        body: JSON.stringify(form),
      });
      toast.success(`Account created for ${form.email}`);
      setShowCreate(false);
      setForm({ email: "", password: "", firstName: "", lastName: "", isSuperuser: false });
      mutate();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed to create user");
    } finally {
      setCreating(false);
    }
  }

  async function toggleActive(user: User) {
    setBusyId(user.id);
    try {
      await api(`/auth/users/${user.id}`, {
        method: "PATCH",
        body: JSON.stringify({ isActive: !user.isActive }),
      });
      toast.success(user.isActive ? "User deactivated" : "User activated");
      mutate();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed");
    } finally {
      setBusyId(null);
    }
  }

  async function handleDelete(user: User) {
    if (!confirm(`Delete ${user.email}? This cannot be undone.`)) return;
    setBusyId(user.id);
    try {
      await api(`/auth/users/${user.id}`, { method: "DELETE" });
      toast.success("User deleted");
      mutate();
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Failed");
    } finally {
      setBusyId(null);
    }
  }

  const users = data?.results ?? [];

  return (
    <Page>
      <PageHeader
        title="Users"
        description="Manage who has access to this panel."
        actions={
          <Button renderIcon={Add} onClick={() => setShowCreate(true)}>
            New user
          </Button>
        }
      />

      {isLoading ? (
        <InlineLoading description="Loading…" />
      ) : users.length === 0 ? (
        <Tile className="gisila-empty">
          <div className="gisila-settings__empty">
            <UserMultiple size={32} />
            <p>No users yet.</p>
          </div>
        </Tile>
      ) : (
        <TableContainer>
          <Table size="sm">
            <TableHead>
              <TableRow>
                <TableHeader>Name</TableHeader>
                <TableHeader>Email</TableHeader>
                <TableHeader />
              </TableRow>
            </TableHead>
            <TableBody>
              {users.map((user) => {
                const isSelf = user.id === me?.id;
                const busy = busyId === user.id;
                return (
                  <TableRow key={user.id}>
                    <TableCell>
                      <div className="gisila-settings__name">
                        <span>
                          {user.firstName || user.lastName
                            ? `${user.firstName ?? ""} ${user.lastName ?? ""}`.trim()
                            : user.email}
                        </span>
                        {user.isSuperuser && (
                          <Tag type="purple" size="sm" renderIcon={Security}>
                            Superuser
                          </Tag>
                        )}
                        {!user.isActive && (
                          <Tag type="gray" size="sm">
                            Inactive
                          </Tag>
                        )}
                        {isSelf && (
                          <Tag type="outline" size="sm">
                            you
                          </Tag>
                        )}
                      </div>
                    </TableCell>
                    <TableCell>{user.email}</TableCell>
                    <TableCell>
                      <div className="gisila-settings__row-actions">
                        {!isSelf && (
                          <>
                            {busy && <InlineLoading />}
                            <Button
                              kind="ghost"
                              size="sm"
                              renderIcon={user.isActive ? UserMinus : UserFollow}
                              disabled={busy}
                              onClick={() => toggleActive(user)}
                            >
                              {user.isActive ? "Deactivate" : "Activate"}
                            </Button>
                            <Button
                              kind="danger--ghost"
                              size="sm"
                              hasIconOnly
                              renderIcon={TrashCan}
                              iconDescription="Delete user"
                              disabled={busy}
                              onClick={() => handleDelete(user)}
                            />
                          </>
                        )}
                      </div>
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </TableContainer>
      )}

      {/* Create user dialog */}
      <ComposedModal
        open={showCreate}
        onClose={() => setShowCreate(false)}
        size="sm"
      >
        <ModalHeader title="New user" />
        <ModalBody hasForm>
          {/* The submit button lives in the footer, outside the form element, so
              it is wired back to it by id — that keeps the browser's own
              required/minLength/email validation in charge of submission. */}
          <Form id={CREATE_FORM_ID} onSubmit={handleCreate}>
            <Stack gap={5}>
              <div className="gisila-settings__form-row">
                <div className="gisila-settings__form-field">
                  <TextInput
                    id="u-first"
                    labelText="First name"
                    value={form.firstName}
                    onChange={(e) => setForm({ ...form, firstName: e.target.value })}
                    placeholder="Alice"
                  />
                </div>
                <div className="gisila-settings__form-field">
                  <TextInput
                    id="u-last"
                    labelText="Last name"
                    value={form.lastName}
                    onChange={(e) => setForm({ ...form, lastName: e.target.value })}
                    placeholder="Smith"
                  />
                </div>
              </div>
              <TextInput
                id="u-email"
                labelText="Email"
                type="email"
                required
                value={form.email}
                onChange={(e) => setForm({ ...form, email: e.target.value })}
                placeholder="alice@example.com"
              />
              <PasswordInput
                id="u-password"
                labelText="Password"
                required
                minLength={8}
                helperText="At least 8 characters."
                value={form.password}
                onChange={(e) => setForm({ ...form, password: e.target.value })}
              />
              <div>
                <Toggle
                  id="u-superuser"
                  labelText="Grant superuser access"
                  labelA="Off"
                  labelB="On"
                  toggled={form.isSuperuser}
                  onToggle={(checked) => setForm({ ...form, isSuperuser: checked })}
                />
                <p className="gisila-settings__hint">
                  Superusers can manage all users and settings.
                </p>
              </div>
            </Stack>
          </Form>
        </ModalBody>
        <ModalFooter>
          <Button kind="secondary" onClick={() => setShowCreate(false)}>
            Cancel
          </Button>
          <Button
            kind="primary"
            type="submit"
            form={CREATE_FORM_ID}
            disabled={creating}
          >
            {creating ? (
              <InlineLoading
                className="cds--inline-loading--btn"
                description="Creating…"
              />
            ) : (
              "Create account"
            )}
          </Button>
        </ModalFooter>
      </ComposedModal>
    </Page>
  );
}
