"""Plugin catalogue endpoint (Part 5.4 + E7.3 remote).

Exposes the declarative tool / AI-action registry so the client can render the
tool catalogue dynamically and gate features by entitlement in one place. This
endpoint is metadata-only and read-only — it never executes a tool.

E7.3 — Remote plugins: supports remote manifests fetched via httpx, with
source=local|remote, manifest_url, execution_type=local|server, enabled flag
via admin token.
"""

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from app.api.v1.admin import require_admin_token
from app.services.plugins.registry import Entitlement, ExecutionType, PluginKind, PluginSource, ToolPlugin, registry

router = APIRouter()


class PluginModel(BaseModel):
    id: str
    name: str
    description: str
    kind: str
    category: str
    icon: str
    route: str
    entitlement: str
    enabled: bool
    tags: list[str]
    source: str = "local"
    manifest_url: str | None = None
    execution_type: str = "server"


class PluginListResponse(BaseModel):
    count: int
    categories: list[str]
    plugins: list[PluginModel]


class RemotePluginRequest(BaseModel):
    manifest_url: str = Field(..., description="URL to remote plugin manifest JSON")
    enabled: bool = Field(True, description="Whether to enable after fetching")


@router.get("/plugins", response_model=PluginListResponse, tags=["Plugins"])
async def list_plugins(
    kind: PluginKind | None = Query(default=None, description="Filter by plugin kind"),
    category: str | None = Query(default=None, description="Filter by category"),
    entitlement: Entitlement | None = Query(
        default=None,
        description="free = only free plugins; pro = everything a Pro user sees",
    ),
    source: PluginSource | None = Query(default=None, description="Filter by source local|remote"),
):
    """List registered plugins, optionally filtered by kind/category/entitlement/source."""
    plugins = registry.filter(kind=kind, category=category, entitlement=entitlement, source=source)
    return PluginListResponse(
        count=len(plugins),
        categories=registry.categories(),
        plugins=[PluginModel(**p.to_dict()) for p in plugins],
    )


@router.get("/plugins/{plugin_id}", response_model=PluginModel, tags=["Plugins"])
async def get_plugin(plugin_id: str):
    """Return a single plugin descriptor by id."""
    plugin = registry.get(plugin_id)
    if plugin is None or not plugin.enabled:
        raise HTTPException(status_code=404, detail="Plugin not found")
    return PluginModel(**plugin.to_dict())


@router.post("/admin/plugins/remote", response_model=PluginModel, tags=["Admin"], dependencies=[Depends(require_admin_token)])
async def add_remote_plugin(request: RemotePluginRequest):
    """Add a remote plugin by fetching its manifest JSON (E7.3).

    Manifest format (JSON):
    {
      "id": "my-remote-tool",
      "name": "My Remote Tool",
      "description": "Does something",
      "kind": "tool",
      "category": "convert",
      "icon": "extension",
      "route": "/api/v1/convert/pdf-to-word",
      "entitlement": "free",
      "enabled": true,
      "tags": ["remote"],
      "execution_type": "server"
    }

    The manifest is fetched via httpx, validated, and registered via register_or_update().
    Enabled flag controls whether it appears in default list.

    Gated by ADMIN_API_TOKEN via X-Admin-Token header.
    """
    import httpx

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get(request.manifest_url)
            resp.raise_for_status()
            manifest = resp.json()
    except Exception as e:
        raise HTTPException(status_code=422, detail=f"Failed to fetch manifest from {request.manifest_url}: {e}")

    try:
        plugin_id = manifest["id"]
        name = manifest["name"]
        description = manifest.get("description", "")
        kind = PluginKind(manifest.get("kind", "tool"))
        category = manifest.get("category", "general")
        icon = manifest.get("icon", "extension")
        route = manifest.get("route", "")
        entitlement = Entitlement(manifest.get("entitlement", "free"))
        enabled = manifest.get("enabled", True) and request.enabled
        tags = tuple(manifest.get("tags", []))
        execution_type = ExecutionType(manifest.get("execution_type", "server"))
    except Exception as e:
        raise HTTPException(status_code=422, detail=f"Invalid manifest format: {e}")

    plugin = ToolPlugin(
        id=plugin_id,
        name=name,
        description=description,
        kind=kind,
        category=category,
        icon=icon,
        route=route,
        entitlement=entitlement,
        enabled=enabled,
        tags=tags,
        source=PluginSource.REMOTE,
        manifest_url=request.manifest_url,
        execution_type=execution_type,
    )

    registry.register_or_update(plugin)

    return PluginModel(**plugin.to_dict())


@router.delete("/admin/plugins/{plugin_id}", tags=["Admin"], dependencies=[Depends(require_admin_token)])
async def delete_remote_plugin(plugin_id: str):
    """Delete a remote plugin (or disable it) — admin only."""
    plugin = registry.get(plugin_id)
    if not plugin:
        raise HTTPException(status_code=404, detail="Plugin not found")
    if plugin.source != PluginSource.REMOTE:
        raise HTTPException(status_code=400, detail="Only remote plugins can be deleted via this endpoint; disable local via flag")

    disabled = ToolPlugin(
        id=plugin.id,
        name=plugin.name,
        description=plugin.description,
        kind=plugin.kind,
        category=plugin.category,
        icon=plugin.icon,
        route=plugin.route,
        entitlement=plugin.entitlement,
        enabled=False,
        tags=plugin.tags,
        source=plugin.source,
        manifest_url=plugin.manifest_url,
        execution_type=plugin.execution_type,
    )
    registry.register_or_update(disabled)

    return {"deleted": True, "id": plugin_id, "note": "Remote plugin disabled (soft-delete)"}
