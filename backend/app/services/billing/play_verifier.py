"""Server-side Google Play purchase verification.

This is the authoritative source of Pro entitlement — the client's local
entitlement is only a UX cache and is spoofable. Here we call the Google Play
Developer API with a service-account token to confirm a purchase/subscription
is genuine and active.

Setup (one-time):
  1. Create a service account in Google Cloud, enable "Google Play Android
     Developer API".
  2. In Play Console > Users & permissions, grant the service account access
     with the "View financial data / manage orders" permission.
  3. Put the service-account JSON in GOOGLE_PLAY_SERVICE_ACCOUNT_JSON.
"""

from __future__ import annotations

import json
import time
from dataclasses import dataclass
from typing import Optional

import httpx

from app.core.config import settings

_SCOPE = "https://www.googleapis.com/auth/androidpublisher"
_BASE = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications"


@dataclass
class VerificationResult:
    valid: bool
    tier: str            # 'free' | 'monthly' | 'yearly' | 'lifetime'
    expiry_millis: Optional[int]
    raw: dict


def _tier_for_product(product_id: str) -> str:
    if product_id == settings.PRODUCT_MONTHLY:
        return "monthly"
    if product_id == settings.PRODUCT_YEARLY:
        return "yearly"
    if product_id == settings.PRODUCT_LIFETIME:
        return "lifetime"
    return "free"


class PlayVerifier:
    """Verifies purchases against the Play Developer API."""

    def __init__(self):
        self._token: Optional[str] = None
        self._token_exp: float = 0.0

    @property
    def configured(self) -> bool:
        return bool(settings.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON.strip())

    def _fetch_token_sync(self) -> str:
        """Blocking token fetch (runs in a threadpool from async callers)."""
        from google.oauth2 import service_account  # lazy
        from google.auth.transport.requests import Request

        info = json.loads(settings.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON)
        creds = service_account.Credentials.from_service_account_info(
            info, scopes=[_SCOPE]
        )
        creds.refresh(Request())
        # Cache until ~1 min before expiry.
        self._token = creds.token
        self._token_exp = time.time() + 3000
        return creds.token

    async def _access_token(self) -> str:
        if self._token and time.time() < self._token_exp:
            return self._token
        from starlette.concurrency import run_in_threadpool
        return await run_in_threadpool(self._fetch_token_sync)

    async def verify(self, product_id: str, purchase_token: str, is_subscription: bool) -> VerificationResult:
        token = await self._access_token()
        pkg = settings.GOOGLE_PLAY_PACKAGE_NAME
        headers = {"Authorization": f"Bearer {token}"}

        async with httpx.AsyncClient(timeout=30.0) as client:
            if is_subscription:
                url = f"{_BASE}/{pkg}/purchases/subscriptions/{product_id}/tokens/{purchase_token}"
                resp = await client.get(url, headers=headers)
                resp.raise_for_status()
                data = resp.json()
                # paymentState: 0 pending, 1 received, 2 free trial, 3 deferred
                expiry = int(data.get("expiryTimeMillis", "0") or 0)
                active = data.get("paymentState") in (1, 2) and expiry > int(time.time() * 1000)
                return VerificationResult(
                    valid=active,
                    tier=_tier_for_product(product_id) if active else "free",
                    expiry_millis=expiry or None,
                    raw=data,
                )
            else:
                url = f"{_BASE}/{pkg}/purchases/products/{product_id}/tokens/{purchase_token}"
                resp = await client.get(url, headers=headers)
                resp.raise_for_status()
                data = resp.json()
                # purchaseState: 0 purchased, 1 canceled, 2 pending
                purchased = data.get("purchaseState", 1) == 0
                return VerificationResult(
                    valid=purchased,
                    tier=_tier_for_product(product_id) if purchased else "free",
                    expiry_millis=None,  # one-time / lifetime
                    raw=data,
                )


play_verifier = PlayVerifier()
