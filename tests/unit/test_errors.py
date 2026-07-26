"""Unit tests for the error-envelope facade's DB-constraint classifier
(`edge/errors.py`) — fed synthetic SQLAlchemy `IntegrityError` instances so
the mapping is verified without needing a live DB constraint violation (no
domain route exists yet to trigger one for real; T4+ exercises this facade
end-to-end against a genuine constraint)."""

from sqlalchemy.exc import IntegrityError

from orbit.edge.errors import classify_integrity_error


class _FakeDriverError(Exception):
    """Stands in for asyncpg's exception, which exposes `.sqlstate`."""

    def __init__(self, sqlstate: str):
        super().__init__(sqlstate)
        self.sqlstate = sqlstate


def _make_integrity_error(sqlstate: str) -> IntegrityError:
    return IntegrityError("statement", {}, _FakeDriverError(sqlstate))


def test_unique_violation_maps_to_conflict_409():
    code, status = classify_integrity_error(_make_integrity_error("23505"))
    assert (code, status) == ("conflict", 409)


def test_check_violation_maps_to_validation_failed_422():
    code, status = classify_integrity_error(_make_integrity_error("23514"))
    assert (code, status) == ("validation_failed", 422)


def test_foreign_key_violation_maps_to_not_found_404():
    code, status = classify_integrity_error(_make_integrity_error("23503"))
    assert (code, status) == ("not_found", 404)


def test_not_null_violation_maps_to_validation_failed_422():
    code, status = classify_integrity_error(_make_integrity_error("23502"))
    assert (code, status) == ("validation_failed", 422)


def test_unknown_sqlstate_defaults_to_a_4xx_never_a_500():
    """Any constraint violation is a 4xx — the "constraint -> 4xx not 500"
    acceptance shape holds even for a SQLSTATE this table doesn't name."""
    code, status = classify_integrity_error(_make_integrity_error("99999"))
    assert status < 500
    assert code == "validation_failed"
