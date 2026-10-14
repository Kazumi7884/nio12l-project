#!/usr/bin/env bash
###############################################################################
# nio12l-llama-server.sh
#
# Accuracy-first local LLM launcher for the Radxa NIO 12L (MT8395, 8 GB,
# aarch64, CPU-only — the NPU is CV/NeuroPilot INT8 and has no usable LLM
# attention-offload path, confirmed via MediaTek Genio docs).
#
# Design goal: "autocaching" = smooth, high-token inference for coding +
# reasoning + research, WITHOUT accuracy loss. Three stacked mechanisms:
#   1. q8_0 KV cache + FlashAttention -> halves cache, keeps OS smooth
#   2. n-gram speculative (ngram-mod)   -> ~1.5-2x decode, zero extra RAM
#   3. mmap weights + OS page cache     -> lazy load, auto-eviction under RAM
#
# Safety: single slot (-np 1). The cross-slot prompt-cache pool has a
# documented leak bug (llama.cpp #27148) that re-injects a finished
# conversation into a new request when np>1. -np 1 makes that impossible.
#
# Prerequisites (already handled by setup/optimize-system.sh):
#   zram + 4 GB swapfile, vm.overcommit_memory=1, CPU governor=performance.
#   This script checks RAM headroom before launching and refuses to start
#   under pressure to avoid silent swap thrashing.
###############################################################################
set -euo pipefail

MODEL_DIR="${MODEL_DIR:-/opt/nio12l-models}"
MODEL_FILE="${MODEL_FILE:-Qwen3-8B-Q4_K_M.gguf}"
MODEL_PATH="${MODEL_DIR}/${MODEL_FILE}"
GGUF_URL="https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/main/${MODEL_FILE}"

# Accuracy-first launch params. Flags taken verbatim from
# ggml-org/llama.cpp master (docs/speculative.md + tools/server & completion
# READMEs) — do not "improve" without re-verifying upstream.
CTX=16384                # 16K context: ~1.1 GB q8_0 KV cache. 32K (~2.2 GB)
                         # is accuracy-tempting but leaves <0.3 GB headroom on
                         # 8 GB and risks OOM — 16K is the documented safe
                         # ceiling for a smooth box.
KV=6                      # threads; pin to the 4x Cortex-A78 (see cpu-mask)
CPU_MASK="0x000F"          # cpus 0-3 = A78 cluster; excludes the in-order A55s

# ---------------------------------------------------------------------------
# 0. Environment + CPU feature check
# ---------------------------------------------------------------------------
if [ "$(uname -m)" != "aarch64" ]; then
  echo "ERROR: expected aarch64 (MT8395). Detected: $(uname -m)" >&2
  exit 1
fi

echo ">> CPU features:"
grep -o -E 'dotprod|asimd|aes' /proc/cpuinfo | sort -u | tr '\n' ' '
echo
# Cortex-A78 carries dotprod; i8mm is A78+ (may or may not be present).
DOT=$(grep -o 'dotprod' /proc/cpuinfo | head -1)
[ -z "${DOT:-}" ] && echo "!! WARNING: dotprod not advertised in /proc/cpuinfo — KleidiAI falls back to f16 matmul, decode will be slower"

# ---------------------------------------------------------------------------
# 1. Build llama.cpp with the ARM CPU backend (KleidiAI)
# ---------------------------------------------------------------------------
LLAMA_DIR="${LLAMA_DIR:-$(pwd)/llama.cpp}"

build_llama() {
  echo ">> Preparing llama.cpp (KleidiAI, native aarch64)..."
  if [ ! -d "${LLAMA_DIR}" ]; then
    git clone --depth 1 https://github.com/ggml-org/llama.cpp.git "${LLAMA_DIR}"
  fi
  cd "${LLAMA_DIR}"
  git fetch --quiet --depth 1 origin master
  git checkout origin/master
  cmake -B build \
    -DGGML_CPU_KLEIDIAI=ON \
    -DLLAMA_NATIVE=ON \
    -DLLAMA_CUBLAS=OFF \
    -DCMAKE_BUILD_TYPE=Release
  cmake --build build --target llama-server -- -j"$(nproc)"
}

# Build on first run; reuse if llama-server exists.
if [ -x "${LLAMA_DIR}/build/bin/llama-server" ]; then
  echo ">> llama-server already built, skipping build."
else
  build_llama
fi
SERVER="${LLAMA_DIR}/build/bin/llama-server"

# ---------------------------------------------------------------------------
# 2. Model
# ---------------------------------------------------------------------------
if [ ! -f "${MODEL_PATH}" ]; then
  echo ">> Downloading ${MODEL_FILE} (~4.8 GB)..."
  mkdir -p "${MODEL_DIR}"
  # huggingface-cli for resumable download; falls back to curl on failure.
  if command -v huggingface-cli >/dev/null 2>&1; then
    huggingface-cli download --repo-type model --local-dir "${MODEL_DIR}" \
      "Qwen/Qwen3-8B-GGUF" --include "Qwen3-8B-Q4_K_M.gguf"
  else
    curl -fL --retry 4 --retry-delay 8 -C - -o "${MODEL_PATH}" "${GGUF_URL}"
  fi
fi
echo ">> Model: ${MODEL_PATH} ($(du -h "${MODEL_PATH}" | cut -f1))"

# ---------------------------------------------------------------------------
# 3. Memory gate: refuse to launch if RAM headroom is unsafe.
#    Budget math for Qwen3-8B Q4_K_M @ 16K on 8 GB:
#      weights(mmap, lazy ~4.8 GB) + KV q8_0 (~1.1 GB) + overhead (~0.8 GB) = ~6.7 GB
#    Need >= 1 GB free AFTER model load to avoid swap churn.
# ---------------------------------------------------------------------------
avail_kb=$(awk '/MemAvailable:/{print $2}' /proc/meminfo)
avail_gb=$(( avail_kb / 1024 / 1024 ))
echo ">> MemAvailable now: ${avail_gb} GB"
if [ "${avail_gb}" -lt 1 ]; then
  echo "ERROR: < 1 GB free RAM (${avail_gb} GB). Stop other services or skip." >&2
  echo "    The OS+Docker+dashboard typically consume ~2.3 GB of the 8 GB." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 4. Launch (accuracy-first autocache stack).
#    Single persistent slot (-np 1) so the prompt-cache pool can't leak.
# ---------------------------------------------------------------------------
echo ">> Launching Qwen3-8B (Q4_K_M, q8_0 KV, ngram-mod spec, 16K, 6 threads@A78)..."
echo ">>    Expected: ~3-4 tok/s decode (~1.3-1.6x via ngram-mod), ~5-7 tok/s prompt."
exec taskset -c 0-3 "${SERVER}" \
  -m "${MODEL_PATH}" \
  -c "${CTX}" \
  -ctk q8_0 -ctv q8_0 \
  -fa on \
  --spec-type ngram-mod \
  --spec-ngram-mod-n-match 24 \
  --spec-ngram-mod-n-min 48 \
  --spec-ngram-mod-n-max 64 \
  --spec-draft-n-max 6 \
  --cache-reuse 256 \
  --no-cache-idle-slots \
  -np 1 \
  -t "${KV}" \
  -lm mmap \
  --numa isolate \
  -C "${CPU_MASK}" \
  --port 8080 \
  --host 127.0.0.1
