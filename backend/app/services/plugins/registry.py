"""Declarative plugin registry for tools and AI actions (Part 5.4).

Motivation
----------
Tools (PDF operations) and AI actions (summarize / translate / extract / …) were
previously discoverable only by reading the router and the Flutter screens. That
couples every new capability to core code and makes it impossible for the client
to render the tool catalogue dynamically or to gate features by entitlement in
one place.

This registry lets each capability describe itself once — id, name, description,
category, icon, the API route that runs it, the minimum entitlement, and whether
it is enabled — and be looked up by the client through ``/api/v1/plugins``. New
tools register with :meth:`PluginRegistry.register` (or the module-level
:data:`registry`) without touching consumers.

The registry is intentionally metadata-only. It does NOT execute anything; the
actual work still lives in the existing endpoints. This keeps the change purely
additive and backward compatible.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from enum import Enum


class PluginKind(str, Enum):
    """What broad family a plugin belongs to."""

    TOOL = "tool"          # on-device / server PDF operation
    AI_ACTION = "ai_action"  # managed-AI powered capability


class Entitlement(str, Enum):
    """Minimum access level required to use a plugin."""

    FREE = "free"
    PRO = "pro"


@dataclass(frozen=True)
class ToolPlugin:
    """Immutable descriptor for a single tool or AI action.

    Attributes:
        id: Stable machine identifier (kebab-case), unique within the registry.
        name: Human-friendly display name.
        description: One-line summary for the catalogue.
        kind: ``tool`` or ``ai_action``.
        category: Grouping label (e.g. "organize", "convert", "intelligence").
        icon: Icon hint the client maps to its own icon set.
        route: API path that performs the action (or "" for on-device tools).
        entitlement: Minimum entitlement required (free / pro).
        enabled: Feature flag; disabled plugins are hidden from the default list.
        tags: Free-form keywords for search/filtering.
    """

    id: str
    name: str
    description: str
    kind: PluginKind
    category: str
    icon: str = "extension"
    route: str = ""
    entitlement: Entitlement = Entitlement.FREE
    enabled: bool = True
    tags: tuple[str, ...] = field(default_factory=tuple)

    def to_dict(self) -> dict:
        """JSON-serialisable representation (enums flattened to their values)."""
        data = asdict(self)
        data["kind"] = self.kind.value
        data["entitlement"] = self.entitlement.value
        data["tags"] = list(self.tags)
        return data


class PluginRegistry:
    """In-process registry of :class:`ToolPlugin` descriptors."""

    def __init__(self) -> None:
        self._plugins: dict[str, ToolPlugin] = {}

    def register(self, plugin: ToolPlugin) -> ToolPlugin:
        """Register a plugin. Raises ValueError on a duplicate id."""
        if plugin.id in self._plugins:
            raise ValueError(f"Duplicate plugin id: {plugin.id!r}")
        self._plugins[plugin.id] = plugin
        return plugin

    def get(self, plugin_id: str) -> ToolPlugin | None:
        """Return a plugin by id, or None if unknown."""
        return self._plugins.get(plugin_id)

    def all(self, *, include_disabled: bool = False) -> list[ToolPlugin]:
        """All registered plugins, sorted by category then name."""
        items = self._plugins.values()
        if not include_disabled:
            items = [p for p in items if p.enabled]
        return sorted(items, key=lambda p: (p.category, p.name))

    def filter(
        self,
        *,
        kind: PluginKind | None = None,
        category: str | None = None,
        entitlement: Entitlement | None = None,
        include_disabled: bool = False,
    ) -> list[ToolPlugin]:
        """Filtered view of the registry.

        ``entitlement=FREE`` returns only free plugins; ``entitlement=PRO``
        returns everything a Pro user can see (free + pro).
        """
        result = []
        for plugin in self.all(include_disabled=include_disabled):
            if kind is not None and plugin.kind != kind:
                continue
            if category is not None and plugin.category != category:
                continue
            if entitlement is Entitlement.FREE and plugin.entitlement is not Entitlement.FREE:
                continue
            result.append(plugin)
        return result

    def categories(self) -> list[str]:
        """Distinct categories present among enabled plugins."""
        return sorted({p.category for p in self.all()})

    def clear(self) -> None:
        """Remove all plugins (used by tests)."""
        self._plugins.clear()


# Module-level singleton the app and tests share.
registry = PluginRegistry()


def register_builtin_plugins(reg: PluginRegistry) -> None:
    """Register the built-in tool + AI-action catalogue on ``reg``.

    Kept as a function (rather than import-time side effects) so tests can build
    a clean registry deterministically. Routes point at the real endpoints that
    already exist in this backend.
    """
    builtins: list[ToolPlugin] = [
        # --- On-device / server tools -----------------------------------
        ToolPlugin(
            id="convert-pdf-to-word",
            name="PDF to Word",
            description="Convert a PDF into an editable Word (.docx) document.",
            kind=PluginKind.TOOL,
            category="convert",
            icon="description",
            route="/api/v1/convert/pdf-to-word",
            entitlement=Entitlement.PRO,
            tags=("convert", "docx", "office"),
        ),
        ToolPlugin(
            id="convert-pdf-to-excel",
            name="PDF to Excel",
            description="Extract tables from a PDF into an Excel (.xlsx) workbook.",
            kind=PluginKind.TOOL,
            category="convert",
            icon="table_chart",
            route="/api/v1/convert/pdf-to-excel",
            entitlement=Entitlement.PRO,
            tags=("convert", "xlsx", "office"),
        ),
        ToolPlugin(
            id="convert-pdf-to-ppt",
            name="PDF to PowerPoint",
            description="Turn PDF pages into a PowerPoint (.pptx) deck.",
            kind=PluginKind.TOOL,
            category="convert",
            icon="slideshow",
            route="/api/v1/convert/pdf-to-ppt",
            entitlement=Entitlement.PRO,
            tags=("convert", "pptx", "office"),
        ),
        ToolPlugin(
            id="forms-fill",
            name="Fill Form",
            description="Detect and fill AcroForm fields from a saved profile.",
            kind=PluginKind.TOOL,
            category="forms",
            icon="edit_document",
            route="/api/v1/forms/fill",
            entitlement=Entitlement.FREE,
            tags=("forms", "acroform", "autofill"),
        ),
        # --- AI actions --------------------------------------------------
        ToolPlugin(
            id="ai-chat",
            name="Chat with Document",
            description="Ask questions about a document with grounded citations.",
            kind=PluginKind.AI_ACTION,
            category="intelligence",
            icon="chat",
            route="/api/v1/ai/chat",
            entitlement=Entitlement.FREE,
            tags=("ai", "chat", "rag"),
        ),
        ToolPlugin(
            id="ai-summarize",
            name="Summarize",
            description="Produce a concise summary of a long document.",
            kind=PluginKind.AI_ACTION,
            category="intelligence",
            icon="summarize",
            route="/api/v1/document-ai/summarize",
            entitlement=Entitlement.FREE,
            tags=("ai", "summary"),
        ),
        ToolPlugin(
            id="ai-translate",
            name="Translate",
            description="Translate document text into another language.",
            kind=PluginKind.AI_ACTION,
            category="intelligence",
            icon="translate",
            route="/api/v1/document-ai/translate",
            entitlement=Entitlement.PRO,
            tags=("ai", "translate", "i18n"),
        ),
        ToolPlugin(
            id="ai-extract",
            name="Extract Data",
            description="Extract structured data (JSON / table) from a document.",
            kind=PluginKind.AI_ACTION,
            category="intelligence",
            icon="data_object",
            route="/api/v1/document-ai/extract",
            entitlement=Entitlement.PRO,
            tags=("ai", "extract", "structured"),
        ),
        ToolPlugin(
            id="ai-outline",
            name="Document Outline",
            description="Generate a navigable outline / table of contents.",
            kind=PluginKind.AI_ACTION,
            category="intelligence",
            icon="toc",
            route="/api/v1/document-outline",
            entitlement=Entitlement.FREE,
            tags=("ai", "outline", "toc"),
        ),
    ]
    for plugin in builtins:
        reg.register(plugin)


# Populate the shared registry at import time with the built-in catalogue.
register_builtin_plugins(registry)
