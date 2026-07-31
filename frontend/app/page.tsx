"use client";

import RouterLink from "@/compat/link";
import { Navigate } from "react-router-dom";
import { Button, Column, Grid, Tag, Tile } from "@carbon/react";
import {
  Activity,
  Box,
  Branch,
  Chip,
  Earth,
  Locked,
  Rocket,
  Terminal,
} from "@carbon/icons-react";
import { getToken } from "@/lib/api";
import "./(panel)/_batch-a.scss";

const FEATURES = [
  {
    icon: Chip,
    title: "Native execution",
    body:
      "Apps run as plain Linux processes under systemd. No container daemon, no 200 MB idle overhead.",
  },
  {
    icon: Locked,
    title: "Sandboxed by default",
    body:
      "Each app gets a Linux user, AppArmor profile, cgroups v2 limits, seccomp filters and PrivateTmp.",
  },
  {
    icon: Branch,
    title: "git push to deploy",
    body:
      "Wire your repo, push, and the panel compiles, sandboxes, and exposes your service over Nginx + TLS.",
  },
  {
    icon: Terminal,
    title: "Live logs",
    body:
      "Stream stdout/stderr straight from journald into the browser via WebSocket.",
  },
  {
    icon: Activity,
    title: "Per-app metrics",
    body:
      "CPU, RAM and request graphs sampled directly from cgroups — no Prometheus required.",
  },
  {
    icon: Earth,
    title: "Domains & TLS",
    body:
      "Custom domains with automatic Let's Encrypt issuance + renewal — one click each.",
  },
];

export default function LandingPage() {
  // Send already-authenticated visitors straight to the dashboard during render
  // — redirecting in an effect would flash the marketing page first.
  if (getToken()) return <Navigate to="/dashboard" replace />;

  return (
    <div className="gisila-landing">
      <div className="gisila-landing__shell">
        <header className="gisila-landing__bar">
          <RouterLink href="/" className="gisila-brand">
            <Rocket size={20} />
            <span>gisila panel</span>
          </RouterLink>
          <nav>
            <Button as={RouterLink} href="/login" size="sm">
              Sign in
            </Button>
          </nav>
        </header>

        <main>
          <div className="gisila-landing__hero">
            <Tag type="green" size="md">
              open-source · self-hostable · zero-container
            </Tag>
            <h1 className="gisila-landing__title">
              Deploy compiled backends like it&rsquo;s{" "}
              <span className="gisila-landing__accent">2010</span>, without the
              pain of 2010.
            </h1>
            <p className="gisila-landing__lede">
              A lightweight Heroku-style PaaS for Dart, Go, Rust, Zig, Bun, Node
              and Python &mdash; powered by systemd, AppArmor, and Nginx. No
              Docker daemon, no Kubernetes, no per-app RAM tax.
            </p>
            <div className="gisila-landing__actions">
              <Button as={RouterLink} href="/login" size="lg">
                Sign in to your panel
              </Button>
              <Button
                as={RouterLink}
                href="/docs"
                target="_blank"
                size="lg"
                kind="tertiary"
              >
                View the docs
              </Button>
            </div>
          </div>

          <Grid condensed className="gisila-cards">
            {FEATURES.map(({ icon: Icon, title, body }) => (
              <Column key={title} sm={4} md={4} lg={5}>
                <Tile>
                  <span className="gisila-status-icon gisila-status-icon--brand">
                    <Icon size={20} />
                  </span>
                  <h3 className="gisila-feature__title">{title}</h3>
                  <p className="gisila-feature__body">{body}</p>
                </Tile>
              </Column>
            ))}
          </Grid>

          <Tile className="gisila-landing__cta">
            <div className="gisila-landing__cta-copy">
              <Box size={32} />
              <div>
                <p className="gisila-landing__cta-title">Works on a $5 VPS.</p>
                <p className="gisila-landing__cta-note">
                  100+ apps per node, comfortably.
                </p>
              </div>
            </div>
            <Button as={RouterLink} href="/login">
              Sign in
            </Button>
          </Tile>
        </main>

        <footer className="gisila-landing__footer">
          gisila panel · MIT · built with the gisila stack
        </footer>
      </div>
    </div>
  );
}
