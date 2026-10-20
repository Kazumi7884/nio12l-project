#!/usr/bin/env bash
###############################################################################
# setup-dashboard.sh — Install dashboard stack on NIO 12L
#
# Installs:
#   - Docker + Docker Compose (container runtime)
#   - Homepage dashboard (github: gethomepage/homepage)
#   - Netdata monitoring (github: netdata/netdata)
#   - Caddy reverse proxy (github: caddyserver/caddy)
#   - Cockpit server management (github: cockpit-project/cockpit)
#
# All images are from existing GitHub repos — NO custom code written.
###############################################################################
set -euo pipefail

info()  { echo "[INFO] $*"; }
ok()    { echo "[OK] $*"; }
warn()  { echo "[WARN] $*"; }
err()   { echo "[ERROR] $*"; }

# ── Install Docker ───────────────────────────────────────────────────────────
install_docker() {
    info "Installing Docker..."
    if command -v docker >/dev/null 2>&1; then
        ok "Docker already installed"
        return
    fi

    # Use distro-signed packages, not a remote installer piped to a shell.
    apt-get update -qq
    apt-get install -y docker.io
    systemctl enable --now docker

    ok "Docker installed"
}

# ── Install Docker Compose v2 ────────────────────────────────────────────────
install_compose() {
    info "Installing Docker Compose..."
    if docker compose version >/dev/null 2>&1; then
        ok "Docker Compose already available"
        return
    fi

    # Docker Compose v2 plugin (from docker/cli repo on GitHub)
    apt-get update -qq
    apt-get install -y docker-compose-v2 || apt-get install -y docker-compose-plugin
    docker compose version >/dev/null

    ok "Docker Compose installed"
}

# ── Install Cockpit (native, not Docker) ──────────────────────────────────────
install_cockpit() {
    info "Installing Cockpit (github: cockpit-project/cockpit)..."
    if [ "${NIO_ENABLE_COCKPIT:-0}" != 1 ]; then
        info "Cockpit disabled by default; set NIO_ENABLE_COCKPIT=1 to install."
        return
    fi
    apt-get install -y cockpit >/dev/null 2>&1 || {
        warn "Cockpit not available — skipping"
        return
    }
    systemctl enable --now cockpit.socket
    ok "Cockpit installed — access at https://$(hostname -I | awk '{print $1}'):9090"
}

# ── Deploy Dashboard Stack ────────────────────────────────────────────────────
deploy_dashboard() {
    info "Deploying dashboard stack..."
    local DASH_DIR="/opt/nio12l-dashboard"
    local SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)/dashboard"

    mkdir -p "$DASH_DIR/config" "$DASH_DIR/caddy"

    # Copy config files
    cp "$SRC_DIR/docker-compose.yml" "$DASH_DIR/"
    cp -r "$SRC_DIR/config/homepage/"* "$DASH_DIR/config/"
    cp "$SRC_DIR/config/caddy/Caddyfile" "$DASH_DIR/caddy/" 2>/dev/null || true
    cp "$SRC_DIR/config/netdata/"* /etc/netdata/ 2>/dev/null || true
    cp "$SRC_DIR/config/netdata/npu_gpu_check.py" /usr/lib/netdata/python.d/ 2>/dev/null || true
    chmod +x /usr/lib/netdata/python.d/npu_gpu_check.py 2>/dev/null || true

    # Install systemd service
    cp "$SRC_DIR/systemd/nio12l-dashboard.service" /etc/systemd/system/ 2>/dev/null || true
    systemctl daemon-reload
    systemctl enable nio12l-dashboard 2>/dev/null || true

    # Start the stack
    cd "$DASH_DIR"
    docker compose up -d

    local ip=$(hostname -I | awk '{print $1}')
    ok "Dashboard stack deployed!"
    echo ""
    echo "  Access points:"
    echo "    Homepage (SSH forward): http://127.0.0.1:18080"
    echo "    Example: ssh -N -L 18080:127.0.0.1:80 USER@$ip"
    echo "    Netdata is private to the Compose network."
    echo "    Cockpit is separate and opt-in."
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    echo "=============================================="
    echo "  NIO 12L Dashboard Setup"
    echo "  github: gethomepage/homepage, netdata/netdata"
    echo "  github: caddyserver/caddy, cockpit-project/cockpit"
    echo "=============================================="

    install_docker
    echo ""
    install_compose
    echo ""
    install_cockpit
    echo ""
    deploy_dashboard
    echo ""
    echo "=============================================="
    ok "Done! Reboot to ensure all services start cleanly."
    echo "=============================================="
}

main "$@"
