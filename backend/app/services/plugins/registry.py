"""Declarative plugin registry for tools and AI actions (Part 5.4 + E7.3 remote).

E7.3 — Remote plugins: supports remote manifests fetched via httpx, with
source=local|remote, manifest_url, execution_type=local|server, enabled flag
via admin token. For server execution, client calls existing endpoints via route.
For remote, backend fetches manifest, validates signature (future), caches.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from enum import Enum
from typing import Optional


class PluginKind(str, Enum):
    TOOL = "tool"
    AI_ACTION = "ai_action"


class Entitlement(str, Enum):
    FREE = "free"
    PRO = "pro"


class PluginSource(str, Enum):
    LOCAL = "local"
    REMOTE = "remote"


class ExecutionType(str, Enum):
    LOCAL = "local"
    SERVER = "server"


@dataclass(frozen=True)
class ToolPlugin:
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
    source: PluginSource = PluginSource.LOCAL
    manifest_url: Optional[str] = None
    execution_type: ExecutionType = ExecutionType.SERVER

    def to_dict(self) -> dict:
        data = asdict(self)
        data["kind"] = self.kind.value
        data["entitlement"] = self.entitlement.value
        data["source"] = self.source.value
        data["execution_type"] = self.execution_type.value
        data["tags"] = list(self.tags)
        return data


class PluginRegistry:
    def __init__(self) -> None:
        self._plugins: dict[str, ToolPlugin] = {}

    def register(self, plugin: ToolPlugin) -> ToolPlugin:
        if plugin.id in self._plugins:
            raise ValueError(f"Duplicate plugin id: {plugin.id!r}")
        self._plugins[plugin.id] = plugin
        return plugin

    def register_or_update(self, plugin: ToolPlugin) -> ToolPlugin:
        self._plugins[plugin.id] = plugin
        return plugin

    def get(self, plugin_id: str) -> ToolPlugin | None:
        return self._plugins.get(plugin_id)

    def all(self, *, include_disabled: bool = False) -> list[ToolPlugin]:
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
        source: PluginSource | None = None,
        execution_type: ExecutionType | None = None,
        include_disabled: bool = False,
    ) -> list[ToolPlugin]:
        result = []
        for plugin in self.all(include_disabled=include_disabled):
            if kind is not None and plugin.kind != kind:
                continue
            if category is not None and plugin.category != category:
                continue
            if entitlement is Entitlement.FREE and plugin.entitlement is not Entitlement.FREE:
                continue
            if source is not None and plugin.source != source:
                continue
            if execution_type is not None and plugin.execution_type != execution_type:
                continue
            result.append(plugin)
        return result

    def categories(self) -> list[str]:
        return sorted({p.category for p in self.all()})

    def clear(self) -> None:
        self._plugins.clear()


registry = PluginRegistry()


def register_builtin_plugins(reg: PluginRegistry) -> None:
    builtins: list[ToolPlugin] = [
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
            source=PluginSource.LOCAL,
            execution_type=ExecutionType.SERVER,
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
            source=PluginSource.LOCAL,
            execution_type=ExecutionType.SERVER,
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
            source=PluginSource.LOCAL,
            execution_type=ExecutionType.SERVER,
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
            source=PluginSource.LOCAL,
            execution_type=ExecutionType.SERVER,
        ),
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
            source=PluginSource.LOCAL,
            execution_type=ExecutionType.SERVER,
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
            source=PluginSource.LOCAL,
            execution_type=ExecutionType.SERVER,
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
            source=PluginSource.LOCAL,
            execution_type=ExecutionType.SERVER,
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
            source=PluginSource.LOCAL,
            execution_type=ExecutionType.SERVER,
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
            source=PluginSource.LOCAL,
            execution_type=ExecutionType.SERVER,
        ),
        ToolPlugin(
            id="redact-true",
            name="True Redaction",
            description="Permanently remove content via PyMuPDF redact (E1.7) — irreversible, audit logged.",
            kind=PluginKind.TOOL,
            category="security",
            icon="ink_eraser",
            route="/api/v1/document-ai/redact",
            entitlement=Entitlement.PRO,
            tags=("redact", "security", "pii"),
            source=PluginSource.LOCAL,
            execution_type=ExecutionType.SERVER,
        ),
        ToolPlugin(
            id="forms-vision-detect",
            name="Vision Form Detect",
            description="Detect form fields via vision model for low-confidence crops (E2.7).",
            kind=PluginKind.AI_ACTION,
            category="forms",
            icon="document_scanner",
            route="/api/v1/forms/vision-detect",
            entitlement=Entitlement.FREE,
            tags=("forms", "vision", "ai"),
            source=PluginSource.LOCAL,
            execution_type=ExecutionType.SERVER,
        ),
    ]
    for plugin in builtins:
        reg.register(plugin)


register_builtin_plugins(registry)
