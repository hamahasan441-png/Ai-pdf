"""Tests for the plugin registry and /plugins endpoint (Part 5.4)."""

import pytest

from app.services.plugins.registry import (
    Entitlement,
    PluginKind,
    PluginRegistry,
    ToolPlugin,
    register_builtin_plugins,
)

BASE = "/api/v1/plugins"


# --- Registry unit tests -------------------------------------------------

def _plugin(pid="p1", **kw):
    defaults = dict(
        id=pid,
        name="Test",
        description="desc",
        kind=PluginKind.TOOL,
        category="misc",
    )
    defaults.update(kw)
    return ToolPlugin(**defaults)


def test_register_and_get():
    reg = PluginRegistry()
    reg.register(_plugin("a"))
    assert reg.get("a") is not None
    assert reg.get("missing") is None


def test_duplicate_registration_rejected():
    reg = PluginRegistry()
    reg.register(_plugin("a"))
    with pytest.raises(ValueError):
        reg.register(_plugin("a"))


def test_disabled_hidden_by_default():
    reg = PluginRegistry()
    reg.register(_plugin("on", enabled=True))
    reg.register(_plugin("off", enabled=False))
    ids = {p.id for p in reg.all()}
    assert ids == {"on"}
    assert {p.id for p in reg.all(include_disabled=True)} == {"on", "off"}


def test_filter_by_kind_and_entitlement():
    reg = PluginRegistry()
    reg.register(_plugin("free-tool", kind=PluginKind.TOOL, entitlement=Entitlement.FREE))
    reg.register(_plugin("pro-ai", kind=PluginKind.AI_ACTION, entitlement=Entitlement.PRO))

    only_ai = reg.filter(kind=PluginKind.AI_ACTION)
    assert [p.id for p in only_ai] == ["pro-ai"]

    # FREE entitlement filter hides pro plugins.
    free_only = reg.filter(entitlement=Entitlement.FREE)
    assert [p.id for p in free_only] == ["free-tool"]

    # PRO entitlement filter shows everything.
    pro_view = reg.filter(entitlement=Entitlement.PRO)
    assert {p.id for p in pro_view} == {"free-tool", "pro-ai"}


def test_builtins_register_cleanly():
    reg = PluginRegistry()
    register_builtin_plugins(reg)
    assert len(reg.all()) >= 8
    # Sanity: the AI chat action is present and free.
    chat = reg.get("ai-chat")
    assert chat is not None
    assert chat.entitlement is Entitlement.FREE


def test_to_dict_flattens_enums():
    d = _plugin("x", entitlement=Entitlement.PRO, tags=("a", "b")).to_dict()
    assert d["kind"] == "tool"
    assert d["entitlement"] == "pro"
    assert d["tags"] == ["a", "b"]


# --- Endpoint integration tests -----------------------------------------

async def test_list_plugins_endpoint(client):
    resp = await client.get(BASE)
    assert resp.status_code == 200
    body = resp.json()
    assert body["count"] >= 8
    assert "intelligence" in body["categories"]
    assert any(p["id"] == "ai-chat" for p in body["plugins"])


async def test_list_plugins_filter_free(client):
    resp = await client.get(BASE, params={"entitlement": "free"})
    assert resp.status_code == 200
    body = resp.json()
    assert all(p["entitlement"] == "free" for p in body["plugins"])


async def test_list_plugins_filter_kind(client):
    resp = await client.get(BASE, params={"kind": "ai_action"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["count"] >= 1
    assert all(p["kind"] == "ai_action" for p in body["plugins"])


async def test_get_plugin_by_id(client):
    resp = await client.get(f"{BASE}/ai-summarize")
    assert resp.status_code == 200
    assert resp.json()["id"] == "ai-summarize"


async def test_get_unknown_plugin_404(client):
    resp = await client.get(f"{BASE}/does-not-exist")
    assert resp.status_code == 404
