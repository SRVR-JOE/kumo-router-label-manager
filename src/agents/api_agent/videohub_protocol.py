"""Blackmagic Videohub TCP 9990 protocol implementation.

Handles connection, label reading, and label uploading for Blackmagic
Videohub matrix routers using the Videohub Ethernet Protocol.
"""

import logging
import socket
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)

# Videohub TCP port and protocol constants
VIDEOHUB_PORT = 9990
VIDEOHUB_TIMEOUT = 2.0
VIDEOHUB_MAX_LABEL_LENGTH = 255


@dataclass
class VideohubInfo:
    """Information returned by a Videohub device on connect."""

    model_name: str = "Blackmagic Videohub"
    friendly_name: str = ""
    protocol_version: str = "Unknown"
    video_inputs: int = 0
    video_outputs: int = 0
    input_labels: List[str] = field(default_factory=list)
    output_labels: List[str] = field(default_factory=list)
    locks: Dict[int, str] = field(default_factory=dict)  # {0: "U", 1: "O", ...} 0-based port index to lock state
    routing: Dict[int, int] = field(default_factory=dict)  # {0: 0, 1: 1, ...} output port -> input port (0-based)
    take_mode: bool = False


def _recv_until_blank(sock: socket.socket, buf_size: int = 4096, timeout: float = 5.0) -> str:
    """Read from socket until 300ms of silence (end of initial dump).

    The Videohub protocol sends multiple blocks separated by blank lines.
    We accumulate all data until the device goes quiet for 300ms, which
    signals the end of the full initial state dump.
    """
    sock.settimeout(timeout)
    data = b""
    try:
        # Read initial data
        data = sock.recv(buf_size)
    except socket.timeout:
        logger.debug("Videohub recv timed out waiting for initial data (%.1fs)", timeout)
        return data.decode("utf-8", errors="replace")

    # Keep reading until 300ms of silence
    while True:
        sock.settimeout(0.3)
        try:
            chunk = sock.recv(buf_size)
            if not chunk:
                break
            data += chunk
        except (socket.timeout, BlockingIOError):
            break  # 300ms of silence = dump is complete

    return data.decode("utf-8", errors="replace")


def _parse_videohub_dump(raw: str) -> VideohubInfo:
    """Parse the Videohub initial state dump into a VideohubInfo object.

    The protocol uses named blocks:
        BLOCK NAME:
        key value
        key value

        NEXT BLOCK:
        ...

    Each block ends with a blank line.
    """
    info = VideohubInfo()

    # Split into blocks on blank lines
    blocks: Dict[str, List[str]] = {}
    current_block: Optional[str] = None
    current_lines: List[str] = []

    for line in raw.splitlines():
        stripped = line.rstrip()
        if stripped.endswith(":") and not stripped.startswith(" ") and not stripped[0].isdigit():
            # New block header
            if current_block is not None:
                blocks[current_block] = current_lines
            current_block = stripped[:-1]  # strip trailing colon
            current_lines = []
        elif stripped == "":
            # Blank line — end of current block
            if current_block is not None:
                blocks[current_block] = current_lines
                current_block = None
                current_lines = []
        else:
            if current_block is not None:
                current_lines.append(stripped)

    # Flush any trailing block
    if current_block is not None:
        blocks[current_block] = current_lines

    # --- PROTOCOL PREAMBLE ---
    if "PROTOCOL PREAMBLE" in blocks:
        for entry in blocks["PROTOCOL PREAMBLE"]:
            if entry.startswith("Version:"):
                info.protocol_version = entry.split(":", 1)[1].strip()

    # --- VIDEOHUB DEVICE ---
    if "VIDEOHUB DEVICE" in blocks:
        for entry in blocks["VIDEOHUB DEVICE"]:
            if entry.startswith("Model name:"):
                info.model_name = entry.split(":", 1)[1].strip()
            elif entry.startswith("Friendly name:"):
                info.friendly_name = entry.split(":", 1)[1].strip()
            elif entry.startswith("Video inputs:"):
                try:
                    info.video_inputs = int(entry.split(":", 1)[1].strip())
                except ValueError:
                    logger.warning("Could not parse video input count: %s", entry)
            elif entry.startswith("Video outputs:"):
                try:
                    info.video_outputs = int(entry.split(":", 1)[1].strip())
                except ValueError:
                    logger.warning("Could not parse video output count: %s", entry)

    # --- INPUT LABELS ---
    # Initialise with defaults first, then overwrite with what the device sent.
    if info.video_inputs > 0:
        info.input_labels = [f"Input {i+1}" for i in range(info.video_inputs)]
    if "INPUT LABELS" in blocks:
        for entry in blocks["INPUT LABELS"]:
            parts = entry.split(" ", 1)
            idx_str = parts[0]
            label_text = parts[1] if len(parts) == 2 else ""
            try:
                idx = int(idx_str)  # 0-based from device
                # Extend list if needed (device may report more than declared)
                while len(info.input_labels) <= idx:
                    info.input_labels.append(f"Input {len(info.input_labels)+1}")
                info.input_labels[idx] = label_text
            except (ValueError, IndexError):
                continue

    # --- OUTPUT LABELS ---
    if info.video_outputs > 0:
        info.output_labels = [f"Output {i+1}" for i in range(info.video_outputs)]
    if "OUTPUT LABELS" in blocks:
        for entry in blocks["OUTPUT LABELS"]:
            parts = entry.split(" ", 1)
            idx_str = parts[0]
            label_text = parts[1] if len(parts) == 2 else ""
            try:
                idx = int(idx_str)
                while len(info.output_labels) <= idx:
                    info.output_labels.append(f"Output {len(info.output_labels)+1}")
                info.output_labels[idx] = label_text
            except (ValueError, IndexError):
                continue

    # --- VIDEO OUTPUT LOCKS ---
    if "VIDEO OUTPUT LOCKS" in blocks:
        for entry in blocks["VIDEO OUTPUT LOCKS"]:
            parts = entry.split(" ", 1)
            if len(parts) == 2:
                try:
                    idx = int(parts[0])
                    info.locks[idx] = parts[1].strip()
                except ValueError:
                    continue

    # --- VIDEO OUTPUT ROUTING ---
    if "VIDEO OUTPUT ROUTING" in blocks:
        for entry in blocks["VIDEO OUTPUT ROUTING"]:
            parts = entry.split(" ", 1)
            if len(parts) == 2:
                try:
                    out_idx = int(parts[0])
                    in_idx = int(parts[1].strip())
                    info.routing[out_idx] = in_idx
                except ValueError:
                    continue

    # --- CONFIGURATION ---
    if "CONFIGURATION" in blocks:
        for entry in blocks["CONFIGURATION"]:
            if entry.startswith("Take Mode:"):
                val = entry.split(":", 1)[1].strip().lower()
                info.take_mode = val == "true"

    return info


def connect_videohub(ip: str) -> Tuple[bool, Optional[VideohubInfo], Optional[str]]:
    """Open a TCP connection to a Videohub, read and parse the initial dump.

    Args:
        ip: IP address of the Videohub device.

    Returns:
        Tuple of (success, VideohubInfo | None, error_message | None).
    """
    try:
        sock = socket.create_connection((ip, VIDEOHUB_PORT), timeout=VIDEOHUB_TIMEOUT)
    except (ConnectionRefusedError, OSError) as exc:
        return False, None, f"Cannot connect to {ip}:{VIDEOHUB_PORT} — {exc}"
    except socket.timeout:
        return False, None, f"Connection to {ip}:{VIDEOHUB_PORT} timed out after {VIDEOHUB_TIMEOUT}s"

    try:
        raw = _recv_until_blank(sock)
    finally:
        sock.close()

    if not raw.strip():
        return False, None, "Connected but received no data from device"

    info = _parse_videohub_dump(raw)
    return True, info, None


def upload_videohub_labels(
    ip: str,
    labels: list,
) -> Tuple[int, int, List[str]]:
    """Upload changed labels to a Videohub device over TCP port 9990.

    Sends one block per label type (INPUT LABELS / OUTPUT LABELS) containing
    all changed labels of that type.  Waits for an ACK after each block.

    Args:
        ip: IP address of the Videohub device.
        labels: All labels (only those with has_changes() == True are sent).
                Each label must have port_number, port_type, new_label, and
                has_changes() attributes (RouterLabel compatible).

    Returns:
        Tuple of (success_count, error_count, error_messages).
    """
    changes = [l for l in labels if l.has_changes()]
    if not changes:
        return 0, 0, []

    inputs_to_send = [l for l in changes if l.port_type == "INPUT"]
    outputs_to_send = [l for l in changes if l.port_type == "OUTPUT"]

    success_count = 0
    error_count = 0
    error_messages: List[str] = []

    try:
        sock = socket.create_connection((ip, VIDEOHUB_PORT), timeout=VIDEOHUB_TIMEOUT)
    except (ConnectionRefusedError, OSError, socket.timeout) as exc:
        msg = f"Cannot connect to {ip}:{VIDEOHUB_PORT} — {exc}"
        return 0, len(changes), [msg]

    try:
        # Drain the initial state dump so we start clean
        sock.settimeout(VIDEOHUB_TIMEOUT)
        try:
            _recv_until_blank(sock)
        except (socket.timeout, BlockingIOError):
            pass  # No initial data or already silent — safe to proceed
        except OSError:
            sock.close()
            return 0, len(changes), ["Socket error draining initial state dump"]

        def send_block(block_name: str, port_labels: list) -> Tuple[int, int, List[str]]:
            """Send a single labelled block and wait for ACK."""
            lines = [f"{block_name}:"]
            for lbl in port_labels:
                # Protocol is 0-based
                zero_idx = lbl.port_number - 1
                lines.append(f"{zero_idx} {lbl.new_label}")
            lines.append("")  # blank line terminates block
            payload = "\n".join(lines) + "\n"

            try:
                sock.sendall(payload.encode("utf-8"))
            except OSError as exc:
                msgs = [f"Send error for {block_name}: {exc}"]
                return 0, len(port_labels), msgs

            # Wait for ACK — the device replies with "ACK\n\n" on success
            sock.settimeout(5.0)
            ack_buf = b""
            try:
                while b"\n\n" not in ack_buf:
                    chunk = sock.recv(1024)
                    if not chunk:
                        break
                    ack_buf += chunk
            except socket.timeout:
                pass
            except OSError as exc:
                msgs = [f"{block_name}: connection lost waiting for ACK: {exc}"]
                return 0, len(port_labels), msgs

            ack_text = ack_buf.decode("utf-8", errors="replace").strip().upper()
            if "ACK" in ack_text:
                return len(port_labels), 0, []
            elif "NAK" in ack_text:
                msgs = [f"{block_name}: device returned NAK (not acknowledged)"]
                return 0, len(port_labels), msgs
            elif not ack_text.strip():
                msgs = [f"{block_name}: no response from device (timeout)"]
                return 0, len(port_labels), msgs
            else:
                logger.warning("Ambiguous response for %s: %r", block_name, ack_text)
                msgs = [f"{block_name}: ambiguous response from device: {ack_text!r}"]
                return 0, len(port_labels), msgs

        if inputs_to_send:
            ok, fail, msgs = send_block("INPUT LABELS", inputs_to_send)
            success_count += ok
            error_count += fail
            error_messages.extend(msgs)

        if outputs_to_send:
            ok, fail, msgs = send_block("OUTPUT LABELS", outputs_to_send)
            success_count += ok
            error_count += fail
            error_messages.extend(msgs)

    finally:
        sock.close()

    return success_count, error_count, error_messages


def videohub_info_to_router_labels(info: VideohubInfo, router_label_cls: type) -> list:
    """Convert a parsed VideohubInfo into a flat RouterLabel list (1-based ports).

    Args:
        info: Parsed VideohubInfo from connect_videohub.
        router_label_cls: The RouterLabel class to instantiate.

    Returns:
        List of RouterLabel instances.
    """
    router_labels = []
    for i, text in enumerate(info.input_labels, start=1):
        router_labels.append(router_label_cls(port_number=i, port_type="INPUT", current_label=text))
    for i, text in enumerate(info.output_labels, start=1):
        router_labels.append(router_label_cls(port_number=i, port_type="OUTPUT", current_label=text))
    return router_labels


# ---------------------------------------------------------------------------
# Lock management
# ---------------------------------------------------------------------------

def _send_command_and_wait(sock: socket.socket, payload: str, timeout: float = 2.0) -> str:
    """Send a protocol command and read the response.

    Returns the raw response text. Raises OSError on send failure.
    """
    sock.sendall(payload.encode("utf-8"))
    sock.settimeout(timeout)
    buf = b""
    try:
        while b"\n\n" not in buf:
            chunk = sock.recv(4096)
            if not chunk:
                break
            buf += chunk
    except socket.timeout:
        pass
    return buf.decode("utf-8", errors="replace")


def _response_is_ack(response: str) -> bool:
    """Return True if the device response contains an ACK."""
    return "ACK" in response.upper()


def set_videohub_lock(sock: socket.socket, output_port_0based: int, lock: bool, timeout: float = 2.0) -> bool:
    """Lock or unlock a Videohub output port.

    Sends::

        VIDEO OUTPUT LOCKS:
        {port} {O|U}

        (blank line to end block)

    Args:
        sock: Connected socket to the Videohub device.
        output_port_0based: 0-based output port index.
        lock: True to lock (O), False to unlock (U).
        timeout: Socket timeout in seconds.

    Returns:
        True if the device acknowledged the command.
    """
    state = "O" if lock else "U"
    payload = f"VIDEO OUTPUT LOCKS:\n{output_port_0based} {state}\n\n"
    response = _send_command_and_wait(sock, payload, timeout)
    return _response_is_ack(response)


def get_videohub_locks(sock: socket.socket, timeout: float = 2.0) -> Dict[int, str]:
    """Query current lock states from the device.

    Reads the current socket data and parses VIDEO OUTPUT LOCKS block.

    Args:
        sock: Connected socket to the Videohub device.
        timeout: Socket timeout in seconds.

    Returns:
        Dict mapping 0-based output port index to lock state string (U/O/L).
    """
    raw = _recv_until_blank(sock, timeout=timeout)
    info = _parse_videohub_dump(raw)
    return info.locks


# ---------------------------------------------------------------------------
# Take mode
# ---------------------------------------------------------------------------

def set_videohub_take_mode(sock: socket.socket, enabled: bool, timeout: float = 2.0) -> bool:
    """Enable or disable take mode on the Videohub.

    Sends::

        CONFIGURATION:
        Take Mode: {true|false}

        (blank line to end block)

    Args:
        sock: Connected socket to the Videohub device.
        enabled: True to enable take mode, False to disable.
        timeout: Socket timeout in seconds.

    Returns:
        True if the device acknowledged the command.
    """
    val = "true" if enabled else "false"
    payload = f"CONFIGURATION:\nTake Mode: {val}\n\n"
    response = _send_command_and_wait(sock, payload, timeout)
    return _response_is_ack(response)


# ---------------------------------------------------------------------------
# Routing
# ---------------------------------------------------------------------------

def switch_videohub_route(
    sock: socket.socket,
    output_port_0based: int,
    input_port_0based: int,
    timeout: float = 2.0,
) -> bool:
    """Route an input to an output on the Videohub.

    Sends::

        VIDEO OUTPUT ROUTING:
        {output} {input}

        (blank line to end block)

    Args:
        sock: Connected socket to the Videohub device.
        output_port_0based: 0-based output port index.
        input_port_0based: 0-based input port index.
        timeout: Socket timeout in seconds.

    Returns:
        True if the device acknowledged the command.
    """
    payload = f"VIDEO OUTPUT ROUTING:\n{output_port_0based} {input_port_0based}\n\n"
    response = _send_command_and_wait(sock, payload, timeout)
    return _response_is_ack(response)


def get_videohub_routing(sock: socket.socket, timeout: float = 2.0) -> Dict[int, int]:
    """Get current routing table from the device.

    Args:
        sock: Connected socket to the Videohub device.
        timeout: Socket timeout in seconds.

    Returns:
        Dict mapping 0-based output port index to 0-based input port index.
    """
    raw = _recv_until_blank(sock, timeout=timeout)
    info = _parse_videohub_dump(raw)
    return info.routing
