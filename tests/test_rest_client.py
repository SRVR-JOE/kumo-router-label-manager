"""Tests for the RestClient network client.

Covers initialization, connection lifecycle, HTTP request handling,
port detection, and label download with mocked aiohttp sessions.
"""

import asyncio
import json
from unittest.mock import AsyncMock, MagicMock, patch

import aiohttp
import pytest

from src.agents.api_agent.rest_client import RestClient
from src.agents.api_agent.router_protocols import Protocol


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _mock_json_response(data, status=200):
    """Build an AsyncMock that behaves like an aiohttp response context manager."""
    resp = AsyncMock()
    resp.status = status
    resp.json = AsyncMock(return_value=data)
    resp.text = AsyncMock(return_value=json.dumps(data) if data else "")
    resp.__aenter__ = AsyncMock(return_value=resp)
    resp.__aexit__ = AsyncMock(return_value=False)
    return resp


# ===================================================================
# Initialization
# ===================================================================


class TestRestClientInit:
    """Test RestClient initialization and configuration."""

    def test_default_config(self):
        client = RestClient("192.168.1.100")
        assert client.router_ip == "192.168.1.100"
        assert client.base_url == "http://192.168.1.100"
        assert client._session is None
        assert client._port_count == 32

    def test_custom_timeouts(self):
        client = RestClient(
            "10.0.0.1",
            request_timeout=10.0,
            max_concurrent_requests=16,
            connect_timeout=5.0,
            max_retries=5,
            retry_backoff_base=0.5,
            retry_backoff_multiplier=3,
        )
        assert client._request_timeout == 10.0
        assert client._max_concurrent_requests == 16
        assert client._connect_timeout == 5.0
        assert client._max_retries == 5
        assert client._retry_backoff_base == 0.5
        assert client._retry_backoff_multiplier == 3

    def test_port_count_property(self):
        client = RestClient("10.0.0.1")
        assert client.port_count == 32


# ===================================================================
# Connection lifecycle
# ===================================================================


class TestRestClientConnect:
    """Test connection lifecycle."""

    async def test_connect_creates_session(self):
        client = RestClient("192.168.1.100")
        await client.connect()
        assert client._session is not None
        assert not client._session.closed
        await client.disconnect()

    async def test_double_connect_reuses_session(self):
        client = RestClient("192.168.1.100")
        await client.connect()
        session1 = client._session
        await client.connect()  # should be a no-op
        assert client._session is session1
        await client.disconnect()

    async def test_disconnect_clears_session(self):
        client = RestClient("192.168.1.100")
        await client.connect()
        await client.disconnect()
        assert client._session is None

    async def test_double_disconnect_is_safe(self):
        client = RestClient("192.168.1.100")
        await client.connect()
        await client.disconnect()
        await client.disconnect()  # should not raise
        assert client._session is None


# ===================================================================
# Async context manager
# ===================================================================


class TestRestClientContextManager:
    """Test async context manager usage."""

    async def test_context_manager_opens_and_closes(self):
        async with RestClient("192.168.1.100") as client:
            assert client._session is not None
        # After exiting the context, session should be cleared
        assert client._session is None


# ===================================================================
# _get method
# ===================================================================


class TestRestClientGet:
    """Test the _get method with mocked HTTP responses."""

    async def test_successful_json_response(self):
        client = RestClient("192.168.1.100")
        await client.connect()

        mock_resp = _mock_json_response({"value_name": "Camera 1"})
        with patch.object(client._session, "get", return_value=mock_resp):
            result = await client._get("/config?action=get&paramid=test")
            assert result == {"value_name": "Camera 1"}

        await client.disconnect()

    async def test_non_200_returns_none_after_retries(self):
        client = RestClient("192.168.1.100", max_retries=1)
        await client.connect()

        mock_resp = _mock_json_response(None, status=404)
        with patch.object(client._session, "get", return_value=mock_resp):
            result = await client._get("/config?bad=1")
            assert result is None

        await client.disconnect()

    async def test_timeout_retries_then_returns_none(self):
        client = RestClient(
            "192.168.1.100",
            max_retries=2,
            retry_backoff_base=0.01,
            retry_backoff_multiplier=1,
        )
        await client.connect()

        with patch.object(
            client._session, "get", side_effect=asyncio.TimeoutError()
        ):
            result = await client._get("/config?test=1")
            assert result is None

        await client.disconnect()

    async def test_client_error_retries(self):
        client = RestClient(
            "192.168.1.100",
            max_retries=2,
            retry_backoff_base=0.01,
            retry_backoff_multiplier=1,
        )
        await client.connect()

        with patch.object(
            client._session,
            "get",
            side_effect=aiohttp.ClientError("conn refused"),
        ):
            result = await client._get("/config?test=1")
            assert result is None

        await client.disconnect()

    async def test_auto_connects_if_no_session(self):
        client = RestClient("192.168.1.100", max_retries=1)
        assert client._session is None

        mock_resp = _mock_json_response({"value": "ok"})
        # Patch aiohttp.ClientSession so the auto-created session has our mock
        with patch("aiohttp.ClientSession") as MockSession:
            mock_session = AsyncMock()
            mock_session.get = MagicMock(return_value=mock_resp)
            mock_session.closed = False
            mock_session.close = AsyncMock()
            MockSession.return_value = mock_session

            result = await client._get("/config?test=1")
            assert result == {"value": "ok"}

        await client.disconnect()

    async def test_custom_timeout_passed(self):
        client = RestClient("192.168.1.100", max_retries=1)
        await client.connect()

        mock_resp = _mock_json_response({"value": "ok"})
        with patch.object(client._session, "get", return_value=mock_resp) as mock_get:
            await client._get("/config?test=1", timeout=99.0)
            # Verify the call was made (the timeout kwarg is an aiohttp.ClientTimeout)
            mock_get.assert_called_once()
            call_kwargs = mock_get.call_args
            assert call_kwargs is not None

        await client.disconnect()


# ===================================================================
# test_connection
# ===================================================================


class TestRestClientTestConnection:
    """Test the test_connection convenience method."""

    async def test_returns_true_on_valid_response(self):
        client = RestClient("192.168.1.100")

        async def fake_get(endpoint, timeout=None):
            return {"value_name": "MyKumo"}

        with patch.object(client, "_get", side_effect=fake_get):
            assert await client.test_connection() is True

    async def test_returns_false_on_none(self):
        client = RestClient("192.168.1.100")

        with patch.object(client, "_get", return_value=None):
            assert await client.test_connection() is False


# ===================================================================
# detect_port_count
# ===================================================================


def _detection_responses(mapping):
    """Build a fake ``_get`` that answers by source port number.

    ``mapping`` maps port number -> the value the router returns, or ``None``
    for "the router refuses this port". Ports absent from the mapping are
    treated as refused.
    """

    async def fake_get(endpoint, timeout=None):
        for port in sorted(mapping, reverse=True):
            if f"Source{port}_" in endpoint or endpoint.endswith(f"Source{port}"):
                value = mapping[port]
                return None if value is None else {"value_name": value}
        return None

    return fake_get


class TestRestClientDetectPortCount:
    """Test router size detection (16, 32, 64 ports)."""

    async def test_detects_64_port(self):
        client = RestClient("192.168.1.100")
        # A real 6464: port 33 carries a label, the impossible port 100 does not.
        fake_get = _detection_responses({33: "CAM A", 17: "CAM B", 100: None})

        with patch.object(client, "_get", side_effect=fake_get):
            count = await client.detect_port_count()
            assert count == 64
            assert client.port_count == 64

    async def test_detects_32_port(self):
        client = RestClient("192.168.1.100")
        fake_get = _detection_responses({33: None, 17: "Port 17", 100: None})

        with patch.object(client, "_get", side_effect=fake_get):
            count = await client.detect_port_count()
            assert count == 32

    async def test_detects_16_port(self):
        client = RestClient("192.168.1.100")

        with patch.object(client, "_get", return_value=None):
            count = await client.detect_port_count()
            assert count == 16


class TestRestClientPhantomPortDetection:
    """Firmware that answers reads for ports the chassis does not have.

    Treating any reply as proof of existence sized a KUMO 3232 as a 6464,
    which then wrote labels to ports that were not there.
    """

    async def test_fixed_filler_firmware_is_not_read_as_64_port(self):
        client = RestClient("192.168.1.100")
        # Every non-existent port echoes the same filler, port 100 included.
        fake_get = _detection_responses({33: "---", 17: "IN 17", 100: "---"})

        with patch.object(client, "_get", side_effect=fake_get):
            assert await client.detect_port_count() == 32

    async def test_auto_naming_firmware_is_not_read_as_64_port(self):
        client = RestClient("192.168.1.100")
        # Non-existent ports come back auto-named from their own index.
        fake_get = _detection_responses(
            {33: "Source 33", 17: "IN 17", 100: "Source 100"}
        )

        with patch.object(client, "_get", side_effect=fake_get):
            assert await client.detect_port_count() == 32

    async def test_auto_naming_firmware_still_detects_a_real_64_port(self):
        client = RestClient("192.168.1.100")
        # Port 33 carries a user label, so it is real despite the chatty firmware.
        fake_get = _detection_responses(
            {33: "CAM A", 17: "IN 17", 100: "Source 100"}
        )

        with patch.object(client, "_get", side_effect=fake_get):
            assert await client.detect_port_count() == 64

    async def test_auto_naming_firmware_falls_through_to_16(self):
        client = RestClient("192.168.1.100")
        fake_get = _detection_responses(
            {33: "Source 33", 17: "Source 17", 100: "Source 100"}
        )

        with patch.object(client, "_get", side_effect=fake_get):
            assert await client.detect_port_count() == 16

    async def test_empty_value_is_not_proof_of_existence(self):
        client = RestClient("192.168.1.100")
        fake_get = _detection_responses({33: "", 17: "IN 17", 100: None})

        with patch.object(client, "_get", side_effect=fake_get):
            assert await client.detect_port_count() == 32

    def test_label_containing_the_prefix_word_is_still_real(self):
        # "Source Feed A" is a user label, not the auto-generated "Source 33".
        assert RestClient._port_is_real("Source Feed A", "Source 100", 33) is True

    def test_zero_padded_auto_name_is_recognised_as_phantom(self):
        assert RestClient._port_is_real("Source 033", "Source 100", 33) is False


# ===================================================================
# get_system_name / get_firmware_version
# ===================================================================


class TestRestClientInfoQueries:
    """Test system name and firmware version helpers."""

    async def test_get_system_name_success(self):
        client = RestClient("192.168.1.100")
        with patch.object(
            client, "_get", return_value={"value_name": "MY KUMO 6464"}
        ):
            name = await client.get_system_name()
            assert name == "MY KUMO 6464"

    async def test_get_system_name_fallback(self):
        client = RestClient("192.168.1.100")
        with patch.object(client, "_get", return_value=None):
            name = await client.get_system_name()
            assert name == "KUMO"

    async def test_get_firmware_version_success(self):
        client = RestClient("192.168.1.100")
        with patch.object(
            client, "_get", return_value={"value_name": "v8.5"}
        ):
            ver = await client.get_firmware_version()
            assert ver == "v8.5"

    async def test_get_firmware_version_fallback(self):
        client = RestClient("192.168.1.100")
        with patch.object(client, "_get", return_value=None):
            ver = await client.get_firmware_version()
            assert ver == "Unknown"


# ===================================================================
# download_labels
# ===================================================================


class TestRestClientDownloadLabels:
    """Test bulk label download with mocked _get."""

    async def test_download_returns_protocol_rest(self):
        client = RestClient("192.168.1.100")
        client._port_count = 2  # tiny router for fast test

        call_count = 0

        async def fake_get(endpoint, timeout=None):
            nonlocal call_count
            call_count += 1
            return {"value_name": f"Label{call_count}"}

        with patch.object(client, "_get", side_effect=fake_get):
            protocol, labels = await client.download_labels()

        assert protocol is Protocol.REST
        assert labels is not None
        assert len(labels["inputs"]) == 2
        assert len(labels["outputs"]) == 2
        assert len(labels["inputs_line2"]) == 2
        assert len(labels["outputs_line2"]) == 2

    async def test_download_fills_defaults_on_none(self):
        client = RestClient("192.168.1.100")
        client._port_count = 2

        with patch.object(client, "_get", return_value=None):
            protocol, labels = await client.download_labels()

        assert protocol is Protocol.REST
        # Defaults should be filled in
        assert labels["inputs"][0] == "Source 1"
        assert labels["inputs"][1] == "Source 2"
        assert labels["outputs"][0] == "Dest 1"
        assert labels["outputs"][1] == "Dest 2"

    async def test_download_with_progress_callback(self):
        client = RestClient("192.168.1.100")
        client._port_count = 2

        progress_calls = []

        async def track_progress(current, total):
            progress_calls.append((current, total))

        with patch.object(
            client, "_get", return_value={"value_name": "Test"}
        ):
            await client.download_labels(progress_callback=track_progress)

        # Final callback with total==total should always fire
        assert len(progress_calls) > 0
        assert progress_calls[-1][0] == progress_calls[-1][1]


# ===================================================================
# upload_label / upload_labels_batch
# ===================================================================


class TestRestClientUpload:
    """Test label upload methods."""

    async def test_upload_label_success(self):
        client = RestClient("192.168.1.100")
        with patch.object(client, "_get", return_value={"value": "ok"}):
            ok, err = await client.upload_label(1, "INPUT", "CAM 1")
            assert ok is True
            assert err is None

    async def test_upload_label_failure(self):
        client = RestClient("192.168.1.100")
        with patch.object(client, "_get", return_value=None):
            ok, err = await client.upload_label(1, "OUTPUT", "MON 1")
            assert ok is False
            assert err is not None

    async def test_upload_label_invalid_type(self):
        client = RestClient("192.168.1.100")
        ok, err = await client.upload_label(1, "BOGUS", "test")
        assert ok is False
        assert "Invalid" in err

    async def test_upload_labels_batch(self):
        client = RestClient("192.168.1.100")
        data = [
            {"port": 1, "type": "INPUT", "label": "Cam 1", "line": 1},
            {"port": 2, "type": "OUTPUT", "label": "Mon 2", "line": 1},
        ]
        with patch.object(client, "_get", return_value={"value": "ok"}):
            success, errors, msgs = await client.upload_labels_batch(data)
            assert success == 2
            assert errors == 0
            assert msgs == []

    async def test_upload_labels_batch_partial_failure(self):
        client = RestClient("192.168.1.100")
        data = [
            {"port": 1, "type": "INPUT", "label": "Cam 1"},
            {"port": 2, "type": "OUTPUT", "label": "Mon 2"},
        ]
        call_count = 0

        async def alternating_get(endpoint, timeout=None):
            nonlocal call_count
            call_count += 1
            return {"value": "ok"} if call_count % 2 == 1 else None

        with patch.object(client, "_get", side_effect=alternating_get):
            success, errors, msgs = await client.upload_labels_batch(data)
            assert success == 1
            assert errors == 1


# ===================================================================
# Regressions fixed during the 2026-08-20 audit
# ===================================================================


class TestRestClientTestConnection:
    """test_connection must not confuse "no system name" with "unreachable"."""

    async def test_router_with_no_system_name_is_still_connected(self):
        client = RestClient("192.168.1.100")
        # A router with no system name set answers with empty strings.
        with patch.object(
            client, "_get", return_value={"value": "", "value_name": ""}
        ):
            assert await client.test_connection() is True

    async def test_named_router_is_connected(self):
        client = RestClient("192.168.1.100")
        with patch.object(client, "_get", return_value={"value": "FOH-KUMO"}):
            assert await client.test_connection() is True

    async def test_paramid_only_response_is_connected(self):
        client = RestClient("192.168.1.100")
        with patch.object(client, "_get", return_value={"paramid": "eParamID_SysName"}):
            assert await client.test_connection() is True

    async def test_no_response_is_not_connected(self):
        client = RestClient("192.168.1.100")
        with patch.object(client, "_get", return_value=None):
            assert await client.test_connection() is False

    async def test_error_response_is_not_connected(self):
        client = RestClient("192.168.1.100")
        with patch.object(
            client, "_get", return_value={"error": "unknown parameter"}
        ):
            assert await client.test_connection() is False

    async def test_unrecognised_payload_is_not_connected(self):
        client = RestClient("192.168.1.100")
        with patch.object(client, "_get", return_value={"unexpected": "shape"}):
            assert await client.test_connection() is False


class TestRestClientUploadResponseValidation:
    """A 200 response carrying an error must not be reported as a write."""

    async def test_upload_label_rejects_error_payload(self):
        client = RestClient("192.168.1.100")
        with patch.object(client, "_get", return_value={"error": "port out of range"}):
            ok, err = await client.upload_label(99, "INPUT", "CAM A")
            assert ok is False
            assert "port out of range" in err

    async def test_upload_label_accepts_normal_payload(self):
        client = RestClient("192.168.1.100")
        with patch.object(client, "_get", return_value={"value": "CAM A"}):
            ok, err = await client.upload_label(1, "INPUT", "CAM A")
            assert ok is True
            assert err is None

    async def test_upload_label_reports_no_response_as_failure(self):
        client = RestClient("192.168.1.100")
        with patch.object(client, "_get", return_value=None):
            ok, err = await client.upload_label(1, "INPUT", "CAM A")
            assert ok is False
            assert err

    async def test_upload_color_rejects_error_payload(self):
        client = RestClient("192.168.1.100")
        with patch.object(client, "_get", return_value={"error": "bad color"}):
            ok, err = await client.upload_color(1, "INPUT", 3)
            assert ok is False
            assert "bad color" in err

    async def test_upload_color_accepts_normal_payload(self):
        client = RestClient("192.168.1.100")
        with patch.object(client, "_get", return_value={"value": "3"}):
            ok, err = await client.upload_color(1, "INPUT", 3)
            assert ok is True
            assert err is None
