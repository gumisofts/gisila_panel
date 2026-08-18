---
title: "Set Up Your Own Mail Server on Gisila Panel"
description: "Host real mailboxes on the same VPS as your apps: install Postfix and Dovecot from the panel, publish SPF/DKIM/DMARC, and connect a mail client."
date: 2026-08-13
author: Gisila Team
tags: [mail, postfix, dovecot, dkim, tutorial, self-hosting]
---

# Set Up Your Own Mail Server on Gisila Panel

You already have a panel and at least one app. The next thing many operators want is **email on the same box**: `hello@yourdomain.com` in Thunderbird or on a phone, not a $15/month Google Workspace seat per address.

Gisila Panel can do that. It is not a transactional relay bolted onto an app. It is a full virtual-mailbox stack on the host: **Postfix** for SMTP, **Dovecot** for IMAP/POP3, **OpenDKIM** for signing. You install it from the dashboard, add a domain, publish DNS, and create mailboxes.

This post is the walkthrough.

---

## What you get

| Piece | Role |
|-------|------|
| Postfix | Inbound SMTP (port 25) and authenticated submission (587 / 465) |
| Dovecot | IMAP (143 / 993), POP3 (110 / 995), LMTP delivery into maildirs |
| OpenDKIM | Signs outbound mail; the panel shows the public key to publish |
| Virtual users | One `vmail` Linux user; every address is a mailbox, not a system account |

Mail lives under `/var/mail/vhosts/<domain>/<local>/`. One host can serve many domains. Apps on the same VPS are unrelated: they still run as isolated systemd units. Mail is extra infrastructure on the node, managed from **Mail** in the sidebar.

Installing the panel does **not** install mail. That is deliberate. Mail needs open ports, a matching reverse DNS name, and DNS you control. You opt in from the UI.

---

## Before you start

You need:

- A production Gisila Panel node (see [Install and Getting Started](./04-install-and-getting-started.md))
- A **superuser** account. Adding domains and mailboxes is superuser-only
- A domain whose DNS you can edit
- A **public IPv4** on the VPS, with the ability to set **reverse DNS (PTR)** at the hosting provider
- Port **25 inbound** (and usually outbound) unblocked. Many clouds lock SMTP until you ask

Also true in practice:

| Check | Why it matters |
|-------|----------------|
| PTR for the VPS IP equals `mail.yourdomain.com` | Gmail and Outlook drop or spam mail whose HELO does not match reverse DNS |
| Mail hostname is DNS-only | If Cloudflare's orange cloud proxies the A record, SMTP never reaches your box |
| IPv4 is enough | Gisila forces Postfix to IPv4. Provider IPv6 PTRs are usually a generic hostname, which fails SPF and FCrDNS |

If your provider still blocks port 25, inbound mail will not arrive and outbound mail to other servers will sit in the queue. Open a support ticket before you spend an afternoon on DNS.

---

## Step 1: Install email tools

Sign in as a superuser. Open **Mail**.

Until the stack is on disk, the page is a single prompt: **Install email tools**. Click it.

That queues `gisila-agent mail setup`. The worker installs:

- `postfix`
- `dovecot-core`, `dovecot-imapd`, `dovecot-pop3d`, `dovecot-lmtpd`
- `opendkim`, `opendkim-tools`

It also creates the `vmail` user (uid/gid 5000), writes base Postfix/Dovecot/OpenDKIM config, enables the daemons, and (if `ufw` is present) allows TCP **25, 465, 587, 143, 993, 110, 995**, plus **80** so Let's Encrypt can issue a certificate for the mail hostname.

The page polls `/mail/status` every few seconds. When `installed` flips to true, you get the normal domain UI. A first install often takes about a minute.

Watch the worker if it seems stuck:

```bash
journalctl -fu gisila-worker
```

---

## Step 2: Add a domain

Click **Add domain** and enter the apex, for example `example.com` (not `mail.example.com`).

The panel stores the domain, then queues a **sync**. The agent:

1. Adds the domain to Postfix `virtual_mailbox_domains`
2. Sets `myhostname` to `mail.example.com` (unless you change it)
3. Generates a 2048-bit DKIM key, selector `gisila`
4. Detects the public IPv4 and stores it for the SPF record
5. Tries Let's Encrypt for the mail hostname; falls back to a self-signed cert if DNS is not ready yet

The DNS panel will show **Waiting for DKIM key…** until that sync finishes. Hit the refresh icon if you do not want to wait for the poll.

Default settings (edit them on the domain card):

| Setting | Default | Meaning |
|---------|---------|---------|
| Mail hostname | `mail.<domain>` | A record, MX target, and the name clients connect to |
| DMARC policy | `none` | Receivers only report failures. Tighten later |

Use one mail hostname per server. Postfix announces that name as HELO. It must match the PTR.

---

## Step 3: Publish DNS (and PTR)

Open the domain card. **DNS records** lists copyable values. Publish them at your registrar or DNS host.

For `example.com` on a server at `203.0.113.10`, it looks like this:

| Type | Host | Value |
|------|------|--------|
| **A** | `mail.example.com` | `203.0.113.10` (DNS-only, not proxied) |
| **MX** | `example.com` | `mail.example.com` (priority 10) |
| **TXT** (SPF) | `example.com` | `v=spf1 ip4:203.0.113.10 ~all` |
| **TXT** (DKIM) | `gisila._domainkey.example.com` | `v=DKIM1; k=rsa; p=<public key>` |
| **TXT** (DMARC) | `_dmarc.example.com` | `v=DMARC1; p=none; rua=mailto:postmaster@example.com` |

Wait for the DKIM row to show a real `p=` value before you create that record. A placeholder means the key is not on the host yet.

Then set **reverse DNS** at Hetzner / DigitalOcean / Contabo / whoever owns the IP:

```
203.0.113.10  →  mail.example.com
```

Forward and reverse must agree. Skip this and Gmail will answer with something like `5.7.26` even when SPF looks fine.

TTL of 300 seconds is enough while you are iterating. After mail flows, you can raise it.

Create the `postmaster` mailbox in the next step if you want DMARC aggregate reports (`rua=`) to land somewhere you can read.

---

## Step 4: Create a mailbox

On the domain card: **New mailbox**.

| Field | Example |
|-------|---------|
| Address | `hello` (becomes `hello@example.com`) |
| Password | at least 6 characters |
| Quota | empty for unlimited, or a size in MB |

The password is stored as a Dovecot `{SSHA512}` hash. The panel never shows it again. Reset it from the mailbox row if you forget.

Sync writes `/etc/postfix/vmailbox` and `/etc/dovecot/users` and reloads the daemons. The maildir appears under `/var/mail/vhosts/example.com/hello/`.

---

## Step 5: Connect a client

Each mailbox row has **Connection settings**. Use the full address as the username.

| Protocol | Port | Security | When to use |
|----------|------|----------|-------------|
| SMTP submission | **587** | STARTTLS | Sending from a desktop or phone |
| SMTP | **465** | SSL/TLS | Same, implicit TLS |
| IMAP | **993** | SSL/TLS | Preferred for reading |
| IMAP | **143** | STARTTLS | If the client insists |
| POP3 | **995** | SSL/TLS | Download-and-delete clients |
| POP3 | **110** | STARTTLS | Legacy |

Host: `mail.example.com`. Username: `hello@example.com`.

Do **not** send through port 25 from a mail client. 25 is for other servers delivering to you. Submission is 587 or 465, and it requires SASL (your mailbox password).

If Let's Encrypt has not issued yet, the client will warn about a self-signed certificate. That is expected until `mail.example.com` resolves to this box and port 80 is reachable. After the next sync (or a certbot run), the daemons read `/etc/gisila/mail/mail.crt`, which the agent copies from the `gisila-mail` Let's Encrypt lineage. A deploy hook reloads Postfix and Dovecot on renewal.

---

## A worked example

Domain `acme.test`, VPS `203.0.113.10`.

1. Superuser opens **Mail** → **Install email tools**
2. **Add domain** → `acme.test`
3. Settings stay at hostname `mail.acme.test`, DMARC `none`
4. DNS:

   ```
   mail.acme.test.                    A      203.0.113.10
   acme.test.                         MX 10  mail.acme.test.
   acme.test.                         TXT    "v=spf1 ip4:203.0.113.10 ~all"
   gisila._domainkey.acme.test.       TXT    "v=DKIM1; k=rsa; p=MIIBIj..."
   _dmarc.acme.test.                  TXT    "v=DMARC1; p=none; rua=mailto:postmaster@acme.test"
   ```

5. Provider PTR: `203.0.113.10` → `mail.acme.test`
6. Mailboxes: `hello@acme.test`, `postmaster@acme.test`
7. Thunderbird: IMAP 993 + SMTP 587, username `hello@acme.test`
8. Send a message to a Gmail address, then check [mail-tester.com](https://www.mail-tester.com/) or Gmail's "Show original" for SPF/DKIM/DMARC pass

Propagation is often minutes, sometimes an hour. Test after `dig MX acme.test` and `dig -x 203.0.113.10` look right.

---

## How it is wired

```
You (Mail UI)  →  Dart API  →  Redis (gisila:queue:mail)
                                      →  gisila-worker
                                      →  gisila-agent mail setup|sync
                                      →  postfix + dovecot + opendkim
```

Mutations (install, add domain, add mailbox, reset password) enqueue `setup` or `sync`. The agent is idempotent: re-running sync converges maps, keys, and TLS.

On disk:

```
/var/mail/vhosts/<domain>/<user>/     maildir
/etc/postfix/vmailbox                 address → maildir map
/etc/dovecot/users                    passwd-file (hashes only)
/etc/opendkim/keys/<domain>/gisila.*  DKIM keypair
/etc/gisila/mail/mail.crt             TLS cert the daemons actually read
```

Outbound mail is signed by OpenDKIM on `127.0.0.1:8891`. Postfix `inet_protocols=ipv4` keeps delivery on the address your SPF record authorises.

---

## Day-two operations

**More domains.** Repeat add-domain + DNS. They share the same Postfix/Dovecot. Prefer one mail hostname (and one PTR) for the server; extra domains MX to that same host.

**Tighten DMARC.** Start at `none`, watch reports, then `quarantine`, then `reject` once SPF and DKIM pass for everything you send. Save settings on the domain card and re-publish the `_dmarc` TXT.

**Extra senders.** If a SaaS also sends as `@example.com`, add `include:` or another `ip4:` in SPF *before* you switch `~all` to `-all`. The panel's default is `ip4:<this server> ~all` on purpose: MX-based SPF breaks if you later put the mail hostname behind a CDN.

**Quota and password.** Edit from the mailbox row. Sync pushes the new hash or quota.

**Remove a domain.** Deletes its mailboxes in the database and the next sync drops them from Postfix/Dovecot. Maildirs on disk are the operator's to clean up if you want the bytes gone.

**Logs:**

```bash
journalctl -fu postfix
journalctl -fu dovecot
journalctl -fu opendkim
journalctl -fu gisila-worker
```

**Re-sync** from the DNS panel refresh button, or:

```http
POST /mail/domains/{id}/sync
Authorization: Bearer <superuser jwt>
```

---

## If mail does not flow

**Install never finishes.** Worker or agent failed on `apt`. `journalctl -u gisila-worker` plus `dpkg -l postfix dovecot-core opendkim`.

**DKIM stays on "Waiting…".** Sync did not complete. Trigger refresh. Confirm `/etc/opendkim/keys/<domain>/gisila.txt` exists on the host.

**Inbound never arrives.** `dig MX example.com` should return `mail.example.com`, and that name's A record should be this VPS, unproxied. Provider firewall and `ufw` must allow 25/tcp. From another network: `nc -vz mail.example.com 25`.

**Outbound sits in the queue or Gmail says 5.7.26.** Classic trio: port 25 egress blocked, PTR ≠ `myhostname`, or Cloudflare proxy on the A record. Check:

```bash
postqueue -p
dig -x $(curl -s https://api.ipify.org)
postconf myhostname inet_protocols
```

`myhostname` must be the PTR target. Gisila sets it from the first domain's mail hostname on sync.

**Client warns about the certificate.** `mail.example.com` did not resolve here when the last sync ran, so certbot fell back to self-signed. Point DNS, open port 80, sync again. Confirm:

```bash
sudo openssl x509 -in /etc/gisila/mail/mail.crt -noout -issuer -subject -dates
```

**Auth works in IMAP but SMTP is rejected.** You are on port 25 instead of 587/465, or the client is not using the full `user@domain` as the username.

---

## What this is not

Gisila mail is **self-hosted IMAP/SMTP for people and small teams**. It is a good fit for `hello@`, `jobs@`, and catching DMARC reports.

It is a poor fit if you need:

- High-volume transactional mail (use SES, Postmark, or similar, and `include:` them in SPF)
- Shared calendars and ActiveSync (this is not Exchange or iCloud)
- Multi-node mail (one node, one Postfix, today)

Managed **SMTP / Mailpit** under **Services** is a different feature: app-side relays and catch-all inboxes for development, not public MX hosting.

---

## Further reading

- [Install and Getting Started](./04-install-and-getting-started.md): stand up the panel first
- [How a Deployment Works](./03-how-a-deployment-works.md): same worker/agent pattern apps use
- [Architecture](../docs/ARCHITECTURE.md)
- [API reference](../docs/API.md)

---

**Previous:** [← Install and Getting Started](./04-install-and-getting-started.md)
