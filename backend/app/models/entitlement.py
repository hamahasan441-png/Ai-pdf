"""Entitlement model — server-side record of a verified Play purchase.

Guest-first: entitlement is keyed by the Play ``purchase_token`` (not an
account), so the app works without login. The managed AI endpoint accepts the
token via the ``X-Entitlement-Token`` header to grant unlimited (Pro) access.
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import Boolean, DateTime, String, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.db.database import Base


class Entitlement(Base):
    """A verified purchase/subscription and the Pro tier it grants."""

    __tablename__ = "entitlements"

    id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    # The Play purchase token — the lookup key from the client.
    purchase_token: Mapped[str] = mapped_column(
        String(512), unique=True, index=True, nullable=False
    )
    product_id: Mapped[str] = mapped_column(String(128), nullable=False)
    tier: Mapped[str] = mapped_column(String(32), default="free")  # monthly/yearly/lifetime
    valid: Mapped[bool] = mapped_column(Boolean, default=False)
    # Subscription expiry (ms since epoch). Null for lifetime / free.
    expiry_millis: Mapped[int | None] = mapped_column(nullable=True)

    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )

    def is_active(self) -> bool:
        """True if this entitlement currently grants Pro access."""
        if not self.valid or self.tier == "free":
            return False
        if self.tier == "lifetime" or self.expiry_millis is None:
            return True
        now_ms = int(datetime.now(timezone.utc).timestamp() * 1000)
        return self.expiry_millis > now_ms
