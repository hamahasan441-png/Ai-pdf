"""Login / 2FA routes are rate limited per client IP (brute-force protection)."""

from app.core.config import settings

LOGIN = "/api/v1/auth/login"
CREDS = {"email": "rl@example.com", "password": "wrong-password"}


async def test_login_rate_limited(client, monkeypatch):
    monkeypatch.setattr(settings, "AUTH_RATE_LIMIT_MAX_REQUESTS", 3)
    codes = [(await client.post(LOGIN, json=CREDS)).status_code for _ in range(4)]
    assert codes == [401, 401, 401, 429]

    # Login and 2FA routes share the bucket, so switching route doesn't help.
    two_fa = await client.post(f"{LOGIN}/2fa", json=CREDS)
    assert two_fa.status_code == 429

    # Unrelated routes are not affected.
    reg = await client.post(
        "/api/v1/auth/register",
        json={"email": "rl2@example.com", "password": "password123", "full_name": "RL"},
    )
    assert reg.status_code == 201


async def test_login_rate_limit_can_be_disabled(client, monkeypatch):
    monkeypatch.setattr(settings, "AUTH_RATE_LIMIT_MAX_REQUESTS", 0)
    for _ in range(15):
        assert (await client.post(LOGIN, json=CREDS)).status_code == 401
