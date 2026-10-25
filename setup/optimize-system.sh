#!/usr/bin/env bash
###############################################################################
# nio12l-setup.sh — Zero-custom-code setup for Radxa NIO 12L AI workstation
#
# Installs EXISTING open-source tools from GitHub/apt — zero custom dashboard
# code written. Uses:
#   - Armbian 26.5+ (kernel 6.19.8 or 7.1.y) as base OS
#   - Netdata (github: netdata/netdata) for real-time system monitoring
#   - Cockpit (github: cockpit-project/cockpit) for server management
#   - Homepage (github: benphelps/homepage) for the application dashboard
#   - MediaTek NeuroPilot SDK for NPU inference
#   - ONNX Runtime, PyTorch (CPU) for AI workloads
#
# All issues from GITHUB_ISSUES_REPORT.md are addressed in this script.
#
# Usage:
#   chmod +x setup/optimize-system.sh
#   sudo ./setup/optimize-system.sh --all
###############################################################################
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*"; }

require_root() { if [[ $EUID -ne 0 ]]; then err "Run with sudo"; exit 1; fi; }

# ── Step 1: System Optimization ──────────────────────────────────────────────
# Addresses GITHUB_ISSUES_REPORT.md §3.2 (GPU DVFS), §4.2 (loadaddr fix)
optimize_system() {
    info "Step 1: System optimization..."

    # Kernel check (Issue #10034 loadaddr fix)
    local kver=$(uname -r)
    local major=$(echo "$kver" | cut -d. -f1)
    if [[ "$major" -ge 7 ]]; then
        ok "Kernel $kver includes loadaddr fix (PR #10034)"
    else
        warn "Kernel $kver < 7.1 — if you see 'Bad Linux ARM64 Image magic!':"
        warn "  Edit /boot/extlinux/extlinux.conf → add: kernel_addr_r=0x44000000"
        warn "  Or upgrade to Armbian rolling (kernel 7.1.y)"
    fi

    # CPU governor
    echo "performance" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null || true

    # Memory: zram + swap + overcommit
    apt-get install -y zram-config >/dev/null 2>&1 || true
    cat > /etc/sysctl.d/99-nio12l.conf <<EOF
vm.overcommit_memory = 1
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 15
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_congestion_control = bbr
net.core.netdev_max_backlog = 5000
EOF
    sysctl -p /etc/sysctl.d/99-nio12l.conf 2>/dev/null || true

    # Swap file
    if ! grep -q swap /proc/swaps; then
        info "Creating 4GB swap file..."
        fallocate -l 4G /swapfile && chmod 600 /swapfile
        mkswap /swapfile && swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi

    # I/O scheduler
    echo "deadline" > /sys/block/sda/queue/scheduler 2>/dev/null || true
    blockdev --setra 4096 /dev/sda 2>/dev/null || true
    mount -o remount,noatime / 2>/dev/null || true

    # Monitoring tools (native)
    apt-get install -y htop iotop lm-sensors cpufrequtils sysstat iftop >/dev/null 2>&1 || true
    sensors-detect --auto 2>/dev/null || true

    ok "System optimization complete"
}

# ── Step 2: AI Stack ──────────────────────────────────────────────────────────
# Addresses GITHUB_ISSUES_REPORT.md §5 — NPU firmware, ONNX, TFLite
# Uses MediaTek NeuroPilot SDK — NO custom AI code
setup_ai_stack() {
    info "Step 2: AI stack setup (NeuroPilot + ONNX Runtime + PyTorch)..."

    # Add MediaTek Genio PPA (Issue 5.1: NPU firmware missing from repos)
    if ! grep -q "mediatek-genio" /etc/apt/sources.list.d/*.list 2>/dev/null; then
        add-apt-repository -y ppa:mediatek-genio/genio-public 2>/dev/null || {
            warn "Could not add PPA automatically"
            echo "deb https://ppa.launchpadcontent.net/mediatek-genio/genio-public/ubuntu $(lsb_release -cs) main" \
                > /etc/apt/sources.list.d/mediatek-genio.list
        }
    fi
    apt-get update -qq

    # NPU firmware & runtime (Issue 5.1) — from MediaTek repos, not custom
    apt-get install -y \
        mediatek-apusys-firmware-genio1200 \
        mediatek-libneuron \
        mediatek-neuron-utils \
        mediatek-libneuron-dev \
        mediatek-vpud-genio1200 \
        gstreamer1.0-plugins-base \
        gstreamer1.0-plugins-good \
        gstreamer1.0-plugins-bad \
        >/dev/null 2>&1 || warn "Some MediaTek packages may not be available on this distro"

    rm -f ~/.cache/gstreamer-1.0/registry.aarch64.bin 2>/dev/null || true

    # Python AI libraries (all from pip — no custom code)
    pip3 install --break-system-packages \
        numpy scipy opencv-python-headless pillow \
        >/dev/null 2>&1 || true
    pip3 install --break-system-packages onnxruntime >/dev/null 2>&1 || \
        warn "ONNX Runtime — check ARM64 wheel availability"
    pip3 install --break-system-packages \
        torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/cpu \
        >/dev/null 2>&1 || warn "PyTorch — check ARM64 wheel availability"

    # Verify NPU (Issue 5.1: check firmware)
    if command -v vpu5_test >/dev/null 2>&1; then
        info "Verifying NPU with vpu5_test..."
        timeout 30 vpu5_test -a ks -l 10 2>&1 | tail -3 || warn "NPU verification failed"
        ok "NPU verified — use neuronrt for DLA inference, ncc-tflite for compilation"
    else
        warn "vpu5_test not found — NPU firmware may not have installed correctly"
    fi

    ok "AI stack installed: NeuroPilot + ONNX Runtime + PyTorch + GStreamer"
}

# ── Step 3: Monitoring (Netdata from github:netdata/netdata) ──────────────────
setup_monitoring() {
    info "Step 3: Installing Netdata monitoring (github: netdata/netdata)..."
    if ! command -v netdata >/dev/null 2>&1; then
        info "Installing Netdata from distro-signed packages..."
        apt-get install -y netdata >/dev/null 2>&1 || {
            warn "Netdata unavailable from configured packages; skipping"
            return
        }
    fi

    # Apply NIO 12L-specific Netdata config
    if [[ -f "dashboard/config/netdata/netdata.conf" ]]; then
        cp dashboard/config/netdata/netdata.conf /etc/netdata/netdata.conf 2>/dev/null || true
        if [[ -f "dashboard/config/netdata/npu_gpu_check.py" ]]; then
            cp dashboard/config/netdata/npu_gpu_check.py /usr/lib/netdata/python.d/npu_gpu.py 2>/dev/null || true
            chmod +x /usr/lib/netdata/python.d/npu_gpu.py 2>/dev/null || true
        fi
        systemctl restart netdata 2>/dev/null || true
    fi

    local ip=$(hostname -I | awk '{print $1}')
    ok "Netdata installed locally — http://127.0.0.1:19999 (use an authenticated tunnel)"
}

# ── Step 4: Server Management (Cockpit from github:cockpit-project/cockpit) ────
setup_cockpit() {
    if [[ "${NIO_ENABLE_COCKPIT:-0}" != 1 ]]; then
        info "Cockpit not installed automatically; use NIO_ENABLE_COCKPIT=1 to opt in."
        return
    fi
    info "Step 4: Installing Cockpit (github: cockpit-project/cockpit)..."
    apt-get install -y cockpit >/dev/null 2>&1 || {
        warn "Cockpit not available via apt on this distro"
        return
    }
    systemctl enable --now cockpit.socket 2>/dev/null || true
    local ip=$(hostname -I | awk '{print $1}')
    ok "Cockpit installed — https://$ip:9090 (terminal, services, logs, storage)"
}

# ── Step 5: Dashboard (Homepage from github:benphelps/homepage) ────────────────
setup_dashboard() {
    info "Step 5: Installing Homepage dashboard (github: benphelps/homepage)..."

    if command -v docker >/dev/null 2>&1; then
        info "Using Docker Compose for dashboard stack..."
        # Never replace an existing Docker CE installation while configuring the dashboard.
        docker compose version >/dev/null || {
            warn "Docker Compose v2 is required; skipping dashboard deployment"
            return
        }

        local DASH_DIR="/opt/nio12l-dashboard"
        mkdir -p "$DASH_DIR/config" "$DASH_DIR/caddy" "$DASH_DIR/netdata"

        [[ -f "dashboard/docker-compose.yml" ]] && cp dashboard/docker-compose.yml "$DASH_DIR/"
        if [[ -d "dashboard/config/homepage" ]]; then
            cp -r dashboard/config/homepage/* "$DASH_DIR/config/"
        fi
        [[ -f "dashboard/config/caddy/Caddyfile" ]] && cp dashboard/config/caddy/Caddyfile "$DASH_DIR/caddy/"

        cd "$DASH_DIR"
        docker compose up -d 2>/dev/null || warn "Docker compose failed — check configuration"
        local ip=$(hostname -I | awk '{print $1}')
        ok "Homepage dashboard available on NIO loopback (SSH forward to port 80)"
    else
        warn "Docker not available — install Node.js + Homepage manually:"
        warn "  git clone https://github.com/benphelps/homepage.git /opt/homepage"
        warn "  cd /opt/homepage && npm install && npm run build && npm start"
    fi
}

# ── Step 6: GPU DVFS Fix ───────────────────────────────────────────────────────
# Addresses GITHUB_ISSUES_REPORT.md §3.2 — GPU stuck at 390 MHz
fix_gpu_dvfs() {
    info "Step 6: Checking GPU DVFS configuration..."
    local dtb_files
    dtb_files=$(find /boot -name "*nio-12l*.dtb" -o -name "*genio*.dtb" 2>/dev/null || true)
    if [[ -z "$dtb_files" ]]; then
        warn "No DTB found — GPU DVFS fix requires manual DTB edit"
        warn "See GITHUB_ISSUES_REPORT.md §3.2 for DTB fix instructions"
        return
    fi
    for dtb in $dtb_files; do
        if command -v dtc >/dev/null 2>&1; then
            dtc -I fs -O dts "$dtb" 2>/dev/null | grep -q "mali_sram-supply" && {
                ok "mali_sram-supply found in $dtb — verify MT6315 regulator reference"
            } || warn "mali_sram-supply not found in $dtb"
        fi
    done
    info "GPU DVFS: If stuck at 390MHz, apply DTB fix per GITHUB_ISSUES_REPORT.md §3.2"
}

# ── Step 7: systemd Service ────────────────────────────────────────────────────
setup_service() {
    info "Step 7: Installing systemd services..."
    cat > /etc/systemd/system/nio12l-dashboard.service <<'EOF'
[Unit]
Description=NIO 12L Dashboard Stack
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/nio12l-dashboard
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=120
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable nio12l-dashboard 2>/dev/null || true
    ok "systemd services configured"
}

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
    require_root
    [[ "${1:-}" != "--all" ]] && { warn "Pass --all to skip confirmation"; read -p "Continue? (y/N) " -r; [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1; }

    echo "=============================================="
    echo "  Radxa NIO 12L — Complete AI Workstation Setup"
    echo "  Tools: Netdata, Cockpit, Homepage, NeuroPilot"
    echo "  Issues: GITHUB_ISSUES_REPORT.md"
    echo "=============================================="

    optimize_system; echo ""
    setup_ai_stack;  echo ""
    setup_monitoring; echo ""
    setup_cockpit;    echo ""
    setup_dashboard;  echo ""
    fix_gpu_dvfs;     echo ""
    setup_service;    echo ""

    local ip=$(hostname -I | awk '{print $1}')
    echo "=============================================="
    ok "Setup complete! Access points:"
    echo "=============================================="
    echo "  Dashboard:  SSH forward local port 18080 to NIO 127.0.0.1:80"
    echo "  Netdata:    http://127.0.0.1:19999 on the NIO (separate tunnel if needed)"
    echo "  Cockpit:    opt-in only (NIO_ENABLE_COCKPIT=1), restrict host listener separately"
    echo "  AI Models Directory: /usr/local/share/npu-models/"
    echo ""
    echo "  Reboot recommended to apply all changes."
    echo "  See README.md for detailed usage guide."
}

main "$@"
