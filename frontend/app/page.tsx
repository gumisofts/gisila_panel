"use client";

import Link from "next/link";
import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { getToken } from "@/lib/api";
import {
  Activity,
  Box,
  Cpu,
  GitBranch,
  Globe,
  Lock,
  Rocket,
  Terminal,
} from "lucide-react";

export default function LandingPage() {
  const router = useRouter();
  useEffect(() => {
    if (getToken()) router.replace("/dashboard");
  }, [router]);

  return (
    <div className="min-h-screen bg-[radial-gradient(circle_at_top,_rgba(139,_92,_246,_0.12),_transparent_60%)]">
      <header className="container flex items-center justify-between py-6">
        <Link href="/" className="flex items-center gap-2 font-semibold">
          <Rocket className="h-5 w-5 text-primary" />
          <span>gisila panel</span>
        </Link>
        <nav className="flex items-center gap-3">
          <Button asChild variant="ghost" size="sm">
            <Link href="/login">Sign in</Link>
          </Button>
          <Button asChild size="sm">
            <Link href="/register">Get started</Link>
          </Button>
        </nav>
      </header>

      <main className="container py-20">
        <div className="mx-auto max-w-3xl text-center">
          <span className="inline-flex items-center gap-2 rounded-full border border-border bg-muted/40 px-3 py-1 text-xs font-medium text-muted-foreground">
            <span className="h-1.5 w-1.5 rounded-full bg-emerald-500" />
            open-source · self-hostable · zero-container
          </span>
          <h1 className="mt-6 text-balance text-5xl font-semibold tracking-tight md:text-6xl">
            Deploy compiled backends like it&rsquo;s{" "}
            <span className="bg-gradient-to-br from-primary to-fuchsia-400 bg-clip-text text-transparent">
              2010
            </span>
            , without the pain of 2010.
          </h1>
          <p className="mx-auto mt-6 max-w-2xl text-pretty text-lg text-muted-foreground">
            A lightweight Heroku-style PaaS for Dart, Go, Rust, Zig, Bun, Node and
            Python &mdash; powered by systemd, AppArmor, and Nginx. No Docker
            daemon, no Kubernetes, no per-app RAM tax.
          </p>
          <div className="mt-10 flex items-center justify-center gap-3">
            <Button asChild size="lg">
              <Link href="/register">Start your free panel</Link>
            </Button>
            <Button asChild size="lg" variant="outline">
              <Link href="/docs" target="_blank">
                View the docs
              </Link>
            </Button>
          </div>
        </div>

        <div className="mx-auto mt-24 grid max-w-5xl grid-cols-1 gap-4 md:grid-cols-3">
          {[
            {
              icon: <Cpu className="h-5 w-5" />,
              title: "Native execution",
              body:
                "Apps run as plain Linux processes under systemd. No container daemon, no 200 MB idle overhead.",
            },
            {
              icon: <Lock className="h-5 w-5" />,
              title: "Sandboxed by default",
              body:
                "Each app gets a Linux user, AppArmor profile, cgroups v2 limits, seccomp filters and PrivateTmp.",
            },
            {
              icon: <GitBranch className="h-5 w-5" />,
              title: "git push to deploy",
              body:
                "Wire your repo, push, and the panel compiles, sandboxes, and exposes your service over Nginx + TLS.",
            },
            {
              icon: <Terminal className="h-5 w-5" />,
              title: "Live logs",
              body:
                "Stream stdout/stderr straight from journald into the browser via WebSocket.",
            },
            {
              icon: <Activity className="h-5 w-5" />,
              title: "Per-app metrics",
              body:
                "CPU, RAM and request graphs sampled directly from cgroups &mdash; no Prometheus required.",
            },
            {
              icon: <Globe className="h-5 w-5" />,
              title: "Domains & TLS",
              body:
                "Custom domains with automatic Let&rsquo;s Encrypt issuance + renewal &mdash; one click each.",
            },
          ].map((c) => (
            <div
              key={c.title}
              className="rounded-2xl border border-border/60 bg-card/40 p-6 backdrop-blur"
            >
              <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-primary/15 text-primary">
                {c.icon}
              </div>
              <h3 className="mt-4 text-base font-semibold">{c.title}</h3>
              <p className="mt-2 text-sm text-muted-foreground">{c.body}</p>
            </div>
          ))}
        </div>

        <div className="mx-auto mt-24 flex max-w-4xl flex-col items-center justify-between gap-4 rounded-2xl border border-border/60 bg-card/40 p-8 md:flex-row">
          <div className="flex items-center gap-4">
            <Box className="h-10 w-10 text-primary" />
            <div>
              <p className="font-semibold">Works on a $5 VPS.</p>
              <p className="text-sm text-muted-foreground">
                100+ apps per node, comfortably.
              </p>
            </div>
          </div>
          <Button asChild>
            <Link href="/register">Try it free</Link>
          </Button>
        </div>
      </main>

      <footer className="container py-12 text-center text-xs text-muted-foreground">
        gisila panel · MIT · built with the gisila stack
      </footer>
    </div>
  );
}
