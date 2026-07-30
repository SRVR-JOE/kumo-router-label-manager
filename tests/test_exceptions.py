"""Tests for src.utils.exceptions — Helix custom exception hierarchy.

Covers __str__ formatting, the details dict merge behavior, and the
specialized subclass attribute wiring (router_ip, field, operation, etc.).
"""

import pytest

from src.utils.exceptions import (
    HelixConnectionError,
    HelixException,
    HelixFileError,
    HelixValidationError,
)

# ---------------------------------------------------------------------------
# HelixException base class
# ---------------------------------------------------------------------------


class TestHelixException:
    def test_message_stored_and_accessible(self) -> None:
        exc = HelixException("boom")
        assert exc.message == "boom"
        assert str(exc) == "boom"

    def test_details_default_to_empty_dict(self) -> None:
        exc = HelixException("boom")
        assert exc.details == {}

    def test_str_includes_details_when_present(self) -> None:
        exc = HelixException("boom", details={"port": 42})
        s = str(exc)
        assert "boom" in s
        assert "port=42" in s

    def test_str_with_multiple_details(self) -> None:
        exc = HelixException("boom", details={"a": 1, "b": "two"})
        s = str(exc)
        assert "a=1" in s
        assert "b=two" in s

    def test_is_exception_subclass(self) -> None:
        assert issubclass(HelixException, Exception)

    def test_raises_and_catches_as_base_exception(self) -> None:
        # Verifies HelixException is a plain Exception subclass so existing
        # `except Exception` blocks still catch it.
        with pytest.raises(HelixException):
            raise HelixException("boom")

    def test_none_details_becomes_empty_dict(self) -> None:
        exc = HelixException("boom", details=None)
        assert exc.details == {}


# ---------------------------------------------------------------------------
# HelixConnectionError
# ---------------------------------------------------------------------------


class TestHelixConnectionError:
    def test_inherits_from_helix_exception(self) -> None:
        assert issubclass(HelixConnectionError, HelixException)

    def test_router_ip_merges_into_details(self) -> None:
        exc = HelixConnectionError("unreachable", router_ip="192.168.1.100")
        assert exc.router_ip == "192.168.1.100"
        assert exc.details["router_ip"] == "192.168.1.100"

    def test_error_code_merges_into_details(self) -> None:
        exc = HelixConnectionError("timeout", error_code="ETIMEDOUT")
        assert exc.error_code == "ETIMEDOUT"
        assert exc.details["error_code"] == "ETIMEDOUT"

    def test_extra_details_are_preserved(self) -> None:
        exc = HelixConnectionError(
            "fail",
            router_ip="1.2.3.4",
            details={"retry_count": 3},
        )
        assert exc.details["retry_count"] == 3
        assert exc.details["router_ip"] == "1.2.3.4"

    def test_minimal_construction(self) -> None:
        exc = HelixConnectionError("plain")
        assert exc.router_ip is None
        assert exc.error_code is None
        # No ip/code means no auto-populated keys in details
        assert "router_ip" not in exc.details
        assert "error_code" not in exc.details


# ---------------------------------------------------------------------------
# HelixValidationError
# ---------------------------------------------------------------------------


class TestHelixValidationError:
    def test_inherits_from_helix_exception(self) -> None:
        assert issubclass(HelixValidationError, HelixException)

    def test_field_and_value_captured(self) -> None:
        exc = HelixValidationError("bad label", field="new_label", value="x" * 300)
        assert exc.field == "new_label"
        assert exc.value == "x" * 300
        assert exc.details["field"] == "new_label"
        # value is stringified in details for safe serialisation
        assert exc.details["value"] == "x" * 300

    def test_validation_errors_list_captured(self) -> None:
        errors = ["too long", "contains newline"]
        exc = HelixValidationError("invalid", validation_errors=errors)
        assert exc.validation_errors == errors
        assert exc.details["validation_errors"] == errors

    def test_empty_string_value_ignored_in_details(self) -> None:
        # value=None is the "not provided" sentinel, but empty string should
        # still round-trip through str() — verifies stringification path.
        exc = HelixValidationError("bad", value="")
        assert exc.details["value"] == ""

    def test_none_value_not_added_to_details(self) -> None:
        exc = HelixValidationError("bad", value=None)
        assert "value" not in exc.details

    def test_default_validation_errors_is_empty_list(self) -> None:
        exc = HelixValidationError("bad")
        assert exc.validation_errors == []


# ---------------------------------------------------------------------------
# HelixFileError
# ---------------------------------------------------------------------------


class TestHelixFileError:
    def test_inherits_from_helix_exception(self) -> None:
        assert issubclass(HelixFileError, HelixException)

    def test_file_path_and_operation_captured(self) -> None:
        exc = HelixFileError(
            "cannot read",
            file_path="/tmp/labels.csv",
            operation="read",
        )
        assert exc.file_path == "/tmp/labels.csv"
        assert exc.operation == "read"
        assert exc.details["file_path"] == "/tmp/labels.csv"
        assert exc.details["operation"] == "read"

    def test_original_exception_captured_as_string(self) -> None:
        original = OSError("Permission denied")
        exc = HelixFileError(
            "cannot write",
            file_path="/root/x",
            operation="write",
            original_exception=original,
        )
        assert exc.original_exception is original
        assert "Permission denied" in exc.details["original_error"]

    def test_minimal_construction_has_no_spurious_keys(self) -> None:
        exc = HelixFileError("gone")
        assert exc.file_path is None
        assert exc.operation is None
        assert exc.original_exception is None
        assert "file_path" not in exc.details
        assert "operation" not in exc.details
        assert "original_error" not in exc.details


# ---------------------------------------------------------------------------
# Cross-type catching
# ---------------------------------------------------------------------------


class TestHierarchyCatching:
    """Verify the hierarchy is catchable via the base class everywhere."""

    @pytest.mark.parametrize(
        "exc_cls",
        [HelixConnectionError, HelixValidationError, HelixFileError],
    )
    def test_all_subclasses_caught_by_base(self, exc_cls) -> None:  # noqa: ANN001
        with pytest.raises(HelixException):
            raise exc_cls("something failed")

    def test_connection_not_caught_by_validation(self) -> None:
        with pytest.raises(HelixConnectionError):
            try:
                raise HelixConnectionError("conn")
            except HelixValidationError:
                pytest.fail("HelixValidationError should not catch HelixConnectionError")
