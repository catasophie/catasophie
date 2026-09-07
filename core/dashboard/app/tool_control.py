"""Start/stop/status control for tools via `podman-compose`.

The dashboard container has the host's podman API socket and podman CLI
mounted in, so it can drive `podman-compose` against the tool's compose
file directly (compose files reference the shared external `catasophie`
network).
"""
from __future__ import annotations

import os
import subprocess

from .manifests import ToolManifest

REPO_ROOT = os.environ.get("CATASOPHIE_ROOT", "/workspace")


def _compose_file(tool: ToolManifest) -> str:
    return os.path.join(REPO_ROOT, "tools", tool.id, "docker-compose.yml")


def _run(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(args, capture_output=True, text=True, timeout=60)


def tool_status(tool: ToolManifest) -> str:
    """Returns 'running', 'stopped', or 'unknown'."""
    result = _run([
        "podman-compose", "-f", _compose_file(tool), "ps", "--status", "running", "-q",
    ])
    if result.returncode != 0:
        return "unknown"
    return "running" if result.stdout.strip() else "stopped"


def start_tool(tool: ToolManifest) -> tuple[bool, str]:
    result = _run(["podman-compose", "-f", _compose_file(tool), "up", "-d"])
    return result.returncode == 0, (result.stdout + result.stderr).strip()


def stop_tool(tool: ToolManifest) -> tuple[bool, str]:
    result = _run(["podman-compose", "-f", _compose_file(tool), "stop"])
    return result.returncode == 0, (result.stdout + result.stderr).strip()
