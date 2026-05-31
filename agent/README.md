# gisila-agent

> Privileged host-side deployment agent for the Gisila Panel.

The Dart backend (and its worker) **never** run as root. When the worker
needs to provision a Linux user, write a systemd unit, install an AppArmor
profile, generate an Nginx vhost, issue a TLS cert, or restart a service,
it invokes `gisila-agent` over a tightly scoped sudoers rule.

## Subcommands

```
gisila-agent provision    --app-id ID --user app_xxx --work-dir PATH --port N
gisila-agent build        --app-id ID --user app_xxx --work-dir PATH \
                          --runtime dart|go|rust|node|python|binary \
                          --source-type binary|git|zip \
                          [--git-url URL] [--git-branch B] \
                          [--build-command CMD]
gisila-agent apply-unit   --app-id ID --user app_xxx --work-dir PATH --port N \
                          [--start-command CMD] \
                          --memory-mb MB --cpu-quota PCT --tasks-max N
gisila-agent apply-vhost  --app-id ID --port N
gisila-agent issue-cert   --hostname HOSTNAME
gisila-agent start        --user app_xxx
gisila-agent stop         --user app_xxx
gisila-agent restart      --user app_xxx
gisila-agent uninstall    --user app_xxx
```

Each subcommand is **idempotent** and emits a JSON status line on success
so the worker can correlate output with the deployment timeline.

## Install

```bash
cd agent
dart pub get
dart compile exe bin/gisila-agent.dart -o build/gisila-agent
sudo install -m 0755 build/gisila-agent /usr/local/bin/gisila-agent
sudo install -m 0440 ../infra/sudoers.d_gisila /etc/sudoers.d/gisila
```

The bundled `sudoers.d_gisila` grants the `gisila` system user the right to
run **only** `/usr/local/bin/gisila-agent` as root, with no other commands.

## Security notes

- Strict path validation: every `--user` and `--work-dir` is checked against
  a regex (`^app_[a-z0-9]{6,}$` and `^/srv/apps/app_[a-z0-9]{6,}(/.*)?$`)
  before being passed to `useradd`, `systemctl`, etc.
- Generated systemd units always include the hardening directives required
  by the panel: `NoNewPrivileges`, `ProtectSystem=strict`, `PrivateTmp`,
  `ProtectHome`, `RestrictNamespaces`, `MemoryMax`, `CPUQuota`, `TasksMax`.
- AppArmor profiles default-deny everything outside `/srv/apps/<user>/`,
  `/tmp/` and the runtime's standard libraries.
- TLS issuance uses `certbot --nginx`. The agent refuses to touch hostnames
  that aren't already present in a managed vhost.
