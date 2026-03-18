"""
Pydantic models for file data validation.
"""
from typing import Optional, Literal, List
from pydantic import BaseModel, ConfigDict, Field, field_validator

from src.utils.validation import PORT_NUMBER_MAX, COLOR_ID_MIN, COLOR_ID_MAX


class PortData(BaseModel):
    """Model for a single port row."""

    port: int = Field(..., ge=1, le=PORT_NUMBER_MAX, description="Port number (1-120)")
    type: Literal["INPUT", "OUTPUT"] = Field(..., description="Port type")
    current_label: str = Field(default="", max_length=255, description="Current label (Line 1)")
    new_label: Optional[str] = Field(default=None, max_length=255, description="New label to apply (Line 1)")
    current_label_line2: str = Field(default="", max_length=255, description="Current label (Line 2)")
    new_label_line2: Optional[str] = Field(default=None, max_length=255, description="New label to apply (Line 2)")
    current_color: int = Field(default=4, ge=COLOR_ID_MIN, le=COLOR_ID_MAX, description="Current button color (1-9)")
    new_color: Optional[int] = Field(default=None, ge=COLOR_ID_MIN, le=COLOR_ID_MAX, description="New button color to apply (1-9)")
    notes: str = Field(default="", max_length=500, description="Additional notes")

    @field_validator("type", mode="before")
    @classmethod
    def validate_type(cls, v: str) -> str:
        """Validate and normalize port type."""
        if isinstance(v, str):
            v = v.upper().strip()
        if v not in ("INPUT", "OUTPUT"):
            raise ValueError(f"Port type must be INPUT or OUTPUT, got '{v}'")
        return v

    @field_validator("current_label", "new_label", "current_label_line2", "new_label_line2", "notes")
    @classmethod
    def strip_strings(cls, v: Optional[str]) -> Optional[str]:
        """Strip whitespace from string fields."""
        if v is None:
            return v
        return v.strip()

    model_config = ConfigDict(
        str_strip_whitespace=True,
        validate_assignment=True,
    )


class FileData(BaseModel):
    """Model for complete file data with all ports."""

    ports: List[PortData] = Field(default_factory=list, description="List of port data")

    @field_validator("ports")
    @classmethod
    def validate_ports(cls, v: List[PortData]) -> List[PortData]:
        """Validate port list constraints."""
        if len(v) > 240:
            raise ValueError(f"Cannot have more than 240 ports (120 inputs + 120 outputs), got {len(v)}")

        # Check for duplicate (port, type) combinations
        # Same port number is valid for INPUT and OUTPUT (e.g., Input 1 and Output 1)
        port_keys = [(port.port, port.type) for port in v]
        if len(port_keys) != len(set(port_keys)):
            duplicates = [k for k in port_keys if port_keys.count(k) > 1]
            raise ValueError(f"Duplicate port entries found: {set(duplicates)}")

        return v

    def get_inputs(self) -> List[PortData]:
        """Get all INPUT ports."""
        return [p for p in self.ports if p.type == "INPUT"]

    def get_outputs(self) -> List[PortData]:
        """Get all OUTPUT ports."""
        return [p for p in self.ports if p.type == "OUTPUT"]

    def get_port(self, port_number: int, port_type: Optional[str] = None) -> Optional[PortData]:
        """Get port by number and optional type.

        Args:
            port_number: Port number to find
            port_type: Optional "INPUT" or "OUTPUT" to disambiguate
        """
        for port in self.ports:
            if port.port == port_number:
                if port_type is None or port.type == port_type:
                    return port
        return None

    model_config = ConfigDict(
        validate_assignment=True,
    )
