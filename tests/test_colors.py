"""Tests for KUMO button color feature.

Coverage targets:
- KUMO_COLORS dict structure and completeness
- ResponseParser.parse_button_color() — JSON, raw-string, fallback
- ResponseParser.encode_button_color() — valid and out-of-range IDs
- KumoParamID.button_color() — input vs output index mapping
- APIEndpoint.get_button_color() / set_button_color() URL construction
- Label model color validation (current_color, new_color)
- Label.has_changes() / apply_changes() / apply_color_change() with colors
- Label.to_dict() / from_dict() color roundtrip
- Label.__str__() color change display
- _extract_base_name() edge cases
- assign_like_name_colors() grouping and cycling
"""

import pytest

from src.agents.api_agent.router_protocols import (
    KUMO_COLORS,
    KUMO_DEFAULT_COLOR,
    KumoParamID,
    APIEndpoint,
    ResponseParser,
)
from src.models.label import Label, PortType
from src.cli import _extract_base_name, assign_like_name_colors, _color_block


# ===========================================================================
# KUMO_COLORS dictionary
# ===========================================================================


class TestKumoColors:
    def test_has_nine_entries(self):
        assert len(KUMO_COLORS) == 9

    def test_ids_are_1_through_9(self):
        assert set(KUMO_COLORS.keys()) == set(range(1, 10))

    def test_default_color_is_blue(self):
        assert KUMO_DEFAULT_COLOR == 4
        assert KUMO_COLORS[4][0] == "Blue"

    def test_each_entry_has_name_idle_active(self):
        for color_id, entry in KUMO_COLORS.items():
            assert len(entry) == 3, f"Color {color_id} should have (name, idle_hex, active_hex)"
            name, idle, active = entry
            assert isinstance(name, str) and name
            assert idle.startswith("#") and len(idle) == 7
            assert active.startswith("#") and len(active) == 7


# ===========================================================================
# ResponseParser.parse_button_color
# ===========================================================================


class TestParseButtonColor:
    def test_json_format(self):
        assert ResponseParser.parse_button_color('{"classes":"color_1"}') == 1

    def test_json_format_all_colors(self):
        for i in range(1, 10):
            assert ResponseParser.parse_button_color(f'{{"classes":"color_{i}"}}') == i

    def test_raw_string_format(self):
        assert ResponseParser.parse_button_color("color_5") == 5

    def test_none_returns_default(self):
        assert ResponseParser.parse_button_color(None) == KUMO_DEFAULT_COLOR

    def test_empty_string_returns_default(self):
        assert ResponseParser.parse_button_color("") == KUMO_DEFAULT_COLOR

    def test_garbage_returns_default(self):
        assert ResponseParser.parse_button_color("nonsense_data") == KUMO_DEFAULT_COLOR

    def test_out_of_range_high_returns_default(self):
        assert ResponseParser.parse_button_color('{"classes":"color_10"}') == KUMO_DEFAULT_COLOR

    def test_out_of_range_zero_returns_default(self):
        assert ResponseParser.parse_button_color('{"classes":"color_0"}') == KUMO_DEFAULT_COLOR

    def test_malformed_json_falls_back_to_raw(self):
        # Not valid JSON but contains color_3
        assert ResponseParser.parse_button_color("{color_3}") == 3


# ===========================================================================
# ResponseParser.encode_button_color
# ===========================================================================


class TestEncodeButtonColor:
    def test_encode_valid_color(self):
        result = ResponseParser.encode_button_color(1)
        assert '"classes"' in result
        assert '"color_1"' in result

    def test_encode_all_valid_colors(self):
        for i in range(1, 10):
            result = ResponseParser.encode_button_color(i)
            assert f'"color_{i}"' in result

    def test_encode_out_of_range_clamps_to_default(self):
        result = ResponseParser.encode_button_color(0)
        assert f'"color_{KUMO_DEFAULT_COLOR}"' in result

    def test_encode_negative_clamps_to_default(self):
        result = ResponseParser.encode_button_color(-1)
        assert f'"color_{KUMO_DEFAULT_COLOR}"' in result

    def test_encode_too_high_clamps_to_default(self):
        result = ResponseParser.encode_button_color(10)
        assert f'"color_{KUMO_DEFAULT_COLOR}"' in result


# ===========================================================================
# KumoParamID.button_color
# ===========================================================================


class TestButtonColorParamID:
    def test_input_port_1(self):
        assert KumoParamID.button_color(1, "INPUT") == "eParamID_Button_Settings_1"

    def test_input_port_64(self):
        assert KumoParamID.button_color(64, "INPUT") == "eParamID_Button_Settings_64"

    def test_output_port_1(self):
        assert KumoParamID.button_color(1, "OUTPUT") == "eParamID_Button_Settings_65"

    def test_output_port_64(self):
        assert KumoParamID.button_color(64, "OUTPUT") == "eParamID_Button_Settings_128"

    def test_case_insensitive_output(self):
        assert KumoParamID.button_color(1, "output") == "eParamID_Button_Settings_65"

    def test_case_insensitive_input(self):
        assert KumoParamID.button_color(5, "input") == "eParamID_Button_Settings_5"


# ===========================================================================
# APIEndpoint.get_button_color / set_button_color
# ===========================================================================


class TestButtonColorEndpoints:
    def test_get_button_color_contains_param(self):
        url = APIEndpoint.get_button_color(1, "INPUT")
        assert "eParamID_Button_Settings_1" in url
        assert "action=get" in url

    def test_set_button_color_contains_value(self):
        url = APIEndpoint.set_button_color(1, "INPUT", 3)
        assert "eParamID_Button_Settings_1" in url
        assert "action=set" in url
        assert "color_3" in url


# ===========================================================================
# Label model — color validation
# ===========================================================================


class TestLabelColorValidation:
    def test_default_color_is_blue(self):
        label = Label(port_number=1, port_type=PortType.INPUT)
        assert label.current_color == 4
        assert label.new_color is None

    def test_valid_colors_1_through_9(self):
        for c in range(1, 10):
            label = Label(port_number=1, port_type=PortType.INPUT, current_color=c)
            assert label.current_color == c

    def test_color_0_raises_value_error(self):
        with pytest.raises(ValueError, match="1 and 9"):
            Label(port_number=1, port_type=PortType.INPUT, current_color=0)

    def test_color_10_raises_value_error(self):
        with pytest.raises(ValueError, match="1 and 9"):
            Label(port_number=1, port_type=PortType.INPUT, current_color=10)

    def test_color_negative_raises_value_error(self):
        with pytest.raises(ValueError, match="1 and 9"):
            Label(port_number=1, port_type=PortType.INPUT, current_color=-1)

    def test_new_color_none_is_valid(self):
        label = Label(port_number=1, port_type=PortType.INPUT, new_color=None)
        assert label.new_color is None

    def test_new_color_valid(self):
        label = Label(port_number=1, port_type=PortType.INPUT, new_color=7)
        assert label.new_color == 7

    def test_new_color_0_raises_value_error(self):
        with pytest.raises(ValueError, match="1 and 9"):
            Label(port_number=1, port_type=PortType.INPUT, new_color=0)

    def test_new_color_string_raises_type_error(self):
        with pytest.raises(TypeError, match="integer"):
            Label(port_number=1, port_type=PortType.INPUT, new_color="red")

    def test_current_color_string_raises_type_error(self):
        with pytest.raises(TypeError, match="integer"):
            Label(port_number=1, port_type=PortType.INPUT, current_color="4")


# ===========================================================================
# Label.has_changes / apply_changes / apply_color_change with color
# ===========================================================================


class TestLabelColorChanges:
    def test_no_color_change_by_default(self):
        label = Label(port_number=1, port_type=PortType.INPUT, current_color=4)
        assert not label.has_changes()

    def test_color_change_detected(self):
        label = Label(port_number=1, port_type=PortType.INPUT, current_color=4, new_color=1)
        assert label.has_changes()

    def test_same_color_no_change(self):
        label = Label(port_number=1, port_type=PortType.INPUT, current_color=4, new_color=4)
        assert not label.has_changes()

    def test_apply_changes_promotes_color(self):
        label = Label(port_number=1, port_type=PortType.INPUT, current_color=4, new_color=1)
        label.apply_changes()
        assert label.current_color == 1
        assert label.new_color is None

    def test_apply_color_change_only_touches_color(self):
        label = Label(
            port_number=1, port_type=PortType.INPUT,
            current_label="OLD", new_label="NEW",
            current_color=4, new_color=1,
        )
        label.apply_color_change()
        assert label.current_color == 1
        assert label.new_color is None
        # Text change should still be pending
        assert label.new_label == "NEW"
        assert label.current_label == "OLD"

    def test_str_includes_color_change(self):
        label = Label(port_number=1, port_type=PortType.INPUT, current_color=4, new_color=1)
        s = str(label)
        assert "Color: 4 -> 1" in s

    def test_str_no_color_change(self):
        label = Label(port_number=1, port_type=PortType.INPUT, current_color=4)
        s = str(label)
        assert "Color" not in s


# ===========================================================================
# Label.to_dict / from_dict color roundtrip
# ===========================================================================


class TestLabelColorRoundtrip:
    def test_to_dict_includes_colors(self):
        label = Label(port_number=1, port_type=PortType.INPUT, current_color=3, new_color=7)
        d = label.to_dict()
        assert d["current_color"] == 3
        assert d["new_color"] == 7

    def test_from_dict_with_colors(self):
        d = {
            "port_number": 1,
            "port_type": "INPUT",
            "current_color": 5,
            "new_color": 8,
        }
        label = Label.from_dict(d)
        assert label.current_color == 5
        assert label.new_color == 8

    def test_from_dict_missing_color_defaults_to_blue(self):
        d = {"port_number": 1, "port_type": "INPUT"}
        label = Label.from_dict(d)
        assert label.current_color == 4
        assert label.new_color is None

    def test_roundtrip(self):
        original = Label(port_number=5, port_type=PortType.OUTPUT, current_color=9, new_color=2)
        restored = Label.from_dict(original.to_dict())
        assert restored.current_color == original.current_color
        assert restored.new_color == original.new_color


# ===========================================================================
# _extract_base_name
# ===========================================================================


class TestExtractBaseName:
    def test_trailing_number(self):
        assert _extract_base_name("CAM 1") == "CAM"

    def test_trailing_dash_number(self):
        assert _extract_base_name("Monitor-3") == "Monitor"

    def test_trailing_underscore_number(self):
        assert _extract_base_name("DECK_01") == "DECK"

    def test_trailing_dot_number(self):
        assert _extract_base_name("MIX.2") == "MIX"

    def test_no_trailing_number(self):
        assert _extract_base_name("PLAYBACK") == "PLAYBACK"

    def test_leading_number(self):
        assert _extract_base_name("1CAM") == "1CAM"

    def test_all_digits_returns_original(self):
        assert _extract_base_name("123") == "123"

    def test_empty_string_returns_empty(self):
        assert _extract_base_name("") == ""

    def test_whitespace_stripped(self):
        assert _extract_base_name("  CAM 1  ") == "CAM"

    def test_multiple_trailing_separators(self):
        assert _extract_base_name("CAM - 01") == "CAM"


# ===========================================================================
# assign_like_name_colors
# ===========================================================================


class TestAssignLikeNameColors:
    """Uses a minimal stub for RouterLabel since we only need current_label."""

    class StubLabel:
        def __init__(self, current_label, new_color=None):
            self.current_label = current_label
            self.new_color = new_color

    def test_groups_by_base_name(self):
        labels = [
            self.StubLabel("CAM 1"),
            self.StubLabel("CAM 2"),
            self.StubLabel("MON 1"),
            self.StubLabel("MON 2"),
        ]
        result = assign_like_name_colors(labels)
        assert "cam" in result
        assert "mon" in result
        assert len(result) == 2

    def test_skips_single_member_groups(self):
        labels = [
            self.StubLabel("CAM 1"),
            self.StubLabel("CAM 2"),
            self.StubLabel("SOLO"),
        ]
        result = assign_like_name_colors(labels)
        assert "cam" in result
        assert "solo" not in result

    def test_skips_empty_labels(self):
        labels = [
            self.StubLabel(""),
            self.StubLabel("  "),
            self.StubLabel("CAM 1"),
            self.StubLabel("CAM 2"),
        ]
        result = assign_like_name_colors(labels)
        assert len(result) == 1

    def test_colors_skip_blue_default(self):
        labels = [
            self.StubLabel("CAM 1"),
            self.StubLabel("CAM 2"),
        ]
        result = assign_like_name_colors(labels)
        assert result["cam"] != 4  # Blue is skipped

    def test_color_cycling(self):
        from src.cli import LIKE_NAMES_COLOR_CYCLE
        # Create 9 groups (more than palette size of 8) to test cycling
        groups = []
        for letter in "ABCDEFGHI":
            groups.append(self.StubLabel(f"{letter} 1"))
            groups.append(self.StubLabel(f"{letter} 2"))
        result = assign_like_name_colors(groups)
        assert len(result) == 9
        # 9th group should cycle back to first color
        sorted_keys = sorted(result.keys())
        assert result[sorted_keys[8]] == LIKE_NAMES_COLOR_CYCLE[8 % len(LIKE_NAMES_COLOR_CYCLE)]


# ===========================================================================
# _color_block
# ===========================================================================


class TestColorBlock:
    def test_valid_color_returns_markup(self):
        result = _color_block(1)
        assert "[on #cb7676]" in result

    def test_invalid_color_returns_spaces(self):
        result = _color_block(99)
        assert result == "  "

    def test_all_valid_colors_return_markup(self):
        for i in range(1, 10):
            result = _color_block(i)
            assert "[on " in result
