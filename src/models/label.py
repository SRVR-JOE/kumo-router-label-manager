"""Label data model for KUMO router port labels.

This module defines the Label class representing a single port label
configuration on the KUMO router.
"""

from dataclasses import dataclass
from enum import Enum
from typing import Optional


class PortType(Enum):
    """Enumeration of port types."""

    INPUT = "INPUT"
    OUTPUT = "OUTPUT"


@dataclass
class Label:
    """Represents a label for a router port.

    Attributes:
        port_number: Port number (1-32)
        port_type: Type of port (INPUT or OUTPUT)
        current_label: Current label text on the router
        new_label: New label text to be applied (if any)
    """

    port_number: int
    port_type: PortType
    current_label: str = ""
    new_label: Optional[str] = None

    def __post_init__(self) -> None:
        """Validate label data after initialization."""
        self.validate_port_number()
        self.validate_port_type()
        self.validate_label_text()

    def validate_port_number(self) -> None:
        """Validate that port number is within valid range (1-120).

        Supports KUMO (16x16, 32x32, 64x64) and Videohub (up to 120x120).

        Raises:
            ValueError: If port number is not between 1 and 120
        """
        if not isinstance(self.port_number, int):
            raise TypeError(f"Port number must be an integer, got {type(self.port_number)}")

        if not 1 <= self.port_number <= 120:
            raise ValueError(f"Port number must be between 1 and 120, got {self.port_number}")

    def validate_port_type(self) -> None:
        """Validate that port type is a valid PortType enum.

        Raises:
            TypeError: If port_type is not a PortType enum
        """
        if not isinstance(self.port_type, PortType):
            raise TypeError(f"Port type must be a PortType enum, got {type(self.port_type)}")

    def validate_label_text(self) -> None:
        """Validate label text format and length.

        Raises:
            TypeError: If labels are not strings
            ValueError: If label text exceeds maximum length
        """
        max_length = 255  # Maximum label length (255 for Videohub, 50 for KUMO)

        if not isinstance(self.current_label, str):
            raise TypeError(f"current_label must be a string, got {type(self.current_label)}")

        if self.new_label is not None and not isinstance(self.new_label, str):
            raise TypeError(f"new_label must be a string or None, got {type(self.new_label)}")

        if len(self.current_label) > max_length:
            raise ValueError(
                f"current_label exceeds maximum length of {max_length} characters: "
                f"'{self.current_label[:20]}...'"
            )

        if self.new_label is not None and len(self.new_label) > max_length:
            raise ValueError(
                f"new_label exceeds maximum length of {max_length} characters: "
                f"'{self.new_label[:20]}...'"
            )

    def has_changes(self) -> bool:
        """Check if there are pending changes to apply.

        Returns:
            True if new_label is set and different from current_label
        """
        return self.new_label is not None and self.new_label != self.current_label

    def apply_changes(self) -> None:
        """Apply new label to current label and clear new_label."""
        if self.new_label is not None:
            self.current_label = self.new_label
            self.new_label = None

    def to_dict(self) -> dict:
        """Convert label to dictionary representation.

        Returns:
            Dictionary containing label data
        """
        return {
            "port_number": self.port_number,
            "port_type": self.port_type.value,
            "current_label": self.current_label,
            "new_label": self.new_label,
            "has_changes": self.has_changes(),
        }

    @classmethod
    def from_dict(cls, data: dict) -> "Label":
        """Create Label instance from dictionary.

        Args:
            data: Dictionary containing label data

        Returns:
            Label instance

        Raises:
            KeyError: If required keys are missing
            ValueError: If port_type value is invalid
        """
        port_type_str = data["port_type"]
        port_type = PortType(port_type_str) if isinstance(port_type_str, str) else port_type_str

        return cls(
            port_number=data["port_number"],
            port_type=port_type,
            current_label=data.get("current_label", ""),
            new_label=data.get("new_label"),
        )

    def __str__(self) -> str:
        """String representation of the label."""
        change_indicator = " -> " + self.new_label if self.has_changes() else ""
        return f"Port {self.port_number} ({self.port_type.value}): {self.current_label}{change_indicator}"
