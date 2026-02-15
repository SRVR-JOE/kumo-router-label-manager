"""Protocol definitions and constants for AJA KUMO router communication.

This module defines the communication protocols, API endpoints, and response
parsers for different KUMO router API formats.
"""

from enum import Enum
from typing import Dict, List, Optional, Any
import re


class Protocol(Enum):
    """Communication protocols supported by KUMO routers."""

    REST_BULK = "rest_bulk"
    REST_INDIVIDUAL = "rest_individual"
    TELNET = "telnet"
    DEFAULT = "default"


class APIEndpoint:
    """REST API endpoint definitions for KUMO routers."""

    # Bulk configuration endpoints
    BULK_CONFIG = "/api/config"
    BULK_STATUS = "/api/status"
    CGI_CONFIG = "/cgi-bin/config"
    CONFIG_JSON = "/config.json"
    STATUS_JSON = "/status.json"

    # Individual port endpoints
    INPUT_PORT = "/api/inputs/{port}"
    OUTPUT_PORT = "/api/outputs/{port}"
    CGI_GET_LABEL = "/cgi-bin/getlabel?type={port_type}&port={port}"

    # Update endpoints
    INPUT_LABEL_UPDATE = "/api/inputs/{port}/label"
    OUTPUT_LABEL_UPDATE = "/api/outputs/{port}/label"
    CGI_SET_LABEL = "/cgi-bin/setlabel"

    @classmethod
    def get_bulk_endpoints(cls) -> List[str]:
        """Get list of bulk configuration endpoints to try.

        Returns:
            List of endpoint URLs in priority order
        """
        return [
            cls.BULK_CONFIG,
            cls.BULK_STATUS,
            cls.CGI_CONFIG,
            cls.CONFIG_JSON,
            cls.STATUS_JSON,
        ]

    @classmethod
    def get_individual_input_endpoints(cls, port: int) -> List[str]:
        """Get list of individual input port endpoints to try.

        Args:
            port: Port number (1-32)

        Returns:
            List of endpoint URLs with port number substituted
        """
        return [
            cls.INPUT_PORT.format(port=port),
            cls.CGI_GET_LABEL.format(port_type="input", port=port),
        ]

    @classmethod
    def get_individual_output_endpoints(cls, port: int) -> List[str]:
        """Get list of individual output port endpoints to try.

        Args:
            port: Port number (1-32)

        Returns:
            List of endpoint URLs with port number substituted
        """
        return [
            cls.OUTPUT_PORT.format(port=port),
            cls.CGI_GET_LABEL.format(port_type="output", port=port),
        ]


class TelnetCommand:
    """Telnet command definitions for KUMO routers."""

    # Query commands
    QUERY_INPUT_LABEL = "LABEL INPUT {port} ?"
    QUERY_OUTPUT_LABEL = "LABEL OUTPUT {port} ?"

    # Set commands
    SET_INPUT_LABEL = 'LABEL INPUT {port} "{label}"'
    SET_OUTPUT_LABEL = 'LABEL OUTPUT {port} "{label}"'

    # Response pattern for label queries (captures quoted label)
    LABEL_RESPONSE_PATTERN = re.compile(r'"([^"]+)"')

    @classmethod
    def query_input(cls, port: int) -> str:
        """Get query command for input port label.

        Args:
            port: Port number (1-32)

        Returns:
            Telnet command string
        """
        return cls.QUERY_INPUT_LABEL.format(port=port)

    @classmethod
    def query_output(cls, port: int) -> str:
        """Get query command for output port label.

        Args:
            port: Port number (1-32)

        Returns:
            Telnet command string
        """
        return cls.QUERY_OUTPUT_LABEL.format(port=port)

    @classmethod
    def set_input(cls, port: int, label: str) -> str:
        """Get set command for input port label.

        Args:
            port: Port number (1-32)
            label: Label text to set

        Returns:
            Telnet command string
        """
        # Escape quotes in label
        escaped_label = label.replace('"', '\\"')
        return cls.SET_INPUT_LABEL.format(port=port, label=escaped_label)

    @classmethod
    def set_output(cls, port: int, label: str) -> str:
        """Get set command for output port label.

        Args:
            port: Port number (1-32)
            label: Label text to set

        Returns:
            Telnet command string
        """
        # Escape quotes in label
        escaped_label = label.replace('"', '\\"')
        return cls.SET_OUTPUT_LABEL.format(port=port, label=escaped_label)

    @classmethod
    def parse_label_response(cls, response: str) -> Optional[str]:
        """Parse label from telnet response.

        Args:
            response: Raw telnet response string

        Returns:
            Extracted label text, or None if parsing failed
        """
        if not response:
            return None

        match = cls.LABEL_RESPONSE_PATTERN.search(response)
        if match:
            return match.group(1)

        return None


class ResponseParser:
    """Parsers for different KUMO router API response formats."""

    @staticmethod
    def parse_bulk_config(response: Dict[str, Any]) -> Optional[Dict[str, List[str]]]:
        """Parse bulk configuration response.

        Args:
            response: JSON response from bulk config endpoint

        Returns:
            Dictionary with 'inputs' and 'outputs' lists of labels, or None if invalid
        """
        try:
            result = {"inputs": [], "outputs": []}

            # Try direct format: {inputs: [...], outputs: [...]}
            if "inputs" in response:
                for i in range(32):
                    if i < len(response["inputs"]):
                        item = response["inputs"][i]
                        label = item.get("label", f"Input {i + 1}") if isinstance(item, dict) else str(item)
                        result["inputs"].append(label)
                    else:
                        result["inputs"].append(f"Input {i + 1}")

            if "outputs" in response:
                for i in range(32):
                    if i < len(response["outputs"]):
                        item = response["outputs"][i]
                        label = item.get("label", f"Output {i + 1}") if isinstance(item, dict) else str(item)
                        result["outputs"].append(label)
                    else:
                        result["outputs"].append(f"Output {i + 1}")

            # Return only if we found at least some labels
            if result["inputs"] or result["outputs"]:
                return result

            return None

        except (KeyError, TypeError, IndexError):
            return None

    @staticmethod
    def parse_individual_port(response: Any) -> Optional[str]:
        """Parse individual port query response.

        Args:
            response: JSON response from individual port endpoint

        Returns:
            Label text, or None if parsing failed
        """
        try:
            # Try dictionary format with 'label' key
            if isinstance(response, dict) and "label" in response:
                return str(response["label"])

            # Try string format
            if isinstance(response, str) and response.strip():
                return response.strip()

            return None

        except (KeyError, TypeError):
            return None


class DefaultLabelGenerator:
    """Generator for default labels when router communication fails."""

    @staticmethod
    def generate_default_labels() -> Dict[str, List[str]]:
        """Generate default labels for all ports.

        Returns:
            Dictionary with default 'inputs' and 'outputs' label lists
        """
        return {
            "inputs": [f"Input {i + 1}" for i in range(32)],
            "outputs": [f"Output {i + 1}" for i in range(32)],
        }

    @staticmethod
    def generate_input_label(port: int) -> str:
        """Generate default label for input port.

        Args:
            port: Port number (1-32)

        Returns:
            Default label string
        """
        return f"Input {port}"

    @staticmethod
    def generate_output_label(port: int) -> str:
        """Generate default label for output port.

        Args:
            port: Port number (1-32)

        Returns:
            Default label string
        """
        return f"Output {port}"


# Timeout constants (in seconds)
TIMEOUT_BULK_REQUEST = 10  # Bulk config requests
TIMEOUT_INDIVIDUAL_REQUEST = 5  # Individual port requests
TIMEOUT_TELNET_CONNECT = 5  # Telnet connection
TIMEOUT_TELNET_COMMAND = 2  # Individual telnet command

# Delay constants (in seconds)
DELAY_TELNET_INITIAL = 2  # Initial wait after telnet connection
DELAY_TELNET_COMMAND = 0.2  # Delay between telnet commands
DELAY_REST_REQUEST = 0.1  # Delay between individual REST requests
DELAY_UPLOAD_REQUEST = 0.1  # Delay between upload requests

# Retry constants
MAX_RETRIES = 3  # Maximum retry attempts for failed requests
RETRY_BACKOFF_BASE = 1  # Base delay for exponential backoff (seconds)
RETRY_BACKOFF_MULTIPLIER = 2  # Multiplier for exponential backoff
