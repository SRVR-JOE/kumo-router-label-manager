"""Async Telnet client for AJA KUMO routers.

This module provides an async Telnet client for communicating with KUMO routers
when REST API is not available or fails.
"""

import asyncio
import logging
from typing import Dict, List, Optional, Tuple

from .router_protocols import (
    TelnetCommand,
    DefaultLabelGenerator,
    Protocol,
    TIMEOUT_TELNET_CONNECT,
    TIMEOUT_TELNET_COMMAND,
    DELAY_TELNET_INITIAL,
    DELAY_TELNET_COMMAND,
)


logger = logging.getLogger(__name__)


class TelnetClientError(Exception):
    """Base exception for Telnet client errors."""

    pass


class TelnetConnectionError(TelnetClientError):
    """Exception raised when Telnet connection fails."""

    pass


class TelnetCommandError(TelnetClientError):
    """Exception raised when Telnet command fails."""

    pass


class TelnetClient:
    """Async Telnet client for KUMO routers.

    Provides methods for downloading and uploading port labels via Telnet protocol.
    Implements proper connection handling and command execution with timeouts.
    """

    def __init__(self, router_ip: str, port: int = 23, port_count: int = 32):
        """Initialize Telnet client.

        Args:
            router_ip: IP address of the KUMO router
            port: Telnet port (default: 23)
            port_count: Number of input/output ports (16, 32, or 64)
        """
        self.router_ip = router_ip
        self.port = port
        self._port_count = port_count
        self._reader: Optional[asyncio.StreamReader] = None
        self._writer: Optional[asyncio.StreamWriter] = None
        self._connected = False

    async def __aenter__(self):
        """Async context manager entry."""
        await self.connect()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        await self.disconnect()

    async def connect(self) -> None:
        """Connect to router via Telnet.

        Raises:
            TelnetConnectionError: If connection fails
        """
        if self._connected:
            logger.debug(f"Already connected to {self.router_ip}")
            return

        try:
            logger.info(f"Connecting to {self.router_ip}:{self.port} via Telnet")

            # Open connection with timeout
            self._reader, self._writer = await asyncio.wait_for(
                asyncio.open_connection(self.router_ip, self.port),
                timeout=TIMEOUT_TELNET_CONNECT,
            )

            self._connected = True

            # Wait for initial prompt
            logger.debug(f"Waiting {DELAY_TELNET_INITIAL}s for initial prompt")
            await asyncio.sleep(DELAY_TELNET_INITIAL)

            # Clear any welcome message
            try:
                await asyncio.wait_for(
                    self._reader.read(4096), timeout=0.5
                )
            except asyncio.TimeoutError:
                pass

            logger.info(f"Telnet connection established to {self.router_ip}")

        except asyncio.TimeoutError:
            self._connected = False
            raise TelnetConnectionError(
                f"Connection timeout to {self.router_ip}:{self.port}"
            )

        except OSError as e:
            self._connected = False
            raise TelnetConnectionError(
                f"Connection failed to {self.router_ip}:{self.port}: {e}"
            )

        except Exception as e:
            self._connected = False
            raise TelnetConnectionError(
                f"Unexpected error connecting to {self.router_ip}:{self.port}: {e}"
            )

    async def disconnect(self) -> None:
        """Disconnect from router."""
        if self._writer is not None:
            try:
                self._writer.close()
                await self._writer.wait_closed()
            except Exception as e:
                logger.warning(f"Error closing Telnet connection: {e}")

        self._reader = None
        self._writer = None
        self._connected = False
        logger.info(f"Telnet connection closed to {self.router_ip}")

    async def _send_command(self, command: str) -> Optional[str]:
        """Send command and read response.

        Args:
            command: Command string to send

        Returns:
            Response string, or None if command failed

        Raises:
            TelnetCommandError: If not connected or send fails
        """
        if not self._connected or self._writer is None or self._reader is None:
            raise TelnetCommandError("Not connected to router")

        try:
            # Send command
            logger.debug(f"Sending command: {command}")
            self._writer.write((command + "\n").encode("utf-8"))
            await self._writer.drain()

            # Read response with timeout
            response_bytes = await asyncio.wait_for(
                self._reader.readline(), timeout=TIMEOUT_TELNET_COMMAND
            )

            response = response_bytes.decode("utf-8", errors="ignore").strip()
            logger.debug(f"Received response: {response[:100]}")

            return response

        except asyncio.TimeoutError:
            logger.warning(f"Command timeout: {command}")
            return None

        except Exception as e:
            logger.error(f"Command error: {command} - {e}")
            return None

    async def download_labels(self) -> Tuple[Protocol, Optional[Dict[str, List[str]]]]:
        """Download all labels using Telnet.

        Returns:
            Tuple of (protocol_used, labels_dict) where labels_dict contains
            'inputs' and 'outputs' lists, or (Protocol.TELNET, None) if failed
        """
        if not self._connected:
            await self.connect()

        logger.info(f"Downloading labels via Telnet from {self.router_ip}")

        labels = {"inputs": [], "outputs": []}
        success_count = 0
        port_count = self._port_count

        # Query all inputs
        for port in range(1, port_count + 1):
            command = TelnetCommand.query_input(port)
            response = await self._send_command(command)

            if response:
                label = TelnetCommand.parse_label_response(response)
                if label:
                    labels["inputs"].append(label)
                    success_count += 1
                    logger.debug(f"Input {port}: {label}")
                else:
                    labels["inputs"].append(DefaultLabelGenerator.generate_input_label(port))
            else:
                labels["inputs"].append(DefaultLabelGenerator.generate_input_label(port))

            # Delay between commands
            await asyncio.sleep(DELAY_TELNET_COMMAND)

        # Query all outputs
        for port in range(1, port_count + 1):
            command = TelnetCommand.query_output(port)
            response = await self._send_command(command)

            if response:
                label = TelnetCommand.parse_label_response(response)
                if label:
                    labels["outputs"].append(label)
                    success_count += 1
                    logger.debug(f"Output {port}: {label}")
                else:
                    labels["outputs"].append(DefaultLabelGenerator.generate_output_label(port))
            else:
                labels["outputs"].append(DefaultLabelGenerator.generate_output_label(port))

            # Delay between commands
            await asyncio.sleep(DELAY_TELNET_COMMAND)

        total_ports = port_count * 2
        if success_count > 0:
            logger.info(
                f"Telnet download successful - {success_count}/{total_ports} ports retrieved"
            )
            return Protocol.TELNET, labels
        else:
            logger.warning("Telnet label download failed - no valid responses")
            return Protocol.TELNET, None

    async def upload_label(
        self, port: int, port_type: str, label: str
    ) -> Tuple[bool, Optional[str]]:
        """Upload a single label to the router.

        Args:
            port: Port number (1-32)
            port_type: "INPUT" or "OUTPUT"
            label: Label text to set

        Returns:
            Tuple of (success, error_message)
        """
        if not self._connected:
            await self.connect()

        # Generate command based on port type
        if port_type.upper() == "INPUT":
            command = TelnetCommand.set_input(port, label)
        elif port_type.upper() == "OUTPUT":
            command = TelnetCommand.set_output(port, label)
        else:
            return False, f"Invalid port type: {port_type}"

        # Send command
        response = await self._send_command(command)

        if response is not None:
            logger.debug(f"Uploaded {port_type} {port} label via Telnet: {label}")
            return True, None
        else:
            error_msg = f"Failed to upload {port_type} {port} label via Telnet"
            logger.warning(error_msg)
            return False, error_msg

    async def upload_labels_batch(
        self, labels: List[Dict], progress_callback=None
    ) -> Tuple[int, int, List[str]]:
        """Upload multiple labels to the router.

        Args:
            labels: List of label dictionaries with 'port', 'type', 'label' keys
            progress_callback: Optional async callback(current, total, port_type, port)

        Returns:
            Tuple of (success_count, error_count, error_messages)
        """
        if not self._connected:
            await self.connect()

        logger.info(f"Uploading {len(labels)} labels via Telnet to {self.router_ip}")

        success_count = 0
        error_count = 0
        error_messages = []

        total = len(labels)

        for idx, label_data in enumerate(labels):
            port = label_data["port"]
            port_type = label_data["type"]
            label = label_data["label"]

            # Update progress
            if progress_callback:
                await progress_callback(idx + 1, total, port_type, port)

            # Upload label
            success, error_msg = await self.upload_label(port, port_type, label)

            if success:
                success_count += 1
            else:
                error_count += 1
                if error_msg:
                    error_messages.append(error_msg)

            # Delay between commands
            await asyncio.sleep(DELAY_TELNET_COMMAND)

        logger.info(
            f"Telnet upload complete - {success_count} succeeded, {error_count} failed"
        )
        return success_count, error_count, error_messages

    def is_connected(self) -> bool:
        """Check if client is connected.

        Returns:
            True if connected, False otherwise
        """
        return self._connected
