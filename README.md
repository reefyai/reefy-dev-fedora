# reefy-dev-fedora

Fedora 45 with **systemd as PID 1**, packaged for use as a development
environment container.

The base image for the **dev-fedora** app on
[Reefy](https://reefy.ai) - turn your home server into a Reef.

## What's in the image

- `quay.io/fedora/fedora:45` base
- `systemd` so the container behaves like a Linux host (unit-managed
  services, journald, cron, sshd, udev, ...)
- Container-friendly pruning of default systemd units that don't make
  sense in a container (initctl, plymouth, conflicting udev sockets,
  most `multi-user.target.wants/*`, ...)

Build/dev dependencies (gcc, qemu, parted, mtools, ...) are NOT baked
in - they live in the consuming project's setup script so this image
rebuilds rarely.

## Tags

- `45`, `latest` - Fedora 45
- Immutable date+run tags like `45-YYYY.MM.DD-NN` for downstream pinning

Pull from `ghcr.io/reefyai/reefy-dev-fedora`.

## Runtime requirements

systemd-as-PID-1 needs cgroup access + tmpfs for `/run` and `/tmp`:

```bash
docker run -d \
  --privileged \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  --tmpfs /run --tmpfs /tmp \
  ghcr.io/reefyai/reefy-dev-fedora:45
```

## Reefy app spec

The catalog spec for the Reefy `dev-fedora` app lives under
[`reefy/app.json`](reefy/app.json).

## License

[MIT](LICENSE).
