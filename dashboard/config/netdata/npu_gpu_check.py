#!/usr/bin/env python3
"""
npu_gpu_check.py — Netdata python.d module for NIO 12L NPU/GPU metrics
======================================================================
This is a Netdata custom collector plugin that reads MediaTek APU/NPU
and Mali GPU stats from sysfs. Placed at /etc/netdata/python.d/npu_gpu.py

No custom dashboard code — uses Netdata's built-in chart rendering.
The charts appear automatically in Netdata UI at the board's IP:19999.
"""
import os
import glob
import subprocess

ORDER = ['npu_stats', 'gpu_stats', 'vpu_stats']

CHARTS = {
    'npu_stats': {
        'title': 'NPU Utilization',
        'type': 'utilization',
        'units': 'percent',
        'family': 'npu',
        'chart_type': 'line',
        'stack': False,
    },
    'gpu_stats': {
        'title': 'GPU Utilization',
        'type': 'utilization',
        'units': 'percent',
        'family': 'gpu',
        'chart_type': 'line',
        'stack': False,
    },
    'vpu_stats': {
        'title': 'VPU Load',
        'type': 'utilization',
        'units': 'percent',
        'family': 'vpu',
        'chart_type': 'line',
        'stack': False,
    },
}


class NPUMetricCollector:
    """Reads NPU/GPU/VPU metrics from MediaTek sysfs interfaces."""

    def __init__(self, config):
        self.order = ORDER
        self.definitions = CHARTS

    def get_data(self):
        data = {}
        data.update(self._read_npu())
        data.update(self._read_gpu())
        data.update(self._read_vpu())
        return data

    def _read_npu(self):
        """Read APU/NPU metrics from /sys/kernel/debug/apusys."""
        result = {}
        apusys = Path("/sys/kernel/debug/apusys")
        if not apusys.exists():
            return {"npu_util": 0}

        # Try to read APU device utilization
        try:
            for dev in sorted((apusys / "device").iterdir()):
                if dev.is_dir():
                    util_file = dev / "utilization"
                    if util_file.exists():
                        val = util_file.read_text().strip()
                        result[f"npu_util_{dev.name}"] = int(val) if val.isdigit() else 0
        except Exception:
            pass

        if not result:
            result["npu_util"] = 0
        return result

    def _read_gpu(self):
        """Read Mali GPU frequency/utilization."""
        result = {}
        # Try /sys/class/drm for GPU info
        drm_path = Path("/sys/class/drm/card0/device")
        if drm_path.exists():
            result["gpu_available"] = 1
            # Try to read GPU load via /dev/dri query
            try:
                result_val = subprocess.run(
                    ["cat", str(drm_path / "gpu_busy_percent")],
                    capture_output=True, text=True, timeout=5
                )
                if result_val.returncode == 0:
                    result["gpu_util"] = int(result_val.stdout.strip()) if result_val.stdout.strip().isdigit() else 0
                else:
                    result["gpu_util"] = 0
            except Exception:
                result["gpu_util"] = 0
        else:
            result["gpu_available"] = 0
            result["gpu_util"] = 0
        return result

    def _read_vpu(self):
        """Read VPU (Video Processing Unit) thermal/metrics."""
        result = {}
        # Check for VPU device nodes
        vpu_devs = glob.glob("/dev/vpu*") + glob.glob("/dev/mtk-*vpu*")
        result["vpu_available"] = 1 if vpu_devs else 0
        result["vpu_util"] = 0  # VPU utilization requires MediaTek tools
        return result


from pathlib import Path  # noqa: E402
