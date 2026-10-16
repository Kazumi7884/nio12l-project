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
from pathlib import Path

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
        """Read Mali GPU frequency/utilization from sysfs."""
        result = {}
        drm_path = Path("/sys/class/drm/card0/device")
        if drm_path.exists():
            result["gpu_available"] = 1
            # Read GPU load directly from sysfs (no subprocess cat needed)
            try:
                gpu_util = (drm_path / "gpu_busy_percent").read_text().strip()
                if gpu_util.isdigit():
                    result["gpu_util"] = int(gpu_util)
            except Exception:
                result["gpu_util"] = 0
        else:
            result["gpu_available"] = 0
            result["gpu_util"] = 0
        return result

    def _read_vpu(self):
        """Read VPU (Video Processing Unit) stats from sysfs and device nodes."""
        result = {}
        # Check for VPU device nodes
        vpu_devs = glob.glob("/dev/vpu*") + glob.glob("/dev/mtk-*vpu*")
        result["vpu_available"] = 1 if vpu_devs else 0

        # Try reading VPU utilization from sysfs
        vpu_stat_paths = [
            Path("/sys/class/mediatesk/mt8395/vpu/stat"),
            Path("/sys/class/vpu/"),
        ]
        for vpu_stat in vpu_stat_paths:
            try:
                if vpu_stat.is_file():
                    vpu_text = vpu_stat.read_text().strip()
                    if vpu_text.isdigit():
                        result["vpu_util"] = int(vpu_text)
                        break
            except Exception:
                continue

        # Fall back to default if no VPU stats found
        if "vpu_util" not in result:
            result["vpu_util"] = 0

        return result
