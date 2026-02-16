"""Async REST API client for AJA KUMO routers.

Uses the real AJA KUMO REST API:
  GET /config?action=get&configid=0&paramid=eParamID_XPT_Source{N}_Line_1
  GET /config?action=set&configid=0&paramid=eParamID_XPT_Source{N}_Line_1&value=NewName
"""

import asyncio
import logging
from typing import Dict, List, Optional, Any, Tuple

import aiohttp

from .router_protocols import (
    APIEndpoint,
    ResponseParser,
    DefaultLabelGenerator,
    Protocol,
    KumoParamID,
    TIMEOUT_REST_REQUEST,
    MAX_RETRIES,
    RETRY_BACKOFF_BASE,
    RETRY_BACKOFF_MULTIPLIER,
)


logger = logging.getLogger(__name__)

# Concurrency limit for parallel requests to avoid overwhelming the router
MAX_CONCURRENT_REQUESTS = 16


class RestClientError(Exception):
    pass


class RestConnectionError(RestClientError):
    pass


class RestTimeoutError(RestClientError):
    pass


class RestClient:
    """Async REST API client for KUMO routers using the real AJA API."""

    def __init__(self, router_ip: str):
        self.router_ip = router_ip
        self.base_url = f"http://{router_ip}"
        self._session: Optional[aiohttp.ClientSession] = None
        self._port_count: int = 32

    async def __aenter__(self):
        await self.connect()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        await self.disconnect()

    async def connect(self) -> None:
        if self._session is None:
            connector = aiohttp.TCPConnector(
                limit=MAX_CONCURRENT_REQUESTS,
                keepalive_timeout=30,
            )
            timeout = aiohttp.ClientTimeout(total=TIMEOUT_REST_REQUEST)
            self._session = aiohttp.ClientSession(
                timeout=timeout,
                connector=connector,
            )

    async def disconnect(self) -> None:
        if self._session is not None:
            await self._session.close()
            self._session = None

    async def _get(self, endpoint: str, timeout: float = TIMEOUT_REST_REQUEST) -> Optional[Dict]:
        """Make a GET request and return parsed JSON."""
        if self._session is None:
            await self.connect()

        url = f"{self.base_url}{endpoint}"

        for attempt in range(MAX_RETRIES):
            try:
                req_timeout = aiohttp.ClientTimeout(total=timeout)
                async with self._session.get(url, timeout=req_timeout) as response:
                    if response.status == 200:
                        try:
                            return await response.json()
                        except Exception:
                            text = await response.text()
                            return {"value": text.strip()} if text.strip() else None
                    else:
                        logger.warning(f"HTTP {response.status}: {endpoint}")
            except asyncio.TimeoutError:
                logger.warning(f"Timeout (attempt {attempt + 1}): {endpoint}")
            except aiohttp.ClientError as e:
                logger.warning(f"Client error (attempt {attempt + 1}): {e}")
            except Exception as e:
                logger.error(f"Unexpected error: {e}")

            if attempt < MAX_RETRIES - 1:
                await asyncio.sleep(RETRY_BACKOFF_BASE * (RETRY_BACKOFF_MULTIPLIER ** attempt))

        return None

    async def test_connection(self) -> bool:
        """Test connection by reading the system name."""
        endpoint = APIEndpoint.get_system_name()
        result = await self._get(endpoint, timeout=5)
        if result and ResponseParser.parse_param_response(result):
            return True
        return False

    async def get_system_name(self) -> str:
        """Get the router's system name."""
        endpoint = APIEndpoint.get_system_name()
        result = await self._get(endpoint)
        if result:
            name = ResponseParser.parse_param_response(result)
            if name:
                return name
        return "KUMO"

    async def get_firmware_version(self) -> str:
        """Get the router's firmware version."""
        endpoint = APIEndpoint.get_firmware_version()
        result = await self._get(endpoint)
        if result:
            version = ResponseParser.parse_param_response(result)
            if version:
                return version
        return "Unknown"

    async def detect_port_count(self) -> int:
        """Detect router size (16, 32, or 64 ports)."""
        # Check for 64-port
        endpoint = APIEndpoint.get_source_name(33)
        result = await self._get(endpoint, timeout=3)
        if result and ResponseParser.parse_param_response(result):
            self._port_count = 64
            return 64

        # Check for 32-port (try source 17)
        endpoint = APIEndpoint.get_source_name(17)
        result = await self._get(endpoint, timeout=3)
        if result and ResponseParser.parse_param_response(result):
            self._port_count = 32
            return 32

        self._port_count = 16
        return 16

    @property
    def port_count(self) -> int:
        """Get the detected port count."""
        return self._port_count

    async def _fetch_label(
        self, port: int, port_type: str, semaphore: asyncio.Semaphore
    ) -> Tuple[int, str, Optional[str]]:
        """Fetch a single label with concurrency control.

        Args:
            port: Port number
            port_type: 'input' or 'output'
            semaphore: Semaphore for concurrency limiting

        Returns:
            Tuple of (port_number, port_type, label_or_None)
        """
        async with semaphore:
            if port_type == "input":
                endpoint = APIEndpoint.get_source_name(port)
            else:
                endpoint = APIEndpoint.get_dest_name(port)

            result = await self._get(endpoint)
            label = None
            if result:
                label = ResponseParser.parse_param_response(result)
            return port, port_type, label

    async def download_labels(
        self, progress_callback=None
    ) -> Tuple[Protocol, Optional[Dict[str, List[str]]]]:
        """Download all labels using parallel requests via the AJA KUMO REST API.

        Uses asyncio.gather with a semaphore to download multiple labels
        concurrently while respecting the router's connection limits.

        Args:
            progress_callback: Optional async callback(current, total) for progress

        Returns:
            Tuple of (protocol_used, labels_dict) where labels_dict has
            'inputs' and 'outputs' lists of label strings
        """
        port_count = self._port_count
        semaphore = asyncio.Semaphore(MAX_CONCURRENT_REQUESTS)

        # Build all fetch tasks for inputs and outputs
        tasks = []
        for port in range(1, port_count + 1):
            tasks.append(self._fetch_label(port, "input", semaphore))
        for port in range(1, port_count + 1):
            tasks.append(self._fetch_label(port, "output", semaphore))

        # Execute all fetches concurrently
        total_tasks = len(tasks)
        results = await asyncio.gather(*tasks, return_exceptions=True)

        if progress_callback:
            await progress_callback(total_tasks, total_tasks)

        # Organize results into labels dict
        input_labels = [""] * port_count
        output_labels = [""] * port_count

        for result in results:
            if isinstance(result, Exception):
                logger.warning(f"Label fetch error: {result}")
                continue

            port, port_type, label = result
            if port_type == "input":
                input_labels[port - 1] = label or DefaultLabelGenerator.generate_input_label(port)
            else:
                output_labels[port - 1] = label or DefaultLabelGenerator.generate_output_label(port)

        # Fill any gaps with defaults
        for i in range(port_count):
            if not input_labels[i]:
                input_labels[i] = DefaultLabelGenerator.generate_input_label(i + 1)
            if not output_labels[i]:
                output_labels[i] = DefaultLabelGenerator.generate_output_label(i + 1)

        labels = {"inputs": input_labels, "outputs": output_labels}

        return Protocol.REST, labels

    async def upload_label(
        self, port: int, port_type: str, label: str
    ) -> Tuple[bool, Optional[str]]:
        """Upload a single label using the real AJA KUMO REST API."""
        if port_type.upper() == "INPUT":
            endpoint = APIEndpoint.set_source_name(port, label)
        elif port_type.upper() == "OUTPUT":
            endpoint = APIEndpoint.set_dest_name(port, label)
        else:
            return False, f"Invalid port type: {port_type}"

        result = await self._get(endpoint)
        if result is not None:
            return True, None
        return False, f"Failed to set {port_type} {port} label"

    async def _upload_single(
        self, label_data: Dict[str, Any], semaphore: asyncio.Semaphore
    ) -> Tuple[bool, Optional[str], Dict[str, Any]]:
        """Upload a single label with concurrency control."""
        async with semaphore:
            port = label_data["port"]
            port_type = label_data["type"]
            label = label_data["label"]
            success, error_msg = await self.upload_label(port, port_type, label)
            return success, error_msg, label_data

    async def upload_labels_batch(
        self, labels: List[Dict[str, Any]], progress_callback=None
    ) -> Tuple[int, int, List[str]]:
        """Upload multiple labels with parallel execution."""
        semaphore = asyncio.Semaphore(MAX_CONCURRENT_REQUESTS)

        tasks = [self._upload_single(ld, semaphore) for ld in labels]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        success_count = 0
        error_count = 0
        error_messages = []

        for result in results:
            if isinstance(result, Exception):
                error_count += 1
                error_messages.append(str(result))
            else:
                success, error_msg, _ = result
                if success:
                    success_count += 1
                else:
                    error_count += 1
                    if error_msg:
                        error_messages.append(error_msg)

        if progress_callback:
            await progress_callback(len(labels), len(labels))

        return success_count, error_count, error_messages
