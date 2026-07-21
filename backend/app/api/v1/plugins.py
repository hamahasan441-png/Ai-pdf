"""Plugin catalogue endpoint (Part 5.4).

Exposes the declarative tool / AI-action registry so the client can render the
tool catalogue dynamically and gate features by entitlement in one place. This
endpoint is metadata-only and read-only — it never executes a tool.
"""

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel

from app.services.plugins.registry import Entitlement, PluginKind, registry

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


class PluginListResponse(BaseModel):
    count: int
    categories: list[str]
    plugins: list[PluginModel]


@router.get("/plugins", response_model=PluginListResponse, tags=["Plugins"])
async def list_plugins(
    kind: PluginKind | None = Query(default=None, description="Filter by plugin kind"),
    category: str | None = Query(default=None, description="Filter by category"),
    entitlement: Entitlement | None = Query(
        default=None,
        description="free = only free plugins; pro = everything a Pro user sees",
    ),
):
    """List registered plugins, optionally filtered by kind/category/entitlement."""
    plugins = registry.filter(kind=kind, category=category, entitlement=entitlement)
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
