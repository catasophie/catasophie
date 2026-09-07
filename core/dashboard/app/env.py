"""Environment / .env loading utilities."""
from __future__ import annotations

import os
from pathlib import Path

ENV_PATH = Path(os.environ.get("CATASOPHIE_ENV_FILE", "/app/.env"))


def load_env() -> dict[str, str]:
    """Parse the .env file into a dict without mutating os.environ.

    Falls back to an empty dict if the file doesn't exist yet (pre first-boot).
    """
    values: dict[str, str] = {}
    if not ENV_PATH.exists():
        return values
    for line in ENV_PATH.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        values[key.strip()] = value.strip()
    return values


def get_env(key: str, default: str | None = None) -> str | None:
    # os.environ takes precedence (e.g. set directly in compose), then .env file
    if key in os.environ:
        return os.environ[key]
    return load_env().get(key, default)


def write_env(updates: dict[str, str]) -> None:
    """Merge `updates` into the .env file, preserving existing keys/order/comments."""
    lines: list[str] = []
    seen: set[str] = set()

    if ENV_PATH.exists():
        for line in ENV_PATH.read_text().splitlines():
            stripped = line.strip()
            if stripped and not stripped.startswith("#") and "=" in stripped:
                key = stripped.split("=", 1)[0].strip()
                if key in updates:
                    lines.append(f"{key}={updates[key]}")
                    seen.add(key)
                    continue
            lines.append(line)
    for key, value in updates.items():
        if key not in seen:
            lines.append(f"{key}={value}")

    ENV_PATH.parent.mkdir(parents=True, exist_ok=True)
    ENV_PATH.write_text("\n".join(lines) + "\n")
