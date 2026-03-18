"""Tests for the TelnetClient network client.

Covers initialization, connection lifecycle, command sending,
label download/upload, and timeout handling -- all with mocked TCP I/O.
"""

import asyncio
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from src.agents.api_agent.telnet_client import (
    TelnetClient,
    TelnetCommandError,
    TelnetConnectionError,
)
from src.agents.api_agent.router_protocols import Protocol


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _make_reader_writer():
    """Create mocked asyncio StreamReader / StreamWriter pair."""
    reader = AsyncMock(spec=asyncio.StreamReader)
    writer = MagicMock(spec=asyncio.StreamWriter)
    writer.write = MagicMock()
    writer.drain = AsyncMock()
    writer.close = MagicMock()
    writer.wait_closed = AsyncMock()
    return reader, writer


# ===================================================================
# Initialization
# ===================================================================


class TestTelnetClientInit:
    """Test TelnetClient initialization and configuration."""

    def test_default_config(self):
        client = TelnetClient("192.168.1.100")
        assert client.router_ip == "192.168.1.100"
        assert client.port == 23
        assert client._port_count == 32
        assert client._connected is False
        assert client._reader is None
        assert client._writer is None

    def test_custom_config(self):
        client = TelnetClient(
            "10.0.0.1",
            port=2323,
            port_count=64,
            connect_timeout=10.0,
            command_timeout=5.0,
            command_delay=0.5,
            initial_delay=1.0,
        )
        assert client.port == 2323
        assert client._port_count == 64
        assert client._connect_timeout == 10.0
        assert client._command_timeout == 5.0
        assert client._command_delay == 0.5
        assert client._initial_delay == 1.0

    def test_is_connected_initially_false(self):
        client = TelnetClient("192.168.1.100")
        assert client.is_connected() is False


# ===================================================================
# Connection lifecycle
# ===================================================================


class TestTelnetClientConnect:
    """Test connect / disconnect lifecycle with mocked TCP."""

    async def test_connect_sets_connected(self):
        reader, writer = _make_reader_writer()
        # reader.read for clearing the welcome banner
        reader.read = AsyncMock(return_value=b"Welcome\n")

        client = TelnetClient("192.168.1.100", initial_delay=0, command_delay=0)

        with patch("asyncio.open_connection", return_value=(reader, writer)):
            await client.connect()

        assert client.is_connected() is True
        assert client._reader is reader
        assert client._writer is writer

        await client.disconnect()

    async def test_double_connect_is_noop(self):
        reader, writer = _make_reader_writer()
        reader.read = AsyncMock(return_value=b"")

        client = TelnetClient("192.168.1.100", initial_delay=0)

        with patch("asyncio.open_connection", return_value=(reader, writer)) as mock_open:
            await client.connect()
            await client.connect()  # should not call open_connection again
            assert mock_open.call_count == 1

        await client.disconnect()

    async def test_disconnect_clears_state(self):
        reader, writer = _make_reader_writer()
        reader.read = AsyncMock(return_value=b"")

        client = TelnetClient("192.168.1.100", initial_delay=0)

        with patch("asyncio.open_connection", return_value=(reader, writer)):
            await client.connect()

        await client.disconnect()
        assert client.is_connected() is False
        assert client._reader is None
        assert client._writer is None

    async def test_disconnect_when_not_connected(self):
        client = TelnetClient("192.168.1.100")
        await client.disconnect()  # should not raise
        assert client.is_connected() is False

    async def test_connect_timeout_raises(self):
        client = TelnetClient("192.168.1.100", connect_timeout=0.01)

        async def slow_open(*a, **kw):
            await asyncio.sleep(10)

        with patch("asyncio.open_connection", side_effect=slow_open):
            with pytest.raises(TelnetConnectionError, match="timeout"):
                await client.connect()

        assert client.is_connected() is False

    async def test_connect_os_error_raises(self):
        client = TelnetClient("192.168.1.100")

        with patch(
            "asyncio.open_connection",
            side_effect=OSError("Connection refused"),
        ):
            with pytest.raises(TelnetConnectionError, match="Connection failed"):
                await client.connect()

        assert client.is_connected() is False


# ===================================================================
# Async context manager
# ===================================================================


class TestTelnetClientContextManager:
    """Test async context manager usage."""

    async def test_context_manager(self):
        reader, writer = _make_reader_writer()
        reader.read = AsyncMock(return_value=b"")

        with patch("asyncio.open_connection", return_value=(reader, writer)):
            async with TelnetClient("192.168.1.100", initial_delay=0) as client:
                assert client.is_connected() is True
            # After exit
            assert client.is_connected() is False


# ===================================================================
# _send_command
# ===================================================================


class TestTelnetClientSendCommand:
    """Test command sending with mocked reader/writer."""

    async def test_send_command_success(self):
        reader, writer = _make_reader_writer()
        reader.read = AsyncMock(return_value=b"")
        reader.readline = AsyncMock(return_value=b'"Camera 1"\n')

        client = TelnetClient("192.168.1.100", initial_delay=0)

        with patch("asyncio.open_connection", return_value=(reader, writer)):
            await client.connect()

        response = await client._send_command("LABEL INPUT 1 ?")
        assert response == '"Camera 1"'
        writer.write.assert_called_with(b"LABEL INPUT 1 ?\n")
        writer.drain.assert_awaited()

        await client.disconnect()

    async def test_send_command_not_connected(self):
        client = TelnetClient("192.168.1.100")
        with pytest.raises(TelnetCommandError, match="Not connected"):
            await client._send_command("LABEL INPUT 1 ?")

    async def test_send_command_timeout_returns_none(self):
        reader, writer = _make_reader_writer()
        reader.read = AsyncMock(return_value=b"")

        async def slow_readline():
            await asyncio.sleep(10)

        reader.readline = slow_readline

        client = TelnetClient("192.168.1.100", initial_delay=0, command_timeout=0.01)

        with patch("asyncio.open_connection", return_value=(reader, writer)):
            await client.connect()

        result = await client._send_command("LABEL INPUT 1 ?")
        assert result is None

        await client.disconnect()

    async def test_send_command_exception_returns_none(self):
        reader, writer = _make_reader_writer()
        reader.read = AsyncMock(return_value=b"")
        reader.readline = AsyncMock(side_effect=ConnectionResetError("reset"))

        client = TelnetClient("192.168.1.100", initial_delay=0)

        with patch("asyncio.open_connection", return_value=(reader, writer)):
            await client.connect()

        result = await client._send_command("LABEL INPUT 1 ?")
        assert result is None

        await client.disconnect()


# ===================================================================
# download_labels
# ===================================================================


class TestTelnetClientDownloadLabels:
    """Test label download with mocked command responses."""

    async def test_download_labels_success(self):
        client = TelnetClient(
            "192.168.1.100", port_count=2, initial_delay=0, command_delay=0
        )
        client._connected = True
        client._reader = AsyncMock()
        client._writer = MagicMock()

        call_idx = 0
        responses = [
            '"Cam 1"',   # input 1
            '"Cam 2"',   # input 2
            '"Mon 1"',   # output 1
            '"Mon 2"',   # output 2
        ]

        async def fake_send(cmd):
            nonlocal call_idx
            resp = responses[call_idx] if call_idx < len(responses) else None
            call_idx += 1
            return resp

        with patch.object(client, "_send_command", side_effect=fake_send):
            protocol, labels = await client.download_labels()

        assert protocol is Protocol.TELNET
        assert labels is not None
        assert labels["inputs"] == ["Cam 1", "Cam 2"]
        assert labels["outputs"] == ["Mon 1", "Mon 2"]
        # Telnet does not support line 2
        assert labels["inputs_line2"] == ["", ""]
        assert labels["outputs_line2"] == ["", ""]

    async def test_download_labels_all_fail_returns_none(self):
        client = TelnetClient(
            "192.168.1.100", port_count=2, initial_delay=0, command_delay=0
        )
        client._connected = True
        client._reader = AsyncMock()
        client._writer = MagicMock()

        with patch.object(client, "_send_command", return_value=None):
            protocol, labels = await client.download_labels()

        assert protocol is Protocol.TELNET
        assert labels is None  # no valid responses -> None

    async def test_download_labels_partial_uses_defaults(self):
        client = TelnetClient(
            "192.168.1.100", port_count=2, initial_delay=0, command_delay=0
        )
        client._connected = True
        client._reader = AsyncMock()
        client._writer = MagicMock()

        call_idx = 0

        async def partial_send(cmd):
            nonlocal call_idx
            call_idx += 1
            # Only first input succeeds
            if call_idx == 1:
                return '"Cam 1"'
            return None

        with patch.object(client, "_send_command", side_effect=partial_send):
            protocol, labels = await client.download_labels()

        assert protocol is Protocol.TELNET
        assert labels is not None
        assert labels["inputs"][0] == "Cam 1"
        assert labels["inputs"][1] == "Source 2"  # default
        assert labels["outputs"][0] == "Dest 1"  # default
        assert labels["outputs"][1] == "Dest 2"  # default


# ===================================================================
# upload_label / upload_labels_batch
# ===================================================================


class TestTelnetClientUpload:
    """Test label upload methods."""

    async def test_upload_label_success(self):
        client = TelnetClient("192.168.1.100", initial_delay=0, command_delay=0)
        client._connected = True
        client._reader = AsyncMock()
        client._writer = MagicMock()

        with patch.object(client, "_send_command", return_value="OK"):
            ok, err = await client.upload_label(1, "INPUT", "Cam 1")
            assert ok is True
            assert err is None

    async def test_upload_label_failure(self):
        client = TelnetClient("192.168.1.100", initial_delay=0, command_delay=0)
        client._connected = True
        client._reader = AsyncMock()
        client._writer = MagicMock()

        with patch.object(client, "_send_command", return_value=None):
            ok, err = await client.upload_label(1, "OUTPUT", "Mon 1")
            assert ok is False
            assert err is not None

    async def test_upload_label_invalid_type(self):
        client = TelnetClient("192.168.1.100", initial_delay=0, command_delay=0)
        client._connected = True
        client._reader = AsyncMock()
        client._writer = MagicMock()

        ok, err = await client.upload_label(1, "BOGUS", "test")
        assert ok is False
        assert "Invalid" in err

    async def test_upload_labels_batch(self):
        client = TelnetClient(
            "192.168.1.100", initial_delay=0, command_delay=0
        )
        client._connected = True
        client._reader = AsyncMock()
        client._writer = MagicMock()

        data = [
            {"port": 1, "type": "INPUT", "label": "Cam 1", "line": 1},
            {"port": 2, "type": "OUTPUT", "label": "Mon 2", "line": 1},
        ]

        with patch.object(client, "_send_command", return_value="OK"):
            success, errors, msgs = await client.upload_labels_batch(data)
            assert success == 2
            assert errors == 0

    async def test_upload_labels_batch_skips_line2(self):
        client = TelnetClient(
            "192.168.1.100", initial_delay=0, command_delay=0
        )
        client._connected = True
        client._reader = AsyncMock()
        client._writer = MagicMock()

        data = [
            {"port": 1, "type": "INPUT", "label": "Cam 1", "line": 1},
            {"port": 1, "type": "INPUT", "label": "line2", "line": 2},
        ]

        with patch.object(client, "_send_command", return_value="OK"):
            success, errors, msgs = await client.upload_labels_batch(data)
            # Only line 1 should be uploaded; line 2 is skipped
            assert success == 1
            assert errors == 0
