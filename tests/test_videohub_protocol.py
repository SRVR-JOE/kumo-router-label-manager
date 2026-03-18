"""Tests for Blackmagic Videohub protocol: locks, routing, and take mode."""

import socket
from unittest.mock import MagicMock, patch

import pytest

from src.agents.api_agent.videohub_protocol import (
    VideohubInfo,
    _parse_videohub_dump,
    set_videohub_lock,
    set_videohub_take_mode,
    switch_videohub_route,
    get_videohub_locks,
    get_videohub_routing,
)

# ---------------------------------------------------------------------------
# Real device dump from a Blackmagic Smart Videohub 40x40
# (truncated to 2 ports per block for brevity; parser handles any count)
# ---------------------------------------------------------------------------
REAL_DUMP = """\
PROTOCOL PREAMBLE:
Version: 2.8

VIDEOHUB DEVICE:
Device present: true
Model name: Blackmagic Smart Videohub 40 x 40
Friendly name: 4040
Unique ID: 7C2E0D07C323
Video inputs: 40
Video processing units: 0
Video outputs: 40
Video monitoring outputs: 0
Serial ports: 0

INPUT LABELS:
0 Input 1
1 Input 2

OUTPUT LABELS:
0 Output 1
1 Output 2

VIDEO OUTPUT LOCKS:
0 U
1 U

VIDEO OUTPUT ROUTING:
0 0
1 1

CONFIGURATION:
Take Mode: false

END PRELUDE:
"""


# ===================================================================
# _parse_videohub_dump — full dump
# ===================================================================

class TestParseVideohubDump:
    """Tests for _parse_videohub_dump with the real 40x40 dump."""

    def test_model_name(self):
        info = _parse_videohub_dump(REAL_DUMP)
        assert info.model_name == "Blackmagic Smart Videohub 40 x 40"

    def test_friendly_name(self):
        info = _parse_videohub_dump(REAL_DUMP)
        assert info.friendly_name == "4040"

    def test_protocol_version(self):
        info = _parse_videohub_dump(REAL_DUMP)
        assert info.protocol_version == "2.8"

    def test_input_output_counts(self):
        info = _parse_videohub_dump(REAL_DUMP)
        assert info.video_inputs == 40
        assert info.video_outputs == 40

    def test_input_labels_parsed(self):
        info = _parse_videohub_dump(REAL_DUMP)
        # The dump declares 40 inputs but only sends labels for 0 and 1.
        # Parser should default-fill the rest.
        assert len(info.input_labels) == 40
        assert info.input_labels[0] == "Input 1"
        assert info.input_labels[1] == "Input 2"
        # Defaults for ports not in the dump
        assert info.input_labels[2] == "Input 3"
        assert info.input_labels[39] == "Input 40"

    def test_output_labels_parsed(self):
        info = _parse_videohub_dump(REAL_DUMP)
        assert len(info.output_labels) == 40
        assert info.output_labels[0] == "Output 1"
        assert info.output_labels[1] == "Output 2"

    def test_locks_parsed(self):
        info = _parse_videohub_dump(REAL_DUMP)
        assert info.locks == {0: "U", 1: "U"}

    def test_routing_parsed(self):
        info = _parse_videohub_dump(REAL_DUMP)
        assert info.routing == {0: 0, 1: 1}

    def test_take_mode_false(self):
        info = _parse_videohub_dump(REAL_DUMP)
        assert info.take_mode is False

    def test_take_mode_true(self):
        dump = REAL_DUMP.replace("Take Mode: false", "Take Mode: true")
        info = _parse_videohub_dump(dump)
        assert info.take_mode is True


# ===================================================================
# Edge cases
# ===================================================================

class TestParseEdgeCases:

    def test_empty_dump(self):
        info = _parse_videohub_dump("")
        assert info.model_name == "Blackmagic Videohub"  # default
        assert info.locks == {}
        assert info.routing == {}
        assert info.take_mode is False

    def test_partial_blocks_no_locks(self):
        """Dump with device info but no lock or routing blocks."""
        partial = """\
VIDEOHUB DEVICE:
Model name: Blackmagic Videohub 20 x 20
Video inputs: 20
Video outputs: 20

"""
        info = _parse_videohub_dump(partial)
        assert info.model_name == "Blackmagic Videohub 20 x 20"
        assert info.locks == {}
        assert info.routing == {}

    def test_unknown_lock_states(self):
        """Lock states other than U/O/L should still be stored."""
        dump = """\
VIDEOHUB DEVICE:
Video inputs: 2
Video outputs: 2

VIDEO OUTPUT LOCKS:
0 X
1 Z

"""
        info = _parse_videohub_dump(dump)
        assert info.locks[0] == "X"
        assert info.locks[1] == "Z"

    def test_lock_states_all_types(self):
        """U=unlocked, O=owned, L=locked by other."""
        dump = """\
VIDEOHUB DEVICE:
Video inputs: 3
Video outputs: 3

VIDEO OUTPUT LOCKS:
0 U
1 O
2 L

"""
        info = _parse_videohub_dump(dump)
        assert info.locks == {0: "U", 1: "O", 2: "L"}

    def test_zero_based_indexing(self):
        """Port indices in the protocol are 0-based."""
        dump = """\
VIDEOHUB DEVICE:
Video inputs: 4
Video outputs: 4

VIDEO OUTPUT ROUTING:
0 3
1 2
2 1
3 0

"""
        info = _parse_videohub_dump(dump)
        assert info.routing[0] == 3
        assert info.routing[3] == 0


# ===================================================================
# Command formatting — lock
# ===================================================================

class TestLockCommandFormatting:

    def _make_sock(self, response: bytes = b"ACK\n\n"):
        sock = MagicMock(spec=socket.socket)
        sock.recv.return_value = response
        return sock

    def test_lock_sends_correct_payload(self):
        sock = self._make_sock()
        set_videohub_lock(sock, 5, lock=True, timeout=1.0)
        sent = sock.sendall.call_args[0][0]
        assert sent == b"VIDEO OUTPUT LOCKS:\n5 O\n\n"

    def test_unlock_sends_correct_payload(self):
        sock = self._make_sock()
        set_videohub_lock(sock, 0, lock=False, timeout=1.0)
        sent = sock.sendall.call_args[0][0]
        assert sent == b"VIDEO OUTPUT LOCKS:\n0 U\n\n"

    def test_lock_returns_true_on_ack(self):
        sock = self._make_sock(b"ACK\n\n")
        assert set_videohub_lock(sock, 0, lock=True) is True

    def test_lock_returns_false_on_nak(self):
        sock = self._make_sock(b"NAK\n\n")
        assert set_videohub_lock(sock, 0, lock=True) is False

    def test_lock_returns_false_on_empty_response(self):
        sock = self._make_sock(b"")
        # recv returns empty -> loop breaks immediately
        assert set_videohub_lock(sock, 0, lock=True) is False


# ===================================================================
# Command formatting — route
# ===================================================================

class TestRouteCommandFormatting:

    def _make_sock(self, response: bytes = b"ACK\n\n"):
        sock = MagicMock(spec=socket.socket)
        sock.recv.return_value = response
        return sock

    def test_route_sends_correct_payload(self):
        sock = self._make_sock()
        switch_videohub_route(sock, output_port_0based=2, input_port_0based=7, timeout=1.0)
        sent = sock.sendall.call_args[0][0]
        assert sent == b"VIDEO OUTPUT ROUTING:\n2 7\n\n"

    def test_route_port_zero(self):
        """Port 0 is valid (0-based)."""
        sock = self._make_sock()
        switch_videohub_route(sock, 0, 0)
        sent = sock.sendall.call_args[0][0]
        assert sent == b"VIDEO OUTPUT ROUTING:\n0 0\n\n"

    def test_route_returns_true_on_ack(self):
        sock = self._make_sock(b"ACK\n\n")
        assert switch_videohub_route(sock, 0, 1) is True

    def test_route_returns_false_on_nak(self):
        sock = self._make_sock(b"NAK\n\n")
        assert switch_videohub_route(sock, 0, 1) is False


# ===================================================================
# Command formatting — take mode
# ===================================================================

class TestTakeModeCommandFormatting:

    def _make_sock(self, response: bytes = b"ACK\n\n"):
        sock = MagicMock(spec=socket.socket)
        sock.recv.return_value = response
        return sock

    def test_enable_take_mode_payload(self):
        sock = self._make_sock()
        set_videohub_take_mode(sock, enabled=True, timeout=1.0)
        sent = sock.sendall.call_args[0][0]
        assert sent == b"CONFIGURATION:\nTake Mode: true\n\n"

    def test_disable_take_mode_payload(self):
        sock = self._make_sock()
        set_videohub_take_mode(sock, enabled=False, timeout=1.0)
        sent = sock.sendall.call_args[0][0]
        assert sent == b"CONFIGURATION:\nTake Mode: false\n\n"

    def test_take_mode_returns_true_on_ack(self):
        sock = self._make_sock(b"ACK\n\n")
        assert set_videohub_take_mode(sock, enabled=True) is True

    def test_take_mode_returns_false_on_nak(self):
        sock = self._make_sock(b"NAK\n\n")
        assert set_videohub_take_mode(sock, enabled=True) is False


# ===================================================================
# Query helpers (get_videohub_locks / get_videohub_routing)
# ===================================================================

class TestQueryHelpers:

    def _make_sock_with_dump(self, dump_text: str):
        """Create a mock socket that returns dump_text then times out."""
        sock = MagicMock(spec=socket.socket)
        call_count = [0]
        encoded = dump_text.encode("utf-8")

        def fake_recv(bufsize):
            if call_count[0] == 0:
                call_count[0] += 1
                return encoded
            raise socket.timeout("done")

        sock.recv.side_effect = fake_recv
        return sock

    def test_get_locks_returns_dict(self):
        dump = "VIDEO OUTPUT LOCKS:\n0 U\n1 O\n2 L\n\n"
        sock = self._make_sock_with_dump(dump)
        locks = get_videohub_locks(sock, timeout=0.5)
        assert locks == {0: "U", 1: "O", 2: "L"}

    def test_get_routing_returns_dict(self):
        dump = "VIDEO OUTPUT ROUTING:\n0 5\n1 3\n\n"
        sock = self._make_sock_with_dump(dump)
        routing = get_videohub_routing(sock, timeout=0.5)
        assert routing == {0: 5, 1: 3}
