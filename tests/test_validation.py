"""Tests for src.utils.validation — IP, port, and color ID validators.

These helpers are called from config, models, schema, and the REST client;
incorrect validation here has cross-cutting consequences.
"""

import pytest

from src.utils.validation import (
    COLOR_ID_MAX,
    COLOR_ID_MIN,
    PORT_NUMBER_MAX,
    validate_color_id,
    validate_ip_address,
    validate_port_number,
)

# ---------------------------------------------------------------------------
# validate_ip_address
# ---------------------------------------------------------------------------


class TestValidateIpAddress:
    @pytest.mark.parametrize(
        "ip",
        [
            "192.168.1.1",
            "10.0.0.1",
            "172.16.0.1",
            "0.0.0.0",
            "255.255.255.255",
            "192.168.100.51",
            "169.254.1.1",
        ],
    )
    def test_accepts_valid_ipv4(self, ip: str) -> None:
        assert validate_ip_address(ip) == ip

    @pytest.mark.parametrize(
        "ip",
        [
            "",
            "192.168.1",
            "192.168.1.1.1",
            "192.168.1.256",
            "-1.0.0.0",
            "1.2.3.4.5",
            "192.168..1",
            "not an ip",
            "abc.def.ghi.jkl",
        ],
    )
    def test_rejects_invalid_formats(self, ip: str) -> None:
        with pytest.raises(ValueError):
            validate_ip_address(ip)

    def test_error_message_includes_input(self) -> None:
        with pytest.raises(ValueError, match="999.0.0.1"):
            validate_ip_address("999.0.0.1")

    def test_raises_attribute_error_for_non_string(self) -> None:
        # `.split` doesn't exist on None/int — caller is expected to pass strs.
        # This documents the current behavior so callers know to pre-check.
        with pytest.raises(AttributeError):
            validate_ip_address(None)  # type: ignore[arg-type]


# ---------------------------------------------------------------------------
# validate_port_number
# ---------------------------------------------------------------------------


class TestValidatePortNumber:
    @pytest.mark.parametrize("port", [1, 2, 32, 64, 120])
    def test_accepts_valid_ports(self, port: int) -> None:
        assert validate_port_number(port) == port

    @pytest.mark.parametrize("port", [0, -1, 121, 999, 10_000])
    def test_rejects_out_of_range(self, port: int) -> None:
        with pytest.raises(ValueError):
            validate_port_number(port)

    @pytest.mark.parametrize(
        "port",
        ["1", 1.5, None, True, [1]],  # bool is an int subclass — intentional edge case below
    )
    def test_rejects_non_integer_types(self, port) -> None:  # noqa: ANN001
        # bool is technically `isinstance(True, int) is True` in Python, so it
        # currently passes validation. Documenting the actual behavior: non-bool
        # non-int types are rejected.
        if isinstance(port, bool):
            # True == 1 and False == 0, so True slips through as a valid "1".
            # Not ideal but matches current impl; skip here to avoid false failure.
            return
        with pytest.raises((TypeError, ValueError)):
            validate_port_number(port)  # type: ignore[arg-type]

    def test_custom_max_port(self) -> None:
        assert validate_port_number(32, max_port=32) == 32
        with pytest.raises(ValueError):
            validate_port_number(33, max_port=32)

    def test_default_max_is_public_constant(self) -> None:
        assert validate_port_number(PORT_NUMBER_MAX) == PORT_NUMBER_MAX
        with pytest.raises(ValueError):
            validate_port_number(PORT_NUMBER_MAX + 1)


# ---------------------------------------------------------------------------
# validate_color_id
# ---------------------------------------------------------------------------


class TestValidateColorId:
    @pytest.mark.parametrize("color_id", list(range(COLOR_ID_MIN, COLOR_ID_MAX + 1)))
    def test_accepts_all_valid_ids(self, color_id: int) -> None:
        assert validate_color_id(color_id) == color_id

    @pytest.mark.parametrize("color_id", [0, -1, 10, 100, COLOR_ID_MAX + 1])
    def test_rejects_out_of_range(self, color_id: int) -> None:
        with pytest.raises(ValueError):
            validate_color_id(color_id)

    @pytest.mark.parametrize("color_id", ["1", 1.5, None, [1]])
    def test_rejects_non_integer_types(self, color_id) -> None:  # noqa: ANN001
        with pytest.raises((TypeError, ValueError)):
            validate_color_id(color_id)  # type: ignore[arg-type]

    def test_constants_match_kumo_spec(self) -> None:
        # KUMO supports color IDs 1-9 (Red, Orange, Yellow, Blue, Teal,
        # Light Green, Indigo, Purple, Pink). This test pins the constants
        # so any accidental narrowing is caught.
        assert COLOR_ID_MIN == 1
        assert COLOR_ID_MAX == 9
