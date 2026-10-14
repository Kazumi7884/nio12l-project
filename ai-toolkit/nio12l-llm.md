# NIO 12L on-device LLM (accuracy-first, CPU-only)

> The MT8395 NPU is **out** for LLMs: MediaTek Genio docs confirm ONNX on the
> Genio 1200 (MT8395) runs via **CPU EP**; the NPU is CV-only
> (INT8 conv/act/pool, 3.9 TOPS, no attention offload path).
> CPU llama.cpp is the only viable inference path.

## Decision: Qwen3-8B @ Q4_K_M + the "autocache" stack

Accuracy is the priority, so every mechanism chosen here has **zero accuracy
cost** (no weight retraining, no KV distillation, no aggressive eviction):

| Layer | Mechanism | Flag | Effect |
|-------|-----------|------|--------|
| Token ceiling | q8_0 KV cache + FlashAttention | `-ctk q8_0 -ctv q8_0 -fa on` | halves the cache (64→32 KB/token) so 16 K context fits with headroom |
| Decode speed | n-gram speculative (no 2nd model) | `--spec-type ngram-mod` | ~1.5-2x tok/s, 16 MB hash of your own history drafts tokens; target verifies every one — exact output |
| Startup speed | prompt-cache persistence | `--prompt-cache /opt/nio12l-models/prompt-cache.state` | long system prompt / repo context restores from KV, no recompute |
| CPU use | pin to 4x A78 | `-C 0x000F`, `taskset -c 0-3` | excludes the in-order A55s that stall matmul |
| RAM | mmap + lazy + swap | `-lm mmap` (no mlock), zram (setup/optimize-system.sh) | model pages evicted under pressure instead of pinned |

Why **Qwen3-8B**: GQA (32 Q / 8 KV heads) shrinks the cache vs Llama-3.1;
native 32 K context with YaRN; strong across coding + reasoning + research.
**Rejected**: q4_0 KV cache (degrades attention → reasoning harm); the
TurboQuant-H2O eviction fork (arXiv 2607.13205 shows heavy-hitter eviction
collapses exact-match on JSON/structured inputs 88%→0% — fatal for code
research), and any multi-slot server config (llama.cpp #27148 leaks a finished
conversation into a new request — mitigated by `-np 1` `--no-cache-idle-slots`).

## Memory budget (8 GB, Qwen3-8B Q4_K_M, 16 K, q8_0 KV, 6 threads)
- weights ~4.8 GB (mmap, lazy) + KV ~1.1 GB + overhead ~0.8 GB ≈ **6.7 GB peak**
  → ~1.1 GB headroom. 32 K ctx ≈ 2.2 GB KV is possible but leaves <0.2 GB —
  only use 32 K if the dashboard is stopped.

## How to run
```sh
sudo ./ai-toolkit/nio12l-llama-server.sh
# then: curl http://127.0.0.1:8080
```
The script builds llama.cpp with `-DGGML_CPU_KLEIDIAI=ON` (DotProd/i8mm
microkernels for the A78), fetches `Qwen3-8B-Q4_K_M.gguf`, sets swappiness=10 +
zram, and aborts if MemAvailable < 1 GB.

## Expected throughput (reality, not a promise)
- decode ~3 tok/s baseline → ~4 tok/s with ngram-mod
- prompt ingest ~5-7 tok/s (FlashAttention + A78s)
- these are bandwidth-bound on LPDDR4X-4266 (~26 GB/s sustained); more threads
  do not help past 6.
