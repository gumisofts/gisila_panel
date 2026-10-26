"use client";

import { useState } from "react";
import { Button, PasswordInput, Stack, TextInput } from "@carbon/react";
import { useRouter } from "@/compat/navigation";
import { toast } from "@/lib/toast";
import { api, setToken } from "@/lib/api";
import type { LoginResponse, User } from "@/lib/types";
import "../../(panel)/_batch-a.scss";

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  // Set once the password was accepted for an account with 2FA on.
  const [challenge, setChallenge] = useState<string | null>(null);
  const [code, setCode] = useState("");

  function signedIn(access: string) {
    setToken(access);
    toast.success("Welcome back");
    router.push("/dashboard");
  }

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    try {
      const res = await api<LoginResponse>("/auth/login", {
        method: "POST",
        body: JSON.stringify({ email, password }),
      });
      if (res.mfaRequired) {
        setChallenge(res.challenge);
        setPassword("");
      } else {
        signedIn(res.access);
      }
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Login failed");
    } finally {
      setLoading(false);
    }
  }

  async function onSubmitCode(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    try {
      const res = await api<{ access: string; user: User }>("/auth/login/mfa", {
        method: "POST",
        body: JSON.stringify({ challenge, code }),
      });
      signedIn(res.access);
    } catch (err: unknown) {
      toast.error(err instanceof Error ? err.message : "Login failed");
      setCode("");
    } finally {
      setLoading(false);
    }
  }

  if (challenge) {
    return (
      <Stack gap={6}>
        <div>
          <h1 className="gisila-auth__title">Two-factor authentication</h1>
          <p className="gisila-auth__subtitle">
            Enter the 6-digit code from your authenticator app, or one of your
            recovery codes.
          </p>
        </div>
        <form onSubmit={onSubmitCode}>
          <Stack gap={5}>
            <TextInput
              id="code"
              labelText="Authentication code"
              value={code}
              required
              autoFocus
              autoComplete="one-time-code"
              inputMode="text"
              onChange={(e) => setCode(e.target.value)}
              placeholder="123456"
            />
            <Button
              className="gisila-auth__submit"
              type="submit"
              disabled={loading}
            >
              {loading ? "Verifying…" : "Verify"}
            </Button>
            <Button
              kind="ghost"
              size="sm"
              onClick={() => {
                setChallenge(null);
                setCode("");
              }}
            >
              Back
            </Button>
          </Stack>
        </form>
      </Stack>
    );
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
