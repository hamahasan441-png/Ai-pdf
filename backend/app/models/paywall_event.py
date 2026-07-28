"""Paywall A/B analytics event model — E6.3A Phase 6.

Tracks paywall exposures and conversions per variant for CVR measurement.

Design:
- Each event is scoped to user_id (optional, for logged-in) + variant (A/B) + event_type (exposure/conversion) + plan (monthly/yearly/lifetime) + timestamp
- Admin dashboard aggregates exposure vs conversion per variant
- No PII, just variant + plan + timestamp
- For anonymous users, owner_id nullable, but we still track variant exposure via client-side SharedPreferences + backend endpoint

Privacy: no document data, just paywall metrics.
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import DateTime, ForeignKey, String, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.db.database import Base


class PaywallEvent(Base):
    """Paywall A/B exposure or conversion event."""

    __tablename__ = "paywall_events"

    id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    owner_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )
    variant: Mapped[str] = mapped_column(String(8), nullable=False, index=True)  # A or B
    event_type: Mapped[str] = mapped_column(String(32), nullable=False, index=True)  # exposure, conversion, trial_start
    plan: Mapped[str | None] = mapped_column(String(32), nullable=True)  # monthly, yearly, lifetime, or None for exposure
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True
    )
