#!/usr/bin/env bash
###############################################################################
# nio12l-benchmark.sh — AI inference benchmark for Radxa NIO 12L
#
# Compares NPU (via neuronrt) vs CPU (via onnxruntime) performance.
# Uses EXISTING tools — no custom inference code.
#
# Prerequisites (installed by setup/optimize-system.sh):
#   - mediatek-neuron-utils (provides vpu5_test, neuronrt, ncc-tflite)
#   - onnxruntime (Python package)
#   - A compiled .dla model at /usr/local/share/npu-models/
#
# Usage:
#   sudo ./ai-toolkit/nio12l-benchmark.sh model.dla model.onnx
###############################################################################
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*"; }

DA_MODEL="${1:-/usr/local/share/npu-models/model.dla}"
ONNX_MODEL="${2:-/usr/local/share/npu-models/model.onnx}"
ITERATIONS="${3:-10}"

if [[ ! -f "$DA_MODEL" ]]; then
    err "DLA model not found: $DA_MODEL"
    err "Place your compiled .dla model in /usr/local/share/npu-models/"
    exit 1
fi

info "=== NIO 12L AI Benchmark ==="
info "DLA model: $DA_MODEL"
info "ONNX model: $ONNX_MODEL"
info "Iterations: $ITERATIONS"
echo ""

# ── NPU Benchmark (MediaTek neuronrt) ──────────────────────────────────────
info "Benchmarking NPU (neuronrt)..."
if command -v neuronrt >/dev/null 2>&1; then
    # Create dummy input if not provided
    INPUT_FILE="/tmp/benchmark_input.bin"
    if [[ ! -f "$INPUT_FILE" ]]; then
        dd if=/dev/zero of="$INPUT_FILE" bs=1M count=1 2>/dev/null
    fi

    info "Running neuronrt -m hw -a $DA_MODEL -i $INPUT_FILE -c $ITERATIONS..."
    if timeout 60 neuronrt -m hw -a "$DA_MODEL" -i "$INPUT_FILE" -c "$ITERATIONS" -v 2>&1 | tee /tmp/npu_bench_output.txt; then
        ok "NPU benchmark complete"
    else
        warn "NPU benchmark failed — check NPU firmware installation"
    fi
else
    warn "neuronrt not found — NPU benchmark skipped"
    warn "Install: apt install mediatek-neuron-utils"
fi

# ── CPU Benchmark (ONNX Runtime) ────────────────────────────────────────────
info ""
info "Benchmarking CPU (onnxruntime)..."
if python3 -c "import onnxruntime" 2>/dev/null; then
    if [[ -f "$ONNX_MODEL" ]]; then
        python3 -c "
import time
import onnxruntime as ort
import numpy as np

sess = ort.InferenceSession('$ONNX_MODEL', providers=['CPUExecutionProvider'])
inputs = {inp.name: np.zeros(inp.shape, dtype=np.float32) for inp in sess.get_inputs()}

# Warmup
sess.run(None, inputs)

# Benchmark
latencies = []
for _ in range($ITERATIONS):
    start = time.perf_counter()
    sess.run(None, inputs)
    latencies.append(time.perf_counter() - start)

avg_ms = sum(latencies) / len(latencies) * 1000
fps = 1 / (sum(latencies) / len(latencies))
print(f'CPU avg latency: {avg_ms:.2f} ms')
print(f'CPU throughput:  {fps:.2f} FPS')
" 2>&1 | tee /tmp/cpu_bench_output.txt
        ok "CPU benchmark complete"
    else
        warn "ONNX model not found: $ONNX_MODEL — CPU benchmark skipped"
    fi
else
    warn "onnxruntime not installed — CPU benchmark skipped"
    warn "Install: pip install onnxruntime"
fi

# ── Summary ─────────────────────────────────────────────────────────────────
info ""
echo "=============================================="
info "=== Benchmark Summary ==="
echo "=============================================="

if [[ -f /tmp/npu_bench_output.txt ]]; then
    info "NPU output:"
    cat /tmp/npu_bench_output.txt | grep -i "avg\|latency\|FPS\|time\|PASS\|FAIL" | head -5
fi

if [[ -f /tmp/cpu_bench_output.txt ]]; then
    info "CPU output:"
    cat /tmp/cpu_bench_output.txt | grep -i "avg\|latency\|throughput" | head -5
fi

echo ""
info "Results saved to /tmp/npu_bench_output.txt and /tmp/cpu_bench_output.txt"
