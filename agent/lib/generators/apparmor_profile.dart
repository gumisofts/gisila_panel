/// Render a baseline AppArmor profile for an app.
class ApparmorProfile {
  ApparmorProfile({
    required this.linuxUser,
    required this.workDir,
    this.writableSource = false,
  });

  final String linuxUser;
  final String workDir;

  /// Grant the build source tree write access (in addition to the read+mmap+exec
  /// already granted to `releases/**`). Required for Node/Bun server frameworks
  /// that write runtime caches into their build output (e.g. Next `.next/cache`).
  final bool writableSource;

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
${writableSource ? '''
    # Server frameworks (Next/Nuxt/SvelteKit/…) write runtime caches into their
    # own build tree. Grant the source tree write so e.g. .next/cache works.
    owner $workDir/releases/current_build/** rwk,
''' : ''}

    # corepack cache (COREPACK_HOME=$workDir/.corepack). corepack downloads the
    # pinned package manager here on first run and node mmaps+executes it, so the
    # tree needs read+write+mmap+inherit-exec — not just the rw granted to the
    # plain scratch dirs above. Must stay in sync with the systemd unit's
    # ReadWritePaths and the Provisioner's created dirs.
    owner $workDir/.corepack/ rwk,
    owner $workDir/.corepack/** rwkmix,

    # ── Read + mmap: shared libraries, certs, and language-runtime trees ───────
    # `m` (mmap) is required to dlopen .so files and to map a runtime's stdlib /
    # native extensions — inherit-exec alone does not grant it. These cover the
    # system libs plus the pyenv / fnm / pnpm / bun runtime stores.
    /etc/ssl/certs/** r,
    /usr/share/ca-certificates/** r,
    /usr/lib/** rm,
    /lib/** rm,
    /opt/** rm,

    # ── Execute: standard system binaries + interpreters (inherit-exec) ────────
    # This profile confines arbitrary, operator-supplied application code. Such
    # apps legitimately spawn a shell for npm/pnpm/yarn lifecycle scripts
    # (`sh -c '<script>'`), launch their own node_modules/.bin/* tools, and call
    # out to system utilities (git, openssl, image/video tooling, …). Enumerating
    # every executable is unmaintainable and was the source of recurring
    # crash-loops (e.g. "spawn sh EACCES", "env: node: Permission denied").
    #
    # Allowing inherit-exec (`ix` — the child stays confined to THIS profile) of
    # the standard binary and library locations does not meaningfully weaken
    # confinement here: under the systemd unit these paths are read-only
    # (ProtectSystem=strict), the service runs as an unprivileged per-app user,
    # /home is hidden (ProtectHome), devices are private (PrivateDevices), and
    # privilege escalation + dangerous syscalls are blocked by NoNewPrivileges,
    # seccomp, and the explicit denials below. The host's protection comes from
    # *write* confinement (only the app's own dirs are writable, above) — not
    # from policing which read-only binaries the app may exec.
    /bin/** ix,
    /sbin/** ix,
    /usr/bin/** ix,
    /usr/sbin/** ix,
    /usr/local/bin/** ix,
    /usr/local/sbin/** ix,
    /usr/lib/** ix,
    /lib/** ix,
    /opt/** ix,

    # Networking
    network inet stream,
    network inet6 stream,
    network unix stream,
    # Netlink: libuv/libc use an AF_NETLINK socket to enumerate interfaces and
    # routes (os.networkInterfaces(), getifaddrs, getaddrinfo). Without it Next's
    # startup banner and many DNS paths fail. Must match the systemd unit's
    # RestrictAddressFamilies, which also lists AF_NETLINK.
    network netlink raw,

    # Deny dangerous syscalls implicitly via systemd's seccomp filters.
    deny ptrace,
    deny mount,
    deny umount,
    deny capability sys_admin,
    deny capability sys_module,
}
''';
}
