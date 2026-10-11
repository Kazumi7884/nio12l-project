# Flashing Guide — Radxa NIO 12L

> Based on official Radxa docs and community experience (Reddit r/SBCs).

## Prerequisites

- Radxa NIO 12L board
- 5V/3A+ USB-A wall adapter (NOT PD — PD not supported)
- USB-C to USB-A cable (for flashing)
- USB-C to USB-A cable (for power) — use correct port
- Computer (Linux/Windows/macOS) with Python 3 and pip
- Correct DDR variant firmware (4GB / 8GB / 16GB)

## Step 1: Install genio-tools

```bash
pip3 install -U genio-tools
genio-config  # Checks if host is properly configured
```

## Step 2: Download Armbian Image

Go to [armbian.com/boards/radxa-nio-12l](https://armbian.com/boards/radxa-nio-12l)
and download the **UFS** image matching your RAM:

| Your RAM | Image Variant | Firmware Files |
|----------|--------------|----------------|
| 4GB | `...-ddr4g-ufs-...` | `fip-ddr4g.bin`, `u-boot-initial-env-ddr4g` |
| 8GB | `...-ddr8g-ufs-...` | `fip-ddr8g.bin`, `u-boot-initial-env-ddr8g` |
| 16GB | `...-ddr16g-ufs-...` | `fip-ddr16g.bin`, `u-boot-initial-env-ddr16g` |

> **WARNING**: Using the wrong DDR variant = boot loop with NO error messages.

## Step 3: Prepare Firmware

```bash
cd ~/Downloads/armed-image/  # directory with extracted Armbian image
# For 16GB RAM:
cp fip-ddr16g.bin fip.bin
cp u-boot-initial-env-ddr16g u-boot-initial-env
```

## Step 4: Enter Download Mode

1. **Power off** the board completely.
2. Hold the **Download Button** (small button near USB-C ports).
3. While holding, plug **power cable** into the **DC IN** USB-C port (NOT OTG).
4. The green LED should flash — release the Download button.
5. Connect **OTG USB-C cable** to your computer.

## Step 5: Flash

```bash
genio-flash
```

> Run `genio-flash` BEFORE entering download mode (on host PC), then enter
> download mode. The tool detects the board automatically.

## Step 6: First Boot

1. Wait for the board to boot (may take 2-3 minutes).
2. SSH: `ssh root@<board-ip>` (no password by default on Armbian)
3. Or use HDMI monitor + USB keyboard.

## Troubleshooting

### Board won't boot (green LED solid, no display)

- Check power adapter — needs 5V/3A+. Laptop USB ports often insufficient.
- Verify correct DDR firmware was used.
- Try Armbian 26.5.x instead of 26.8+ (Issue #10646).

### No video output on HDMI/USBC

- Ensure HDMI cable is connected BEFORE powering on.
- Use Armbian Desktop image (not minimal) for first boot.
- If using Ubuntu official image — GPU driver will crash. Use Armbian instead.

### GPU stuck at 390MHz

See GITHUB_ISSUES_REPORT.md §3.2 — requires DTB modification to fix
`mali_sram-supply` regulator reference.

### NPU not detected

```bash
vpu5_test -a ks -l 10  # Should show PASS
```

If it fails, install: `apt install mediatek-apusys-firmware-genio1200 mediatek-neuron-utils`
