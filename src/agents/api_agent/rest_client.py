"""Async REST API client for AJA KUMO routers.

Uses the real AJA KUMO REST API:
  GET /config?action=get&configid=0&paramid=eParamID_XPT_Source{N}_Line_1
  GET /config?action=set&configid=0&paramid=eParamID_XPT_Source{N}_Line_1&value=NewName
"""

import asyncio
import json
import logging
from typing import Dict, List, Optional, Any, Tuple

import aiohttp

from .router_protocols import (
    APIEndpoint,
    ResponseParser,
    DefaultLabelGenerator,
    Protocol,
    KumoParamID,
    KUMO_DEFAULT_COLOR,
    TIMEOUT_REST_REQUEST,
    MAX_RETRIES,
    RETRY_BACKOFF_BASE,
    RETRY_BACKOFF_MULTIPLIER,
)

# Concurrency limit for parallel requests to avoid overwhelming the router.
# 32 works well for KUMO 6464-12G on a LAN; 16 is safer for smaller models.
MAX_CONCURRENT_REQUESTS = 32


logger = logging.getLogger(__name__)


class RestClientError(Exception):
    pass


class RestConnectionError(RestClientError):
    pass


class RestTimeoutError(RestClientError):
    pass


class RestClient:
    """Async REST API client for KUMO routers using the real AJA API."""

    def __init__(
        self,
        router_ip: str,
        max_concurrent_requests: int = MAX_CONCURRENT_REQUESTS,
        request_timeout: float = TIMEOUT_REST_REQUEST,
        connect_timeout: float = 3.0,
        keepalive_timeout: int = 30,
        max_retries: int = MAX_RETRIES,
        retry_backoff_base: float = RETRY_BACKOFF_BASE,
        retry_backoff_multiplier: float = RETRY_BACKOFF_MULTIPLIER,
    ):
        self.router_ip = router_ip
        self.base_url = f"http://{router_ip}"
        self._session: Optional[aiohttp.ClientSession] = None
        self._port_count: int = 32
        self._max_concurrent_requests = max_concurrent_requests
        self._request_timeout = request_timeout
        self._connect_timeout = connect_timeout
        self._keepalive_timeout = keepalive_timeout
        self._max_retries = max_retries
        self._retry_backoff_base = retry_backoff_base
        self._retry_backoff_multiplier = retry_backoff_multiplier

    async def __aenter__(self):
        await self.connect()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        await self.disconnect()

    async def connect(self) -> None:
        if self._session and not self._session.closed:
            return  # Already connected
        connector = aiohttp.TCPConnector(
            limit=self._max_concurrent_requests,
            keepalive_timeout=self._keepalive_timeout,
            enable_cleanup_closed=True,
        )
        timeout = aiohttp.ClientTimeout(
            total=self._request_timeout,
            connect=self._connect_timeout,
            sock_read=self._request_timeout,
        )
        self._session = aiohttp.ClientSession(
            timeout=timeout,
            connector=connector,
        )

    async def disconnect(self) -> None:
        if self._session and not self._session.closed:
            await self._session.close()
        self._session = None

    async def _get(self, endpoint: str, timeout: Optional[float] = None) -> Optional[Dict]:
        """Make a GET request and return parsed JSON."""
        if self._session is None:
            await self.connect()

        url = f"{self.base_url}{endpoint}"
        effective_timeout = timeout if timeout is not None else self._request_timeout

        for attempt in range(self._max_retries):
            try:
                req_timeout = aiohttp.ClientTimeout(total=effective_timeout)
                async with self._session.get(url, timeout=req_timeout) as response:
                    if response.status == 200:
                        try:
                            return await response.json(content_type=None)
                        except (json.JSONDecodeError, ValueError):
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

            if attempt < self._max_retries - 1:
                await asyncio.sleep(self._retry_backoff_base * (self._retry_backoff_multiplier ** attempt))

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
        """Detect router size (16, 32, or 64 ports).

        Probes in parallel for faster detection on LAN.
        """
        # Probe 64-port and 32-port simultaneously
        ep64 = APIEndpoint.get_source_name(33)
        ep32 = APIEndpoint.get_source_name(17)
        r64, r32 = await asyncio.gather(
            self._get(ep64, timeout=3),
            self._get(ep32, timeout=3),
        )

        if r64 and ResponseParser.parse_param_response(r64):
            self._port_count = 64
            return 64
        if r32 and ResponseParser.parse_param_response(r32):
            self._port_count = 32
            return 32

        self._port_count = 16
        return 16

    @property
    def port_count(self) -> int:
        """Get the detected port count."""
        return self._port_count

    async def _fetch_label(
        self, port: int, port_type: str, semaphore: asyncio.Semaphore, line: int = 1
    ) -> Tuple[int, str, int, Optional[str]]:
        """Fetch a single label with concurrency control.

        Args:
            port: Port number
            port_type: 'input' or 'output'
            semaphore: Semaphore for concurrency limiting
            line: Label line number (1 or 2)

        Returns:
            Tuple of (port_number, port_type, line, label_or_None)
        """
        async with semaphore:
            if port_type == "input":
                endpoint = APIEndpoint.get_source_name(port, line=line)
            else:
                endpoint = APIEndpoint.get_dest_name(port, line=line)

            result = await self._get(endpoint)
            label = None
            if result:
                label = ResponseParser.parse_param_response(result)
            return port, port_type, line, label

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
        semaphore = asyncio.Semaphore(self._max_concurrent_requests)

        # Build all fetch tasks for inputs and outputs (Line 1 and Line 2)
        tasks = []
        for port in range(1, port_count + 1):
            tasks.append(self._fetch_label(port, "input", semaphore, line=1))
            tasks.append(self._fetch_label(port, "input", semaphore, line=2))
        for port in range(1, port_count + 1):
            tasks.append(self._fetch_label(port, "output", semaphore, line=1))
            tasks.append(self._fetch_label(port, "output", semaphore, line=2))

        # Execute all fetches concurrently with incremental progress
        total_tasks = len(tasks)
        completed = 0

        async def _tracked_fetch(coro):
            nonlocal completed
            result = await coro
            completed += 1
            if progress_callback and completed % 16 == 0:
                await progress_callback(completed, total_tasks)
            return result

        tracked = [_tracked_fetch(t) for t in tasks]
        results = await asyncio.gather(*tracked, return_exceptions=True)

        if progress_callback:
            await progress_callback(total_tasks, total_tasks)

        # Organize results into labels dict
        input_labels = [""] * port_count
        output_labels = [""] * port_count
        input_labels_line2 = [""] * port_count
        output_labels_line2 = [""] * port_count

        for result in results:
            if isinstance(result, Exception):
                logger.warning(f"Label fetch error: {result}")
                continue

            port, port_type, line, label = result
            if port_type == "input":
                if line == 1:
                    input_labels[port - 1] = label or DefaultLabelGenerator.generate_input_label(port)
                else:
                    input_labels_line2[port - 1] = label or ""
            else:
                if line == 1:
                    output_labels[port - 1] = label or DefaultLabelGenerator.generate_output_label(port)
                else:
                    output_labels_line2[port - 1] = label or ""

        # Fill any gaps with defaults
        for i in range(port_count):
            if not input_labels[i]:
                input_labels[i] = DefaultLabelGenerator.generate_input_label(i + 1)
            if not output_labels[i]:
                output_labels[i] = DefaultLabelGenerator.generate_output_label(i + 1)

        labels = {
            "inputs": input_labels,
            "outputs": output_labels,
            "inputs_line2": input_labels_line2,
            "outputs_line2": output_labels_line2,
        }

        return Protocol.REST, labels

    async def upload_label(
        self, port: int, port_type: str, label: str, line: int = 1
    ) -> Tuple[bool, Optional[str]]:
        """Upload a single label using the real AJA KUMO REST API."""
        if port_type.upper() == "INPUT":
            endpoint = APIEndpoint.set_source_name(port, label, line=line)
        elif port_type.upper() == "OUTPUT":
            endpoint = APIEndpoint.set_dest_name(port, label, line=line)
        else:
            return False, f"Invalid port type: {port_type}"

        result = await self._get(endpoint)
        if result is not None:
            return True, None
        return False, f"Failed to set {port_type} {port} line {line} label"

    async def _upload_single(
        self, label_data: Dict[str, Any], semaphore: asyncio.Semaphore
    ) -> Tuple[bool, Optional[str], Dict[str, Any]]:
        """Upload a single label with concurrency control."""
        async with semaphore:
            port = label_data["port"]
            port_type = label_data["type"]
            label = label_data["label"]
            line = label_data.get("line", 1)
            success, error_msg = await self.upload_label(port, port_type, label, line=line)
            return success, error_msg, label_data

    async def upload_labels_batch(
        self, labels: List[Dict[str, Any]], progress_callback=None
    ) -> Tuple[int, int, List[str]]:
        """Upload multiple labels with parallel execution."""
        semaphore = asyncio.Semaphore(self._max_concurrent_requests)

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

    # ------------------------------------------------------------------
    # Button color methods
    # ------------------------------------------------------------------

    async def _fetch_color(
        self, port: int, port_type: str, semaphore: asyncio.Semaphore
    ) -> Tuple[int, str, int]:
        """Fetch a single button color with concurrency control.

        Returns:
            Tuple of (port_number, port_type, color_id)
        """
        async with semaphore:
            endpoint = APIEndpoint.get_button_color(port, port_type)
            result = await self._get(endpoint)
            color_id = KUMO_DEFAULT_COLOR
            if result and isinstance(result, dict):
                # Button settings store JSON like {"classes":"color_N"} in
                # the "value" field.  parse_param_response() prefers
                # "value_name" which may not contain valid JSON for button
                # settings, so try each candidate directly.
                for key in ("value", "value_name"):
                    candidate = result.get(key)
                    if candidate and isinstance(candidate, str) and "color_" in candidate:
                        color_id = ResponseParser.parse_button_color(candidate.strip())
                        break
                else:
                    # Fallback: use parse_param_response output
                    raw = ResponseParser.parse_param_response(result)
                    color_id = ResponseParser.parse_button_color(raw)
            return port, port_type, color_id

    async def download_colors(
        self, port_count: Optional[int] = None
    ) -> Dict[str, List[int]]:
        """Download all button colors using parallel requests.

        Args:
            port_count: Number of ports per type. Uses detected count if None.

        Returns:
            Dict with 'input_colors' and 'output_colors' lists (1-indexed values)
        """
        pc = port_count or self._port_count
        semaphore = asyncio.Semaphore(self._max_concurrent_requests)

        tasks = []
        for port in range(1, pc + 1):
            tasks.append(self._fetch_color(port, "input", semaphore))
        for port in range(1, pc + 1):
            tasks.append(self._fetch_color(port, "output", semaphore))

        results = await asyncio.gather(*tasks, return_exceptions=True)

        input_colors = [KUMO_DEFAULT_COLOR] * pc
        output_colors = [KUMO_DEFAULT_COLOR] * pc

        for result in results:
            if isinstance(result, Exception):
                logger.warning(f"Color fetch error: {result}")
                continue
            port, port_type, color_id = result
            if port_type == "input":
                input_colors[port - 1] = color_id
            else:
                output_colors[port - 1] = color_id

        return {"input_colors": input_colors, "output_colors": output_colors}

    async def upload_color(
        self, port: int, port_type: str, color_id: int
    ) -> Tuple[bool, Optional[str]]:
        """Upload a single button color.

        Args:
            port: Port number (1-64)
            port_type: 'INPUT' or 'OUTPUT'
            color_id: Color ID (1-9)

        Returns:
            Tuple of (success, error_message)
        """
        pt = "output" if port_type.upper() == "OUTPUT" else "input"
        endpoint = APIEndpoint.set_button_color(port, pt, color_id)
        result = await self._get(endpoint)
        if result is not None:
            return True, None
        return False, f"Failed to set {port_type} {port} color to {color_id}"
