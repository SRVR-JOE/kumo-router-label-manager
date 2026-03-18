"""Shared validation utilities for the KUMO Router Management System.

Consolidates duplicate validation logic for IP addresses, port numbers,
and color IDs used across settings, models, and schema modules.
"""

PORT_NUMBER_MAX = 120
COLOR_ID_MIN = 1
COLOR_ID_MAX = 9


def validate_ip_address(ip: str) -> str:
    """Validate an IPv4 address string.

    Args:
        ip: IP address string to validate

    Returns:
        The validated IP address string

    Raises:
        ValueError: If the IP address format is invalid
    """
    parts = ip.split(".")
    if len(parts) != 4:
        raise ValueError(f"Invalid IP address format: {ip}")
    try:
        for part in parts:
            num = int(part)
            if not 0 <= num <= 255:
                raise ValueError(f"Invalid IP address octet: {part}")
    except ValueError as e:
        raise ValueError(f"Invalid IP address format: {ip}") from e
    return ip


def validate_port_number(port: int, max_port: int = PORT_NUMBER_MAX) -> int:
    """Validate a port number is within valid range.

    Args:
        port: Port number to validate
        max_port: Maximum allowed port number (default: 120)

    Returns:
        The validated port number

    Raises:
        TypeError: If port is not an integer
        ValueError: If port is out of range
    """
    if not isinstance(port, int):
        raise TypeError(f"Port number must be an integer, got {type(port)}")
    if not 1 <= port <= max_port:
        raise ValueError(f"Port number must be between 1 and {max_port}, got {port}")
    return port


def validate_color_id(color_id: int) -> int:
    """Validate a button color ID is within valid range (1-9).

    Args:
        color_id: Color ID to validate

    Returns:
        The validated color ID

    Raises:
        TypeError: If color_id is not an integer
        ValueError: If color_id is out of range
    """
    if not isinstance(color_id, int):
        raise TypeError(f"Color ID must be an integer, got {type(color_id)}")
    if not COLOR_ID_MIN <= color_id <= COLOR_ID_MAX:
        raise ValueError(
            f"Color ID must be between {COLOR_ID_MIN} and {COLOR_ID_MAX}, got {color_id}"
        )
    return color_id
