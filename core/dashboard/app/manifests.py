"""Discover and validate tool manifests under tools/*/manifest.json."""
from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from pathlib import Path

TOOLS_DIR = Path(os.environ.get("TOOLS_DIR", "/app/tools"))

REQUIRED_FIELDS = {
    "id", "name", "description", "icon", "category", "url_path",
    "port", "health_check", "autostart", "required_role", "version",
}
VALID_ROLES = {"user", "admin"}
VALID_CATEGORIES = {"information", "communication", "system"}


@dataclass
class ToolManifest:
    id: str
    name: str
    description: str
    icon: str
    category: str
    url_path: str
    port: int
    health_check: str
    autostart: bool
    required_role: str
    version: str
    requires_host_device: list[str] = field(default_factory=list)
    path: Path | None = None
    errors: list[str] = field(default_factory=list)

    @property
    def valid(self) -> bool:
        return not self.errors


def _validate(data: dict, folder_name: str) -> list[str]:
    errors = []
    missing = REQUIRED_FIELDS - data.keys()
    if missing:
        errors.append(f"missing fields: {', '.join(sorted(missing))}")
    if data.get("id") and data.get("id") != folder_name:
        errors.append(f"id '{data.get('id')}' does not match folder name '{folder_name}'")
    if data.get("required_role") not in VALID_ROLES:
        errors.append(f"required_role must be one of {VALID_ROLES}")
    if data.get("category") not in VALID_CATEGORIES:
        errors.append(f"category must be one of {VALID_CATEGORIES}")
    return errors


def discover_tools(skip_hidden: bool = True) -> list[ToolManifest]:
    """Scan TOOLS_DIR for tool folders and parse+validate their manifests."""
    tools: list[ToolManifest] = []
    if not TOOLS_DIR.exists():
        return tools

    for folder in sorted(TOOLS_DIR.iterdir()):
        if not folder.is_dir():
            continue
        if skip_hidden and folder.name.startswith("_"):
            continue
        manifest_path = folder / "manifest.json"
        if not manifest_path.exists():
            continue

        errors: list[str] = []
        data: dict = {}
        try:
            data = json.loads(manifest_path.read_text())
        except json.JSONDecodeError as exc:
            errors.append(f"invalid JSON: {exc}")

        if data:
            errors.extend(_validate(data, folder.name))

        tools.append(
            ToolManifest(
                id=data.get("id", folder.name),
                name=data.get("name", folder.name),
                description=data.get("description", ""),
                icon=data.get("icon", "puzzle"),
                category=data.get("category", "information"),
                url_path=data.get("url_path", f"/tools/{folder.name}/"),
                port=data.get("port", 0),
                health_check=data.get("health_check", "/health"),
                autostart=bool(data.get("autostart", False)),
                required_role=data.get("required_role", "user"),
                version=data.get("version", "0.0.0"),
                requires_host_device=data.get("requires_host_device", []),
                path=folder,
                errors=errors,
            )
        )
    return tools


def get_tool(tool_id: str) -> ToolManifest | None:
    for tool in discover_tools():
        if tool.id == tool_id:
            return tool
    return None
