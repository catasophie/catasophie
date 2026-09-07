"""System health: disk, RAM, CPU, temperature."""
from __future__ import annotations

from dataclasses import dataclass

import psutil


@dataclass
class SystemHealth:
    cpu_percent: float
    ram_percent: float
    ram_used_gb: float
    ram_total_gb: float
    disk_percent: float
    disk_used_gb: float
    disk_total_gb: float
    cpu_temp_c: float | None
    warnings: list[str]


def _read_cpu_temp() -> float | None:
    """Best-effort CPU temperature reading (Raspberry Pi / most Linux boards)."""
    try:
        temps = psutil.sensors_temperatures()
    except (AttributeError, NotImplementedError):
        return None
    for label in ("cpu_thermal", "coretemp", "cpu-thermal", "soc_thermal"):
        entries = temps.get(label)
        if entries:
            return round(entries[0].current, 1)
    for entries in temps.values():
        if entries:
            return round(entries[0].current, 1)
    return None


def get_system_health(
    disk_path: str = "/",
    disk_warn_pct: float = 90.0,
    ram_warn_pct: float = 90.0,
    temp_warn_c: float = 80.0,
) -> SystemHealth:
    cpu = psutil.cpu_percent(interval=0.2)
    vm = psutil.virtual_memory()
    disk = psutil.disk_usage(disk_path)
    temp = _read_cpu_temp()

    warnings: list[str] = []
    if disk.percent >= disk_warn_pct:
        warnings.append(f"Disk usage high: {disk.percent:.0f}%")
    if vm.percent >= ram_warn_pct:
        warnings.append(f"RAM usage high: {vm.percent:.0f}%")
    if temp is not None and temp >= temp_warn_c:
        warnings.append(f"CPU temperature high: {temp:.0f}\u00b0C")

    return SystemHealth(
        cpu_percent=cpu,
        ram_percent=vm.percent,
        ram_used_gb=round(vm.used / 1e9, 1),
        ram_total_gb=round(vm.total / 1e9, 1),
        disk_percent=disk.percent,
        disk_used_gb=round(disk.used / 1e9, 1),
        disk_total_gb=round(disk.total / 1e9, 1),
        cpu_temp_c=temp,
        warnings=warnings,
    )
