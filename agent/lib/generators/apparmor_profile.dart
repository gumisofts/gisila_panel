/// Render a baseline AppArmor profile for an app.
class ApparmorProfile {
  ApparmorProfile({required this.linuxUser, required this.workDir});

  final String linuxUser;
  final String workDir;

  String get profileName => 'gisila-$linuxUser';

  String render() => '''
# Managed by gisila-agent — do not edit by hand.
#include <tunables/global>

profile $profileName flags=(attach_disconnected,mediate_deleted) {
    #include <abstractions/base>
    #include <abstractions/nameservice>
    #include <abstractions/openssl>

    # Read its own bundle
    $workDir/** r,
    $workDir/current/** mrix,
    $workDir/releases/** rmix,

    # Writable scratch
    owner $workDir/shared/** rwk,
    owner $workDir/tmp/** rwk,
    owner $workDir/logs/** rwk,
    owner /tmp/** rwk,

    # corepack cache (COREPACK_HOME=$workDir/.corepack). corepack downloads the
    # pinned package manager here on first run and node mmaps+executes it, so the
    # tree needs read+write+mmap+inherit-exec — not just the rw granted to the
    # plain scratch dirs above. Must stay in sync with the systemd unit's
    # ReadWritePaths and the Provisioner's created dirs.
    owner $workDir/.corepack/ rwk,
    owner $workDir/.corepack/** rwkmix,

    # Standard runtime needs
    /etc/ssl/certs/** r,
    /usr/share/ca-certificates/** r,
    /usr/lib/** rm,
    /lib/** rm,

    # Python pyenv runtime. Even when the venv binary is a copy, the stdlib,
    # the .so extension modules (lib-dynload), and a shared libpython all live
    # in the pyenv-managed prefix. AppArmor is deny-by-default, so without these
    # rules the interpreter cannot even import `encodings` during init and dies
    # with "Fatal Python error: init_fs_encoding". `mr` grants read + mmap so
    # shared objects can be loaded; the bin rule allows execution when the venv
    # reaches the interpreter through a symlink rather than a --copies binary.
    /opt/pyenv/versions/*/ r,
    /opt/pyenv/versions/*/lib/ r,
    /opt/pyenv/versions/*/lib/** mr,
    /opt/pyenv/versions/*/bin/python* ix,

    # Node.js system runtime. The start command (e.g. `pnpm start`) lives outside
    # the work directory, so /usr/bin/node and the package manager shims must be
    # explicitly allowed. Without these rules AppArmor returns EACCES and the
    # service logs "/usr/bin/env: 'node': Permission denied".
    /usr/bin/node* ix,
    /usr/local/bin/node* ix,
    /usr/bin/npm ix,
    /usr/bin/npx ix,
    /usr/bin/corepack ix,
    /usr/local/bin/npm ix,
    /usr/local/bin/npx ix,
    /usr/local/bin/pnpm ix,
    /usr/local/bin/yarn ix,
    /usr/local/bin/corepack ix,
    # fnm-managed Node versions (pinned deployments)
    /opt/fnm/ r,
    /opt/fnm/** mr,
    /opt/fnm/node-versions/**/bin/** ix,

    # Shared, version-pinned pnpm store (corepack-free). The build installs a
    # standalone pnpm here and the service invokes it by absolute path; node
    # reads+mmaps the .cjs and execs the bin shim, so the tree needs r+m+ix.
    /opt/pnpm-versions/ r,
    /opt/pnpm-versions/** mrix,

    # Bun runtime
    /opt/bun-versions/ r,
    /opt/bun-versions/** mr,
    /opt/bun-versions/**/bun ix,
    /usr/local/bin/bun ix,
    /usr/bin/bun ix,

    # Networking
    network inet stream,
    network inet6 stream,
    network unix stream,

    # Deny dangerous syscalls implicitly via systemd's seccomp filters.
    deny ptrace,
    deny mount,
    deny umount,
    deny capability sys_admin,
    deny capability sys_module,
}
''';
}
