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


class RestClientError(Exception):
    pass


class ConnectionError(RestClientError):
    pass


class TimeoutError(RestClientError):
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
            timeout = aiohttp.ClientTimeout(total=TIMEOUT_REST_REQUEST)
            self._session = aiohttp.ClientSession(timeout=timeout)

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

    async def download_labels(self) -> Tuple[Protocol, Optional[Dict[str, List[str]]]]:
        """Download all labels using the real AJA KUMO REST API.

        Returns:
            Tuple of (protocol_used, labels_dict) where labels_dict has
            'inputs' and 'outputs' lists of label strings
        """
        port_count = self._port_count
        labels = {"inputs": [], "outputs": []}

        # Download source names (inputs)
        for port in range(1, port_count + 1):
            endpoint = APIEndpoint.get_source_name(port)
            result = await self._get(endpoint)
            label = None
            if result:
                label = ResponseParser.parse_param_response(result)
            labels["inputs"].append(label or DefaultLabelGenerator.generate_input_label(port))

        # Download destination names (outputs)
        for port in range(1, port_count + 1):
            endpoint = APIEndpoint.get_dest_name(port)
            result = await self._get(endpoint)
            label = None
            if result:
                label = ResponseParser.parse_param_response(result)
            labels["outputs"].append(label or DefaultLabelGenerator.generate_output_label(port))

        if any(l != DefaultLabelGenerator.generate_input_label(i + 1) for i, l in enumerate(labels["inputs"])):
            return Protocol.REST, labels
        else:
            logger.warning("REST download returned only default labels")
            return Protocol.REST, None

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

    async def upload_labels_batch(
        self, labels: List[Dict[str, Any]], progress_callback=None
    ) -> Tuple[int, int, List[str]]:
        """Upload multiple labels."""
        success_count = 0
        error_count = 0
        error_messages = []
        total = len(labels)

        for idx, label_data in enumerate(labels):
            port = label_data["port"]
            port_type = label_data["type"]
            label = label_data["label"]

            if progress_callback:
                await progress_callback(idx + 1, total, port_type, port)

            success, error_msg = await self.upload_label(port, port_type, label)
            if success:
                success_count += 1
            else:
                error_count += 1
                if error_msg:
                    error_messages.append(error_msg)

        return success_count, error_count, error_messages
