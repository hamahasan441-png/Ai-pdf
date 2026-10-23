"""Verification of third-party OIDC ID tokens (SSO sign-in, Pub/Sub push auth).

Every token must be signed by a key published in the issuer's JWKS, use an
asymmetric algorithm, carry an ``aud`` from the configured allow-list and an
``iss`` from the expected issuer(s), and be unexpired. Unsigned (``alg=none``)
or HMAC tokens are rejected because only RS256/ES256 are accepted.

``_signing_key`` is the single network touchpoint (it fetches and caches the
JWKS); tests monkeypatch it to serve a local key.
"""

from __future__ import annotations

from typing import Iterable

import jwt as pyjwt
from jwt import PyJWKClient
from starlette.concurrency import run_in_threadpool

GOOGLE_JWKS_URL = "https://www.googleapis.com/oauth2/v3/certs"
GOOGLE_ISSUERS = ["accounts.google.com", "https://accounts.google.com"]
APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys"
APPLE_ISSUERS = ["https://appleid.apple.com"]

_ALGORITHMS = ["RS256", "ES256"]
_REQUIRED_CLAIMS = ["exp", "iat", "iss", "aud", "sub"]

_jwk_clients: dict[str, PyJWKClient] = {}


class InvalidIdToken(Exception):
    """The token is malformed, unsigned, forged, expired or for another audience."""


class IdTokenKeysUnavailable(Exception):
    """The issuer's JWKS could not be fetched (network / provider outage)."""


def _signing_key(jwks_url: str, token: str):
    """Return the public key from ``jwks_url`` matching the token's ``kid``."""
    client = _jwk_clients.get(jwks_url)
    if client is None:
        client = PyJWKClient(jwks_url, cache_keys=True, lifespan=3600, timeout=10)
        _jwk_clients[jwks_url] = client
    return client.get_signing_key_from_jwt(token).key


async def verify_id_token(
    token: str,
    *,
    jwks_url: str,
    audiences: Iterable[str],
    issuers: Iterable[str],
) -> dict:
    """Verify ``token`` and return its claims, or raise :class:`InvalidIdToken`.

    ``audiences`` and ``issuers`` must be non-empty: an unconfigured caller can
    never accept a token.
    """
    audiences = [a for a in audiences if a]
    issuers = [i for i in issuers if i]
    if not audiences or not issuers or not jwks_url:
        raise InvalidIdToken("ID token verification is not configured")

    try:
        key = await run_in_threadpool(_signing_key, jwks_url, token)
    except pyjwt.PyJWKClientConnectionError as e:
        raise IdTokenKeysUnavailable(str(e)) from e
    except Exception as e:  # noqa: BLE001 - unknown kid, malformed header, ...
        raise InvalidIdToken("Unknown signing key") from e

    try:
        return pyjwt.decode(
            token,
            key,
            algorithms=_ALGORITHMS,
            audience=audiences,
            issuer=issuers,
            leeway=60,
            options={"require": _REQUIRED_CLAIMS},
        )
    except pyjwt.PyJWTError as e:
        raise InvalidIdToken(str(e)) from e
