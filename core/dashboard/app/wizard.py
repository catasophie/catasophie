"""First-boot setup wizard: hardware detection + writing initial config."""
from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

import psutil

from .env import get_env, write_env

REPO_ROOT = Path(os.environ.get("CATASOPHIE_ROOT", "/app"))
USERS_DB_PATH = REPO_ROOT / "core" / "auth" / "users_database.yml"


def is_setup_complete() -> bool:
    return get_env("SETUP_COMPLETE", "false") == "true"


def detect_hardware_profile() -> str:
    """Best-effort guess: pi | mini-pc | laptop."""
    model_path = Path("/proc/device-tree/model")
    if model_path.exists():
        try:
            model = model_path.read_text(errors="ignore").lower()
            if "raspberry pi" in model:
                return "pi"
        except OSError:
            pass

    if psutil.sensors_battery() is not None:
        return "laptop"

    return "mini-pc"


def suggest_llm_model(hardware_profile: str) -> str:
    ram_gb = psutil.virtual_memory().total / 1e9
    if hardware_profile == "pi" or ram_gb < 6:
        return "llama3.2:1b"
    if ram_gb < 12:
        return "llama3.2:3b"
    return "llama3.1:8b"


def _generate_admin_hash(password: str) -> str | None:
    """Shells out to the authelia image to generate an argon2id hash.

    Requires the podman socket to be reachable from inside the dashboard
    container (it is, per core/dashboard/docker-compose.yml). Returns None
    if generation fails (e.g. offline and image not yet pulled) so the
    caller can fall back to instructing the user to run the script manually.
    """
    try:
        result = subprocess.run(
            [
                "podman", "run", "--rm", "authelia/authelia:latest",
                "authelia", "crypto", "hash", "generate", "argon2",
                "--password", password,
            ],
            capture_output=True, text=True, timeout=60,
        )
    except (subprocess.TimeoutExpired, OSError):
        return None
    if result.returncode != 0:
        return None
    match = re.search(r"Digest:\s*(\S+)", result.stdout)
    return match.group(1) if match else None


def _write_admin_password(username: str, password_hash: str) -> bool:
    if not USERS_DB_PATH.exists():
        return False
    text = USERS_DB_PATH.read_text()
    pattern = re.compile(
        rf'(^\s*{re.escape(username)}:\n(?:^\s+.*\n)*?^\s+password:\s*).*$',
        re.MULTILINE,
    )
    new_text, count = pattern.subn(lambda m: m.group(1) + f'"{password_hash}"', text)
    if count == 0:
        return False
    USERS_DB_PATH.write_text(new_text)
    return True


def complete_setup(
    *,
    admin_password: str,
    wifi_ap_enabled: bool,
    wifi_ssid: str,
    wifi_password: str,
    wifi_country_code: str,
    map_region: str,
    hardware_profile: str,
    power_backend: str,
) -> dict:
    """Persist all first-boot wizard choices. Returns a dict of warnings."""
    warnings: list[str] = []

    write_env({
        "SETUP_COMPLETE": "true",
        "HARDWARE_PROFILE": hardware_profile,
        "POWER_BACKEND": power_backend,
        "MAP_REGION": map_region,
        "WIFI_AP_ENABLED": "true" if wifi_ap_enabled else "false",
        "WIFI_AP_SSID": wifi_ssid,
        "WIFI_AP_PASSWORD": wifi_password,
        "WIFI_AP_COUNTRY_CODE": wifi_country_code,
    })

    password_hash = _generate_admin_hash(admin_password)
    if password_hash and _write_admin_password("admin", password_hash):
        pass
    else:
        warnings.append(
            "Could not automatically set the admin password (Podman socket "
            "unavailable or image not pulled). Run "
            "./scripts/generate-admin-password.sh manually to set it."
        )

    return {"warnings": warnings}
