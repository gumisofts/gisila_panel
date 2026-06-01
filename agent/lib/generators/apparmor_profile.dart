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
