# reefy-dev-fedora: Fedora 45 with systemd as PID 1.
#
# Sibling of reefy-dev-ubuntu, same shape: full-VM-like container with
# systemd, sshd, cron, udev, basic CLI, build toolchain, Linux image
# tooling, and modern secret tooling (sops + age). General-purpose
# Linux dev sandbox.
#
# Pattern: vendored to our org so the supply chain stays under our
# control. CI rebuilds on Dockerfile change.

FROM quay.io/fedora/fedora:45

LABEL org.opencontainers.image.title="reefy-dev-fedora" \
      org.opencontainers.image.description="Fedora 45 with systemd as PID 1. Base image for the dev-fedora app on https://reefy.ai" \
      org.opencontainers.image.licenses="MIT"

ENV container=docker

# Single big dnf RUN so all packages share one layer (smaller image).
# Categories mirror the reefy-dev-ubuntu Dockerfile:
#   - systemd + basic CLI: full-VM feel
#   - @development-tools: build toolchain (gcc, make, autoconf, ...)
#   - python3 + pip: scripting + venv host
#   - bc/bison/flex/openssl-devel/elfutils-libelf-devel/ncurses-devel/cpio:
#     kernel + buildroot-style image build deps
#   - systemd-boot-unsigned: UEFI bootloader stub (linuxx64.efi.stub)
#   - ragel: state-machine parser generator
#   - mtools/gdisk/parted/dosfstools/zip: disk image partition tooling
#   - age: file encryption (SOPS recipients, etc.)
RUN dnf -y install \
        systemd \
        sudo less vim jq curl tmux nano git \
        iproute iputils procps-ng net-tools \
        ca-certificates openssh-clients openssh-server \
        @development-tools python3 python3-pip \
        bc bison flex openssl-devel elfutils-libelf-devel ncurses-devel \
        unzip cpio rsync file bzip2 wget patch \
        systemd-boot-unsigned ragel \
        mtools gdisk parted dosfstools zip \
        age \
    && dnf clean all \
    && rm -rf /var/cache/dnf /tmp/* /var/tmp/*

# SOPS (Mozilla's secret encryption tool). Single Go binary not in
# distro repos; fetched from upstream releases.
ARG SOPS_VERSION=v3.13.0
RUN curl --retry 5 --retry-delay 5 --retry-all-errors --retry-max-time 300 \
        -fsSL "https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.linux.amd64" \
        -o /usr/local/bin/sops \
    && chmod +x /usr/local/bin/sops

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
