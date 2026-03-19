"""Label data model for router port labels.

This module defines the Label class representing a single port label
configuration on a video router.
"""

from dataclasses import dataclass
from enum import Enum
from typing import Optional

from src.utils.validation import validate_port_number, validate_color_id, PORT_NUMBER_MAX


class PortType(Enum):
    """Enumeration of port types."""

    INPUT = "INPUT"
    OUTPUT = "OUTPUT"


@dataclass
class Label:
    """Represents a label for a router port.

    Attributes:
        port_number: Port number (1-120)
        port_type: Type of port (INPUT or OUTPUT)
        current_label: Current label text on the router
        new_label: New label text to be applied (if any)
    """

    port_number: int
    port_type: PortType
    current_label: str = ""
    new_label: Optional[str] = None
    current_label_line2: str = ""
    new_label_line2: Optional[str] = None
    current_color: int = 4       # 1-9, default blue
    new_color: Optional[int] = None

    def __post_init__(self) -> None:
        """Validate label data after initialization."""
        self.validate_port_number()
        self.validate_port_type()
        self.validate_label_text()
        self.validate_color()

    def validate_port_number(self) -> None:
        """Validate that port number is within valid range (1-120).

        Supports KUMO (16x16, 32x32, 64x64) and Videohub (up to 120x120).

        Raises:
            ValueError: If port number is not between 1 and 120
        """
        validate_port_number(self.port_number, PORT_NUMBER_MAX)

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

        for field_name, value in [
            ("current_label", self.current_label),
            ("current_label_line2", self.current_label_line2),
        ]:
            if not isinstance(value, str):
                raise TypeError(f"{field_name} must be a string, got {type(value)}")
            if len(value) > max_length:
                raise ValueError(
                    f"{field_name} exceeds maximum length of {max_length} characters: "
                    f"'{value[:20]}...'"
                )

        for field_name, value in [
            ("new_label", self.new_label),
            ("new_label_line2", self.new_label_line2),
        ]:
            if value is not None and not isinstance(value, str):
                raise TypeError(f"{field_name} must be a string or None, got {type(value)}")
            if value is not None and len(value) > max_length:
                raise ValueError(
                    f"{field_name} exceeds maximum length of {max_length} characters: "
                    f"'{value[:20]}...'"
                )

    def validate_color(self) -> None:
        """Validate that color values are within valid range (1-9).

        Raises:
            TypeError: If color is not an int (or None for new_color)
            ValueError: If color is not between 1 and 9
        """
        validate_color_id(self.current_color)
        if self.new_color is not None:
            validate_color_id(self.new_color)

    def has_changes(self) -> bool:
        """Check if there are pending changes to apply.

        Returns:
            True if new_label, new_label_line2, or new_color is set and different from current
        """
        line1 = self.new_label is not None and self.new_label != self.current_label
        line2 = self.new_label_line2 is not None and self.new_label_line2 != self.current_label_line2
        color = self.new_color is not None and self.new_color != self.current_color
        return line1 or line2 or color

    def apply_changes(self) -> None:
        """Apply new labels/color to current values and clear new values."""
        if self.new_label is not None:
            self.current_label = self.new_label
            self.new_label = None
        if self.new_label_line2 is not None:
            self.current_label_line2 = self.new_label_line2
            self.new_label_line2 = None
        if self.new_color is not None:
            self.current_color = self.new_color
            self.new_color = None

    def apply_color_change(self) -> None:
        """Apply only the color change, leaving text changes untouched."""
        if self.new_color is not None:
            self.current_color = self.new_color
            self.new_color = None

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
            "current_label_line2": self.current_label_line2,
            "new_label_line2": self.new_label_line2,
            "current_color": self.current_color,
            "new_color": self.new_color,
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
            current_label_line2=data.get("current_label_line2", ""),
            new_label_line2=data.get("new_label_line2"),
            current_color=data.get("current_color", 4),
            new_color=data.get("new_color"),
        )

    def __str__(self) -> str:
        """String representation of the label."""
        parts = []
        if self.new_label is not None and self.new_label != self.current_label:
            parts.append(f"L1: {self.current_label} -> {self.new_label}")
        if self.new_label_line2 is not None and self.new_label_line2 != self.current_label_line2:
            parts.append(f"L2: {self.current_label_line2} -> {self.new_label_line2}")
        if self.new_color is not None and self.new_color != self.current_color:
            parts.append(f"Color: {self.current_color} -> {self.new_color}")
        change_indicator = " | ".join(parts)
        if change_indicator:
            change_indicator = " [" + change_indicator + "]"
        return f"Port {self.port_number} ({self.port_type.value}): {self.current_label}{change_indicator}"
