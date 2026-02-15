"""Router configuration model for KUMO router management.

This module defines the Router class representing the KUMO router
configuration and state.
"""

from dataclasses import dataclass, field
from enum import Enum
from typing import Dict, List, Optional
from datetime import datetime


class ConnectionStatus(Enum):
    """Enumeration of router connection states."""

    DISCONNECTED = "disconnected"
    CONNECTING = "connecting"
    CONNECTED = "connected"
    ERROR = "error"


@dataclass
class Router:
    """Represents a KUMO router configuration and state.

    Attributes:
        ip_address: IP address of the router
        connection_status: Current connection status
        port_info: Dictionary mapping port numbers to port information
        last_connected: Timestamp of last successful connection
        error_message: Optional error message if connection failed
    """

    ip_address: str
    connection_status: ConnectionStatus = ConnectionStatus.DISCONNECTED
    port_info: Dict[int, dict] = field(default_factory=dict)
    last_connected: Optional[datetime] = None
    error_message: Optional[str] = None

    def __post_init__(self) -> None:
        """Validate router data after initialization."""
        self.validate_ip_address()
        self.validate_connection_status()

    def validate_ip_address(self) -> None:
        """Validate IP address format.

        Raises:
            TypeError: If ip_address is not a string
            ValueError: If ip_address format is invalid
        """
        if not isinstance(self.ip_address, str):
            raise TypeError(f"IP address must be a string, got {type(self.ip_address)}")

        if not self.ip_address:
            raise ValueError("IP address cannot be empty")

        # Basic IP address validation
        parts = self.ip_address.split(".")
        if len(parts) != 4:
            raise ValueError(f"Invalid IP address format: {self.ip_address}")

        try:
            for part in parts:
                num = int(part)
                if not 0 <= num <= 255:
                    raise ValueError(f"Invalid IP address octet: {part}")
        except ValueError as e:
            raise ValueError(f"Invalid IP address format: {self.ip_address}") from e

    def validate_connection_status(self) -> None:
        """Validate connection status is a valid enum value.

        Raises:
            TypeError: If connection_status is not a ConnectionStatus enum
        """
        if not isinstance(self.connection_status, ConnectionStatus):
            raise TypeError(
                f"connection_status must be a ConnectionStatus enum, "
                f"got {type(self.connection_status)}"
            )

    def is_connected(self) -> bool:
        """Check if router is currently connected.

        Returns:
            True if connection status is CONNECTED
        """
        return self.connection_status == ConnectionStatus.CONNECTED

    def set_connected(self) -> None:
        """Mark router as connected and update timestamp."""
        self.connection_status = ConnectionStatus.CONNECTED
        self.last_connected = datetime.utcnow()
        self.error_message = None

    def set_disconnected(self, error_message: Optional[str] = None) -> None:
        """Mark router as disconnected.

        Args:
            error_message: Optional error message explaining disconnection
        """
        self.connection_status = ConnectionStatus.DISCONNECTED
        self.error_message = error_message

    def set_connecting(self) -> None:
        """Mark router as currently connecting."""
        self.connection_status = ConnectionStatus.CONNECTING
        self.error_message = None

    def set_error(self, error_message: str) -> None:
        """Mark router connection as error state.

        Args:
            error_message: Error message explaining the failure
        """
        self.connection_status = ConnectionStatus.ERROR
        self.error_message = error_message

    def update_port_info(self, port_number: int, info: dict) -> None:
        """Update information for a specific port.

        Args:
            port_number: Port number (1-32)
            info: Dictionary containing port information

        Raises:
            ValueError: If port number is invalid
        """
        if not 1 <= port_number <= 32:
            raise ValueError(f"Port number must be between 1 and 32, got {port_number}")

        self.port_info[port_number] = info

    def get_port_info(self, port_number: int) -> Optional[dict]:
        """Get information for a specific port.

        Args:
            port_number: Port number (1-32)

        Returns:
            Dictionary containing port information, or None if not found
        """
        return self.port_info.get(port_number)

    def get_all_ports(self) -> List[int]:
        """Get list of all configured port numbers.

        Returns:
            Sorted list of port numbers
        """
        return sorted(self.port_info.keys())

    def clear_port_info(self) -> None:
        """Clear all port information."""
        self.port_info.clear()

    def to_dict(self) -> dict:
        """Convert router to dictionary representation.

        Returns:
            Dictionary containing router data
        """
        return {
            "ip_address": self.ip_address,
            "connection_status": self.connection_status.value,
            "port_info": self.port_info,
            "last_connected": self.last_connected.isoformat() if self.last_connected else None,
            "error_message": self.error_message,
            "is_connected": self.is_connected(),
        }

    @classmethod
    def from_dict(cls, data: dict) -> "Router":
        """Create Router instance from dictionary.

        Args:
            data: Dictionary containing router data

        Returns:
            Router instance

        Raises:
            KeyError: If required keys are missing
        """
        status_str = data["connection_status"]
        connection_status = (
            ConnectionStatus(status_str) if isinstance(status_str, str) else status_str
        )

        last_connected = None
        if data.get("last_connected"):
            last_connected = datetime.fromisoformat(data["last_connected"])

        return cls(
            ip_address=data["ip_address"],
            connection_status=connection_status,
            port_info=data.get("port_info", {}),
            last_connected=last_connected,
            error_message=data.get("error_message"),
        )

    def __str__(self) -> str:
        """String representation of the router."""
        status = self.connection_status.value
        port_count = len(self.port_info)
        return f"Router {self.ip_address} [{status}] ({port_count} ports configured)"
