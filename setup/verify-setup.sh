#!/usr/bin/env bash
###############################################################################
# verify-setup.sh — Post-installation verification for NIO 12L
#
# Verifies that all components from setup/optimize-system.sh are working:
#   1. Kernel version (PR #10034 loadaddr fix check)
#   2. CPU governor & memory optimization
#   3. NPU firmware & neuronrt availability
#   4. AI libraries (PyTorch, ONNX Runtime)
#   5. Netdata monitoring
#   6. Cockpit server management
#   7. Homepage dashboard
#   8. GPU DVFS status
#
# Usage: sudo ./setup/verify-setup.sh
###############################################################################
set -uo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}✓${NC} $*"; }
warn() { echo -e "  ${YELLOW}!${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*"; }

echo "=============================================="
echo "  NIO 12L Setup Verification"
echo "=============================================="
echo ""

# 1. Kernel
echo "1. Kernel"
kver=$(uname -r)
major=$(echo "$kver" | cut -d. -f1)
if [[ "$major" -ge 7 ]]; then
    ok "Kernel $kver (>= 7.1 — includes loadaddr fix, PR #10034)"
else
    warn "Kernel $kver (< 7.1 — may need loadaddr fix: 0x44000000)"
fi

# Check collabora kernel (Issue #8093: vendor kernel dropped)
echo "$kver" | grep -qi "collabora\|genio\|mtk" && ok "Collaba/mainline kernel" || warn "Non-collabora kernel (may cause GPU issues)"
echo ""

# 2. CPU governor
echo "2. CPU Governor"
gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unknown")
[[ "$gov" == "performance" ]] && ok "CPU governor: $gov" || warn "CPU governor: $gov (expected: performance)"

# 3. Memory
echo ""
echo "3. Memory"
swap_on=$(grep -c swap /proc/swaps 2>/dev/null || echo 0)
[[ "$swap_on" -gt 0 ]] && ok "Swap configured" || warn "No swap found"
overcommit=$(sysctl vm.overcommit_memory 2>/dev/null | awk '{print $3}')
[[ "$overcommit" == "1" ]] && ok "VM overcommit: $overcommit (for AI models)" || warn "VM overcommit: $overcommit (recommend 1)"

# 4. NPU
echo ""
echo "4. NPU (MediaTek NeuroPilot)"
if command -v vpu5_test >/dev/null 2>&1; then
    ok "vpu5_test available"
    if timeout 30 vpu5_test -a ks -l 1 >/dev/null 2>&1; then
        ok "NPU hardware test: PASS"
    else
        fail "NPU hardware test: FAIL"
    fi
else
    fail "vpu5_test not found — install mediatek-neuron-utils"
fi

# Check NPU device nodes
if [[ -d "/sys/kernel/debug/apusys" ]]; then
    ok "APU sysfs available"
else
    warn "APU sysfs not found"
fi
echo ""

# 5. AI libraries
echo "5. AI Libraries"
python -c "import onnxruntime; print(f'  ✓ ONNX Runtime: {onnxruntime.__version__}')" 2>/dev/null || fail "ONNX Runtime not installed"
python -c "import torch; print(f'  ✓ PyTorch: {torch.__version__}')" 2>/dev/null || warn "PyTorch — may need ARM64 wheel check"
python -c "import numpy; print(f'  ✓ NumPy: {numpy.__version__}')" 2>/dev/null || fail "NumPy not installed"
echo ""

# 6. Netdata
echo "6. Monitoring (Netdata)"
if pgrep -x netdata >/dev/null 2>&1; then
    ok "Netdata running"
    port=$(ss -tlnp | grep 19999 | head -1 || true)
    [[ -n "$port" ]] && ok "Listening on port 19999" || warn "Port 19999 not listening"
else
    fail "Netdata not running"
fi
echo ""

# 7. Cockpit
echo "7. Server Management (Cockpit)"
if systemctl is-active --quiet cockpit.socket 2>/dev/null; then
    ok "Cockpit running on port 9090"
else
    fail "Cockpit not running — install: apt-get install cockpit"
fi
echo ""

# 8. Dashboard
echo "8. Dashboard (Homepage + Docker)"
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "nio12l-homepage"; then
    ok "Homepage container running"
else
    warn "Homepage container not running — run: docker compose up -d"
fi

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "nio12l-netdata"; then
    ok "Netdata container running"
else
    warn "Netdata container not running"
fi

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "nio12l-caddy"; then
    ok "Caddy reverse proxy running"
else
    warn "Caddy proxy not running"
fi
echo ""

# 9. GPU DVFS
echo "9. GPU DVFS"
if command -v dtc >/dev/null 2>&1 && find /boot -name "*nio-12l*.dtb" 2>/dev/null | head -1 | grep -q .; then
    dtb=$(find /boot -name "*nio-12l*.dtb" 2>/dev/null | head -1)
    dtc -I fs -O dts "$dtb" 2>/dev/null | grep -q "mali_sram-supply" && {
        reg=$(dtc -I fs -O dts "$dtb" 2>/dev/null | grep "mali_sram-supply" | grep -o '<[^>]*>' | head -1)
        if echo "$reg" | grep -qi "mt6315\|vdd"; then
            ok "GPU DVFS: mali_sram-supply → $reg (FIXED)"
        else
            warn "GPU DVFS: mali_sram-supply → $reg (UNFIXED — see §3.2 in GITHUB_ISSUES_REPORT.md)"
        fi
    } || warn "GPU DVFS: mali_sram-supply not found in DTB"
else
    warn "GPU DVFS: Cannot check (dtc or DTB not found)"
fi

# Check GPU frequency if available
gpu_freq=$(cat /sys/class/drm/card0/device/gpu_busy_percent 2>/dev/null || echo "N/A")
echo "  GPU busy%: $gpu_freq"
echo ""

# Summary
echo "=============================================="
echo "  Verification complete"
echo "=============================================="
echo ""
echo "Known issues to check:"
echo "  - Armbian 26.8+ broken (Issue #10646): use 26.5.x"
echo "  - No Vulkan (no panvk ICD in Mesa25)"
echo "  - GPU DVFS fix (mali_sram-supply) may need DTB overlay"
