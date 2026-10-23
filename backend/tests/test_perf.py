"""Public perf telemetry ingest must not grow memory without bound."""

from app.api.v1 import perf


async def test_perf_ingest_bounds_route_keys(client, monkeypatch):
    monkeypatch.setattr(perf, "_summary_by_route", type(perf._summary_by_route)(list))
    monkeypatch.setattr(perf, "_MAX_ROUTES", 3)
    for i in range(10):
        resp = await client.post("/api/v1/admin/perf/ingest", json={"route": f"/r{i}", "p95Ms": 10})
        assert resp.status_code == 200
    assert len(perf._summary_by_route) <= 4  # 3 real routes + the overflow bucket

    long_route = await client.post("/api/v1/admin/perf/ingest", json={"route": "/" + "x" * 300, "p95Ms": 1})
    assert long_route.status_code == 422
