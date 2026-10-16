# README.md — Radxa NIO 12L AI Workstation
# A zero-custom-code setup using existing GitHub open-source tools

# Radxa NIO 12L AI Workstation

A complete, feature-rich setup for the **Radxa NIO 12L** (MediaTek MT8395 / Genio 1200)
that makes the board viable for complex AI tasks.

> **Zero custom dashboard code.** This project assembles existing open-source tools
> from GitHub into a cohesive AI development environment.

## What This Provides

| Component | GitHub Repo | Purpose |
|-----------|------------|---------|
| **OS** | [armbian/build](https://github.com/armbian/build) | Armbian 26.5+ with kernel 6.19.8 or 7.1y (fixes GitHub issues) |
| **Dashboard** | [gethomepage/homepage](https://github.com/gethomepage/homepage) | Application dashboard with system widgets |
| **Monitoring** | [netdata/netdata](https://github.com/netdata/netdata) | Real-time system + NPU/GPU metrics |
| **Server Admin** | [cockpit-project/cockpit](https://github.com/cockpit-project/cockpit) | Web-based terminal, services, storage, network |
| **Reverse Proxy** | [caddyserver/caddy](https://github.com/caddyserver/caddy) | HTTPS, routing, auth |
| **AI Runtime** | [MediaTek NeuroPilot](https://neuropilot-developer.mediatek.com) | NPU (APU) inference via Neuron SDK |
| **AI Frameworks** | [pytorch](https://github.com/pytorch/pytorch), [onnxruntime](https://github.com/microsoft/onnxruntime) | CPU-side model development |

## Quick Start

### 1. Flash Armbian (not Ubuntu — see GITHUB_ISSUES_REPORT.md)

```bash
# Install genio-tools
pip3 install -U genio-tools

# Download Armbian from https://armbian.com/boards/radxa-nio-12l
# Select UFS image, DDR variant matching your RAM (4g/8g/16g)

# Copy DDR-matching firmware
cp fip-ddr16g.bin fip.bin          # for 16GB board
cp u-boot-initial-env-ddr16g u-boot-initial-env
genio-flash
# Hold Download button + connect USB-C OTG → release when green LED flashes
```

See [FLASHING_GUIDE.md](FLASHING_GUIDE.md) for full details.

### 2. Install Everything (one command)

```bash
# On the NIO 12L board (Armbian):
sudo ./setup/optimize-system.sh --all
```

This installs and configures:
- System optimizations (CPU governor, memory, I/O, thermal)
- MediaTek NeuroPilot SDK (NPU firmware + Neuron runtime)
- PyTorch + ONNX Runtime + OpenCV (Python AI libraries)
- Netdata monitoring (github: netdata/netdata)
- Cockpit server management (github: cockpit-project/cockpit)
- Homepage dashboard (github: gethomepage/homepage) via Docker Compose

### 5. Backup your data (new extra use)

```bash
# Install rclone + restic and configure backup destination
sudo ./setup/backup-setup.sh --install

# Perform a backup of /etc, /home, dashboard config, and NPU model cache
sudo ./setup/backup-setup.sh --backup

# Restore from latest snapshot
sudo ./setup/backup-setup.sh --restore latest

# Check backup status
sudo ./setup/backup-setup.sh --status
```

Backups are stored locally at `/var/lib/nio12l-backup` or on a remote
(SFTP/S3/Crypt) configured in `/etc/nio12l-backup/rclone.conf`.

### 3. Benchmark AI Performance

```bash
# Compare NPU vs CPU inference performance
sudo ./ai-toolkit/nio12l-benchmark.sh model.dla model.onnx
```

Uses `neuronrt` (NPU) and `onnxruntime` (CPU) — no custom inference code.
See [ai-toolkit/nio12l-ai-setup.md](ai-toolkit/nio12l-ai-setup.md) for model
conversion steps.

### 4. Access the Dashboard

After installation, reboot and browse to:

```
http://<board-ip>/              → Homepage dashboard (system widgets + service links)
http://<board-ip>:19999         → Netdata (full metrics, NPU/GPU charts)
https://<board-ip>:9090         → Cockpit (terminal, services, storage, logs)
```

## Project Structure

```nio12l-project/
├── LICENSE                            ← MIT License
├── .gitignore                         ← Git ignore rules
├── README.md                          ← This file
├── GITHUB_ISSUES_REPORT.md            ← All researched GitHub issues + workarounds
├── FLASHING_GUIDE.md                  ← Step-by-step board flashing guide
├── setup/
│   ├── optimize-system.sh             ← One-command setup (7 steps, all tools)
│   ├── backup-setup.sh                ← Backup solution (rclone + restic)
│   └── verify-setup.sh                ← Post-installation verification
├── ai-toolkit/
│   ├── nio12l-ai-setup.md             ← AI model workflow (NeuroPilot, ONNX, PyTorch)
│   ├── nio12l-benchmark.sh            ← NPU vs CPU inference benchmark
│   ├── nio12l-llama-server.sh         ← Local LLM (Qwen3-8B, accuracy-first)
│   └── nio12l-llm.md                  ← Local LLM documentation
└── dashboard/
    ├── docker-compose.yml             ← Docker stack (Caddy + Homepage + Netdata)
    ├── setup-dashboard.sh             ← Dashboard-only installation script
    ├── config/
    │   ├── caddy/Caddyfile            ← Reverse proxy config
    │   ├── netdata/
    │   │   ├── netdata.conf           ← Netdata config with NPU/GPU collectors
    │   │   ├── npu_gpu.py             ← Netdata python.d module (fixed)
    │   │   └── npu_gpu_check.py       ← Removed (superseded by npu_gpu.py)
    │   └── homepage/
    │       ├── services.yaml          ← Service cards (System, AI, Storage, Network)
    │       ├── widgets.yaml           ← Info widgets (resources, datetime, search)
    │       └── settings.yaml          ← Theme & layout settings
    └── systemd/
        └── nio12l-dashboard.service   ← Auto-start dashboard on boot
```

## GitHub Issues Referenced

- `radxa-build/radxa-nio-12l` — archived, use dl.radxa.com instead
- `radxa-docs/docs` — 173 open issues (8 NIO 12L specific, all merged)
- `armbian/build#8093` — dropped broken vendor kernel (HDMI build issues)
- `armbian/build#10034` — kernel 7.1.y mainline + loadaddr fix
- `armbian/build#7926` — initial Genio family + NIO 12L board config
- `armbian/build#10646` — Armbian 26.08 broken on NIO 12L (use 26.5.x)

## Known Limitations (from GitHub research)

- **Vulkan**: Not available (no `panvk` ICD in Mesa25) — use OpenGL ES / OpenCL
- **Ubuntu GPU**: Crashes on official Ubuntu image — use Armbian instead
- **GPU DVFS**: May be stuck at 390MHz — requires DTB fix (see §3.2 in issues report)
- **NPU**: Uses MediaTek's NeuroPilot (TFLite/ONNX), not PyTorch native
- **No SD card slot**: Must flash via USB-C OTG using genio-tools

See [GITHUB_ISSUES_REPORT.md](GITHUB_ISSUES_REPORT.md) for full details.
