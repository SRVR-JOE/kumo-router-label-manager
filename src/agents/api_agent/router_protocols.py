"""Protocol definitions and constants for AJA KUMO router communication.

This module defines the communication protocols, API endpoints, and response
parsers for different KUMO router API formats.

The AJA KUMO REST API uses:
  GET  /config?action=get&configid=0&paramid={paramid}
  GET  /config?action=set&configid=0&paramid={paramid}&value={value}
  GET  /config?action=connect&configid=0              (get connection ID)
  POST /authenticator/login                           (if auth enabled)

Key eParamID values for labels:
  eParamID_XPT_Source{N}_Line_1      - Source (input) name, line 1
  eParamID_XPT_Source{N}_Line_2      - Source (input) name, line 2
  eParamID_XPT_Destination{N}_Line_1 - Destination (output) name, line 1
  eParamID_XPT_Destination{N}_Line_2 - Destination (output) name, line 2
  eParamID_XPT_Destination{N}_Status - Crosspoint: which source routed to dest N
  eParamID_SysName                   - Router system name
  eParamID_SWVersion                 - Firmware version
"""

import json
from enum import Enum
from typing import Dict, List, Optional, Any, Tuple
import re
import urllib.parse


# ---------------------------------------------------------------------------
# KUMO Button Color Presets (1-9)
# ---------------------------------------------------------------------------

KUMO_COLORS: Dict[int, Tuple[str, str, str]] = {
    # id: (name, idle_hex, active_hex)
    1: ("Red",         "#cb7676", "#fe0000"),
    2: ("Orange",      "#e6a52e", "#f76700"),
    3: ("Yellow",      "#d9cb7e", "#d7af00"),
    4: ("Blue",        "#87b4c8", "#009af4"),
    5: ("Teal",        "#64c896", "#00a263"),
    6: ("Light Green", "#ade68e", "#60b71f"),
    7: ("Indigo",      "#7888cb", "#3a5ef6"),
    8: ("Purple",      "#9b8ce1", "#8100f4"),
    9: ("Pink",        "#c84b91", "#f30088"),
}

KUMO_DEFAULT_COLOR = 4  # Blue


class Protocol(Enum):
    """Communication protocols supported by KUMO routers."""

    REST = "rest"
    TELNET = "telnet"
    DEFAULT = "default"


class KumoParamID:
    """AJA KUMO eParamID constants."""

    SYS_NAME = "eParamID_SysName"
    SW_VERSION = "eParamID_SWVersion"

    @staticmethod
    def source_name(port: int, line: int = 1) -> str:
        """Get eParamID for source (input) name.

        Args:
            port: Port number (1-64)
            line: Name line (1 or 2, KUMO supports 2-line names)
        """
        return f"eParamID_XPT_Source{port}_Line_{line}"

    @staticmethod
    def dest_name(port: int, line: int = 1) -> str:
        """Get eParamID for destination (output) name.

        Args:
            port: Port number (1-64)
            line: Name line (1 or 2)
        """
        return f"eParamID_XPT_Destination{port}_Line_{line}"

    @staticmethod
    def dest_status(port: int) -> str:
        """Get eParamID for crosspoint status (which source is routed to dest).

        Args:
            port: Destination port number (1-64)
        """
        return f"eParamID_XPT_Destination{port}_Status"

    @staticmethod
    def button_color(port: int, port_type: str) -> str:
        """Get eParamID for button color setting.

        Button settings use interleaved blocks of 16:
          Sources 1-16  -> 1-16,   Destinations 1-16  -> 17-32,
          Sources 17-32 -> 33-48,  Destinations 17-32 -> 49-64,
          Sources 33-48 -> 65-80,  Sources 49-64      -> 81-96,
          Destinations 33-48 -> 97-112, Destinations 49-64 -> 113-128.

        Args:
            port: Port number (1-64)
            port_type: 'input' or 'output' (case-insensitive)
        """
        block = (port - 1) // 16          # 0, 1, 2, 3
        offset_in_block = (port - 1) % 16  # 0..15
        base = block * 32 + offset_in_block + 1
        if port_type.upper() == "OUTPUT":
            base += 16
        return f"eParamID_Button_Settings_{base}"


class APIEndpoint:
    """REST API endpoint builder for AJA KUMO routers.

    All KUMO REST calls go through /config with query parameters.
    """

    @staticmethod
    def get_param(param_id: str) -> str:
        """Build GET endpoint for reading a parameter.

        Args:
            param_id: eParamID string

        Returns:
            URL path with query string
        """
        return f"/config?action=get&configid=0&paramid={param_id}"

    @staticmethod
    def set_param(param_id: str, value: str) -> str:
        """Build SET endpoint for writing a parameter.

        Args:
            param_id: eParamID string
            value: Value to set (will be URL-encoded)

        Returns:
            URL path with query string
        """
        encoded = urllib.parse.quote(value, safe="")
        return f"/config?action=set&configid=0&paramid={param_id}&value={encoded}"

    @staticmethod
    def connect() -> str:
        """Build connection endpoint (gets a connection/session ID)."""
        return "/config?action=connect&configid=0"

    @staticmethod
    def get_source_name(port: int, line: int = 1) -> str:
        """Build endpoint to get source (input) name."""
        return APIEndpoint.get_param(KumoParamID.source_name(port, line))

    @staticmethod
    def set_source_name(port: int, value: str, line: int = 1) -> str:
        """Build endpoint to set source (input) name."""
        return APIEndpoint.set_param(KumoParamID.source_name(port, line), value)

    @staticmethod
    def get_dest_name(port: int, line: int = 1) -> str:
        """Build endpoint to get destination (output) name."""
        return APIEndpoint.get_param(KumoParamID.dest_name(port, line))

    @staticmethod
    def set_dest_name(port: int, value: str, line: int = 1) -> str:
        """Build endpoint to set destination (output) name."""
        return APIEndpoint.set_param(KumoParamID.dest_name(port, line), value)

    @staticmethod
    def get_system_name() -> str:
        """Build endpoint to get router system name."""
        return APIEndpoint.get_param(KumoParamID.SYS_NAME)

    @staticmethod
    def get_firmware_version() -> str:
        """Build endpoint to get firmware version."""
        return APIEndpoint.get_param(KumoParamID.SW_VERSION)

    @staticmethod
    def get_button_color(port: int, port_type: str) -> str:
        """Build endpoint to get button color."""
        return APIEndpoint.get_param(KumoParamID.button_color(port, port_type))

    @staticmethod
    def set_button_color(port: int, port_type: str, color_id: int) -> str:
        """Build endpoint to set button color."""
        value = ResponseParser.encode_button_color(color_id)
        return APIEndpoint.set_param(
            KumoParamID.button_color(port, port_type), value
        )


class TelnetCommand:
    """Telnet command definitions for KUMO routers."""

    QUERY_INPUT_LABEL = "LABEL INPUT {port} ?"
    QUERY_OUTPUT_LABEL = "LABEL OUTPUT {port} ?"
    SET_INPUT_LABEL = 'LABEL INPUT {port} "{label}"'
    SET_OUTPUT_LABEL = 'LABEL OUTPUT {port} "{label}"'
    LABEL_RESPONSE_PATTERN = re.compile(r'"([^"]+)"')

    @classmethod
    def query_input(cls, port: int) -> str:
        return cls.QUERY_INPUT_LABEL.format(port=port)

    @classmethod
    def query_output(cls, port: int) -> str:
        return cls.QUERY_OUTPUT_LABEL.format(port=port)

    @classmethod
    def _escape_label(cls, label: str) -> str:
        """Escape special characters to prevent telnet command injection."""
        escaped = label.replace('"', '\\"')
        escaped = escaped.replace('\n', '').replace('\r', '')
        return escaped

    @classmethod
    def set_input(cls, port: int, label: str) -> str:
        escaped_label = cls._escape_label(label)
        return cls.SET_INPUT_LABEL.format(port=port, label=escaped_label)

    @classmethod
    def set_output(cls, port: int, label: str) -> str:
        escaped_label = cls._escape_label(label)
        return cls.SET_OUTPUT_LABEL.format(port=port, label=escaped_label)

    @classmethod
    def parse_label_response(cls, response: str) -> Optional[str]:
        if not response:
            return None
        match = cls.LABEL_RESPONSE_PATTERN.search(response)
        return match.group(1) if match else None


class ResponseParser:
    """Parse JSON responses from KUMO REST API."""

    @staticmethod
    def parse_param_response(response: Dict[str, Any]) -> Optional[str]:
        """Parse a /config?action=get response.

        AJA KUMO returns JSON like:
            {"paramid":"...", "name":"eParamID_...", "value":"...", "value_name":"..."}

        Args:
            response: Parsed JSON dict from the API

        Returns:
            The value string, or None
        """
        if not isinstance(response, dict):
            return None

        # value_name has the human-readable form
        if response.get("value_name") and str(response["value_name"]).strip():
            return str(response["value_name"]).strip()

        # Fall back to value
        if response.get("value") and str(response["value"]).strip():
            return str(response["value"]).strip()

        return None

    @staticmethod
    def parse_button_color(value: Optional[str]) -> int:
        """Parse button color from API response value.

        The API returns JSON like: {"classes":"color_N"}

        Args:
            value: Raw value string from the API response

        Returns:
            Color ID (1-9), defaults to KUMO_DEFAULT_COLOR (4/Blue)
        """
        if not value:
            return KUMO_DEFAULT_COLOR
        # Try JSON format first: {"classes":"color_N"}
        try:
            data = json.loads(value)
            classes = data.get("classes", "")
            match = re.search(r"color_(\d+)", classes)
            if match:
                color_id = int(match.group(1))
                if 1 <= color_id <= 9:
                    return color_id
        except (json.JSONDecodeError, AttributeError, TypeError):
            pass
        # Fallback: search raw string for color_N pattern
        match = re.search(r"color_(\d+)", value)
        if match:
            color_id = int(match.group(1))
            if 1 <= color_id <= 9:
                return color_id
        return KUMO_DEFAULT_COLOR

    @staticmethod
    def encode_button_color(color_id: int) -> str:
        r"""Encode a color ID into the JSON value for the SET API.

        The KUMO web UI sends values with escaped inner quotes so that the
        stored string is valid JSON-within-JSON.  The returned string looks
        like: {\"classes\":\"color_N\"}

        Args:
            color_id: Color ID (1-9)

        Returns:
            Escaped JSON string like {\"classes\":\"color_N\"}
        """
        if not 1 <= color_id <= 9:
            color_id = KUMO_DEFAULT_COLOR
        return '{{\\"classes\\":\\"color_{0}\\"}}'.format(color_id)


class DefaultLabelGenerator:
    """Generator for default labels when router communication fails."""

    @staticmethod
    def generate_default_labels(port_count: int = 32) -> Dict[str, List[str]]:
        return {
            "inputs": [f"Source {i + 1}" for i in range(port_count)],
            "outputs": [f"Dest {i + 1}" for i in range(port_count)],
            "inputs_line2": [""] * port_count,
            "outputs_line2": [""] * port_count,
        }

    @staticmethod
    def generate_input_label(port: int) -> str:
        return f"Source {port}"

    @staticmethod
    def generate_output_label(port: int) -> str:
        return f"Dest {port}"


# Timeout constants (seconds) - tuned for LAN connectivity.
# These serve as fallback defaults; override via Settings (HLX_ env vars).
TIMEOUT_REST_REQUEST = 4
TIMEOUT_TELNET_CONNECT = 3
TIMEOUT_TELNET_COMMAND = 2

# Delay constants (seconds) - override via Settings.
DELAY_TELNET_INITIAL = 0.5
DELAY_TELNET_COMMAND = 0.1

# Retry constants - override via Settings.
MAX_RETRIES = 2
RETRY_BACKOFF_BASE = 0.3
RETRY_BACKOFF_MULTIPLIER = 2
