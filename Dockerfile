# reefy-dev-fedora: Fedora 45 with systemd as PID 1.
#
# Sibling of reefy-dev-ubuntu, same shape: gives the container a full-VM
# feel (systemd unit management, journald, sshd, cron, udev, and basic
# CLI tools) so a fresh shell feels like a Linux box rather than a
# stripped container.
#
# Heavier build/dev deps (gcc, make, qemu, parted, mtools, ...) are NOT
# baked here - they belong in the consuming project's setup script so
# this image rebuilds rarely.
#
# Pattern: vendored to our org so the supply chain stays under our
# control. CI rebuilds on Dockerfile change.

FROM quay.io/fedora/fedora:45

LABEL org.opencontainers.image.title="reefy-dev-fedora" \
      org.opencontainers.image.description="Fedora 45 with systemd as PID 1. Base image for the dev-fedora app on https://reefy.ai" \
      org.opencontainers.image.licenses="MIT"

ENV container=docker

RUN dnf -y install \
        systemd \
        sudo less vim jq curl tmux nano \
        iproute iputils procps-ng net-tools \
        ca-certificates openssh-clients \
    && dnf clean all \
    && rm -rf /var/cache/dnf /tmp/* /var/tmp/*

# Prune systemd units that don't belong in a container. Same idea as
# reefy-dev-ubuntu: drop auto-started units that try to talk to kernel
# subsystems that aren't there in a container (initctl, plymouth, udev
# sockets that conflict with host's udev, etc).
RUN cd /lib/systemd/system/sysinit.target.wants/ \
    && ls | grep -v systemd-tmpfiles-setup | xargs rm -f $1
RUN rm -f /lib/systemd/system/multi-user.target.wants/* \
    /etc/systemd/system/*.wants/* \
    /lib/systemd/system/local-fs.target.wants/* \
    /lib/systemd/system/sockets.target.wants/*udev* \
    /lib/systemd/system/sockets.target.wants/*initctl* \
    /lib/systemd/system/basic.target.wants/* \
    /lib/systemd/system/anaconda.target.wants/* \
    /lib/systemd/system/plymouth* \
    /lib/systemd/system/systemd-update-utmp*

# /sys/fs/cgroup is bind-mounted from the host at runtime via
# host_mounts in apps/dev-fedora/app.json; declaring as VOLUME makes
# `docker run` complain less if the mount is missing.
VOLUME [ "/sys/fs/cgroup" ]

CMD ["/usr/sbin/init"]
