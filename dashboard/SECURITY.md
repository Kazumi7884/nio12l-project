# Legacy dashboard security and rollout

This repository retains a **separate legacy** NIO dashboard design. The actively maintained `radxa-setup` stack is the preferred NIO owner; do not run both stacks together without resolving duplicate port, storage, and lifecycle ownership.

## Boundaries

- Only Caddy HTTP on **127.0.0.1:80** is published by default. Do not expose it directly on a WAN or untrusted LAN: the dashboard does not enforce edge authentication.
- Homepage and Netdata listen on the private Compose network only.
- No application receives `/var/run/docker.sock`. Container-aware status badges based on Homepage's Docker integration are intentionally unavailable; Netdata metrics from its network widget remain available.
- Netdata no longer receives `SYS_PTRACE` or unconfined AppArmor. Some process-level host metrics may disappear.
- Cockpit is installed/started only when an operator explicitly sets `NIO_ENABLE_COCKPIT=1`. It requires its own access-control and firewall review. This script does not configure remote Cockpit access.
- Docker is installed only from the distribution's signed package repositories when absent; no downloaded installer scripts are executed.

## Rollout

1. Keep an existing working SSH/USB recovery path. Check current services, bound listeners, and backup volumes before touching the device.
2. Compare `docker compose -f dashboard/docker-compose.yml config` with the running configuration.
3. During an approved maintenance window, redeploy **only if this legacy stack is still in use**. Do not remove or replace an active `radxa-setup` stack.
4. Confirm the homepage renders over an SSH port forward, Netdata widget requests succeed, public Docker/Netdata interfaces are absent, and Docker/Compose restart after reboot.
5. If existing widgets relied on Docker container metadata, expect their Docker status fields to be unavailable. Do not restore the raw socket for convenience.
6. Roll back via the previous known-good tagged configuration and volume backups if needed; restoring the old Compose file also restores its old exposure and must not be a default response.

The source checks in CI do not prove real-device deployment or externally effective firewall policy.


## Alternate installer and native Netdata

The root-level `setup/optimize-system.sh --all` previously remained an alternative path that downloaded a Netdata shell installer, automatically enabled Cockpit, and bound native Netdata to every interface. This path now uses distro packages, defaults native Netdata to `127.0.0.1:19999`, and requires `NIO_ENABLE_COCKPIT=1` to install/enable Cockpit. It also avoids reinstalling a different Docker package over an already working Docker CE daemon.

Native Netdata settings are **not** bind-mounted into the private Compose Netdata container: container defaults must be reachable from Homepage only across the private Compose network. Physical validation must check both native and container listeners and service functionality. Already-running Cockpit, native Netdata and old dashboard stacks are not automatically stopped by a Git source change.
