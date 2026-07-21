"""Tests for the health dashboard endpoint."""

URL = "/api/v1/health/dashboard"


async def test_health_dashboard_response(client):
    resp = await client.get(URL)
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] in ("healthy", "degraded", "unhealthy")
    assert body["uptime_seconds"] >= 0
    assert body["environment"] == "development"
    assert "ai_provider" in body["checks"]
    assert "database" in body["checks"]
    assert body["version"] == "1.0.0"
