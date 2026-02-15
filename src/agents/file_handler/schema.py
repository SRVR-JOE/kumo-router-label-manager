"""
Pydantic models for file data validation.
"""
from typing import Optional, Literal
from pydantic import BaseModel, Field, field_validator


class PortData(BaseModel):
    """Model for a single port row."""

    port: int = Field(..., ge=1, le=64, description="Port number (1-64)")
    type: Literal["INPUT", "OUTPUT"] = Field(..., description="Port type")
    current_label: str = Field(default="", max_length=100, description="Current label")
    new_label: Optional[str] = Field(default=None, max_length=100, description="New label to apply")
    notes: str = Field(default="", max_length=500, description="Additional notes")

    @field_validator("port")
    @classmethod
    def validate_port(cls, v: int) -> int:
        """Validate port number is within range."""
        if not 1 <= v <= 64:
            raise ValueError(f"Port must be between 1 and 64, got {v}")
        return v

    @field_validator("type")
    @classmethod
    def validate_type(cls, v: str) -> str:
        """Validate and normalize port type."""
        v = v.upper().strip()
        if v not in ["INPUT", "OUTPUT"]:
            raise ValueError(f"Type must be INPUT or OUTPUT, got {v}")
        return v

    @field_validator("current_label", "new_label", "notes")
    @classmethod
    def strip_strings(cls, v: Optional[str]) -> Optional[str]:
        """Strip whitespace from string fields."""
        if v is None:
            return v
        return v.strip()

    class Config:
        """Pydantic configuration."""
        str_strip_whitespace = True
        validate_assignment = True


class FileData(BaseModel):
    """Model for complete file data with all ports."""

    ports: list[PortData] = Field(default_factory=list, description="List of port data")

    @field_validator("ports")
    @classmethod
    def validate_ports(cls, v: list[PortData]) -> list[PortData]:
        """Validate port list constraints."""
        if len(v) > 64:
            raise ValueError(f"Cannot have more than 64 ports, got {len(v)}")

        # Check for duplicate port numbers
        port_numbers = [port.port for port in v]
        if len(port_numbers) != len(set(port_numbers)):
            duplicates = [p for p in port_numbers if port_numbers.count(p) > 1]
            raise ValueError(f"Duplicate port numbers found: {set(duplicates)}")

        return v

    def get_inputs(self) -> list[PortData]:
        """Get all INPUT ports."""
        return [p for p in self.ports if p.type == "INPUT"]

    def get_outputs(self) -> list[PortData]:
        """Get all OUTPUT ports."""
        return [p for p in self.ports if p.type == "OUTPUT"]

    def get_port(self, port_number: int) -> Optional[PortData]:
        """Get port by number."""
        for port in self.ports:
            if port.port == port_number:
                return port
        return None

    class Config:
        """Pydantic configuration."""
        validate_assignment = True
