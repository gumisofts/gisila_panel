"use client";

import { useState } from "react";
import {
  Button,
  Link as CarbonLink,
  PasswordInput,
  Stack,
  TextInput,
} from "@carbon/react";
import RouterLink from "@/compat/link";
import { useRouter } from "@/compat/navigation";
import { toast } from "@/lib/toast";
import { api, setToken } from "@/lib/api";
import type { User, Team } from "@/lib/types";
import "../../(panel)/_batch-a.scss";

export default function RegisterPage() {
  const router = useRouter();
  const [form, setForm] = useState({
    email: "",
    password: "",
    firstName: "",
    lastName: "",
  });
  const [loading, setLoading] = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    try {
      const res = await api<{ access: string; user: User; team: Team }>(
        "/auth/register",
        {
          method: "POST",
          body: JSON.stringify(form),
        },
      );
      setToken(res.access);
      toast.success(`Welcome ${res.user.firstName ?? ""}!`);
      router.push("/dashboard");
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Sign-up failed");
    } finally {
      setLoading(false);
    }
  }

  return (
    <Stack gap={6}>
      <div>
        <h1 className="gisila-auth__title">Create your panel</h1>
        <p className="gisila-auth__subtitle">
          One panel, infinite apps. 30 seconds to first deploy.
        </p>
      </div>
      <form onSubmit={onSubmit}>
        <Stack gap={5}>
          <div className="gisila-auth__names">
            <TextInput
              id="firstName"
              labelText="First name"
              value={form.firstName}
              onChange={(e) => setForm({ ...form, firstName: e.target.value })}
            />
            <TextInput
              id="lastName"
              labelText="Last name"
              value={form.lastName}
              onChange={(e) => setForm({ ...form, lastName: e.target.value })}
            />
          </div>
          <TextInput
            id="email"
            labelText="Email"
            type="email"
            required
            value={form.email}
            onChange={(e) => setForm({ ...form, email: e.target.value })}
          />
          <PasswordInput
            id="password"
            labelText="Password"
            required
            minLength={8}
            helperText="At least 8 characters."
            value={form.password}
            onChange={(e) => setForm({ ...form, password: e.target.value })}
          />
          <Button
            className="gisila-auth__submit"
            type="submit"
            disabled={loading}
          >
            {loading ? "Creating…" : "Create account"}
          </Button>
        </Stack>
      </form>
      <p className="gisila-auth__footnote">
        Already have an account?{" "}
        <CarbonLink as={RouterLink} href="/login">
          Sign in
        </CarbonLink>
      </p>
    </Stack>
  );
}
