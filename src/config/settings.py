"""Application settings for the Helix Router Management System.

This module defines application configuration using Pydantic BaseSettings,
allowing configuration from environment variables and config files.
"""

from typing import List, Optional
from pydantic import Field, field_validator, ConfigDict
from pydantic_settings import BaseSettings
from pathlib import Path
import logging

from src.utils.validation import validate_ip_address as _validate_ip


class Settings(BaseSettings):
    """Application settings with validation.

    Settings can be configured via environment variables with the prefix 'HLX_'
    or through a .env file.
    """

    # Router Settings
    router_ip: str = Field(
        default="192.168.100.52",
        description="Default IP address of the router"
    )
    router_ips: List[str] = Field(
        default=["192.168.100.51", "192.168.100.52"],
        description="Default IP addresses for multi-router operations"
    )
    router_connection_timeout: int = Field(
        default=10,
        ge=1,
        le=300,
        description="Router connection timeout in seconds"
    )
    router_retry_attempts: int = Field(
        default=2,
        ge=1,
        le=10,
        description="Number of connection retry attempts"
    )
    router_retry_delay: int = Field(
        default=2,
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
        description="Maximum valid port number (supports KUMO 16/32/64, Videohub up to 120, Lightware MX2)"
    )
    max_label_length: int = Field(
        default=255,
        ge=1,
        le=255,
        description="Maximum length for port labels (50 for AJA KUMO, 255 for Videohub)"
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

    # REST Client Settings
    rest_max_concurrent_requests: int = Field(
        default=32, ge=1, le=128,
        description="Max concurrent REST API requests"
    )
    rest_request_timeout: float = Field(
        default=4.0, ge=1.0, le=30.0,
        description="REST request timeout in seconds"
    )
    rest_connect_timeout: float = Field(
        default=3.0, ge=1.0, le=30.0,
        description="REST connection timeout in seconds"
    )
    rest_keepalive_timeout: int = Field(
        default=30, ge=5, le=300,
        description="TCP keepalive timeout in seconds"
    )

    # Telnet Client Settings
    telnet_connect_timeout: float = Field(
        default=3.0, ge=1.0, le=30.0,
        description="Telnet connection timeout in seconds"
    )
    telnet_command_timeout: float = Field(
        default=2.0, ge=0.5, le=10.0,
        description="Telnet per-command timeout in seconds"
    )
    telnet_command_delay: float = Field(
        default=0.1, ge=0.01, le=1.0,
        description="Delay between Telnet commands in seconds"
    )

    # Retry Settings
    retry_max_attempts: int = Field(
        default=2, ge=1, le=10,
        description="Max retry attempts for failed requests"
    )
    retry_backoff_base: float = Field(
        default=0.3, ge=0.1, le=5.0,
        description="Initial retry backoff in seconds"
    )
    retry_backoff_multiplier: float = Field(
        default=2.0, ge=1.0, le=5.0,
        description="Retry backoff multiplier"
    )

    # Protocol Port Settings
    videohub_port: int = Field(
        default=9990, ge=1, le=65535,
        description="Blackmagic Videohub TCP port"
    )
    lightware_port: int = Field(
        default=6107, ge=1, le=65535,
        description="Lightware MX2 LW3 protocol port"
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
        default="Helix Router Manager",
        description="Application name"
    )
    app_version: str = Field(
        default="5.5.0",
        description="Application version"
    )
    debug_mode: bool = Field(
        default=False,
        description="Enable debug mode"
    )

    @staticmethod
    def _validate_single_ip(v: str) -> str:
        """Validate a single IP address format."""
        return _validate_ip(v)

    @field_validator("router_ip")
    @classmethod
    def validate_ip_address(cls, v: str) -> str:
        """Validate IP address format."""
        return cls._validate_single_ip(v)

    @field_validator("router_ips")
    @classmethod
    def validate_router_ips_items(cls, v: List[str]) -> List[str]:
        """Validate each IP in the router_ips list."""
        return [cls._validate_single_ip(ip) for ip in v]

    @field_validator("log_level")
    @classmethod
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

    @field_validator("max_port_number")
    @classmethod
    def validate_port_range(cls, v: int, info) -> int:
        """Validate that max_port_number is greater than min_port_number.

        Args:
            v: Maximum port number
            info: Pydantic validation info

        Returns:
            Validated maximum port number

        Raises:
            ValueError: If max is not greater than min
        """
        min_port = info.data.get("min_port_number", 1)
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

    model_config = ConfigDict(
        env_prefix="HLX_",
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
    )


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
