"""Unit tests for `require_fresh_reauth` (`auth/__init__.py`) — the
`auth_time`-recency guard `DELETE /me` (T8) will depend on. Built now per
T3's explicit scope; tested directly since no route uses it yet."""

import time

import pytest
from fastapi import HTTPException

from orbit.auth import require_fresh_reauth


def test_require_fresh_reauth_accepts_a_recent_auth_time():
    claims = {"uid": "abc", "auth_time": time.time() - 30}  # 30s ago
    result = require_fresh_reauth(user=claims)
    assert result is claims


def test_require_fresh_reauth_rejects_a_stale_auth_time():
    claims = {"uid": "abc", "auth_time": time.time() - 600}  # 10 minutes ago
    with pytest.raises(HTTPException) as exc_info:
        require_fresh_reauth(user=claims)
    assert exc_info.value.status_code == 401


def test_require_fresh_reauth_rejects_a_missing_auth_time():
    claims = {"uid": "abc"}
    with pytest.raises(HTTPException) as exc_info:
        require_fresh_reauth(user=claims)
    assert exc_info.value.status_code == 401
