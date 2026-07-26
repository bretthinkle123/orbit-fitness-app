"""Unit tests for the structlog facade: standard fields + PII/secret redaction
(T1 test slice: "structlog facade fields + redaction")."""

import structlog
from structlog.testing import capture_logs

from orbit.logging import _redact, get_logger

# capture_logs() disables ALL configured processors by default and applies
# only what is passed via its `processors=` argument (structlog >= 25.5), so
# end-to-end assertions on our real pipeline's behavior (level tagging,
# redaction) must reapply the same processors the facade configures.
_PIPELINE_PROCESSORS = [structlog.processors.add_log_level, _redact]


def test_redact_strips_sensitive_field_values():
    """Any field whose key matches the redaction list is replaced, never
    logged verbatim — regardless of which call site produced it."""
    event = {
        "password": "hunter2",
        "token": "abc.def.ghi",
        "Authorization": "Bearer xyz",
        "safe_field": "ok",
    }

    redacted = _redact(None, None, dict(event))

    assert redacted["password"] == "[REDACTED]"
    assert redacted["token"] == "[REDACTED]"
    assert redacted["Authorization"] == "[REDACTED]"
    assert redacted["safe_field"] == "ok"


def test_redact_is_case_insensitive_on_key_names():
    """A differently-cased sensitive key (e.g. `SECRET`) is still redacted."""
    redacted = _redact(None, None, {"SECRET": "top-secret-value"})

    assert redacted["SECRET"] == "[REDACTED]"


def test_get_logger_binds_service_field_and_emits_standard_fields():
    """Every log line carries the standard field set: timestamp/level/service
    (set by the logger, not the caller) plus the event message."""
    with capture_logs(processors=_PIPELINE_PROCESSORS) as captured:
        get_logger().info("hello world", operation="test.op")

    assert len(captured) == 1
    entry = captured[0]
    assert entry["event"] == "hello world"
    assert entry["service"] == "orbit-api"
    assert entry["operation"] == "test.op"
    assert entry["level"] == "info"


def test_get_logger_redacts_a_sensitive_field_end_to_end():
    """The full pipeline (not just the bare `_redact` helper) drops secret
    values before an entry is captured."""
    with capture_logs(processors=_PIPELINE_PROCESSORS) as captured:
        get_logger().info("login attempt", password="hunter2")

    assert captured[0]["password"] == "[REDACTED]"
