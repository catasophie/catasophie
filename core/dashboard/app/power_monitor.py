"""Power monitor: pluggable backends per hardware profile.

Backends:
  - laptop  : reads the OS battery via psutil (works out of the box, no extra
              hardware - covers the "runs on a laptop" case).
  - pi-i2c  : reads a fuel-gauge/UPS HAT over I2C (e.g. PiJuice, Geekworm UPS).
              Stubbed for now - requires the specific HAT's I2C register map.
  - nut     : reads a UPS via Network UPS Tools (upsc CLI/NUT protocol).
              Stubbed for now - requires a NUT server configured for the UPS.
  - none    : no power source detected / not applicable.

`detect_backend()` picks the best available backend automatically; this can
be overridden via the POWER_BACKEND env var (auto|laptop|pi-i2c|nut|none).
"""
from __future__ import annotations

import shutil
import subprocess
from dataclasses import dataclass
from typing import Literal

import psutil

from .env import get_env

BackendName = Literal["laptop", "pi-i2c", "nut", "none"]


@dataclass
class PowerStatus:
    backend: BackendName
    available: bool
    percent: float | None = None
    charging: bool | None = None
    on_mains: bool | None = None
    time_remaining_min: int | None = None
    detail: str = ""


def _laptop_status() -> PowerStatus:
    battery = psutil.sensors_battery()
    if battery is None:
        return PowerStatus(backend="laptop", available=False, detail="No battery detected by OS")

    secs = battery.secsleft
    minutes = None
    if isinstance(secs, (int, float)) and secs not in (
        psutil.POWER_TIME_UNLIMITED,
        psutil.POWER_TIME_UNKNOWN,
    ):
        minutes = int(secs / 60)

    return PowerStatus(
        backend="laptop",
        available=True,
        percent=round(battery.percent, 1),
        charging=bool(battery.power_plugged),
        on_mains=bool(battery.power_plugged),
        time_remaining_min=minutes,
        detail="OS battery (psutil)",
    )


def _pi_i2c_status() -> PowerStatus:
    # Stub: no fuel-gauge HAT integration implemented yet. This is where
    # a specific HAT's I2C register-read logic would go (e.g. via smbus2),
    # keyed off a HAT model env var. Returns "not available" until wired up.
    return PowerStatus(
        backend="pi-i2c",
        available=False,
        detail="No I2C fuel-gauge HAT driver configured yet (see docs/HARDWARE.md)",
    )


def _nut_status() -> PowerStatus:
    """Read a UPS via NUT's `upsc` CLI, if present and reachable."""
    ups_name = get_env("NUT_UPS_NAME")
    host = get_env("NUT_HOST", "localhost")
    port = get_env("NUT_PORT", "3493")

    if not ups_name:
        return PowerStatus(backend="nut", available=False, detail="NUT_UPS_NAME not configured")

    if shutil.which("upsc") is None:
        return PowerStatus(backend="nut", available=False, detail="NUT client (upsc) not installed")

    try:
        result = subprocess.run(
            ["upsc", f"{ups_name}@{host}:{port}"],
            capture_output=True, text=True, timeout=5,
        )
    except (subprocess.TimeoutExpired, OSError) as exc:
        return PowerStatus(backend="nut", available=False, detail=f"upsc failed: {exc}")

    if result.returncode != 0:
        return PowerStatus(backend="nut", available=False, detail=result.stderr.strip() or "upsc error")

    fields = dict(
        line.split(": ", 1) for line in result.stdout.splitlines() if ": " in line
    )
    percent = fields.get("battery.charge")
    status = fields.get("ups.status", "")

    return PowerStatus(
        backend="nut",
        available=True,
        percent=float(percent) if percent else None,
        charging="CHRG" in status,
        on_mains="OL" in status,  # "OL" = on line (mains), "OB" = on battery
        detail=f"NUT UPS '{ups_name}'",
    )


def detect_backend() -> BackendName:
    override = get_env("POWER_BACKEND", "auto")
    if override and override != "auto":
        return override  # type: ignore[return-value]

    if psutil.sensors_battery() is not None:
        return "laptop"
    if get_env("NUT_UPS_NAME"):
        return "nut"
    return "none"


def get_power_status() -> PowerStatus:
    backend = detect_backend()
    if backend == "laptop":
        return _laptop_status()
    if backend == "pi-i2c":
        return _pi_i2c_status()
    if backend == "nut":
        return _nut_status()
    return PowerStatus(backend="none", available=False, detail="No power backend detected/configured")
