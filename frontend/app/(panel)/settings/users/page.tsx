"use client";

import { useState } from "react";
import useSWR from "swr";
import { toast } from "sonner";
import {
  Shield,
  Plus,
  Trash2,
  UserX,
  UserCheck,
  Loader,
  ShieldAlert,
  Users,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { api, fetcher } from "@/lib/api";
import { cn } from "@/lib/utils";
import type { ListResponse, User } from "@/lib/types";

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
      <div className="container py-16">
        <div className="mx-auto flex max-w-md flex-col items-center gap-4 text-center">
          <ShieldAlert className="h-12 w-12 text-muted-foreground/40" />
          <div>
            <h2 className="text-lg font-semibold">Superuser access required</h2>
            <p className="mt-1 text-sm text-muted-foreground">
              Only superusers can manage user accounts.
            </p>
          </div>
        </div>
      </div>
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
    <div className="container space-y-6 py-8">
      <header className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Users</h1>
          <p className="text-sm text-muted-foreground">
            Manage who has access to this panel.
          </p>
        </div>
        <Button onClick={() => setShowCreate(true)}>
          <Plus className="h-4 w-4" /> New user
        </Button>
      </header>

      {isLoading ? (
        <div className="flex items-center gap-2 text-sm text-muted-foreground">
          <Loader className="h-4 w-4 animate-spin" /> Loading…
        </div>
      ) : users.length === 0 ? (
        <Card>
          <CardContent className="flex flex-col items-center gap-3 py-16 text-center">
            <Users className="h-10 w-10 text-muted-foreground/40" />
            <p className="text-sm text-muted-foreground">No users yet.</p>
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-2">
          {users.map((user) => {
            const isSelf = user.id === me?.id;
            const busy = busyId === user.id;
            return (
              <Card key={user.id}>
                <CardContent className="flex items-center justify-between gap-4 px-5 py-3.5">
                  <div className="min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="truncate text-sm font-medium">
                        {user.firstName || user.lastName
                          ? `${user.firstName ?? ""} ${user.lastName ?? ""}`.trim()
                          : user.email}
                      </span>
                      {user.isSuperuser && (
                        <Badge
                          variant="outline"
                          className="gap-1 border-amber-500/40 bg-amber-500/10 text-amber-600 dark:text-amber-400"
                        >
                          <Shield className="h-3 w-3" />
                          Superuser
                        </Badge>
                      )}
                      {!user.isActive && (
                        <Badge variant="secondary">Inactive</Badge>
                      )}
                      {isSelf && (
                        <Badge variant="outline" className="text-xs font-normal">
                          you
                        </Badge>
                      )}
                    </div>
                    <p className="mt-0.5 truncate text-xs text-muted-foreground">
                      {user.email}
                    </p>
                  </div>

                  <div className="flex shrink-0 items-center gap-2">
                    {!isSelf && (
                      <>
                        <Button
                          size="sm"
                          variant="ghost"
                          className={cn(
                            "h-7 px-2 text-xs",
                            user.isActive
                              ? "text-muted-foreground"
                              : "text-emerald-600 hover:text-emerald-700",
                          )}
                          disabled={busy}
                          onClick={() => toggleActive(user)}
                          title={user.isActive ? "Deactivate" : "Activate"}
                        >
                          {busy ? (
                            <Loader className="h-3.5 w-3.5 animate-spin" />
                          ) : user.isActive ? (
                            <UserX className="h-3.5 w-3.5" />
                          ) : (
                            <UserCheck className="h-3.5 w-3.5" />
                          )}
                          {user.isActive ? "Deactivate" : "Activate"}
                        </Button>
                        <Button
                          size="sm"
                          variant="ghost"
                          className="h-7 px-2 text-destructive hover:text-destructive"
                          disabled={busy}
                          onClick={() => handleDelete(user)}
                        >
                          {busy ? (
                            <Loader className="h-3.5 w-3.5 animate-spin" />
                          ) : (
                            <Trash2 className="h-3.5 w-3.5" />
                          )}
                        </Button>
                      </>
                    )}
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}

      {/* Create user dialog */}
      <Dialog open={showCreate} onOpenChange={setShowCreate}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>New user</DialogTitle>
          </DialogHeader>
          <form onSubmit={handleCreate} className="space-y-4 py-1">
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label htmlFor="u-first">First name</Label>
                <Input
                  id="u-first"
                  value={form.firstName}
                  onChange={(e) => setForm({ ...form, firstName: e.target.value })}
                  placeholder="Alice"
                />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="u-last">Last name</Label>
                <Input
                  id="u-last"
                  value={form.lastName}
                  onChange={(e) => setForm({ ...form, lastName: e.target.value })}
                  placeholder="Smith"
                />
              </div>
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="u-email">Email</Label>
              <Input
                id="u-email"
                type="email"
                required
                value={form.email}
                onChange={(e) => setForm({ ...form, email: e.target.value })}
                placeholder="alice@example.com"
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="u-password">Password</Label>
              <Input
                id="u-password"
                type="password"
                required
                minLength={8}
                value={form.password}
                onChange={(e) => setForm({ ...form, password: e.target.value })}
              />
              <p className="text-xs text-muted-foreground">At least 8 characters.</p>
            </div>
            <div className="flex items-center gap-3 rounded-md border border-border bg-muted/30 px-3 py-2.5">
              <button
                type="button"
                role="switch"
                aria-checked={form.isSuperuser}
                onClick={() => setForm({ ...form, isSuperuser: !form.isSuperuser })}
                className={cn(
                  "relative inline-flex h-5 w-9 shrink-0 rounded-full transition-colors",
                  form.isSuperuser ? "bg-amber-500" : "bg-border",
                )}
              >
                <span
                  className={cn(
                    "absolute top-0.5 left-0.5 h-4 w-4 rounded-full bg-white shadow transition-transform",
                    form.isSuperuser && "translate-x-4",
                  )}
                />
              </button>
              <div>
                <p className="text-sm font-medium leading-none">
                  Grant superuser access
                </p>
                <p className="mt-0.5 text-xs text-muted-foreground">
                  Superusers can manage all users and settings.
                </p>
              </div>
            </div>
            <DialogFooter>
              <Button
                type="button"
                variant="outline"
                onClick={() => setShowCreate(false)}
              >
                Cancel
              </Button>
              <Button type="submit" disabled={creating}>
                {creating && <Loader className="h-3.5 w-3.5 animate-spin" />}
                Create account
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  );
}
