#!/usr/bin/env python3
"""Capture CPU/memory evaluation context without hostnames or network identifiers."""
import argparse
import datetime
import json
import os
from pathlib import Path
import platform
import re
import subprocess

CPU_FIELDS = {"Architecture", "CPU op-mode(s)", "Address sizes", "Byte Order", "CPU(s)", "On-line CPU(s) list",
    "Vendor ID", "Model name", "CPU family", "Model", "Thread(s) per core", "Core(s) per socket", "Socket(s)",
    "Stepping", "CPU max MHz", "CPU min MHz", "Virtualization", "Hypervisor vendor", "Virtualization type",
    "L1d cache", "L1i cache", "L2 cache", "L3 cache", "NUMA node(s)"}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists():
        parser.error("Refusing to overwrite an existing host snapshot.")
    result = {"formatVersion": 1, "captureScope": "host environment where this helper runs", "capturedUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "platform": platform.platform(), "processor": platform.processor(), "logicalProcessors": os.cpu_count(),
        "cpu": {}, "memoryBytes": {}, "limits": {}, "loadAverage": list(os.getloadavg()) if hasattr(os, "getloadavg") else None}
    if hasattr(os, "sched_getaffinity"):
        result["allowedCPUs"] = sorted(os.sched_getaffinity(0))
    try:
        data = json.loads(subprocess.check_output(["lscpu", "--json"], text=True, env={**os.environ, "LC_ALL": "C"}))
        def read(items):
            for item in items:
                name = item.get("field", "").rstrip(":")
                if name in CPU_FIELDS or re.fullmatch(r"NUMA node\d+ CPU\(s\)", name):
                    result["cpu"][name] = item.get("data")
                read(item.get("children", []))
        read(data["lscpu"])
    except (OSError, ValueError, subprocess.CalledProcessError):
        result["cpuCaptureUnavailable"] = True
    memory = Path("/proc/meminfo")
    if memory.is_file():
        for line in memory.read_text().splitlines():
            name, _, value = line.partition(":")
            if name in {"MemTotal", "MemAvailable", "SwapTotal", "SwapFree"}:
                result["memoryBytes"][name] = int(value.strip().split()[0]) * 1024
    for name in ["cpu.max", "cpuset.cpus.effective", "memory.max", "memory.high"]:
        path = Path("/sys/fs/cgroup") / name
        if path.is_file():
            result["limits"][name] = path.read_text().strip()
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("x", encoding="utf-8", newline="\n") as destination:
        json.dump(result, destination, indent=2)
        destination.write("\n")
    print(output)

if __name__ == "__main__":
    main()
