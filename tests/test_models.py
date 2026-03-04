"""Tests for Label, Router, and Event data models.

Coverage targets:
- Label: port boundary validation, PortType enforcement, label length limits,
         has_changes / apply_changes logic, to_dict / from_dict roundtrip
- Router: IP address validation, ConnectionStatus transitions, port info helpers,
          to_dict / from_dict roundtrip
- Events: each concrete event class populates its data dict correctly,
          BaseEvent rejects bad argument types
"""

import pytest
from datetime import datetime, timezone

from src.models.label import Label, PortType
from src.models.router import Router, ConnectionStatus
from src.models.events import (
    BaseEvent,
    ConnectionEvent,
    LabelsEvent,
    ValidationEvent,
    FileEvent,
    EventType,
)


# ===========================================================================
# Label model
# ===========================================================================


class TestLabelPortNumberValidation:
    """Port number must be an integer in the range [1, 120]."""

    def test_port_1_is_valid_lower_boundary(self):
        label = Label(port_number=1, port_type=PortType.INPUT)
        assert label.port_number == 1

    def test_port_120_is_valid_upper_boundary(self):
        label = Label(port_number=120, port_type=PortType.OUTPUT)
        assert label.port_number == 120

    def test_port_60_is_valid_midrange(self):
        label = Label(port_number=60, port_type=PortType.INPUT)
        assert label.port_number == 60

    def test_port_0_raises_value_error(self):
        """Port 0 is one below the valid minimum."""
        with pytest.raises(ValueError, match="1 and 120"):
            Label(port_number=0, port_type=PortType.INPUT)

    def test_port_121_raises_value_error(self):
        """Port 121 is one above the valid maximum."""
        with pytest.raises(ValueError, match="1 and 120"):
            Label(port_number=121, port_type=PortType.INPUT)

    def test_negative_port_raises_value_error(self):
        with pytest.raises(ValueError, match="1 and 120"):
            Label(port_number=-1, port_type=PortType.INPUT)

    def test_float_port_raises_type_error(self):
        with pytest.raises(TypeError, match="integer"):
            Label(port_number=1.5, port_type=PortType.INPUT)  # type: ignore[arg-type]

    def test_string_port_raises_type_error(self):
        with pytest.raises(TypeError, match="integer"):
            Label(port_number="1", port_type=PortType.INPUT)  # type: ignore[arg-type]


class TestLabelPortTypeValidation:
    """port_type must be a PortType enum member."""

    def test_input_port_type_accepted(self):
        label = Label(port_number=1, port_type=PortType.INPUT)
        assert label.port_type == PortType.INPUT

    def test_output_port_type_accepted(self):
        label = Label(port_number=1, port_type=PortType.OUTPUT)
        assert label.port_type == PortType.OUTPUT

    def test_string_input_raises_type_error(self):
        """Raw string 'INPUT' is not a PortType enum."""
        with pytest.raises(TypeError, match="PortType"):
            Label(port_number=1, port_type="INPUT")  # type: ignore[arg-type]

    def test_string_output_raises_type_error(self):
        with pytest.raises(TypeError, match="PortType"):
            Label(port_number=1, port_type="OUTPUT")  # type: ignore[arg-type]

    def test_none_port_type_raises_type_error(self):
        with pytest.raises(TypeError, match="PortType"):
            Label(port_number=1, port_type=None)  # type: ignore[arg-type]

    def test_port_type_value_attribute(self):
        """Enum .value should match the string literal used in serialization."""
        assert PortType.INPUT.value == "INPUT"
        assert PortType.OUTPUT.value == "OUTPUT"


class TestLabelTextValidation:
    """Label text must be a string and must not exceed 255 characters."""

    def test_empty_current_label_is_valid(self):
        label = Label(port_number=1, port_type=PortType.INPUT, current_label="")
        assert label.current_label == ""

    def test_255_char_current_label_is_valid(self):
        long_label = "A" * 255
        label = Label(port_number=1, port_type=PortType.INPUT, current_label=long_label)
        assert len(label.current_label) == 255

    def test_256_char_current_label_raises_value_error(self):
        too_long = "A" * 256
        with pytest.raises(ValueError, match="maximum length"):
            Label(port_number=1, port_type=PortType.INPUT, current_label=too_long)

    def test_255_char_new_label_is_valid(self):
        long_label = "B" * 255
        label = Label(port_number=1, port_type=PortType.INPUT, new_label=long_label)
        assert len(label.new_label) == 255

    def test_256_char_new_label_raises_value_error(self):
        too_long = "B" * 256
        with pytest.raises(ValueError, match="maximum length"):
            Label(port_number=1, port_type=PortType.INPUT, new_label=too_long)

    def test_none_new_label_is_valid(self):
        label = Label(port_number=1, port_type=PortType.INPUT, new_label=None)
        assert label.new_label is None

    def test_non_string_current_label_raises_type_error(self):
        with pytest.raises(TypeError, match="string"):
            Label(port_number=1, port_type=PortType.INPUT, current_label=42)  # type: ignore[arg-type]

    def test_non_string_new_label_raises_type_error(self):
        with pytest.raises(TypeError, match="string"):
            Label(port_number=1, port_type=PortType.INPUT, new_label=123)  # type: ignore[arg-type]

    def test_special_characters_in_label_are_accepted(self):
        """Labels can contain unicode, slashes, and other special chars."""
        label = Label(
            port_number=1,
            port_type=PortType.INPUT,
            current_label='CAM/CTRL "A" — Ünïcödé',
        )
        assert "Ünïcödé" in label.current_label


class TestLabelHasChanges:
    """has_changes() returns True iff new_label is set and differs from current_label."""

    def test_no_new_label_has_no_changes(self):
        label = Label(port_number=1, port_type=PortType.INPUT, current_label="CAM 1")
        assert label.has_changes() is False

    def test_new_label_same_as_current_has_no_changes(self):
        label = Label(
            port_number=1,
            port_type=PortType.INPUT,
            current_label="CAM 1",
            new_label="CAM 1",
        )
        assert label.has_changes() is False

    def test_different_new_label_has_changes(self):
        label = Label(
            port_number=1,
            port_type=PortType.INPUT,
            current_label="CAM 1",
            new_label="CAM 2",
        )
        assert label.has_changes() is True


class TestLabelApplyChanges:
    """apply_changes() promotes new_label to current_label and clears new_label."""

    def test_apply_changes_updates_current_label(self):
        label = Label(
            port_number=1,
            port_type=PortType.INPUT,
            current_label="OLD",
            new_label="NEW",
        )
        label.apply_changes()
        assert label.current_label == "NEW"
        assert label.new_label is None

    def test_apply_changes_with_no_pending_change_is_noop(self):
        label = Label(port_number=1, port_type=PortType.INPUT, current_label="KEEP")
        label.apply_changes()
        assert label.current_label == "KEEP"
        assert label.new_label is None


class TestLabelSerialisation:
    """to_dict() and from_dict() must roundtrip without data loss."""

    def test_to_dict_contains_expected_keys(self):
        label = Label(
            port_number=5,
            port_type=PortType.OUTPUT,
            current_label="MON",
            new_label="MONITOR",
        )
        d = label.to_dict()
        assert d["port_number"] == 5
        assert d["port_type"] == "OUTPUT"
        assert d["current_label"] == "MON"
        assert d["new_label"] == "MONITOR"
        assert d["has_changes"] is True

    def test_from_dict_roundtrip(self):
        original = Label(
            port_number=10,
            port_type=PortType.INPUT,
            current_label="SRC",
            new_label=None,
        )
        restored = Label.from_dict(original.to_dict())
        assert restored.port_number == original.port_number
        assert restored.port_type == original.port_type
        assert restored.current_label == original.current_label
        assert restored.new_label == original.new_label

    def test_from_dict_accepts_string_port_type(self):
        """from_dict should handle the serialized string form 'INPUT'/'OUTPUT'."""
        label = Label.from_dict(
            {"port_number": 3, "port_type": "INPUT", "current_label": "X"}
        )
        assert label.port_type == PortType.INPUT

    def test_str_representation_includes_port_and_type(self):
        label = Label(port_number=7, port_type=PortType.OUTPUT, current_label="PGM")
        s = str(label)
        assert "7" in s
        assert "OUTPUT" in s
        assert "PGM" in s


# ===========================================================================
# Router model
# ===========================================================================


class TestConnectionStatusEnum:
    """ConnectionStatus enum must expose all four expected values."""

    def test_disconnected_value(self):
        assert ConnectionStatus.DISCONNECTED.value == "disconnected"

    def test_connecting_value(self):
        assert ConnectionStatus.CONNECTING.value == "connecting"

    def test_connected_value(self):
        assert ConnectionStatus.CONNECTED.value == "connected"

    def test_error_value(self):
        assert ConnectionStatus.ERROR.value == "error"

    def test_enum_has_exactly_four_members(self):
        assert len(ConnectionStatus) == 4


class TestRouterIPValidation:
    """Router rejects malformed IP addresses at construction time."""

    def test_valid_ip_address_accepted(self):
        router = Router(ip_address="192.168.1.100")
        assert router.ip_address == "192.168.1.100"

    def test_loopback_address_accepted(self):
        router = Router(ip_address="127.0.0.1")
        assert router.ip_address == "127.0.0.1"

    def test_empty_ip_raises_value_error(self):
        with pytest.raises(ValueError, match="empty"):
            Router(ip_address="")

    def test_non_string_ip_raises_type_error(self):
        with pytest.raises(TypeError, match="string"):
            Router(ip_address=192168)  # type: ignore[arg-type]

    def test_too_few_octets_raises_value_error(self):
        with pytest.raises(ValueError, match="Invalid IP"):
            Router(ip_address="192.168.1")

    def test_too_many_octets_raises_value_error(self):
        with pytest.raises(ValueError, match="Invalid IP"):
            Router(ip_address="192.168.1.1.1")

    def test_octet_out_of_range_raises_value_error(self):
        with pytest.raises(ValueError, match="Invalid IP"):
            Router(ip_address="192.168.1.256")

    def test_non_numeric_octet_raises_value_error(self):
        with pytest.raises(ValueError, match="Invalid IP"):
            Router(ip_address="192.168.1.abc")


class TestRouterConnectionStatusTransitions:
    """set_connected / set_disconnected / set_connecting / set_error transitions."""

    def test_default_status_is_disconnected(self):
        router = Router(ip_address="10.0.0.1")
        assert router.connection_status == ConnectionStatus.DISCONNECTED
        assert router.is_connected() is False

    def test_set_connected_updates_status_and_timestamp(self):
        router = Router(ip_address="10.0.0.1")
        router.set_connected()
        assert router.is_connected() is True
        assert router.last_connected is not None
        assert router.error_message is None

    def test_set_disconnected_clears_connected_flag(self):
        router = Router(ip_address="10.0.0.1")
        router.set_connected()
        router.set_disconnected()
        assert router.is_connected() is False
        assert router.connection_status == ConnectionStatus.DISCONNECTED

    def test_set_disconnected_stores_error_message(self):
        router = Router(ip_address="10.0.0.1")
        router.set_disconnected("timeout")
        assert router.error_message == "timeout"

    def test_set_connecting_sets_connecting_status(self):
        router = Router(ip_address="10.0.0.1")
        router.set_connecting()
        assert router.connection_status == ConnectionStatus.CONNECTING
        assert router.error_message is None

    def test_set_error_stores_message(self):
        router = Router(ip_address="10.0.0.1")
        router.set_error("auth failure")
        assert router.connection_status == ConnectionStatus.ERROR
        assert router.error_message == "auth failure"

    def test_invalid_connection_status_raises_type_error(self):
        with pytest.raises(TypeError, match="ConnectionStatus"):
            Router(ip_address="10.0.0.1", connection_status="connected")  # type: ignore[arg-type]


class TestRouterPortInfo:
    """update_port_info / get_port_info / get_all_ports / clear_port_info."""

    def test_update_and_retrieve_port_info(self):
        router = Router(ip_address="10.0.0.1")
        router.update_port_info(1, {"label": "CAM 1"})
        assert router.get_port_info(1) == {"label": "CAM 1"}

    def test_get_all_ports_returns_sorted_list(self):
        router = Router(ip_address="10.0.0.1")
        router.update_port_info(5, {})
        router.update_port_info(2, {})
        router.update_port_info(9, {})
        assert router.get_all_ports() == [2, 5, 9]

    def test_get_port_info_returns_none_for_unknown_port(self):
        router = Router(ip_address="10.0.0.1")
        assert router.get_port_info(99) is None

    def test_update_port_info_rejects_port_zero(self):
        router = Router(ip_address="10.0.0.1")
        with pytest.raises(ValueError, match="1 and 120"):
            router.update_port_info(0, {})

    def test_update_port_info_rejects_port_121(self):
        router = Router(ip_address="10.0.0.1")
        with pytest.raises(ValueError, match="1 and 120"):
            router.update_port_info(121, {})

    def test_clear_port_info_removes_all_ports(self):
        router = Router(ip_address="10.0.0.1")
        router.update_port_info(1, {})
        router.update_port_info(2, {})
        router.clear_port_info()
        assert router.get_all_ports() == []


class TestRouterSerialisation:
    """to_dict() / from_dict() roundtrip for Router."""

    def test_to_dict_contains_expected_keys(self):
        router = Router(ip_address="192.168.0.1")
        d = router.to_dict()
        assert d["ip_address"] == "192.168.0.1"
        assert d["connection_status"] == "disconnected"
        assert d["is_connected"] is False
        assert d["last_connected"] is None

    def test_from_dict_roundtrip_preserves_ip_and_status(self):
        original = Router(ip_address="10.1.2.3")
        original.set_connected()
        d = original.to_dict()
        restored = Router.from_dict(d)
        assert restored.ip_address == original.ip_address
        assert restored.connection_status == original.connection_status

    def test_str_representation_includes_ip_and_status(self):
        router = Router(ip_address="10.0.0.5")
        s = str(router)
        assert "10.0.0.5" in s
        assert "disconnected" in s


# ===========================================================================
# Event models
# ===========================================================================


class TestBaseEvent:
    """BaseEvent construction and type guards."""

    def test_default_event_type_is_system(self):
        event = BaseEvent()
        assert event.event_type == EventType.SYSTEM

    def test_timestamp_is_utc_datetime(self):
        event = BaseEvent()
        assert isinstance(event.timestamp, datetime)
        assert event.timestamp.tzinfo is not None

    def test_data_defaults_to_empty_dict(self):
        event = BaseEvent()
        assert event.data == {}

    def test_non_datetime_timestamp_raises_type_error(self):
        with pytest.raises(TypeError, match="datetime"):
            BaseEvent(timestamp="2025-01-01")  # type: ignore[arg-type]

    def test_non_eventtype_event_type_raises_type_error(self):
        with pytest.raises(TypeError, match="EventType"):
            BaseEvent(event_type="connection")  # type: ignore[arg-type]

    def test_non_dict_data_raises_type_error(self):
        with pytest.raises(TypeError, match="dictionary"):
            BaseEvent(data="bad")  # type: ignore[arg-type]


class TestConnectionEvent:
    """ConnectionEvent populates data dict and forces event_type = CONNECTION."""

    def test_event_type_forced_to_connection(self):
        event = ConnectionEvent(router_ip="10.0.0.1", connected=True)
        assert event.event_type == EventType.CONNECTION

    def test_data_dict_contains_router_ip(self):
        event = ConnectionEvent(router_ip="10.0.0.1", connected=True)
        assert event.data["router_ip"] == "10.0.0.1"

    def test_data_dict_contains_connected_flag(self):
        event = ConnectionEvent(router_ip="10.0.0.1", connected=False)
        assert event.data["connected"] is False

    def test_error_message_stored_in_data(self):
        event = ConnectionEvent(
            router_ip="10.0.0.1", connected=False, error_message="timeout"
        )
        assert event.data["error_message"] == "timeout"

    def test_successful_connection_has_null_error(self):
        event = ConnectionEvent(router_ip="10.0.0.1", connected=True)
        assert event.data["error_message"] is None


class TestLabelsEvent:
    """LabelsEvent populates data dict including label_count."""

    def test_event_type_forced_to_labels(self):
        event = LabelsEvent()
        assert event.event_type == EventType.LABELS

    def test_label_count_reflects_list_length(self):
        labels = [{"port": 1}, {"port": 2}, {"port": 3}]
        event = LabelsEvent(labels=labels)
        assert event.data["label_count"] == 3

    def test_empty_labels_list_produces_zero_count(self):
        event = LabelsEvent(labels=[])
        assert event.data["label_count"] == 0

    def test_source_and_operation_stored_in_data(self):
        event = LabelsEvent(source="file", operation="write")
        assert event.data["source"] == "file"
        assert event.data["operation"] == "write"


class TestValidationEvent:
    """ValidationEvent populates data dict with error/warning counts."""

    def test_event_type_forced_to_validation(self):
        event = ValidationEvent()
        assert event.event_type == EventType.VALIDATION

    def test_valid_event_has_error_count_zero(self):
        event = ValidationEvent(valid=True)
        assert event.data["error_count"] == 0

    def test_errors_list_reflected_in_count(self):
        event = ValidationEvent(valid=False, errors=["bad port", "bad type"])
        assert event.data["error_count"] == 2
        assert event.data["valid"] is False

    def test_warnings_list_reflected_in_count(self):
        event = ValidationEvent(warnings=["label truncated"])
        assert event.data["warning_count"] == 1

    def test_validated_item_stored_in_data(self):
        event = ValidationEvent(validated_item="labels")
        assert event.data["validated_item"] == "labels"


class TestFileEvent:
    """FileEvent populates data dict with file path and success flag."""

    def test_event_type_forced_to_file(self):
        event = FileEvent()
        assert event.event_type == EventType.FILE

    def test_file_path_stored_in_data(self):
        event = FileEvent(file_path="/tmp/labels.csv", operation="read", success=True)
        assert event.data["file_path"] == "/tmp/labels.csv"

    def test_success_flag_stored(self):
        event = FileEvent(success=True)
        assert event.data["success"] is True

    def test_failure_event_stores_error_message(self):
        event = FileEvent(success=False, error_message="permission denied")
        assert event.data["error_message"] == "permission denied"
        assert event.data["success"] is False


class TestEventTypeEnum:
    """EventType enum covers all expected domain event categories."""

    def test_all_event_types_present(self):
        names = {member.name for member in EventType}
        assert names == {"CONNECTION", "LABELS", "VALIDATION", "FILE", "SYSTEM"}

    def test_event_type_values(self):
        assert EventType.CONNECTION.value == "connection"
        assert EventType.LABELS.value == "labels"
        assert EventType.VALIDATION.value == "validation"
        assert EventType.FILE.value == "file"
        assert EventType.SYSTEM.value == "system"
