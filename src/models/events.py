"""Event data models for the KUMO Router Management System.

This module defines the event hierarchy used for communication between agents
through the event bus.
"""

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Dict, Optional
from enum import Enum


class EventType(Enum):
    """Enumeration of event types in the system."""

    CONNECTION = "connection"
    LABELS = "labels"
    VALIDATION = "validation"
    FILE = "file"
    SYSTEM = "system"


@dataclass
class BaseEvent:
    """Base event class for all system events.

    Attributes:
        timestamp: UTC timestamp when the event was created
        event_type: Type of the event
        data: Dictionary containing event-specific data
    """

    timestamp: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    event_type: EventType = EventType.SYSTEM
    data: Dict[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        """Validate event data after initialization."""
        if not isinstance(self.timestamp, datetime):
            raise TypeError("timestamp must be a datetime object")
        if not isinstance(self.event_type, EventType):
            raise TypeError("event_type must be an EventType enum")
        if not isinstance(self.data, dict):
            raise TypeError("data must be a dictionary")


@dataclass
class ConnectionEvent(BaseEvent):
    """Event for router connection status changes.

    Attributes:
        router_ip: IP address of the router
        connected: Connection status (True if connected, False otherwise)
        error_message: Optional error message if connection failed
    """

    router_ip: str = ""
    connected: bool = False
    error_message: Optional[str] = None

    def __post_init__(self) -> None:
        """Initialize connection event with proper type."""
        self.event_type = EventType.CONNECTION
        super().__post_init__()

        # Update data dictionary with connection-specific fields
        self.data.update({
            "router_ip": self.router_ip,
            "connected": self.connected,
            "error_message": self.error_message,
        })


@dataclass
class LabelsEvent(BaseEvent):
    """Event for label update operations.

    Attributes:
        labels: List of label dictionaries containing port information
        source: Source of the labels (e.g., 'file', 'router', 'user')
        operation: Operation type (e.g., 'read', 'write', 'update')
    """

    labels: list = field(default_factory=list)
    source: str = "unknown"
    operation: str = "read"

    def __post_init__(self) -> None:
        """Initialize labels event with proper type."""
        self.event_type = EventType.LABELS
        super().__post_init__()

        # Update data dictionary with labels-specific fields
        self.data.update({
            "labels": self.labels,
            "source": self.source,
            "operation": self.operation,
            "label_count": len(self.labels),
        })


@dataclass
class ValidationEvent(BaseEvent):
    """Event for validation results.

    Attributes:
        valid: Whether validation passed
        errors: List of validation error messages
        warnings: List of validation warning messages
        validated_item: Type of item validated (e.g., 'labels', 'router', 'file')
    """

    valid: bool = True
    errors: list = field(default_factory=list)
    warnings: list = field(default_factory=list)
    validated_item: str = "unknown"

    def __post_init__(self) -> None:
        """Initialize validation event with proper type."""
        self.event_type = EventType.VALIDATION
        super().__post_init__()

        # Update data dictionary with validation-specific fields
        self.data.update({
            "valid": self.valid,
            "errors": self.errors,
            "warnings": self.warnings,
            "validated_item": self.validated_item,
            "error_count": len(self.errors),
            "warning_count": len(self.warnings),
        })


@dataclass
class FileEvent(BaseEvent):
    """Event for file operations.

    Attributes:
        file_path: Path to the file
        operation: File operation (e.g., 'read', 'write', 'delete')
        success: Whether the file operation succeeded
        error_message: Optional error message if operation failed
    """

    file_path: str = ""
    operation: str = "read"
    success: bool = True
    error_message: Optional[str] = None

    def __post_init__(self) -> None:
        """Initialize file event with proper type."""
        self.event_type = EventType.FILE
        super().__post_init__()

        # Update data dictionary with file-specific fields
        self.data.update({
            "file_path": self.file_path,
            "operation": self.operation,
            "success": self.success,
            "error_message": self.error_message,
        })
