"use client";

import { useState } from "react";
import { Button, PasswordInput, Stack, TextInput } from "@carbon/react";
import { useRouter } from "@/compat/navigation";
import { toast } from "@/lib/toast";
import { api, setToken } from "@/lib/api";
import type { User } from "@/lib/types";
import "../../(panel)/_batch-a.scss";

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    try {
      const res = await api<{ access: string; user: User }>("/auth/login", {
        method: "POST",
        body: JSON.stringify({ email, password }),
      });
      setToken(res.access);
      toast.success("Welcome back");
      router.push("/dashboard");
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Login failed");
    } finally {
      setLoading(false);
    }
  }

  return (
    <Stack gap={6}>
      <div>
        <h1 className="gisila-auth__title">Sign in to gisila</h1>
        <p className="gisila-auth__subtitle">
          Enter your email and password to access your panel.
        </p>
      </div>
      <form onSubmit={onSubmit}>
        <Stack gap={5}>
          <TextInput
            id="email"
            labelText="Email"
            type="email"
            value={email}
            required
            autoComplete="email"
            onChange={(e) => setEmail(e.target.value)}
            placeholder="you@example.com"
          />
          <PasswordInput
            id="password"
            labelText="Password"
            value={password}
            required
            autoComplete="current-password"
            onChange={(e) => setPassword(e.target.value)}
          />
          <Button
            className="gisila-auth__submit"
            type="submit"
            disabled={loading}
          >
            {loading ? "Signing in…" : "Sign in"}
          </Button>
        </Stack>
      </form>
      <p className="gisila-auth__footnote">
        Contact your administrator to get an account.
      </p>
    </Stack>
  );
}
