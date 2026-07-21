"""Plugin architecture package (Part 5.4).

A declarative registry of tools and AI actions so new capabilities can be added
without editing core screens or routers. See :mod:`app.services.plugins.registry`.
"""

from app.services.plugins.registry import (
    Entitlement,
    PluginKind,
    PluginRegistry,
    ToolPlugin,
    registry,
)

__all__ = [
    "Entitlement",
    "PluginKind",
    "PluginRegistry",
    "ToolPlugin",
    "registry",
]
