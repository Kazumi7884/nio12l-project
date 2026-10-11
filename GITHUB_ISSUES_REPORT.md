# Radxa NIO 12L — GitHub Issues Report

**Last updated**: 2026-06-25  
**Board**: Radxa NIO 12L (MediaTek MT8395 / Genio 1200)

---

## 1. Official Radxa Repositories

### 1.1 `radxa-build/radxa-nio-12l` — ARCHIVED
- **URL**: https://github.com/radxa-build/radxa-nio-12l
- **Status**: Archived Oct 12, 2024. Read-only. 1 commit.
- **Issue**: Official Radxa build repo is no longer maintained. New releases are at `dl.radxa.com/nio12l/images/ubuntu/`.
- **Impact**: No official Ubuntu image updates through GitHub. Users must download from Radxa's CDN.

### 1.2 `radxa-docs/docs` — 173 open issues (general)
- **URL**: https://github.com/radxa-docs/docs/issues
- **NIO 12L-specific issues** (8 found, all merged):
  - #1514 — docs: Add Baidu Netdisk download link (merged Mar 2026)
  - #1212 — feat: NIO 12L camera usage and image link update (merged Dec 2025)
  - #1112 — feat: NIO 12L GPIO usage and download links (merged Dec 2025)
  - #629  — fix: NIO 12L installation guide (merged Jan 2025)
  - #554  — NIO 12L and Zero 3 update (merged Nov 2024)
  - #471  — feat: Add more NIO 12L hardware details (merged Sep 2024)
  - #470  — feat: Add Yocto user guide (merged Sep 2024)
  - #468  — feat: Add Ubuntu user guide (merged Sep 2024)
  - #414  — feat: Use Radxa kernel tree to build Ubuntu kernel (merged Aug 2024)
  - #403  — feat: New Yocto build guide (merged Aug 2024)
  - #334  — Update NIO 12L Ubuntu image and flash guide (merged Jul 2024)
- **Open issues**: 173 total — most are for other Radxa boards (ROCK, CM3, etc.) but share kernel/firmware concerns.

### 1.3 `radxa/apt` — Package conflicts
- **URL**: https://github.com/radxa/apt/issues
- **Known issues**:
  - `radxa-firmware` conflicts with `firmware-misc-nonfree`
  - Missing or outdated `gstreamer1.0-plugins-good` on Debian Bullseye for some boards
  - Some users report NPU-related firmware packages missing or outdated on Ubuntu Jammy (22.04)

---

## 2. Armbian Issues & PRs

### 2.1 PR #8093 — Dropping vendor kernel (MERGED, Apr 2025)
- **URL**: https://github.com/armbian/build/pull/8093
- **Author**: igorpecovnik
- **Summary**: Removed the broken "vendor" kernel target for NIO 12L. Now uses only "collabora" kernel.
- **Root cause**: Vendor kernel had HDMI build-in compilation issues (`CONFIG_DRM_MEDIATEK_HDMI`, `CONFIG_PHY_MTK_HDMI` built-in caused kernel build failure — bug #2107430).
- **Fix**: Switched `CONFIG_DRM_MEDIATEK_HDMI` and `CONFIG_PHY_MTK_HDMI` from `y` → `m` (built-in → module). Removed "vendor" from `KERNEL_TARGET`.
- **Impact**: Users lose vendor-specific optimizations but gain a compilable kernel. The collabora (mainline-based) kernel is now the default.

### 2.2 PR #10034 — Kernel 7.1.y mainline upgrade (MERGED, Jun 2025)
- **URL**: https://github.com/armbian/build/pull/10034
- **Author**: rpardini
- **Summary**: Bumped edge kernel from 6.19 → 7.1.y, pure mainline. Added loadaddr fixes and DTS overlay.
- **Critical bug fixed**: Kernel load address `0x40000000` overlaid reserved low-RAM hole at `0x43200000–0x43DFFFFF`, causing "Reading file would overwrite reserved memory" and silent boot failures.
- **Fix**: Moved `kernel_addr_r` to `0x44000000` (just past the reserved region). Added fatal load guards (if/else+exit) so failed loads abort instead of silently booting garbage.
- **New overlay**: `mt8395-radxa-nio-12l-extra` DTS overlay.
- **Impact**: This fixes the boot hang/garbage boot issue on 16GB RAM models with larger kernels. Use kernel ≥ 7.1 on Armbian 26.5+.

### 2.3 PR #7926 — Initial Genio family + NIO 12L support (MERGED, Mar 2025)
- **URL**: https://github.com/armbian/build/pull/7926
- **Author**: HeyMeco
- **Summary**: Initial board config, Genio family definition (kernel 6.14), WiFi fixes via board firmware.
- **Known limitation**: UFS support requires 4096-byte sector partitioning — not covered in initial PR. SD card boot worked but UFS did not.

### 2.4 Issue #10646 — "Armbian 26.08 broken on Radxa 12L NIO" (OPEN)
- **Source**: Armbian Jira via GitHub Actions workflow
- **URL**: https://github.com/armbian/build (referenced in workflow runs)
- **Status**: Open, reported by user `madduci`
- **Summary**: Armbian 26.08 images are broken on NIO 12L. Likely regression from 26.05→26.08.
- **Workaround**: Use Armbian 26.5.x (kernel 6.19.8) or 26.2.4 instead.

---

## 3. Ubuntu / Official Radxa Issues

### 3.1 Ubuntu GPU driver voltage scaling failure
- **Source**: Reddit r/SBCs (u/ztcsdtx), community testing
- **Description**: Ubuntu official image's Mali GPU driver cannot set correct voltage, crashes when clock speed increases.
- **Root cause**: Driver code is for Kompanio 1380 (MT8195), not Genio 1200 (MT8395). Resource allocations differ.
- **Workaround**: Use Armbian (collabora/mainline kernel) instead of Ubuntu official image.

### 3.2 GPU DVFS stuck at 390 MHz
- **Source**: Reddit r/SBCs
- **Description**: Stock device overlay (`-malibo`) has misconfigured `mali_sram-supply` regulator reference.
- **Fix**: Correct device tree to point both `mali-supply` and `mali_sram-supply` to the correct `MT6315` regulator.
- **Result**: After fix, all 16 OPPs (390–880 MHz) become active with `simple_ondemand` governor.

### 3.3 No Vulkan support
- **Source**: Community testing
- **Description**: No `panvk` ICD found in Mesa25. No Vulkan support on NIO 12L currently.
- **Status**: Part of ongoing upstream development, not board-specific.
- **Impact**: Vulkan applications will fall back to software rendering or fail.

### 3.4 Ubuntu kernel outdated
- **Source**: Radxa docs
- **Description**: Official Ubuntu image ships kernel 5.15.0-1029.33. Armbian provides 6.19.8 (edge) and 7.1.y (rolling).
- **Recommendation**: Use Armbian with kernel ≥ 6.19 for best hardware support.

---

## 4. Hardware / Flashing Issues

### 4.1 No SD card slot
- **Description**: NIO 12L has no microSD boot support. Must flash via USB-C OTG using `genio-tools`.
- **Tool**: `pip3 install genio-tools` then `genio-flash`
- **DDR variant selection**: Must match RAM size:
  - 4GB → `cp fip-ddr4g.bin fip.bin && cp u-boot-initial-env-ddr4g u-boot-initial-env`
  - 8GB → `cp fip-ddr8g.bin fip.bin && cp u-boot-initial-env-ddr8g u-boot-initial-env`
  - 16GB → `cp fip-ddr16g.bin fip.bin && cp u-boot-initial-env-ddr16g u-boot-initial-env`
- **Risk**: Wrong DDR firmware = boot loop with no error messages.

### 4.2 Power supply issues
- **Description**: Board requires 5V/3A+ dedicated supply. Laptop USB-C ports insufficient.
- **PD not supported**: Use USB-A wall adapter + USB-C to USB-A cable, plugged into the correct USB-C port.
- **Symptom**: Boot loop if underpowered.

### 4.3 Video output intermittent
- **Source**: Reddit r/SBCs (u/ztcsdtx)
- **Description**: Video output intermittently vanishes on some images (Ubuntu, Collabora Debian).
- **Symptom**: Green LED stays solid (Armbian/Collabora) vs green→cyan transition (Ubuntu).
- **Workaround**: Armbian 6.19.8 desktop works reliably.

---

## 5. AI / NPU Issues

### 5.1 NPU firmware not in standard repos
- **Source**: Reddit r/SBCs
- **Description**: `firmware-mediatek` package from Debian repos doesn't include NPU support for Genio 1200. Ubuntu Jammy packages are outdated.
- **Fix**: Install `mediatek-apusys-firmware-genio1200` from Radxa PPA (ppa:mediatek-genio/genio-public).
- **Verification**: `sudo vpu5_test -a ks -l 10` should show `PASS`.

### 5.2 ONNX via Neuron API requires manual configuration
- **Description**: ONNX models require loading via Neuron API, not just `ncc-tflite` (TFLite only).
- **Impact**: Extra setup step for ONNX model deployment.

---

## 6. Summary of Workarounds

| Issue | Workaround | Priority |
|-------|-----------|----------|
| Ubuntu GPU crashes | Use Armbian 26.5+ (kernel 6.19.8 or 7.1.y) | High |
| GPU stuck at 390 MHz | Fix DTB: point `mali_sram-supply` to MT6315 regulator | High |
| Boot garbage at 0x40000000 | Use kernel ≥ 7.1 (loadaddr fix) or manual `kernel_addr_r=0x44000000` | Critical |
| No Vulkan | Use OpenGL ES / OpenCL for GPU compute | Low |
| NPU firmware missing | Install `mediatek-apusys-firmware-genio1200` from PPA | High |
| Wrong DDR firmware | Always use matching `fip-ddrXXX.bin` | Critical |
| Underpowered supply | 5V/3A+ USB-A wall adapter | Critical |
