"""Lightware MX2 LW3 TCP 6107 protocol implementation.

Handles connection, label reading, and label uploading for Lightware MX2
matrix routers using the LW3 protocol.
"""

import logging
import re
import socket
import time
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)

# Lightware LW3 TCP port and protocol constants
LIGHTWARE_PORT = 6107
LIGHTWARE_TIMEOUT = 2.0
LIGHTWARE_MAX_LABEL_LENGTH = 255


@dataclass
class LightwareInfo:
    """Information returned by a Lightware MX2 device on connect."""

    product_name: str = "Lightware MX2"
    input_count: int = 0
    output_count: int = 0
    input_labels: Dict[int, str] = field(default_factory=dict)
    output_labels: Dict[int, str] = field(default_factory=dict)


def _lw3_send_command(
    sock: socket.socket,
    command: str,
    send_id: List[int],
) -> List[str]:
    """Frame and send an LW3 command, then read the multiline response block.

    The LW3 protocol wraps every response in a ``{NNNN ... }`` block where
    NNNN matches the 4-digit zero-padded request ID sent with the command.
    Response lines may be prefixed with ``pw``, ``pr``, ``mO``, ``pE``, or ``nE``.

    Args:
        sock:     Connected socket to the Lightware device.
        command:  The bare LW3 command string (e.g. ``GET /.ProductName``).
        send_id:  Mutable single-element list used as a counter so callers
                  share and advance the same ID sequence.

    Returns:
        List of response lines (prefix and braces stripped).
    """
    req_id = send_id[0]
    send_id[0] += 1

    framed = f"{req_id:04d}#{command}\r\n"
    try:
        sock.sendall(framed.encode("ascii"))
    except OSError as exc:
        logger.debug("LW3 send error for %r: %s", command, exc)
        return []

    # Read until the closing brace line for this request ID.
    expected_open = f"{{{req_id:04d}"
    expected_close = "}"
    lines: List[str] = []
    in_block = False
    sock.settimeout(3.0)
    buf = b""

    deadline = time.monotonic() + 5.0
    while time.monotonic() < deadline:
        try:
            chunk = sock.recv(4096)
        except socket.timeout:
            break
        except OSError:
            break
        if not chunk:
            break
        buf += chunk

        # Process any complete lines in the buffer.
        while b"\n" in buf:
            raw_line, buf = buf.split(b"\n", 1)
            text = raw_line.decode("ascii", errors="replace").rstrip("\r")

            if not in_block:
                if text.startswith(expected_open):
                    in_block = True
                continue

            # Inside the block — check for closing brace.
            if text.strip() == expected_close:
                return lines

            # Keep the full line (including any pw/pr/pE/nE prefix) so
            # callers can detect error prefixes.  Callers use substring
            # matching (re.search / "=" in line) which works with prefixes.
            lines.append(text)

    return lines


def connect_lightware(
    ip: str,
    port: int = LIGHTWARE_PORT,
) -> Tuple[bool, Optional[LightwareInfo], Optional[str]]:
    """Open a TCP connection to a Lightware MX2 and read device information.

    Queries ProductName, SourcePortCount, DestinationPortCount, and all
    labels under ``/MEDIA/NAMES/VIDEO.*`` in a single persistent connection.

    Args:
        ip:   IP address of the Lightware device.
        port: TCP port (default 6107).

    Returns:
        Tuple of (success, LightwareInfo | None, error_message | None).
    """
    try:
        sock = socket.create_connection((ip, port), timeout=LIGHTWARE_TIMEOUT)
    except (ConnectionRefusedError, OSError) as exc:
        return False, None, f"Cannot connect to {ip}:{port} — {exc}"
    except socket.timeout:
        return False, None, f"Connection to {ip}:{port} timed out after {LIGHTWARE_TIMEOUT}s"

    info = LightwareInfo()
    send_id = [1]

    try:
        # --- Product name ---
        pn_lines = _lw3_send_command(sock, "GET /.ProductName", send_id)
        for line in pn_lines:
            # Line looks like: "/.ProductName=Lightware MX2-16x16-HDMI20-L"
            if "=" in line:
                info.product_name = line.split("=", 1)[1].strip()
                break

        # --- Port counts ---
        src_lines = _lw3_send_command(sock, "GET /MEDIA/XP/VIDEO.SourcePortCount", send_id)
        for line in src_lines:
            if "=" in line:
                try:
                    info.input_count = int(line.split("=", 1)[1].strip())
                except ValueError:
                    logger.warning("Could not parse SourcePortCount: %s", line)
                break

        dst_lines = _lw3_send_command(sock, "GET /MEDIA/XP/VIDEO.DestinationPortCount", send_id)
        for line in dst_lines:
            if "=" in line:
                try:
                    info.output_count = int(line.split("=", 1)[1].strip())
                except ValueError:
                    logger.warning("Could not parse DestinationPortCount: %s", line)
                break

        # --- Labels (wildcard GET returns all at once) ---
        label_lines = _lw3_send_command(sock, "GET /MEDIA/NAMES/VIDEO.*", send_id)

        # Each line looks like:
        #   pw /MEDIA/NAMES/VIDEO.I1=1;Label Text
        #   pw /MEDIA/NAMES/VIDEO.O3=3;Dest Label
        input_re = re.compile(r"/MEDIA/NAMES/VIDEO\.I(\d+)=\d+;(.*)")
        output_re = re.compile(r"/MEDIA/NAMES/VIDEO\.O(\d+)=\d+;(.*)")

        for line in label_lines:
            m = input_re.search(line)
            if m:
                port_num = int(m.group(1))
                info.input_labels[port_num] = m.group(2)
                continue
            m = output_re.search(line)
            if m:
                port_num = int(m.group(1))
                info.output_labels[port_num] = m.group(2)

        # Seed missing labels with defaults when counts are known.
        for i in range(1, info.input_count + 1):
            info.input_labels.setdefault(i, f"Input {i}")
        for i in range(1, info.output_count + 1):
            info.output_labels.setdefault(i, f"Output {i}")

    except Exception as exc:
        logger.exception("Error querying Lightware device at %s:%d", ip, port)
        return False, None, f"Error querying device: {exc}"
    finally:
        try:
            sock.close()
        except OSError:
            pass

    return True, info, None


def lightware_info_to_router_labels(info: LightwareInfo, router_label_cls: type) -> list:
    """Convert a parsed LightwareInfo into a flat RouterLabel list (1-based ports).

    Args:
        info: Parsed LightwareInfo from connect_lightware.
        router_label_cls: The RouterLabel class to instantiate.

    Returns:
        List of RouterLabel instances.
    """
    router_labels = []
    for port_num in sorted(info.input_labels):
        router_labels.append(router_label_cls(
            port_number=port_num,
            port_type="INPUT",
            current_label=info.input_labels[port_num],
        ))
    for port_num in sorted(info.output_labels):
        router_labels.append(router_label_cls(
            port_number=port_num,
            port_type="OUTPUT",
            current_label=info.output_labels[port_num],
        ))
    return router_labels


def upload_lightware_label(
    ip: str,
    port_type: str,
    port_num: int,
    label: str,
    port: int = LIGHTWARE_PORT,
) -> bool:
    """Upload a single label to a Lightware MX2 device.

    Opens a fresh TCP connection, sends a SET command for the appropriate
    port path, and closes the connection.

    Args:
        ip:        IP address of the Lightware device.
        port_type: "INPUT" or "OUTPUT".
        port_num:  1-based port number.
        label:     New label text (truncated to LIGHTWARE_MAX_LABEL_LENGTH).
        port:      TCP port (default 6107).

    Returns:
        True if the SET was acknowledged, False otherwise.
    """
    type_char = "I" if port_type == "INPUT" else "O"
    # LW3 label path format: /MEDIA/NAMES/VIDEO.I1=1;Label Text
    label_text = label[:LIGHTWARE_MAX_LABEL_LENGTH]
    path = f"/MEDIA/NAMES/VIDEO.{type_char}{port_num}={port_num};{label_text}"
    command = f"SET {path}"

    try:
        sock = socket.create_connection((ip, port), timeout=LIGHTWARE_TIMEOUT)
    except (ConnectionRefusedError, OSError, socket.timeout) as exc:
        logger.warning("LW3 connect failed for SET on port %s%d: %s", type_char, port_num, exc)
        return False

    send_id = [1]
    try:
        response_lines = _lw3_send_command(sock, command, send_id)
    except Exception as exc:
        logger.warning("LW3 SET command failed for %s%d: %s", type_char, port_num, exc)
        return False
    finally:
        try:
            sock.close()
        except OSError:
            pass

    # A successful SET echoes back a "pw" line containing the path.  An error
    # response starts with "pE" (parameter error) or "nE" (node error).
    for line in response_lines:
        if line.startswith("pE") or line.startswith("nE") or line.startswith("-E"):
            logger.warning("LW3 SET error response for %s%d: %r", type_char, port_num, line)
            return False

    # If we got any response lines back, treat it as success.
    return bool(response_lines)
