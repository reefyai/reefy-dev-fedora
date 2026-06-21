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

ENV container=docker \
    SHELL=/bin/bash

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

# Codex CLI. Install the pinned standalone musl binary instead of npm so
# the image does not need Node.js just to run Codex. Authentication and
# user configuration live under the persistent /root volume at runtime.
ARG CODEX_VERSION=0.141.0
ARG TARGETARCH
RUN case "${TARGETARCH}" in \
        amd64) \
            codex_arch=x86_64; \
            codex_sha=f1e2bf9fa0ba6eb82119d621b6b71bc38edd33c06dc2867b31a027052358957d \
            ;; \
        arm64) \
            codex_arch=aarch64; \
            codex_sha=8c9f31811d659fcc17c5f1a21bc0971984469c9e3a63c2b39b61cc7694f3a101 \
            ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && archive="codex-${codex_arch}-unknown-linux-musl.tar.gz" \
    && curl --retry 5 --retry-delay 5 --retry-all-errors --retry-max-time 300 \
        -fsSL "https://github.com/openai/codex/releases/download/rust-v${CODEX_VERSION}/${archive}" \
        -o /tmp/codex.tar.gz \
    && echo "${codex_sha}  /tmp/codex.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/codex.tar.gz -C /tmp \
    && install -m 0755 "/tmp/codex-${codex_arch}-unknown-linux-musl" \
        /usr/local/bin/codex \
    && codex --version \
    && rm -f /tmp/codex.tar.gz \
        "/tmp/codex-${codex_arch}-unknown-linux-musl"

# OpenCode. The upstream installer writes to $HOME/.opencode/bin, but
# /root is a persistent runtime volume for this app and would hide files
# baked into the image. Install through a temporary HOME, then copy the
# binary into /usr/local and wrap it with an executable temp directory
# outside /tmp for render libraries that dlopen extracted .so files.
ARG OPENCODE_VERSION=1.17.9
RUN mkdir -p /usr/local/lib/opencode /var/tmp/opencode \
    && HOME=/tmp/opencode-home TMPDIR=/var/tmp/opencode \
        curl --retry 5 --retry-delay 5 --retry-all-errors --retry-max-time 300 \
        -fsSL https://opencode.ai/install \
        | HOME=/tmp/opencode-home TMPDIR=/var/tmp/opencode \
          bash -s -- --version "${OPENCODE_VERSION}" --no-modify-path \
    && install -m 0755 /tmp/opencode-home/.opencode/bin/opencode \
        /usr/local/lib/opencode/opencode \
    && printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -euo pipefail' \
        'export TMPDIR="${OPENCODE_TMPDIR:-/var/tmp/opencode}"' \
        'mkdir -p "$TMPDIR"' \
        'exec /usr/local/lib/opencode/opencode "$@"' \
        > /usr/local/bin/opencode \
    && chmod 0755 /usr/local/bin/opencode \
    && opencode --version \
    && rm -rf /tmp/opencode-home /var/tmp/opencode/*

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
# host_mounts in reefy/app.json; declaring as VOLUME makes
# `docker run` complain less if the mount is missing.
VOLUME [ "/sys/fs/cgroup" ]

CMD ["/usr/sbin/init"]
