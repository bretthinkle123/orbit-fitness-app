"""Unit tests for the shared validation contracts (`schemas/common.py`):
the `day_key` pattern + future-rejection, and the client-timestamp
future-skew rejection (plan.md's "Validation contracts" table)."""

import datetime as dt

import pytest
from pydantic import BaseModel, ValidationError

from orbit.schemas.common import ClientTimestamp, DayKey, EmptyBody, EmptyQuery


class _DayKeyHolder(BaseModel):
    day_key: DayKey


class _TimestampHolder(BaseModel):
    logged_at: ClientTimestamp


def test_day_key_accepts_a_valid_calendar_date():
    holder = _DayKeyHolder(day_key="2026-07-24")
    assert holder.day_key == "2026-07-24"


def test_day_key_rejects_a_malformed_string():
    with pytest.raises(ValidationError):
        _DayKeyHolder(day_key="not-a-date")


def test_day_key_rejects_a_date_more_than_one_day_in_the_future():
    too_far_future = (dt.date.today() + dt.timedelta(days=5)).isoformat()
    with pytest.raises(ValidationError):
        _DayKeyHolder(day_key=too_far_future)


def test_day_key_accepts_a_backdated_date():
    long_ago = (dt.date.today() - dt.timedelta(days=400)).isoformat()
    holder = _DayKeyHolder(day_key=long_ago)
    assert holder.day_key == long_ago


def test_client_timestamp_accepts_a_backdated_instant():
    long_ago = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=30)
    holder = _TimestampHolder(logged_at=long_ago)
    assert holder.logged_at == long_ago


def test_client_timestamp_rejects_one_beyond_the_skew_window():
    too_far_future = dt.datetime.now(dt.timezone.utc) + dt.timedelta(minutes=10)
    with pytest.raises(ValidationError):
        _TimestampHolder(logged_at=too_far_future)


def test_client_timestamp_accepts_one_within_the_skew_window():
    just_ahead = dt.datetime.now(dt.timezone.utc) + dt.timedelta(minutes=2)
    holder = _TimestampHolder(logged_at=just_ahead)
    assert holder.logged_at == just_ahead


def test_empty_body_rejects_any_field():
    with pytest.raises(ValidationError):
        EmptyBody(unexpected="value")


def test_empty_query_rejects_any_field():
    with pytest.raises(ValidationError):
        EmptyQuery(unexpected="value")
