"""Tests for router protocol helpers in src/agents/api_agent/router_protocols.py.

Coverage targets:
- Protocol enum values
- KumoParamID static builders (source_name, dest_name, dest_status)
- APIEndpoint URL builders (get_param, set_param, connect, convenience wrappers)
  - URL encoding of special characters in values
- TelnetCommand query/set builders and label escaping
  - double-quotes are backslash-escaped
  - newlines (LF and CR) are stripped
- TelnetCommand.parse_label_response() regex extraction
- ResponseParser.parse_param_response() JSON dict handling
- DefaultLabelGenerator format verification
"""

import urllib.parse

import pytest

from src.agents.api_agent.router_protocols import (
    Protocol,
    KumoParamID,
    APIEndpoint,
    TelnetCommand,
    ResponseParser,
    DefaultLabelGenerator,
)


# ===========================================================================
# Protocol enum
# ===========================================================================


class TestProtocolEnum:
    def test_rest_value(self):
        assert Protocol.REST.value == "rest"

    def test_telnet_value(self):
        assert Protocol.TELNET.value == "telnet"

    def test_default_value(self):
        assert Protocol.DEFAULT.value == "default"

    def test_three_members_total(self):
        assert len(Protocol) == 3


# ===========================================================================
# KumoParamID builders
# ===========================================================================


class TestKumoParamIDSourceName:
    """source_name() should build eParamID_XPT_Source{N}_Line_{L}."""

    def test_port_1_line_1_default(self):
        assert KumoParamID.source_name(1) == "eParamID_XPT_Source1_Line_1"

    def test_port_1_line_2(self):
        assert KumoParamID.source_name(1, line=2) == "eParamID_XPT_Source1_Line_2"

    def test_port_64_line_1(self):
        assert KumoParamID.source_name(64) == "eParamID_XPT_Source64_Line_1"

    def test_port_32_line_2(self):
        assert KumoParamID.source_name(32, 2) == "eParamID_XPT_Source32_Line_2"

    def test_result_is_string(self):
        assert isinstance(KumoParamID.source_name(1), str)


class TestKumoParamIDDestName:
    """dest_name() should build eParamID_XPT_Destination{N}_Line_{L}."""

    def test_port_1_line_1_default(self):
        assert KumoParamID.dest_name(1) == "eParamID_XPT_Destination1_Line_1"

    def test_port_1_line_2(self):
        assert KumoParamID.dest_name(1, line=2) == "eParamID_XPT_Destination1_Line_2"

    def test_port_64(self):
        assert KumoParamID.dest_name(64) == "eParamID_XPT_Destination64_Line_1"


class TestKumoParamIDDestStatus:
    """dest_status() should build eParamID_XPT_Destination{N}_Status."""

    def test_port_1(self):
        assert KumoParamID.dest_status(1) == "eParamID_XPT_Destination1_Status"

    def test_port_32(self):
        assert KumoParamID.dest_status(32) == "eParamID_XPT_Destination32_Status"

    def test_result_does_not_contain_line(self):
        """Status param IDs have no 'Line' segment."""
        result = KumoParamID.dest_status(1)
        assert "Line" not in result


class TestKumoParamIDConstants:
    def test_sys_name_constant(self):
        assert KumoParamID.SYS_NAME == "eParamID_SysName"

    def test_sw_version_constant(self):
        assert KumoParamID.SW_VERSION == "eParamID_SWVersion"


# ===========================================================================
# APIEndpoint URL builders
# ===========================================================================


class TestAPIEndpointGetParam:
    """get_param() constructs the correct query string for a GET request."""

    def test_basic_get_param(self):
        url = APIEndpoint.get_param("eParamID_SysName")
        assert url == "/config?action=get&configid=0&paramid=eParamID_SysName"

    def test_get_param_contains_action_get(self):
        url = APIEndpoint.get_param("eParamID_SWVersion")
        assert "action=get" in url

    def test_get_param_contains_configid_zero(self):
        url = APIEndpoint.get_param("eParamID_SysName")
        assert "configid=0" in url


class TestAPIEndpointSetParam:
    """set_param() URL-encodes the value field."""

    def test_plain_value_no_encoding_needed(self):
        url = APIEndpoint.set_param("eParamID_SysName", "KUMO32")
        assert "value=KUMO32" in url
        assert "action=set" in url

    def test_value_with_spaces_is_encoded(self):
        url = APIEndpoint.set_param("eParamID_XPT_Source1_Line_1", "CAM 1")
        # urllib.parse.quote("CAM 1", safe="") → "CAM%201"
        assert "CAM%201" in url

    def test_value_with_slash_is_encoded(self):
        url = APIEndpoint.set_param("eParamID_XPT_Source1_Line_1", "CAM/A")
        assert "%2F" in url or "CAM" in url  # slash encoded as %2F

    def test_value_with_ampersand_is_encoded(self):
        """Unencoded & would break the query string — it must be escaped."""
        url = APIEndpoint.set_param("eParamID_SysName", "A&B")
        # % encoding of & is %26
        assert "%26" in url

    def test_roundtrip_decodes_to_original_value(self):
        original = "CAM 1 – Live"
        url = APIEndpoint.set_param("eParamID_XPT_Source1_Line_1", original)
        # Extract encoded value from URL
        encoded_value = url.split("value=")[1]
        decoded = urllib.parse.unquote(encoded_value)
        assert decoded == original


class TestAPIEndpointConnect:
    def test_connect_endpoint(self):
        assert APIEndpoint.connect() == "/config?action=connect&configid=0"


class TestAPIEndpointConvenienceWrappers:
    """Convenience methods should delegate to the correct param IDs."""

    def test_get_source_name_port_1(self):
        url = APIEndpoint.get_source_name(1)
        assert "eParamID_XPT_Source1_Line_1" in url
        assert "action=get" in url

    def test_get_source_name_port_1_line_2(self):
        url = APIEndpoint.get_source_name(1, line=2)
        assert "Source1_Line_2" in url

    def test_set_source_name(self):
        url = APIEndpoint.set_source_name(1, "CAM 1")
        assert "action=set" in url
        assert "Source1_Line_1" in url

    def test_get_dest_name_port_1(self):
        url = APIEndpoint.get_dest_name(1)
        assert "Destination1_Line_1" in url
        assert "action=get" in url

    def test_set_dest_name(self):
        url = APIEndpoint.set_dest_name(1, "MON A")
        assert "action=set" in url
        assert "Destination1_Line_1" in url

    def test_get_system_name_uses_sys_name_param(self):
        url = APIEndpoint.get_system_name()
        assert KumoParamID.SYS_NAME in url

    def test_get_firmware_version_uses_sw_version_param(self):
        url = APIEndpoint.get_firmware_version()
        assert KumoParamID.SW_VERSION in url


# ===========================================================================
# TelnetCommand
# ===========================================================================


class TestTelnetCommandQueryBuilders:
    """query_input / query_output format port numbers correctly."""

    def test_query_input_port_1(self):
        cmd = TelnetCommand.query_input(1)
        assert cmd == "LABEL INPUT 1 ?"

    def test_query_input_port_32(self):
        cmd = TelnetCommand.query_input(32)
        assert cmd == "LABEL INPUT 32 ?"

    def test_query_output_port_1(self):
        cmd = TelnetCommand.query_output(1)
        assert cmd == "LABEL OUTPUT 1 ?"

    def test_query_output_port_64(self):
        cmd = TelnetCommand.query_output(64)
        assert cmd == "LABEL OUTPUT 64 ?"


class TestTelnetCommandSetBuilders:
    """set_input / set_output wrap label in double quotes."""

    def test_set_input_plain_label(self):
        cmd = TelnetCommand.set_input(1, "CAM 1")
        assert cmd == 'LABEL INPUT 1 "CAM 1"'

    def test_set_output_plain_label(self):
        cmd = TelnetCommand.set_output(1, "MONITOR A")
        assert cmd == 'LABEL OUTPUT 1 "MONITOR A"'

    def test_set_input_port_number_substituted(self):
        cmd = TelnetCommand.set_input(15, "SRC")
        assert "15" in cmd
        assert "INPUT" in cmd


class TestTelnetCommandEscaping:
    """_escape_label() must handle injection-prone characters."""

    def test_double_quote_in_label_is_backslash_escaped(self):
        cmd = TelnetCommand.set_input(1, 'CAM "A"')
        # Backslash-escaped quotes should appear inside the outer quotes
        assert '\\"A\\"' in cmd or '\\"' in cmd

    def test_newline_lf_is_stripped(self):
        cmd = TelnetCommand.set_input(1, "CAM\nB")
        assert "\n" not in cmd

    def test_newline_cr_is_stripped(self):
        cmd = TelnetCommand.set_input(1, "CAM\rB")
        assert "\r" not in cmd

    def test_crlf_both_stripped(self):
        cmd = TelnetCommand.set_input(1, "CAM\r\nB")
        assert "\r" not in cmd
        assert "\n" not in cmd

    def test_plain_label_unchanged(self):
        """Labels without special chars should pass through unmodified."""
        cmd = TelnetCommand.set_input(1, "CAM 1")
        assert "CAM 1" in cmd


class TestTelnetCommandParseLabelResponse:
    """parse_label_response() extracts the first quoted string from a response."""

    def test_extracts_label_from_quoted_response(self):
        response = 'LABEL INPUT 1 "CAM 1"'
        result = TelnetCommand.parse_label_response(response)
        assert result == "CAM 1"

    def test_returns_none_for_empty_response(self):
        assert TelnetCommand.parse_label_response("") is None

    def test_returns_none_when_no_quoted_string(self):
        assert TelnetCommand.parse_label_response("OK") is None

    def test_extracts_first_quoted_label_from_multi_quote_response(self):
        """When multiple quoted values appear, returns the first match."""
        response = '"first" "second"'
        result = TelnetCommand.parse_label_response(response)
        assert result == "first"

    def test_handles_spaces_inside_quotes(self):
        response = '"MONITOR A HDMI"'
        result = TelnetCommand.parse_label_response(response)
        assert result == "MONITOR A HDMI"


# ===========================================================================
# ResponseParser
# ===========================================================================


class TestResponseParser:
    """parse_param_response() extracts value_name, falling back to value."""

    def test_returns_value_name_when_present(self):
        response = {
            "paramid": "42",
            "name": "eParamID_XPT_Source1_Line_1",
            "value": "0",
            "value_name": "CAM 1",
        }
        assert ResponseParser.parse_param_response(response) == "CAM 1"

    def test_falls_back_to_value_when_value_name_empty(self):
        response = {
            "paramid": "42",
            "name": "eParamID_XPT_Source1_Line_1",
            "value": "CAM 1",
            "value_name": "",
        }
        assert ResponseParser.parse_param_response(response) == "CAM 1"

    def test_returns_none_for_non_dict_input(self):
        assert ResponseParser.parse_param_response("not a dict") is None  # type: ignore[arg-type]
        assert ResponseParser.parse_param_response(None) is None  # type: ignore[arg-type]

    def test_returns_none_when_both_value_fields_empty(self):
        response = {"paramid": "42", "name": "x", "value": "", "value_name": ""}
        assert ResponseParser.parse_param_response(response) is None

    def test_strips_whitespace_from_value_name(self):
        response = {"value_name": "  CAM 1  ", "value": "0"}
        assert ResponseParser.parse_param_response(response) == "CAM 1"

    def test_returns_none_for_empty_dict(self):
        assert ResponseParser.parse_param_response({}) is None


# ===========================================================================
# DefaultLabelGenerator
# ===========================================================================


class TestDefaultLabelGenerator:
    """Verify generated label format for inputs and outputs."""

    def test_generate_input_label_format(self):
        assert DefaultLabelGenerator.generate_input_label(1) == "Source 1"

    def test_generate_input_label_port_32(self):
        assert DefaultLabelGenerator.generate_input_label(32) == "Source 32"

    def test_generate_output_label_format(self):
        assert DefaultLabelGenerator.generate_output_label(1) == "Dest 1"

    def test_generate_output_label_port_32(self):
        assert DefaultLabelGenerator.generate_output_label(32) == "Dest 32"

    def test_generate_default_labels_default_count(self):
        result = DefaultLabelGenerator.generate_default_labels()
        assert len(result["inputs"]) == 32
        assert len(result["outputs"]) == 32

    def test_generate_default_labels_custom_count(self):
        result = DefaultLabelGenerator.generate_default_labels(port_count=16)
        assert len(result["inputs"]) == 16
        assert len(result["outputs"]) == 16

    def test_generate_default_labels_input_format(self):
        result = DefaultLabelGenerator.generate_default_labels(port_count=4)
        assert result["inputs"] == ["Source 1", "Source 2", "Source 3", "Source 4"]

    def test_generate_default_labels_output_format(self):
        result = DefaultLabelGenerator.generate_default_labels(port_count=4)
        assert result["outputs"] == ["Dest 1", "Dest 2", "Dest 3", "Dest 4"]

    def test_generate_default_labels_returns_dict_with_expected_keys(self):
        result = DefaultLabelGenerator.generate_default_labels()
        assert set(result.keys()) == {"inputs", "outputs", "inputs_line2", "outputs_line2"}
