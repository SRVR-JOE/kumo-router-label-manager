"""API Agent for communicating with AJA KUMO routers.

This module provides the main APIAgent class that orchestrates communication
with KUMO routers using multiple protocols (REST, Telnet) with automatic fallback.
"""

import asyncio
import logging
from typing import Dict, List, Optional, Any, Tuple
from datetime import datetime

from ...models import Label, PortType, ConnectionEvent, LabelsEvent

from .rest_client import RestClient
from .telnet_client import TelnetClient
from .router_protocols import (
    Protocol,
    DefaultLabelGenerator,
)


logger = logging.getLogger(__name__)


class APIAgentError(Exception):
    """Base exception for API Agent errors."""

    pass


class APIAgent:
    """Main API Agent for KUMO router communication.

    Manages communication with KUMO routers using multiple protocols with
    automatic fallback. Implements label download/upload with retry logic
    and emits events through the event bus for progress tracking.
    """

    def __init__(self, router_ip: str, event_bus=None):
        """Initialize API Agent.

        Args:
            router_ip: IP address of the KUMO router
            event_bus: Optional event bus for emitting events
        """
        self.router_ip = router_ip
        self.event_bus = event_bus
        self._rest_client: Optional[RestClient] = None
        self._telnet_client: Optional[TelnetClient] = None
        self._last_protocol: Optional[Protocol] = None

    async def test_connection(self) -> bool:
        """Test connection to the router.

        Emits ConnectionEvent on success or failure.

        Returns:
            True if connection successful, False otherwise
        """
        logger.info(f"Testing connection to {self.router_ip}")

        try:
            # Try REST connection first
            async with RestClient(self.router_ip) as rest:
                if await rest.test_connection():
                    logger.info(f"Connection successful via REST to {self.router_ip}")
                    self._emit_connection_event(connected=True)
                    return True

            # Try Telnet as fallback
            try:
                async with TelnetClient(self.router_ip) as telnet:
                    if telnet.is_connected():
                        logger.info(f"Connection successful via Telnet to {self.router_ip}")
                        self._emit_connection_event(connected=True)
                        return True
            except Exception as e:
                logger.debug(f"Telnet connection test failed: {e}")

            # All methods failed
            error_msg = f"Cannot connect to router at {self.router_ip}"
            logger.warning(error_msg)
            self._emit_connection_event(connected=False, error_message=error_msg)
            return False

        except Exception as e:
            error_msg = f"Connection test failed: {e}"
            logger.error(error_msg)
            self._emit_connection_event(connected=False, error_message=error_msg)
            return False

    async def download_labels(self) -> List[Label]:
        """Download all labels from the router.

        Uses fallback chain: REST bulk -> REST individual -> Telnet -> defaults

        Emits LabelsEvent with downloaded labels.

        Returns:
            List of Label objects with current labels from router
        """
        logger.info(f"Downloading labels from {self.router_ip}")

        labels_dict = None
        protocol_used = Protocol.DEFAULT

        try:
            # Method 1: Try REST bulk endpoints
            logger.debug("Attempting REST bulk download")
            async with RestClient(self.router_ip) as rest:
                protocol_used, labels_dict = await rest.download_labels_bulk()

                # Method 2: Try REST individual endpoints if bulk failed
                if labels_dict is None:
                    logger.debug("Bulk download failed, trying individual endpoints")
                    protocol_used, labels_dict = await rest.download_labels_individual()

            # Method 3: Try Telnet if REST failed
            if labels_dict is None:
                logger.debug("REST download failed, trying Telnet")
                try:
                    async with TelnetClient(self.router_ip) as telnet:
                        protocol_used, labels_dict = await telnet.download_labels()
                except Exception as e:
                    logger.warning(f"Telnet download failed: {e}")

            # Method 4: Use defaults if all methods failed
            if labels_dict is None:
                logger.warning("All download methods failed, using defaults")
                labels_dict = DefaultLabelGenerator.generate_default_labels()
                protocol_used = Protocol.DEFAULT

            # Store the successful protocol for future uploads
            self._last_protocol = protocol_used

            # Convert to Label objects
            labels = self._dict_to_labels(labels_dict)

            logger.info(
                f"Downloaded {len(labels)} labels using protocol: {protocol_used.value}"
            )

            # Emit event
            self._emit_labels_event(
                labels=labels,
                source="router",
                operation="download",
                metadata={"protocol": protocol_used.value},
            )

            return labels

        except Exception as e:
            error_msg = f"Error downloading labels: {e}"
            logger.error(error_msg)

            # Return defaults on error
            labels_dict = DefaultLabelGenerator.generate_default_labels()
            labels = self._dict_to_labels(labels_dict)

            self._emit_labels_event(
                labels=labels,
                source="default",
                operation="download",
                metadata={"error": str(e)},
            )

            return labels

    async def upload_labels(
        self, labels: List[Label], progress_callback=None
    ) -> Tuple[int, int, List[str]]:
        """Upload labels to the router.

        Uses the last successful download protocol, or tries REST then Telnet.

        Args:
            labels: List of Label objects with new_label set
            progress_callback: Optional async callback(current, total, port_type, port)

        Returns:
            Tuple of (success_count, error_count, error_messages)
        """
        logger.info(f"Uploading {len(labels)} labels to {self.router_ip}")

        # Filter labels that have changes
        labels_to_upload = [label for label in labels if label.has_changes()]

        if not labels_to_upload:
            logger.info("No labels to upload")
            return 0, 0, []

        # Convert to upload format
        upload_data = []
        for label in labels_to_upload:
            upload_data.append({
                "port": label.port_number,
                "type": label.port_type.value,
                "label": label.new_label,
            })

        success_count = 0
        error_count = 0
        error_messages = []

        try:
            # Try REST first (preferred method)
            try:
                logger.debug("Attempting upload via REST")
                async with RestClient(self.router_ip) as rest:
                    success_count, error_count, error_messages = await rest.upload_labels_batch(
                        upload_data, progress_callback
                    )

                    if success_count > 0:
                        logger.info(f"Upload via REST: {success_count} succeeded, {error_count} failed")
                        self._emit_upload_success_event(labels_to_upload, success_count, error_count)
                        return success_count, error_count, error_messages

            except Exception as e:
                logger.warning(f"REST upload failed: {e}")

            # Try Telnet as fallback
            try:
                logger.debug("Attempting upload via Telnet")
                async with TelnetClient(self.router_ip) as telnet:
                    success_count, error_count, error_messages = await telnet.upload_labels_batch(
                        upload_data, progress_callback
                    )

                    logger.info(f"Upload via Telnet: {success_count} succeeded, {error_count} failed")
                    self._emit_upload_success_event(labels_to_upload, success_count, error_count)
                    return success_count, error_count, error_messages

            except Exception as e:
                logger.error(f"Telnet upload failed: {e}")
                error_messages.append(f"Telnet upload failed: {e}")

            # All methods failed
            error_count = len(labels_to_upload)
            error_msg = "All upload methods failed"
            logger.error(error_msg)
            error_messages.append(error_msg)

        except Exception as e:
            error_msg = f"Upload error: {e}"
            logger.error(error_msg)
            error_count = len(labels_to_upload)
            error_messages.append(error_msg)

        return success_count, error_count, error_messages

    def _dict_to_labels(self, labels_dict: Dict[str, List[str]]) -> List[Label]:
        """Convert labels dictionary to Label objects.

        Args:
            labels_dict: Dictionary with 'inputs' and 'outputs' lists

        Returns:
            List of Label objects
        """
        labels = []

        # Convert inputs
        for i, label_text in enumerate(labels_dict.get("inputs", []), start=1):
            labels.append(
                Label(
                    port_number=i,
                    port_type=PortType.INPUT,
                    current_label=label_text,
                    new_label=None,
                )
            )

        # Convert outputs
        for i, label_text in enumerate(labels_dict.get("outputs", []), start=1):
            labels.append(
                Label(
                    port_number=i,
                    port_type=PortType.OUTPUT,
                    current_label=label_text,
                    new_label=None,
                )
            )

        return labels

    async def _emit_connection_event(
        self, connected: bool, error_message: Optional[str] = None
    ) -> None:
        """Emit connection event to event bus.

        Args:
            connected: Connection status
            error_message: Optional error message
        """
        if self.event_bus is None:
            return

        try:
            event = ConnectionEvent(
                router_ip=self.router_ip,
                connected=connected,
                error_message=error_message,
            )
            # Await the async publish method
            if hasattr(self.event_bus, "publish"):
                await self.event_bus.publish(event)
        except Exception as e:
            logger.error(f"Error emitting connection event: {e}")

    async def _emit_labels_event(
        self,
        labels: List[Label],
        source: str,
        operation: str,
        metadata: Optional[Dict] = None,
    ) -> None:
        """Emit labels event to event bus.

        Args:
            labels: List of labels
            source: Source of labels (router, file, default)
            operation: Operation type (download, upload)
            metadata: Optional metadata dictionary
        """
        if self.event_bus is None:
            return

        try:
            # Convert labels to dict format
            labels_data = [label.to_dict() for label in labels]

            event = LabelsEvent(
                labels=labels_data,
                source=source,
                operation=operation,
            )

            # Add metadata to event data
            if metadata:
                event.data.update(metadata)

            # Publish event (await async method)
            if hasattr(self.event_bus, "publish"):
                await self.event_bus.publish(event)
        except Exception as e:
            logger.error(f"Error emitting labels event: {e}")

    def _emit_upload_success_event(
        self, labels: List[Label], success_count: int, error_count: int
    ) -> None:
        """Emit upload success event.

        Args:
            labels: List of uploaded labels
            success_count: Number of successful uploads
            error_count: Number of failed uploads
        """
        self._emit_labels_event(
            labels=labels,
            source="router",
            operation="upload",
            metadata={
                "success_count": success_count,
                "error_count": error_count,
                "total": len(labels),
            },
        )

    async def close(self) -> None:
        """Close all connections and cleanup resources."""
        logger.info(f"Closing API Agent for {self.router_ip}")

        if self._rest_client is not None:
            try:
                await self._rest_client.disconnect()
            except Exception as e:
                logger.warning(f"Error closing REST client: {e}")
            self._rest_client = None

        if self._telnet_client is not None:
            try:
                await self._telnet_client.disconnect()
            except Exception as e:
                logger.warning(f"Error closing Telnet client: {e}")
            self._telnet_client = None


__all__ = [
    "APIAgent",
    "APIAgentError",
]
