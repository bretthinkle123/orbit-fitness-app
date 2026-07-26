"""Shared Pydantic v2 validation contracts (`code-standards`' schema-first
rule + plan.md's "Validation contracts" table) — every endpoint schema in
`schemas/` builds on these rather than hand-rolling its own extra-fields
policy or timestamp/day-key checks.
"""

from __future__ import annotations

import datetime as dt
from typing import Annotated

from pydantic import AfterValidator, AwareDatetime, BaseModel, ConfigDict, StringConstraints

# Client clock skew tolerated before a timestamp counts as "future" (plan
# §Data: "backdating allowed, future (> server now + small skew) rejected 422").
_FUTURE_TIMESTAMP_SKEW = dt.timedelta(minutes=5)

# `day_key` is always `YYYY-MM-DD` (plan §Validation-contracts).
DAY_KEY_PATTERN = r"^\d{4}-\d{2}-\d{2}$"


class StrictModel(BaseModel):
    """Base for every request schema: an unknown field is a 422, never
    silently ignored (mass-assignment + tampering defense — ASVS 2.2.1/
    2.2.2/15.3.3). Every body/query model in `schemas/` inherits this."""

    model_config = ConfigDict(extra="forbid")


class EmptyBody(StrictModel):
    """The NO-BODY contract (plan's validation-contracts table): binds an
    empty, `extra="forbid"` model so any body field on a no-body endpoint
    (`POST /me/bootstrap`, `POST /me/signout`, `DELETE /me`) is a 422."""


class EmptyQuery(StrictModel):
    """The NO-PARAMS contract: binds an empty, `extra="forbid"` model so an
    undeclared query param on a param-less endpoint (`GET /profile`,
    `GET /catalog/quick-foods`, `GET /weight`) is a 422 rather than silently
    passing (the F4-01 escape shape the plan's audit flagged). `GET /health`
    is N/A by design — it binds no query model at all, per the plan."""


def _validate_day_key(value: str) -> str:
    """Parse `day_key` as a real calendar date and reject one more than a day
    in the future (the day-key equivalent of the timestamp future-reject —
    a generous allowance for a caller near a timezone boundary)."""
    try:
        parsed = dt.date.fromisoformat(value)
    except ValueError as error:
        raise ValueError("day_key must be a valid calendar date") from error
    if parsed > dt.date.today() + dt.timedelta(days=1):
        raise ValueError("day_key may not be more than one day in the future")
    return value


DayKey = Annotated[
    str,
    StringConstraints(pattern=DAY_KEY_PATTERN),
    AfterValidator(_validate_day_key),
]


def _validate_not_future(value: dt.datetime) -> dt.datetime:
    """Reject a client-provided timestamp more than the skew ahead of server
    time; backdating is explicitly allowed (plan §Data)."""
    now = dt.datetime.now(dt.timezone.utc)
    if value > now + _FUTURE_TIMESTAMP_SKEW:
        raise ValueError("timestamp may not be in the future")
    return value


# `logged_at` / `done_at` — every client-provided instant in the API (plan's
# validation-contracts table row for these two fields).
ClientTimestamp = Annotated[AwareDatetime, AfterValidator(_validate_not_future)]
