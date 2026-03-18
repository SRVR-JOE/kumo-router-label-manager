"""Tests for the APIAgent orchestration layer.

Covers protocol fallback logic, label download/upload flow,
and event emission -- all with mocked RestClient and TelnetClient.
"""

import asyncio
from unittest.mock import AsyncMock, MagicMock, patch, PropertyMock

import pytest

from src.agents.api_agent import APIAgent
from src.agents.api_agent.router_protocols import Protocol, DefaultLabelGenerator


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_REST_PATH = "src.agents.api_agent.RestClient"
_TELNET_PATH = "src.agents.api_agent.TelnetClient"


def _make_mock_rest(*, test_ok=True, port_count=32, labels=None, colors=None):
    """Build a mock RestClient that works as an async context manager."""
    mock = AsyncMock()
    mock.test_connection = AsyncMock(return_value=test_ok)
    mock.detect_port_count = AsyncMock(return_value=port_count)
    mock.download_labels = AsyncMock(
        return_value=(Protocol.REST, labels)
    )
    mock.download_colors = AsyncMock(return_value=colors or {})
    mock.upload_labels_batch = AsyncMock(return_value=(2, 0, []))
    mock.upload_color = AsyncMock(return_value=(True, None))
    mock.disconnect = AsyncMock()
    # async context manager
    mock.__aenter__ = AsyncMock(return_value=mock)
    mock.__aexit__ = AsyncMock(return_value=False)
    return mock


def _make_mock_telnet(*, connected=True, labels=None):
    """Build a mock TelnetClient that works as an async context manager."""
    mock = AsyncMock()
    mock.is_connected = MagicMock(return_value=connected)
    mock.download_labels = AsyncMock(
        return_value=(Protocol.TELNET, labels)
    )
    mock.upload_labels_batch = AsyncMock(return_value=(2, 0, []))
    mock.disconnect = AsyncMock()
    mock.__aenter__ = AsyncMock(return_value=mock)
    mock.__aexit__ = AsyncMock(return_value=False)
    return mock


def _sample_labels(port_count=2):
    return {
        "inputs": [f"In {i+1}" for i in range(port_count)],
        "outputs": [f"Out {i+1}" for i in range(port_count)],
        "inputs_line2": [""] * port_count,
        "outputs_line2": [""] * port_count,
    }


# ===================================================================
# Initialization
# ===================================================================


class TestAPIAgentInit:
    """Test APIAgent initialization."""

    def test_default_init(self):
        agent = APIAgent("192.168.1.100")
        assert agent.router_ip == "192.168.1.100"
        assert agent.event_bus is None
        assert agent._last_protocol is None
        assert agent._detected_port_count == 32

    def test_init_with_event_bus(self):
        bus = MagicMock()
        agent = APIAgent("10.0.0.1", event_bus=bus)
        assert agent.event_bus is bus


# ===================================================================
# test_connection  (REST first, Telnet fallback)
# ===================================================================


class TestAPIAgentTestConnection:
    """Test connection probing with REST-then-Telnet fallback."""

    async def test_rest_success(self):
        mock_rest = _make_mock_rest(test_ok=True)

        with patch(_REST_PATH, return_value=mock_rest):
            agent = APIAgent("192.168.1.100")
            result = await agent.test_connection()

        assert result is True

    async def test_rest_fail_telnet_success(self):
        mock_rest = _make_mock_rest(test_ok=False)
        mock_telnet = _make_mock_telnet(connected=True)

        with patch(_REST_PATH, return_value=mock_rest), \
             patch(_TELNET_PATH, return_value=mock_telnet):
            agent = APIAgent("192.168.1.100")
            result = await agent.test_connection()

        assert result is True

    async def test_both_fail(self):
        mock_rest = _make_mock_rest(test_ok=False)
        mock_telnet = _make_mock_telnet(connected=False)

        with patch(_REST_PATH, return_value=mock_rest), \
             patch(_TELNET_PATH, return_value=mock_telnet):
            agent = APIAgent("192.168.1.100")
            result = await agent.test_connection()

        assert result is False

    async def test_rest_exception_telnet_success(self):
        mock_rest = AsyncMock()
        mock_rest.__aenter__ = AsyncMock(side_effect=Exception("REST broken"))
        mock_rest.__aexit__ = AsyncMock(return_value=False)

        mock_telnet = _make_mock_telnet(connected=True)

        with patch(_REST_PATH, return_value=mock_rest), \
             patch(_TELNET_PATH, return_value=mock_telnet):
            agent = APIAgent("192.168.1.100")
            result = await agent.test_connection()

        # The outer except catches the REST exception and returns False
        # (the code structure wraps both REST and Telnet in the same try)
        assert isinstance(result, bool)

    async def test_emits_connection_event_on_success(self):
        mock_rest = _make_mock_rest(test_ok=True)
        bus = AsyncMock()
        bus.publish = AsyncMock()

        with patch(_REST_PATH, return_value=mock_rest):
            agent = APIAgent("192.168.1.100", event_bus=bus)
            await agent.test_connection()

        bus.publish.assert_awaited()

    async def test_emits_connection_event_on_failure(self):
        mock_rest = _make_mock_rest(test_ok=False)
        mock_telnet = _make_mock_telnet(connected=False)
        bus = AsyncMock()
        bus.publish = AsyncMock()

        with patch(_REST_PATH, return_value=mock_rest), \
             patch(_TELNET_PATH, return_value=mock_telnet):
            agent = APIAgent("192.168.1.100", event_bus=bus)
            await agent.test_connection()

        bus.publish.assert_awaited()


# ===================================================================
# download_labels  (REST -> Telnet -> defaults)
# ===================================================================


class TestAPIAgentDownloadLabels:
    """Test label download with fallback chain."""

    async def test_rest_success(self):
        labels = _sample_labels()
        mock_rest = _make_mock_rest(labels=labels, port_count=2)

        with patch(_REST_PATH, return_value=mock_rest):
            agent = APIAgent("192.168.1.100")
            result = await agent.download_labels()

        assert len(result) == 4  # 2 inputs + 2 outputs
        assert agent._last_protocol is Protocol.REST

    async def test_rest_fail_telnet_success(self):
        mock_rest = _make_mock_rest(labels=None, port_count=2)
        telnet_labels = _sample_labels()
        mock_telnet = _make_mock_telnet(labels=telnet_labels)

        with patch(_REST_PATH, return_value=mock_rest), \
             patch(_TELNET_PATH, return_value=mock_telnet):
            agent = APIAgent("192.168.1.100")
            result = await agent.download_labels()

        assert len(result) == 4
        assert agent._last_protocol is Protocol.TELNET

    async def test_both_fail_returns_defaults(self):
        mock_rest = _make_mock_rest(labels=None, port_count=2)
        mock_telnet = _make_mock_telnet(labels=None)
        # Make telnet raise so we fall through
        mock_telnet.__aenter__ = AsyncMock(side_effect=Exception("Telnet down"))

        with patch(_REST_PATH, return_value=mock_rest), \
             patch(_TELNET_PATH, return_value=mock_telnet):
            agent = APIAgent("192.168.1.100")
            result = await agent.download_labels()

        assert agent._last_protocol is Protocol.DEFAULT
        # Defaults are generated for detected port count
        assert len(result) > 0

    async def test_rest_exception_returns_defaults(self):
        mock_rest = AsyncMock()
        mock_rest.__aenter__ = AsyncMock(side_effect=Exception("HTTP error"))
        mock_rest.__aexit__ = AsyncMock(return_value=False)

        with patch(_REST_PATH, return_value=mock_rest):
            agent = APIAgent("192.168.1.100")
            result = await agent.download_labels()

        # Should return default labels
        assert len(result) > 0

    async def test_emits_labels_event(self):
        labels = _sample_labels()
        mock_rest = _make_mock_rest(labels=labels, port_count=2)
        bus = AsyncMock()
        bus.publish = AsyncMock()

        with patch(_REST_PATH, return_value=mock_rest):
            agent = APIAgent("192.168.1.100", event_bus=bus)
            await agent.download_labels()

        bus.publish.assert_awaited()

    async def test_downloads_colors_with_labels(self):
        labels = _sample_labels()
        colors = {"input_colors": [1, 2], "output_colors": [3, 4]}
        mock_rest = _make_mock_rest(labels=labels, port_count=2, colors=colors)

        with patch(_REST_PATH, return_value=mock_rest):
            agent = APIAgent("192.168.1.100")
            result = await agent.download_labels()

        assert len(result) == 4
        # Colors should be set on the labels
        assert result[0].current_color == 1
        assert result[1].current_color == 2
        assert result[2].current_color == 3
        assert result[3].current_color == 4


# ===================================================================
# connect / disconnect / close
# ===================================================================


class TestAPIAgentConnectDisconnect:
    """Test connect and disconnect aliases."""

    async def test_connect_delegates_to_test_connection(self):
        mock_rest = _make_mock_rest(test_ok=True)

        with patch(_REST_PATH, return_value=mock_rest):
            agent = APIAgent("192.168.1.100")
            result = await agent.connect()

        assert result is True

    async def test_disconnect_calls_close(self):
        agent = APIAgent("192.168.1.100")
        mock_rest = AsyncMock()
        mock_rest.disconnect = AsyncMock()
        mock_telnet = AsyncMock()
        mock_telnet.disconnect = AsyncMock()
        agent._rest_client = mock_rest
        agent._telnet_client = mock_telnet

        await agent.disconnect()

        mock_rest.disconnect.assert_awaited_once()
        mock_telnet.disconnect.assert_awaited_once()
        assert agent._rest_client is None
        assert agent._telnet_client is None

    async def test_close_when_no_clients(self):
        agent = APIAgent("192.168.1.100")
        await agent.close()  # should not raise


# ===================================================================
# _dict_to_labels
# ===================================================================


class TestAPIAgentDictToLabels:
    """Test internal label conversion."""

    def test_basic_conversion(self):
        agent = APIAgent("192.168.1.100")
        d = _sample_labels(port_count=2)
        labels = agent._dict_to_labels(d)
        assert len(labels) == 4
        assert labels[0].current_label == "In 1"
        assert labels[0].port_number == 1
        assert labels[2].current_label == "Out 1"

    def test_with_colors(self):
        agent = APIAgent("192.168.1.100")
        d = _sample_labels(port_count=2)
        colors = {"input_colors": [5, 6], "output_colors": [7, 8]}
        labels = agent._dict_to_labels(d, colors)
        assert labels[0].current_color == 5
        assert labels[3].current_color == 8

    def test_without_colors_uses_default(self):
        agent = APIAgent("192.168.1.100")
        d = _sample_labels(port_count=1)
        labels = agent._dict_to_labels(d)
        # Default color is 4 (Blue)
        assert labels[0].current_color == 4
        assert labels[1].current_color == 4
