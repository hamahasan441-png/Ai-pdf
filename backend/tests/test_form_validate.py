"""Tests for the /forms/validate endpoint."""

URL = "/api/v1/forms/validate"


async def test_validate_all_valid(client):
    resp = await client.post(URL, json={
        "fields": [
            {"name": "email", "value": "user@example.com", "field_type": "email"},
            {"name": "phone", "value": "+49 176 12345678", "field_type": "phone"},
            {"name": "date", "value": "15.03.1990", "field_type": "date"},
        ]
    })
    assert resp.status_code == 200
    body = resp.json()
    assert body["all_valid"] is True
    assert all(r["valid"] for r in body["results"])


async def test_validate_mixed_results(client):
    resp = await client.post(URL, json={
        "fields": [
            {"name": "email", "value": "not-an-email", "field_type": "email"},
            {"name": "iban", "value": "DE89 3704 0044 0532 0130 00", "field_type": "iban"},
        ]
    })
    assert resp.status_code == 200
    body = resp.json()
    assert body["all_valid"] is False
    assert body["results"][0]["valid"] is False
    assert body["results"][1]["valid"] is True


async def test_validate_empty_fields(client):
    resp = await client.post(URL, json={"fields": []})
    assert resp.status_code == 200
    assert resp.json()["all_valid"] is True
