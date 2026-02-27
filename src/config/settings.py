"""Application settings for the KUMO Router Management System.

This module defines application configuration using Pydantic BaseSettings,
allowing configuration from environment variables and config files.
"""

from typing import List, Optional
from pydantic import Field, validator
from pydantic_settings import BaseSettings
from pathlib import Path
import logging


class Settings(BaseSettings):
    """Application settings with validation.

    Settings can be configured via environment variables with the prefix 'KUMO_'
    or through a .env file.
    """

    # Router Settings
    router_ip: str = Field(
        default="192.168.1.100",
        description="Default IP address of the KUMO router"
    )
    router_connection_timeout: int = Field(
        default=30,
        ge=1,
        le=300,
        description="Router connection timeout in seconds"
    )
    router_retry_attempts: int = Field(
        default=3,
        ge=1,
        le=10,
        description="Number of connection retry attempts"
    )
    router_retry_delay: int = Field(
        default=5,
        ge=1,
        le=60,
        description="Delay between retry attempts in seconds"
    )

    # File Settings
    labels_file_path: str = Field(
        default="labels.csv",
        description="Path to the labels CSV file"
    )
    backup_enabled: bool = Field(
        default=True,
        description="Enable automatic file backups"
    )
    backup_directory: str = Field(
        default="backups",
        description="Directory for backup files"
    )
    max_backups: int = Field(
        default=10,
        ge=1,
        le=100,
        description="Maximum number of backup files to retain"
    )

    # Validation Rules
    min_port_number: int = Field(
        default=1,
        ge=1,
        le=120,
        description="Minimum valid port number"
    )
    max_port_number: int = Field(
        default=120,
        ge=1,
        le=120,
        description="Maximum valid port number (supports KUMO 16/32/64 and Videohub up to 120)"
    )
    max_label_length: int = Field(
        default=255,
        ge=1,
        le=255,
        description="Maximum length for port labels (50 for KUMO, 255 for Videohub)"
    )
    allowed_port_types: List[str] = Field(
        default=["INPUT", "OUTPUT"],
        description="Allowed port types"
    )
    validate_on_load: bool = Field(
        default=True,
        description="Validate labels when loading from file"
    )

    # Logging Configuration
    log_level: str = Field(
        default="INFO",
        description="Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL)"
    )
    log_file: Optional[str] = Field(
        default=None,
        description="Path to log file (None for console only)"
    )
    log_format: str = Field(
        default="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
        description="Log message format"
    )
    log_date_format: str = Field(
        default="%Y-%m-%d %H:%M:%S",
        description="Log date format"
    )

    # Event Bus Settings
    event_queue_max_size: int = Field(
        default=1000,
        ge=10,
        le=10000,
        description="Maximum size of event queues"
    )

    # Application Settings
    app_name: str = Field(
        default="KUMO Router Manager",
        description="Application name"
    )
    app_version: str = Field(
        default="3.0.0",
        description="Application version"
    )
    debug_mode: bool = Field(
        default=False,
        description="Enable debug mode"
    )

    @validator("router_ip")
    def validate_ip_address(cls, v: str) -> str:
        """Validate IP address format.

        Args:
            v: IP address string

        Returns:
            Validated IP address

        Raises:
            ValueError: If IP address format is invalid
        """
        parts = v.split(".")
        if len(parts) != 4:
            raise ValueError(f"Invalid IP address format: {v}")

        try:
            for part in parts:
                num = int(part)
                if not 0 <= num <= 255:
                    raise ValueError(f"Invalid IP address octet: {part}")
        except ValueError as e:
            raise ValueError(f"Invalid IP address format: {v}") from e

        return v

    @validator("log_level")
    def validate_log_level(cls, v: str) -> str:
        """Validate log level.

        Args:
            v: Log level string

        Returns:
            Validated log level

        Raises:
            ValueError: If log level is invalid
        """
        valid_levels = ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]
        v_upper = v.upper()
        if v_upper not in valid_levels:
            raise ValueError(
                f"Invalid log level: {v}. Must be one of {valid_levels}"
            )
        return v_upper

    @validator("max_port_number")
    def validate_port_range(cls, v: int, values: dict) -> int:
        """Validate that max_port_number is greater than min_port_number.

        Args:
            v: Maximum port number
            values: Dictionary of previously validated values

        Returns:
            Validated maximum port number

        Raises:
            ValueError: If max is not greater than min
        """
        min_port = values.get("min_port_number", 1)
        if v < min_port:
            raise ValueError(
                f"max_port_number ({v}) must be >= min_port_number ({min_port})"
            )
        return v

    def get_log_level_int(self) -> int:
        """Get logging level as integer constant.

        Returns:
            Logging level integer constant
        """
        return getattr(logging, self.log_level)

    def create_backup_directory(self) -> Path:
        """Create backup directory if it doesn't exist.

        Returns:
            Path to backup directory
        """
        backup_path = Path(self.backup_directory)
        backup_path.mkdir(parents=True, exist_ok=True)
        return backup_path

    def get_labels_file_path(self) -> Path:
        """Get labels file path as Path object.

        Returns:
            Path to labels file
        """
        return Path(self.labels_file_path)

    class Config:
        """Pydantic configuration."""

        env_prefix = "KUMO_"
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = False


# Global settings instance
_settings: Optional[Settings] = None


def get_settings() -> Settings:
    """Get the global settings instance.

    This function implements a singleton pattern for settings,
    creating the settings instance only once and reusing it.

    Returns:
        Global settings instance
    """
    global _settings
    if _settings is None:
        _settings = Settings()
    return _settings
