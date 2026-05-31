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

    # Standard runtime needs
    /etc/ssl/certs/** r,
    /usr/share/ca-certificates/** r,
    /usr/lib/** rm,
    /lib/** rm,

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
