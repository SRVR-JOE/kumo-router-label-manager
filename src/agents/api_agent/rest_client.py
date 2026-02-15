"""Async REST API client for AJA KUMO routers.

This module provides an async HTTP client for communicating with KUMO routers
via their REST API endpoints.
"""

import asyncio
import logging
from typing import Dict, List, Optional, Any, Tuple
from datetime import datetime

import aiohttp

from .router_protocols import (
    APIEndpoint,
    ResponseParser,
    DefaultLabelGenerator,
    Protocol,
    TIMEOUT_BULK_REQUEST,
    TIMEOUT_INDIVIDUAL_REQUEST,
    DELAY_REST_REQUEST,
    DELAY_UPLOAD_REQUEST,
    MAX_RETRIES,
    RETRY_BACKOFF_BASE,
    RETRY_BACKOFF_MULTIPLIER,
)


logger = logging.getLogger(__name__)


class RestClientError(Exception):
    """Base exception for REST client errors."""

    pass


class ConnectionError(RestClientError):
    """Exception raised when connection to router fails."""

    pass


class TimeoutError(RestClientError):
    """Exception raised when request times out."""

    pass


class RestClient:
    """Async REST API client for KUMO routers.

    Provides methods for downloading and uploading port labels via REST API.
    Implements retry logic with exponential backoff and multiple endpoint fallbacks.
    """

    def __init__(self, router_ip: str):
        """Initialize REST client.

        Args:
            router_ip: IP address of the KUMO router
        """
        self.router_ip = router_ip
        self.base_url = f"http://{router_ip}"
        self._session: Optional[aiohttp.ClientSession] = None

    async def __aenter__(self):
        """Async context manager entry."""
        await self.connect()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        await self.disconnect()

    async def connect(self) -> None:
        """Create HTTP session."""
        if self._session is None:
            timeout = aiohttp.ClientTimeout(total=TIMEOUT_BULK_REQUEST)
            self._session = aiohttp.ClientSession(timeout=timeout)
            logger.info(f"REST client connected to {self.router_ip}")

    async def disconnect(self) -> None:
        """Close HTTP session."""
        if self._session is not None:
            await self._session.close()
            self._session = None
            logger.info(f"REST client disconnected from {self.router_ip}")

    async def _make_request(
        self,
        method: str,
        endpoint: str,
        timeout: float = TIMEOUT_BULK_REQUEST,
        json_data: Optional[Dict] = None,
        retries: int = MAX_RETRIES,
    ) -> Tuple[bool, Optional[Any]]:
        """Make HTTP request with retry logic.

        Args:
            method: HTTP method (GET, PUT, POST)
            endpoint: API endpoint path
            timeout: Request timeout in seconds
            json_data: Optional JSON data for POST/PUT requests
            retries: Number of retry attempts

        Returns:
            Tuple of (success, response_data)
        """
        if self._session is None:
            await self.connect()

        url = f"{self.base_url}{endpoint}"
        last_error = None

        for attempt in range(retries):
            try:
                # Calculate timeout for this attempt
                request_timeout = aiohttp.ClientTimeout(total=timeout)

                async with self._session.request(
                    method,
                    url,
                    json=json_data,
                    timeout=request_timeout,
                ) as response:
                    if response.status == 200:
                        # Try to parse as JSON
                        try:
                            data = await response.json()
                            logger.debug(f"Request succeeded: {method} {endpoint}")
                            return True, data
                        except Exception:
                            # Return text if not JSON
                            text = await response.text()
                            logger.debug(f"Request succeeded (text): {method} {endpoint}")
                            return True, text
                    else:
                        logger.warning(
                            f"Request failed with status {response.status}: {method} {endpoint}"
                        )
                        last_error = f"HTTP {response.status}"

            except asyncio.TimeoutError:
                last_error = f"Timeout after {timeout}s"
                logger.warning(f"Request timeout (attempt {attempt + 1}/{retries}): {endpoint}")

            except aiohttp.ClientError as e:
                last_error = str(e)
                logger.warning(f"Request error (attempt {attempt + 1}/{retries}): {endpoint} - {e}")

            except Exception as e:
                last_error = str(e)
                logger.error(f"Unexpected error (attempt {attempt + 1}/{retries}): {endpoint} - {e}")

            # Exponential backoff before retry
            if attempt < retries - 1:
                backoff = RETRY_BACKOFF_BASE * (RETRY_BACKOFF_MULTIPLIER ** attempt)
                await asyncio.sleep(backoff)

        logger.error(f"Request failed after {retries} attempts: {method} {endpoint} - {last_error}")
        return False, None

    async def test_connection(self) -> bool:
        """Test connection to router.

        Returns:
            True if router is reachable, False otherwise
        """
        logger.info(f"Testing connection to {self.router_ip}")

        # Try each bulk endpoint to find one that works
        for endpoint in APIEndpoint.get_bulk_endpoints():
            success, _ = await self._make_request("GET", endpoint, timeout=5, retries=1)
            if success:
                logger.info(f"Connection test successful via {endpoint}")
                return True

        logger.warning(f"Connection test failed to {self.router_ip}")
        return False

    async def download_labels_bulk(self) -> Tuple[Protocol, Optional[Dict[str, List[str]]]]:
        """Download all labels using bulk endpoints.

        Returns:
            Tuple of (protocol_used, labels_dict) where labels_dict contains
            'inputs' and 'outputs' lists, or (Protocol.REST_BULK, None) if failed
        """
        logger.info(f"Attempting bulk label download from {self.router_ip}")

        for endpoint in APIEndpoint.get_bulk_endpoints():
            logger.debug(f"Trying bulk endpoint: {endpoint}")

            success, response = await self._make_request(
                "GET", endpoint, timeout=TIMEOUT_BULK_REQUEST, retries=2
            )

            if success and response:
                # Try to parse response
                if isinstance(response, dict):
                    labels = ResponseParser.parse_bulk_config(response)
                    if labels:
                        logger.info(
                            f"Bulk download successful via {endpoint} - "
                            f"{len(labels['inputs'])} inputs, {len(labels['outputs'])} outputs"
                        )
                        return Protocol.REST_BULK, labels

        logger.warning("Bulk label download failed - no valid responses")
        return Protocol.REST_BULK, None

    async def download_labels_individual(self) -> Tuple[Protocol, Optional[Dict[str, List[str]]]]:
        """Download labels by querying each port individually.

        Returns:
            Tuple of (protocol_used, labels_dict) where labels_dict contains
            'inputs' and 'outputs' lists, or (Protocol.REST_INDIVIDUAL, None) if failed
        """
        logger.info(f"Attempting individual port label download from {self.router_ip}")

        labels = {"inputs": [], "outputs": []}
        success_count = 0

        # Query all inputs
        for port in range(1, 33):
            label = await self._query_input_label(port)
            if label:
                labels["inputs"].append(label)
                success_count += 1
            else:
                labels["inputs"].append(DefaultLabelGenerator.generate_input_label(port))

            await asyncio.sleep(DELAY_REST_REQUEST)

        # Query all outputs
        for port in range(1, 33):
            label = await self._query_output_label(port)
            if label:
                labels["outputs"].append(label)
                success_count += 1
            else:
                labels["outputs"].append(DefaultLabelGenerator.generate_output_label(port))

            await asyncio.sleep(DELAY_REST_REQUEST)

        if success_count > 0:
            logger.info(
                f"Individual download successful - {success_count}/64 ports retrieved"
            )
            return Protocol.REST_INDIVIDUAL, labels
        else:
            logger.warning("Individual label download failed - no valid responses")
            return Protocol.REST_INDIVIDUAL, None

    async def _query_input_label(self, port: int) -> Optional[str]:
        """Query label for a specific input port.

        Args:
            port: Port number (1-32)

        Returns:
            Label text, or None if query failed
        """
        for endpoint in APIEndpoint.get_individual_input_endpoints(port):
            success, response = await self._make_request(
                "GET", endpoint, timeout=TIMEOUT_INDIVIDUAL_REQUEST, retries=1
            )

            if success and response:
                label = ResponseParser.parse_individual_port(response)
                if label:
                    logger.debug(f"Input {port} label: {label}")
                    return label

        logger.debug(f"Failed to query input {port} label")
        return None

    async def _query_output_label(self, port: int) -> Optional[str]:
        """Query label for a specific output port.

        Args:
            port: Port number (1-32)

        Returns:
            Label text, or None if query failed
        """
        for endpoint in APIEndpoint.get_individual_output_endpoints(port):
            success, response = await self._make_request(
                "GET", endpoint, timeout=TIMEOUT_INDIVIDUAL_REQUEST, retries=1
            )

            if success and response:
                label = ResponseParser.parse_individual_port(response)
                if label:
                    logger.debug(f"Output {port} label: {label}")
                    return label

        logger.debug(f"Failed to query output {port} label")
        return None

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
        # Determine endpoint based on port type
        if port_type.upper() == "INPUT":
            endpoint = APIEndpoint.INPUT_LABEL_UPDATE.format(port=port)
        elif port_type.upper() == "OUTPUT":
            endpoint = APIEndpoint.OUTPUT_LABEL_UPDATE.format(port=port)
        else:
            return False, f"Invalid port type: {port_type}"

        # Prepare request body
        body = {"label": label}

        # Try PUT request
        success, response = await self._make_request(
            "PUT", endpoint, timeout=TIMEOUT_INDIVIDUAL_REQUEST, json_data=body, retries=2
        )

        if success:
            logger.debug(f"Uploaded {port_type} {port} label: {label}")
            return True, None

        # Try alternative CGI endpoint with POST
        cgi_endpoint = APIEndpoint.CGI_SET_LABEL
        cgi_body = {
            "type": port_type.lower(),
            "port": port,
            "label": label,
        }

        success, response = await self._make_request(
            "POST", cgi_endpoint, timeout=TIMEOUT_INDIVIDUAL_REQUEST, json_data=cgi_body, retries=2
        )

        if success:
            logger.debug(f"Uploaded {port_type} {port} label via CGI: {label}")
            return True, None

        error_msg = f"Failed to upload {port_type} {port} label"
        logger.warning(error_msg)
        return False, error_msg

    async def upload_labels_batch(
        self, labels: List[Dict[str, Any]], progress_callback=None
    ) -> Tuple[int, int, List[str]]:
        """Upload multiple labels to the router.

        Args:
            labels: List of label dictionaries with 'port', 'type', 'label' keys
            progress_callback: Optional async callback(current, total, port_type, port)

        Returns:
            Tuple of (success_count, error_count, error_messages)
        """
        logger.info(f"Uploading {len(labels)} labels to {self.router_ip}")

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

            # Delay between requests
            await asyncio.sleep(DELAY_UPLOAD_REQUEST)

        logger.info(
            f"Upload complete - {success_count} succeeded, {error_count} failed"
        )
        return success_count, error_count, error_messages
