# Ubuntu 22.04 host image for production-like Gisila Panel installs.
#
# - systemd as PID 1 (agent uses systemctl like a real VPS)
# - non-root `ubuntu` user with passwordless sudo
# - OpenSSH so the host is reachable from outside the container (host port 2222)
# - DO NOT set DOCKER_DEPLOY here — agent must use systemd, not supervisord
#
# Run via docker-compose.install.yml / scripts/install-env.sh

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    container=docker \
    LANG=C.UTF-8

# systemd + sudo + ssh + tools needed before infra/install.sh (install.sh will apt more)
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends \
      systemd systemd-sysv dbus \
      sudo ca-certificates curl gnupg \
      apt-transport-https \
      iproute2 iputils-ping procps \
      openssh-server \
      locales \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Drop noisy / irrelevant default units for containers
RUN find /etc/systemd/system \
      /lib/systemd/system \
      -path '*.wants/*' \
      \( -name '*getty*' \
         -o -name '*systemd-logind*' \
         -o -name '*systemd-resolved*' \
         -o -name '*NetworkManager*' \
         -o -name '*systemd-timesyncd*' \) \
      -exec rm -f {} + 2>/dev/null || true

# Non-root operator matching a typical VPS login user (passwordless sudo).
# Password is install-env only (ssh from host); change after first login if needed.
RUN useradd --create-home --shell /bin/bash --uid 1000 ubuntu \
 && echo 'ubuntu:ubuntu' | chpasswd \
 && echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu \
 && chmod 0440 /etc/sudoers.d/ubuntu \
 && mkdir -p /workspace /var/run/sshd /home/ubuntu/.ssh \
 && chown ubuntu:ubuntu /workspace /home/ubuntu/.ssh \
 && chmod 700 /home/ubuntu/.ssh \
 && sed -i 's/#\?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
 && sed -i 's/#\?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config \
 && systemctl enable ssh

COPY entrypoint.sh /usr/local/sbin/gisila-host-entrypoint.sh
RUN chmod 0755 /usr/local/sbin/gisila-host-entrypoint.sh

WORKDIR /workspace/gisila-panel

STOPSIGNAL SIGRTMIN+3
VOLUME ["/sys/fs/cgroup"]
EXPOSE 22 80 443 8000

ENTRYPOINT ["/usr/local/sbin/gisila-host-entrypoint.sh"]
CMD ["/lib/systemd/systemd"]
