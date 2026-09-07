"""catasophie dashboard - FastAPI + HTMX."""
from __future__ import annotations

from pathlib import Path

import httpx
from fastapi import FastAPI, Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from . import tool_control, wizard
from .manifests import discover_tools, get_tool
from .power_monitor import get_power_status
from .system_health import get_system_health

APP_DIR = Path(__file__).parent
templates = Jinja2Templates(directory=str(APP_DIR / "templates"))

app = FastAPI(title="catasophie dashboard")

static_dir = APP_DIR / "static"
static_dir.mkdir(exist_ok=True)
app.mount("/static", StaticFiles(directory=str(static_dir)), name="static")


def current_user_role(request: Request) -> str:
    """Reads the group Authelia forwarded via forward_auth headers.

    Caddy's forward_auth is configured to copy `Remote-Groups` through.
    Defaults to "user" if missing (e.g. local dev without auth in front).
    """
    groups = request.headers.get("Remote-Groups", "")
    return "admin" if "admin" in groups.split(",") else "user"


@app.middleware("http")
async def setup_redirect(request: Request, call_next):
    # Force first-boot wizard before anything else is usable, except the
    # wizard routes themselves and static assets.
    path = request.url.path
    if not wizard.is_setup_complete() and not (
        path.startswith("/setup") or path.startswith("/static")
    ):
        return RedirectResponse(url="/setup")
    return await call_next(request)


# ---------------------------------------------------------------------------
# First-boot setup wizard
# ---------------------------------------------------------------------------

@app.get("/setup", response_class=HTMLResponse)
async def setup_page(request: Request):
    if wizard.is_setup_complete():
        return RedirectResponse(url="/")
    profile = wizard.detect_hardware_profile()
    return templates.TemplateResponse(request, "setup.html", {
        "detected_profile": profile,
        "suggested_model": wizard.suggest_llm_model(profile),
    })


@app.post("/setup", response_class=HTMLResponse)
async def setup_submit(
    request: Request,
    admin_password: str = Form(...),
    hardware_profile: str = Form(...),
    power_backend: str = Form("auto"),
    wifi_ap_enabled: bool = Form(False),
    wifi_ssid: str = Form("catasophie"),
    wifi_password: str = Form(""),
    wifi_country_code: str = Form("US"),
    map_region: str = Form(""),
):
    result = wizard.complete_setup(
        admin_password=admin_password,
        wifi_ap_enabled=wifi_ap_enabled,
        wifi_ssid=wifi_ssid,
        wifi_password=wifi_password,
        wifi_country_code=wifi_country_code,
        map_region=map_region,
        hardware_profile=hardware_profile,
        power_backend=power_backend,
    )
    return templates.TemplateResponse(request, "setup_complete.html", {
        "warnings": result["warnings"],
    })


# ---------------------------------------------------------------------------
# Main dashboard
# ---------------------------------------------------------------------------

def _tools_with_status(role: str) -> list[dict]:
    result = []
    for tool in discover_tools():
        result.append({
            "tool": tool,
            "status": tool_control.tool_status(tool) if tool.valid else "invalid",
            "can_access": tool.required_role != "admin" or role == "admin",
        })
    return result


@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    role = current_user_role(request)
    return templates.TemplateResponse(request, "index.html", {
        "tools": _tools_with_status(role),
        "role": role,
        "health": get_system_health(),
        "power": get_power_status(),
    })


@app.get("/fragments/system-health", response_class=HTMLResponse)
async def fragment_system_health(request: Request):
    return templates.TemplateResponse(request, "_system_health.html", {
        "health": get_system_health(),
        "power": get_power_status(),
    })


@app.get("/fragments/tools", response_class=HTMLResponse)
async def fragment_tools(request: Request):
    role = current_user_role(request)
    return templates.TemplateResponse(request, "_tool_list.html", {
        "tools": _tools_with_status(role), "role": role,
    })


@app.post("/tools/{tool_id}/start", response_class=HTMLResponse)
async def tool_start(request: Request, tool_id: str):
    tool = get_tool(tool_id)
    status_msg = "not found"
    if tool:
        ok, status_msg = tool_control.start_tool(tool)
    return templates.TemplateResponse(request, "_tool_action_result.html", {
        "tool": tool, "message": status_msg,
    })


@app.post("/tools/{tool_id}/stop", response_class=HTMLResponse)
async def tool_stop(request: Request, tool_id: str):
    tool = get_tool(tool_id)
    status_msg = "not found"
    if tool:
        ok, status_msg = tool_control.stop_tool(tool)
    return templates.TemplateResponse(request, "_tool_action_result.html", {
        "tool": tool, "message": status_msg,
    })


# ---------------------------------------------------------------------------
# Dynamic tool reverse-proxy (with lazy-start)
# ---------------------------------------------------------------------------

@app.api_route("/tools/{tool_id}/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "PATCH"])
async def proxy_to_tool(request: Request, tool_id: str, path: str):
    tool = get_tool(tool_id)
    if tool is None:
        return HTMLResponse(f"Unknown tool '{tool_id}'", status_code=404)

    role = current_user_role(request)
    if tool.required_role == "admin" and role != "admin":
        return HTMLResponse("Forbidden: admin role required for this tool", status_code=403)

    if tool_control.tool_status(tool) != "running":
        started, _ = tool_control.start_tool(tool)
        if not started:
            return HTMLResponse(f"Failed to start tool '{tool_id}'", status_code=502)

    upstream_url = f"http://{tool.id}:{tool.port}/{path}"
    client = httpx.AsyncClient()
    req = client.build_request(
        request.method, upstream_url,
        headers=dict(request.headers),
        content=await request.body(),
    )
    upstream_resp = await client.send(req, stream=True)
    return StreamingResponse(
        upstream_resp.aiter_raw(),
        status_code=upstream_resp.status_code,
        headers=dict(upstream_resp.headers),
        background=upstream_resp.aclose,
    )
