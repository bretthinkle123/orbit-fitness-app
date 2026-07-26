"""Validation + response contracts for `/weight` (plan §Backend, §Validation
contracts): canonical-kg weight logging + the fixed 30-day window read with
latest + weekly delta (AC12).
"""

from __future__ import annotations

import datetime

from pydantic import BaseModel, Field

from .common import ClientTimestamp, DayKey, StrictModel


class WeightEntryCreate(StrictModel):
    """`POST /weight` request — canonical kg (CLAUDE.md: "Weight stored
    canonical metric (kg); display converts per units setting on the
    client"). `weight_kg` bounds mirror the `weight_entries` DB `CHECK`
    exactly (`20..500`), so the DB constraint is defense-in-depth here —
    there is no live-API path that reaches it, the same shape as T5's
    fuel-macro bounds."""

    weight_kg: float = Field(ge=20, le=500)
    day_key: DayKey
    logged_at: ClientTimestamp


class WeightEntryOut(BaseModel):
    """One weight entry — an explicit response allowlist (`owner_uid` never
    appears)."""

    id: int
    weight_kg: float
    day_key: datetime.date
    logged_at: datetime.datetime

    @classmethod
    def from_domain(cls, entry) -> "WeightEntryOut":
        return cls(id=entry.id, weight_kg=entry.weight_kg, day_key=entry.day_key, logged_at=entry.logged_at)


class WeightWindowOut(BaseModel):
    """`GET /weight` response: the fixed 30-day window + latest + weekly
    delta (AC12). `weekly_delta_kg` is `None` when the window doesn't yet
    span 7 days of history — an honest "not enough data" rather than a
    fabricated zero."""

    entries: list[WeightEntryOut]
    latest: WeightEntryOut | None
    weekly_delta_kg: float | None
