"""
Command-line interface for Router Label Manager v3.0.

Beautiful, fast, and functional CLI powered by Rich.
Supports AJA KUMO and Blackmagic Videohub matrix routers.
"""
import asyncio
import argparse
import logging
import socket
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from rich.console import Console
from rich.table import Table
from rich.panel import Panel
from rich.progress import Progress, SpinnerColumn, TextColumn, BarColumn, TaskProgressColumn
from rich.text import Text
from rich.columns import Columns
from rich import box

from .config.settings import Settings
from .coordinator.event_bus import EventBus
from .agents.api_agent import APIAgent
from .agents.api_agent.rest_client import RestClient
from .agents.file_handler import FileHandlerAgent, FileData, PortData
from .models import Label, PortType


console = Console()
logger = logging.getLogger(__name__)

APP_VERSION = "3.0.0"

# Videohub TCP port
VIDEOHUB_PORT = 9990
VIDEOHUB_TIMEOUT = 2.0
VIDEOHUB_MAX_LABEL_LENGTH = 255


# ---------------------------------------------------------------------------
# Internal label representation — no port-number cap, works for both routers
# ---------------------------------------------------------------------------

@dataclass
class RouterLabel:
    """Unified label representation for KUMO and Videohub routers.

    Unlike the domain Label model, this places no upper bound on port_number
    so it can represent large Videohub matrices (e.g., 120x120).
    """

    port_number: int
    port_type: str          # "INPUT" or "OUTPUT"
    current_label: str = ""
    new_label: Optional[str] = None

    def has_changes(self) -> bool:
        return self.new_label is not None and self.new_label != self.current_label

    def __str__(self) -> str:
        change = f" -> {self.new_label}" if self.has_changes() else ""
        return f"Port {self.port_number} ({self.port_type}): {self.current_label}{change}"


# ---------------------------------------------------------------------------
# Videohub protocol
# ---------------------------------------------------------------------------

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
                    pass
            elif entry.startswith("Video outputs:"):
                try:
                    info.video_outputs = int(entry.split(":", 1)[1].strip())
                except ValueError:
                    pass

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
    labels: List[RouterLabel],
) -> Tuple[int, int, List[str]]:
    """Upload changed labels to a Videohub device over TCP port 9990.

    Sends one block per label type (INPUT LABELS / OUTPUT LABELS) containing
    all changed labels of that type.  Waits for an ACK after each block.

    Args:
        ip: IP address of the Videohub device.
        labels: All labels (only those with has_changes() == True are sent).

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
        except Exception:
            pass

        def send_block(block_name: str, port_labels: List[RouterLabel]) -> Tuple[int, int, List[str]]:
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
                logger.debug("Ambiguous response for %s: %r", block_name, ack_text)
                return len(port_labels), 0, []

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


def detect_router_type(ip: str) -> str:
    """Auto-detect whether the device at ip is a Videohub or KUMO.

    Tries Videohub TCP 9990 first (2-second timeout).  If the first response
    line contains "PROTOCOL PREAMBLE" the device is a Videohub.  Otherwise
    falls back to assuming KUMO.

    Uses makefile().readline() for reliable line reading — a single recv()
    call is not guaranteed to contain a full line on all platforms.

    Returns:
        "videohub" or "kumo"
    """
    sock = None
    sock_file = None
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(2.0)
        sock.connect((ip, VIDEOHUB_PORT))
        sock_file = sock.makefile("r", encoding="utf-8", errors="replace")
        first_line = sock_file.readline()
        if "PROTOCOL PREAMBLE" in first_line:
            return "videohub"
    except (socket.timeout, socket.error, OSError):
        pass
    finally:
        if sock_file:
            try: sock_file.close()
            except: pass
        if sock:
            try: sock.close()
            except: pass
    return "kumo"


# ---------------------------------------------------------------------------
# Shared display helpers
# ---------------------------------------------------------------------------

def setup_logging(verbose: bool = False) -> None:
    """Configure logging based on verbosity."""
    level = logging.DEBUG if verbose else logging.WARNING
    logging.basicConfig(
        level=level,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    )


def print_banner() -> None:
    """Print the application banner."""
    banner = Text()
    banner.append("Router", style="bold purple")
    banner.append(" Label Manager ", style="bold white")
    banner.append(f"v{APP_VERSION}", style="dim purple")

    console.print(Panel(
        banner,
        subtitle="[dim]AJA KUMO | Blackmagic Videohub[/dim]",
        border_style="purple",
        padding=(0, 2),
    ))


def display_router_labels_table(
    labels: List[RouterLabel],
    title: str = "Router Labels",
) -> None:
    """Display RouterLabel objects in a Rich table with inputs and outputs side by side."""
    inputs = [l for l in labels if l.port_type == "INPUT"]
    outputs = [l for l in labels if l.port_type == "OUTPUT"]

    input_table = Table(
        title="[bold green]INPUTS (Sources)[/bold green]",
        box=box.ROUNDED,
        border_style="green",
        header_style="bold green",
        show_lines=False,
        padding=(0, 1),
    )
    input_table.add_column("#", style="dim", justify="right", width=4)
    input_table.add_column("Label", style="white", min_width=20)
    input_table.add_column("Change", style="yellow", min_width=15)

    for lbl in sorted(inputs, key=lambda l: l.port_number):
        change = lbl.new_label if lbl.has_changes() else ""
        input_table.add_row(
            str(lbl.port_number),
            lbl.current_label or "[dim italic]empty[/dim italic]",
            Text(change, style="bold yellow") if change else Text("-", style="dim"),
        )

    output_table = Table(
        title="[bold purple]OUTPUTS (Destinations)[/bold purple]",
        box=box.ROUNDED,
        border_style="purple",
        header_style="bold purple",
        show_lines=False,
        padding=(0, 1),
    )
    output_table.add_column("#", style="dim", justify="right", width=4)
    output_table.add_column("Label", style="white", min_width=20)
    output_table.add_column("Change", style="yellow", min_width=15)

    for lbl in sorted(outputs, key=lambda l: l.port_number):
        change = lbl.new_label if lbl.has_changes() else ""
        output_table.add_row(
            str(lbl.port_number),
            lbl.current_label or "[dim italic]empty[/dim italic]",
            Text(change, style="bold yellow") if change else Text("-", style="dim"),
        )

    console.print()
    console.print(Columns([input_table, output_table], padding=2))
    console.print()

    total = len(labels)
    changes = sum(1 for l in labels if l.has_changes())
    summary = (
        f"  [dim]Total:[/dim] [bold]{total}[/bold] labels"
        f"  [dim]|[/dim]  [dim]Inputs:[/dim] [green]{len(inputs)}[/green]"
        f"  [dim]|[/dim]  [dim]Outputs:[/dim] [purple]{len(outputs)}[/purple]"
    )
    if changes:
        summary += f"  [dim]|[/dim]  [dim]Pending changes:[/dim] [yellow]{changes}[/yellow]"
    console.print(summary)


# ---------------------------------------------------------------------------
# Legacy helpers — used by KUMO path to bridge Label <-> RouterLabel
# ---------------------------------------------------------------------------

def labels_to_filedata(labels: List[Label]) -> FileData:
    """Convert domain Label objects to FileData for file saving."""
    ports = []
    for label in labels:
        ports.append(PortData(
            port=label.port_number,
            type=label.port_type.value,
            current_label=label.current_label,
            new_label=label.new_label,
            notes="",
        ))
    return FileData(ports=ports)


def filedata_to_labels(data: FileData) -> List[Label]:
    """Convert FileData to domain Label objects for upload."""
    labels = []
    for port_data in data.ports:
        port_type = PortType(port_data.type)
        labels.append(Label(
            port_number=port_data.port,
            port_type=port_type,
            current_label=port_data.current_label,
            new_label=port_data.new_label,
        ))
    return labels


def domain_labels_to_router_labels(labels: List[Label]) -> List[RouterLabel]:
    """Convert domain Label objects to RouterLabel for unified display."""
    return [
        RouterLabel(
            port_number=l.port_number,
            port_type=l.port_type.value,
            current_label=l.current_label,
            new_label=l.new_label,
        )
        for l in labels
    ]


def display_labels_table(labels: List[Label], title: str = "Router Labels") -> None:
    """Display domain Label objects — retained for KUMO backward compatibility."""
    display_router_labels_table(domain_labels_to_router_labels(labels), title)


def videohub_info_to_router_labels(info: VideohubInfo) -> List[RouterLabel]:
    """Convert a parsed VideohubInfo into a flat RouterLabel list (1-based ports)."""
    router_labels: List[RouterLabel] = []
    for i, text in enumerate(info.input_labels, start=1):
        router_labels.append(RouterLabel(port_number=i, port_type="INPUT", current_label=text))
    for i, text in enumerate(info.output_labels, start=1):
        router_labels.append(RouterLabel(port_number=i, port_type="OUTPUT", current_label=text))
    return router_labels


def router_labels_to_filedata(labels: List[RouterLabel]) -> Tuple[FileData, int]:
    """Convert RouterLabel list to FileData, capping at 120 ports per type.

    Supports up to 120 inputs + 120 outputs to accommodate Videohub 120x120.

    Returns:
        Tuple of (FileData, number_of_labels_skipped).
    """
    MAX_PER_TYPE = 120
    ports = []
    skipped = 0

    inputs = [l for l in labels if l.port_type == "INPUT"]
    outputs = [l for l in labels if l.port_type == "OUTPUT"]

    for lbl in sorted(inputs, key=lambda l: l.port_number)[:MAX_PER_TYPE]:
        ports.append(PortData(
            port=lbl.port_number,
            type="INPUT",
            current_label=lbl.current_label[:255],
            new_label=lbl.new_label[:255] if lbl.new_label else None,
            notes="",
        ))
    skipped += max(0, len(inputs) - MAX_PER_TYPE)

    for lbl in sorted(outputs, key=lambda l: l.port_number)[:MAX_PER_TYPE]:
        ports.append(PortData(
            port=lbl.port_number,
            type="OUTPUT",
            current_label=lbl.current_label[:255],
            new_label=lbl.new_label[:255] if lbl.new_label else None,
            notes="",
        ))
    skipped += max(0, len(outputs) - MAX_PER_TYPE)

    return FileData(ports=ports), skipped


# ---------------------------------------------------------------------------
# KumoManager — existing KUMO functionality, unchanged
# ---------------------------------------------------------------------------

class KumoManager:
    """Main application coordinator for KUMO router management."""

    def __init__(self, settings: Optional[Settings] = None):
        self.settings = settings or Settings()
        self.event_bus = EventBus()
        self.api_agent = APIAgent(
            router_ip=self.settings.router_ip,
            event_bus=self.event_bus,
        )
        self.file_handler = FileHandlerAgent(event_bus=self.event_bus)

    async def download_labels(self, output_file: str) -> bool:
        """Download current labels from KUMO router and save to file."""
        output_path = Path(output_file)

        supported = {".xlsx", ".csv", ".json"}
        if output_path.suffix.lower() not in supported:
            console.print(
                f"[red]Unsupported format:[/red] {output_path.suffix}\n"
                f"[dim]Supported: {', '.join(supported)}[/dim]"
            )
            return False

        try:
            with Progress(
                SpinnerColumn(),
                TextColumn("[progress.description]{task.description}"),
                BarColumn(bar_width=30),
                TaskProgressColumn(),
                console=console,
            ) as progress:
                task = progress.add_task(
                    f"[purple]Connecting to {self.settings.router_ip}...", total=3
                )
                await self.api_agent.connect()
                progress.update(task, advance=1)

                progress.update(task, description="[purple]Downloading labels (parallel)...")
                labels = await self.api_agent.download_labels()
                progress.update(task, advance=1)

                progress.update(
                    task,
                    description=f"[purple]Saving to {output_path.name}...",
                )
                file_data = labels_to_filedata(labels)
                self.file_handler.save(output_path, file_data)
                progress.update(task, advance=1)

            console.print()
            display_labels_table(labels, title=f"Labels from {self.settings.router_ip}")
            console.print()
            console.print(Panel(
                f"[green bold]Saved {len(labels)} labels to [purple]{output_file}[/purple][/green bold]",
                border_style="green",
                padding=(0, 2),
            ))
            return True

        except Exception as e:
            console.print(f"\n[red bold]Error:[/red bold] {e}")
            logger.exception("Download failed")
            return False
        finally:
            await self.api_agent.disconnect()

    async def upload_labels(self, input_file: str, test_mode: bool = False) -> bool:
        """Upload labels to KUMO router from file."""
        input_path = Path(input_file)

        if not input_path.exists():
            console.print(f"[red]File not found:[/red] {input_file}")
            return False

        try:
            with Progress(
                SpinnerColumn(),
                TextColumn("[progress.description]{task.description}"),
                BarColumn(bar_width=30),
                TaskProgressColumn(),
                console=console,
            ) as progress:
                task = progress.add_task(
                    f"[purple]Loading {input_path.name}...", total=3
                )
                file_data = self.file_handler.load(input_path)
                labels = filedata_to_labels(file_data)
                progress.update(task, advance=1)

                changes = [l for l in labels if l.has_changes()]

                if not changes:
                    progress.update(task, advance=2)
                    console.print("\n[yellow]No pending changes found in file.[/yellow]")
                    display_labels_table(labels)
                    return True

                if test_mode:
                    progress.update(task, advance=2)
                    console.print(
                        f"\n[yellow bold]TEST MODE[/yellow bold] - "
                        f"Would upload [bold]{len(changes)}[/bold] label changes"
                    )
                    display_labels_table(labels)
                    return True

                progress.update(
                    task,
                    description=f"[purple]Connecting to {self.settings.router_ip}...",
                )
                await self.api_agent.connect()
                progress.update(task, advance=1)

                progress.update(
                    task,
                    description=f"[purple]Uploading {len(changes)} labels (parallel)...",
                )
                success_count, error_count, errors = await self.api_agent.upload_labels(labels)
                progress.update(task, advance=1)

            console.print()
            if error_count == 0:
                console.print(Panel(
                    f"[green bold]Uploaded {success_count} labels successfully[/green bold]",
                    border_style="green",
                    padding=(0, 2),
                ))
            else:
                console.print(Panel(
                    f"[yellow]Uploaded {success_count} labels, "
                    f"[red]{error_count} failed[/red][/yellow]",
                    border_style="yellow",
                    padding=(0, 2),
                ))
                for err in errors:
                    console.print(f"  [red]-[/red] {err}")

            return error_count == 0

        except Exception as e:
            console.print(f"\n[red bold]Error:[/red bold] {e}")
            logger.exception("Upload failed")
            return False
        finally:
            await self.api_agent.disconnect()

    async def show_status(self) -> bool:
        """Show KUMO router connection status and info."""
        try:
            with Progress(
                SpinnerColumn(),
                TextColumn("[progress.description]{task.description}"),
                console=console,
            ) as progress:
                progress.add_task(
                    f"[purple]Querying {self.settings.router_ip}...", total=None
                )
                async with RestClient(self.settings.router_ip) as rest:
                    connected = await rest.test_connection()

                    if connected:
                        name = await rest.get_system_name()
                        firmware = await rest.get_firmware_version()
                        port_count = await rest.detect_port_count()
                    else:
                        name = "N/A"
                        firmware = "N/A"
                        port_count = 0

            console.print()

            info_table = Table(
                box=box.ROUNDED,
                border_style="purple",
                show_header=False,
                padding=(0, 2),
            )
            info_table.add_column("Property", style="dim", width=18)
            info_table.add_column("Value", style="bold")

            status_text = (
                "[green bold]Connected[/green bold]"
                if connected
                else "[red bold]Disconnected[/red bold]"
            )

            info_table.add_row("Status", status_text)
            info_table.add_row("Router Type", "AJA KUMO")
            info_table.add_row("Router IP", self.settings.router_ip)
            info_table.add_row("System Name", name)
            info_table.add_row("Firmware", firmware)
            if port_count:
                model = f"KUMO {port_count}x{port_count}"
                info_table.add_row("Model", model)
                info_table.add_row(
                    "Total Ports",
                    f"{port_count} inputs + {port_count} outputs",
                )

            console.print(Panel(
                info_table,
                title="[bold purple]Router Status[/bold purple]",
                border_style="purple",
                padding=(1, 1),
            ))
            return connected

        except Exception as e:
            console.print(f"\n[red bold]Connection failed:[/red bold] {e}")
            return False

    def create_template(self, output_file: str) -> bool:
        """Create a template file."""
        output_path = Path(output_file)

        supported = {".xlsx", ".csv", ".json"}
        if output_path.suffix.lower() not in supported:
            console.print(
                f"[red]Unsupported format:[/red] {output_path.suffix}\n"
                f"[dim]Supported: {', '.join(supported)}[/dim]"
            )
            return False

        try:
            self.file_handler.create_template(output_path)
            console.print(Panel(
                f"[green bold]Template created:[/green bold] [purple]{output_file}[/purple]\n"
                f"[dim]Contains 64 ports (32 inputs + 32 outputs)[/dim]",
                border_style="green",
                padding=(0, 2),
            ))
            return True
        except Exception as e:
            console.print(f"[red bold]Error:[/red bold] {e}")
            return False

    def view_file(self, input_file: str) -> bool:
        """View labels from a file without connecting to router."""
        input_path = Path(input_file)

        if not input_path.exists():
            console.print(f"[red]File not found:[/red] {input_file}")
            return False

        try:
            file_data = self.file_handler.load(input_path)
            labels = filedata_to_labels(file_data)
            display_labels_table(labels, title=f"Labels from {input_path.name}")
            return True
        except Exception as e:
            console.print(f"[red bold]Error reading file:[/red bold] {e}")
            return False


# ---------------------------------------------------------------------------
# VideohubManager — Blackmagic Videohub router support
# ---------------------------------------------------------------------------

class VideohubManager:
    """Application coordinator for Blackmagic Videohub router management."""

    def __init__(self, settings: Optional[Settings] = None):
        self.settings = settings or Settings()
        self.file_handler = FileHandlerAgent()

    def download_labels(self, output_file: str) -> bool:
        """Download current labels from Videohub and save to file."""
        output_path = Path(output_file)

        supported = {".xlsx", ".csv", ".json"}
        if output_path.suffix.lower() not in supported:
            console.print(
                f"[red]Unsupported format:[/red] {output_path.suffix}\n"
                f"[dim]Supported: {', '.join(supported)}[/dim]"
            )
            return False

        try:
            with Progress(
                SpinnerColumn(),
                TextColumn("[progress.description]{task.description}"),
                BarColumn(bar_width=30),
                TaskProgressColumn(),
                console=console,
            ) as progress:
                task = progress.add_task(
                    f"[purple]Connecting to Videohub at {self.settings.router_ip}...", total=3
                )

                success, info, err = connect_videohub(self.settings.router_ip)
                progress.update(task, advance=1)

                if not success:
                    progress.stop()
                    console.print(f"\n[red bold]Connection failed:[/red bold] {err}")
                    console.print(
                        "[dim]Is this a Blackmagic Videohub?  "
                        "Try --router-type kumo for AJA KUMO routers.[/dim]"
                    )
                    return False

                progress.update(task, description="[purple]Parsing labels from initial dump...")
                labels = videohub_info_to_router_labels(info)
                progress.update(task, advance=1)

                progress.update(task, description=f"[purple]Saving to {output_path.name}...")
                file_data, skipped = router_labels_to_filedata(labels)
                self.file_handler.save(output_path, file_data)
                progress.update(task, advance=1)

            console.print()
            display_router_labels_table(labels, title=f"Labels from {self.settings.router_ip}")
            console.print()

            save_msg = (
                f"[green bold]Saved {len(file_data.ports)} labels to "
                f"[purple]{output_file}[/purple][/green bold]"
            )
            if skipped:
                save_msg += (
                    f"\n[yellow dim]Note: {skipped} labels beyond port 120 were not saved "
                    f"(file format limit).[/yellow dim]"
                )
            console.print(Panel(save_msg, border_style="green", padding=(0, 2)))
            return True
        except Exception as e:
            console.print(f"[red bold]Error:[/red bold] {e}")
            return False

    def upload_labels(self, input_file: str, test_mode: bool = False) -> bool:
        """Upload labels to Videohub from file."""
        input_path = Path(input_file)

        if not input_path.exists():
            console.print(f"[red]File not found:[/red] {input_file}")
            return False

        try:
            with Progress(
                SpinnerColumn(),
                TextColumn("[progress.description]{task.description}"),
                BarColumn(bar_width=30),
                TaskProgressColumn(),
                console=console,
            ) as progress:
                task = progress.add_task(
                    f"[purple]Loading {input_path.name}...", total=3
                )
                file_data = self.file_handler.load(input_path)
                # Convert FileData -> RouterLabel for unified display
                labels: List[RouterLabel] = []
                for port_data in file_data.ports:
                    labels.append(RouterLabel(
                        port_number=port_data.port,
                        port_type=port_data.type,
                        current_label=port_data.current_label,
                        new_label=port_data.new_label,
                    ))
                progress.update(task, advance=1)

                changes = [l for l in labels if l.has_changes()]

                if not changes:
                    progress.update(task, advance=2)
                    console.print("\n[yellow]No pending changes found in file.[/yellow]")
                    display_router_labels_table(labels)
                    return True

                if test_mode:
                    progress.update(task, advance=2)
                    console.print(
                        f"\n[yellow bold]TEST MODE[/yellow bold] - "
                        f"Would upload [bold]{len(changes)}[/bold] label changes to Videohub"
                    )
                    display_router_labels_table(labels)
                    return True

                progress.update(
                    task,
                    description=f"[purple]Uploading {len(changes)} labels to Videohub...",
                )
                success_count, error_count, errors = upload_videohub_labels(
                    self.settings.router_ip, labels
                )
                progress.update(task, advance=2)

            console.print()
            if error_count == 0:
                console.print(Panel(
                    f"[green bold]Uploaded {success_count} labels successfully[/green bold]",
                    border_style="green",
                    padding=(0, 2),
                ))
            else:
                console.print(Panel(
                    f"[yellow]Uploaded {success_count} labels, "
                    f"[red]{error_count} failed[/red][/yellow]",
                    border_style="yellow",
                    padding=(0, 2),
                ))
                for err in errors:
                    console.print(f"  [red]-[/red] {err}")

            return error_count == 0

        except Exception as e:
            console.print(f"\n[red bold]Error:[/red bold] {e}")
            logger.exception("Videohub upload failed")
            return False

    def show_status(self) -> bool:
        """Show Videohub connection status and device info."""
        with Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            console=console,
        ) as progress:
            progress.add_task(
                f"[purple]Querying Videohub at {self.settings.router_ip}...", total=None
            )
            success, info, err = connect_videohub(self.settings.router_ip)

        console.print()

        info_table = Table(
            box=box.ROUNDED,
            border_style="purple",
            show_header=False,
            padding=(0, 2),
        )
        info_table.add_column("Property", style="dim", width=20)
        info_table.add_column("Value", style="bold")

        if success and info is not None:
            status_text = "[green bold]Connected[/green bold]"
            display_name = info.friendly_name or info.model_name

            info_table.add_row("Status", status_text)
            info_table.add_row("Router Type", "Blackmagic Videohub")
            info_table.add_row("Router IP", self.settings.router_ip)
            info_table.add_row("Model", info.model_name)
            if info.friendly_name:
                info_table.add_row("Friendly Name", info.friendly_name)
            info_table.add_row("Protocol Version", info.protocol_version)
            info_table.add_row(
                "Total Ports",
                f"{info.video_inputs} inputs + {info.video_outputs} outputs",
            )
        else:
            info_table.add_row("Status", "[red bold]Disconnected[/red bold]")
            info_table.add_row("Router Type", "Blackmagic Videohub")
            info_table.add_row("Router IP", self.settings.router_ip)
            info_table.add_row("Error", err or "Unknown error")

        console.print(Panel(
            info_table,
            title="[bold purple]Router Status[/bold purple]",
            border_style="purple",
            padding=(1, 1),
        ))

        if not success:
            console.print(
                "[dim]Is this a Blackmagic Videohub?  "
                "Try --router-type kumo for AJA KUMO routers.[/dim]"
            )

        return success

    def create_template(self, output_file: str, size: int = 32) -> bool:
        """Create a Videohub template file.

        Args:
            output_file: Output file path.
            size: Number of ports per type (10, 12, 16, 20, 40, 80, 120).
                  Capped at 120 to support Videohub 120x120.
        """
        output_path = Path(output_file)

        supported = {".xlsx", ".csv", ".json"}
        if output_path.suffix.lower() not in supported:
            console.print(
                f"[red]Unsupported format:[/red] {output_path.suffix}\n"
                f"[dim]Supported: {', '.join(supported)}[/dim]"
            )
            return False

        # Cap at 120 to support Videohub 120x120
        capped = min(size, 120)
        labels: List[RouterLabel] = []
        for i in range(1, capped + 1):
            labels.append(RouterLabel(port_number=i, port_type="INPUT", current_label=f"Input {i}"))
        for i in range(1, capped + 1):
            labels.append(RouterLabel(port_number=i, port_type="OUTPUT", current_label=f"Output {i}"))

        try:
            file_data, _ = router_labels_to_filedata(labels)
            self.file_handler.save(output_path, file_data)
            note = ""
            if size > 120:
                note = f"\n[yellow dim]Note: Template capped at 120 ports (maximum supported). Requested {size}.[/yellow dim]"
            console.print(Panel(
                f"[green bold]Videohub template created:[/green bold] [purple]{output_file}[/purple]\n"
                f"[dim]Contains {capped * 2} ports ({capped} inputs + {capped} outputs)[/dim]{note}",
                border_style="green",
                padding=(0, 2),
            ))
            return True
        except Exception as e:
            console.print(f"[red bold]Error:[/red bold] {e}")
            return False


# ---------------------------------------------------------------------------
# Argument parser
# ---------------------------------------------------------------------------

ROUTER_TYPE_CHOICES = ["auto", "kumo", "videohub"]

ROUTER_TYPE_HELP = (
    "Router protocol type.  "
    "'auto' (default) probes TCP 9990 first; if the device responds with a "
    "Videohub PROTOCOL PREAMBLE it is treated as a Videohub, otherwise KUMO. "
    "'kumo' forces AJA KUMO REST/Telnet.  'videohub' forces Blackmagic TCP."
)


def build_parser() -> argparse.ArgumentParser:
    """Build the argument parser with all commands."""
    parser = argparse.ArgumentParser(
        description="Router Label Manager - Professional AV Production Tool",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  kumo-cli download labels.csv --ip 192.168.1.100\n"
            "  kumo-cli download labels.csv --ip 192.168.1.50 --router-type videohub\n"
            "  kumo-cli upload labels.xlsx --ip 192.168.1.100 --test\n"
            "  kumo-cli status --ip 192.168.1.100\n"
            "  kumo-cli status --ip 192.168.1.50 -t videohub\n"
            "  kumo-cli template labels.xlsx\n"
            "  kumo-cli view labels.csv\n"
        ),
    )
    parser.add_argument(
        "-v", "--verbose", action="store_true", help="Enable verbose logging"
    )

    subparsers = parser.add_subparsers(dest="command", help="Available commands")

    # Download command
    dl = subparsers.add_parser("download", help="Download labels from router")
    dl.add_argument("output", help="Output file path (.xlsx, .csv, .json)")
    dl.add_argument("--ip", help="Router IP address")
    dl.add_argument(
        "-t", "--router-type",
        dest="router_type",
        choices=ROUTER_TYPE_CHOICES,
        default="auto",
        help=ROUTER_TYPE_HELP,
    )

    # Upload command
    ul = subparsers.add_parser("upload", help="Upload labels to router")
    ul.add_argument("input", help="Input file path (.xlsx, .csv, .json)")
    ul.add_argument("--ip", help="Router IP address")
    ul.add_argument("--test", action="store_true", help="Dry run (show changes only)")
    ul.add_argument(
        "-t", "--router-type",
        dest="router_type",
        choices=ROUTER_TYPE_CHOICES,
        default="auto",
        help=ROUTER_TYPE_HELP,
    )

    # Status command
    st = subparsers.add_parser("status", help="Show router connection status and info")
    st.add_argument("--ip", help="Router IP address")
    st.add_argument(
        "-t", "--router-type",
        dest="router_type",
        choices=ROUTER_TYPE_CHOICES,
        default="auto",
        help=ROUTER_TYPE_HELP,
    )

    # Template command
    tp = subparsers.add_parser("template", help="Create a template file")
    tp.add_argument("output", help="Template file path (.xlsx, .csv, .json)")
    tp.add_argument(
        "--size",
        type=int,
        default=32,
        metavar="N",
        help=(
            "Number of ports per type for Videohub templates "
            "(e.g. 10, 12, 16, 20, 40, 80, 120). Ignored for KUMO templates. Default: 32"
        ),
    )
    tp.add_argument(
        "-t", "--router-type",
        dest="router_type",
        choices=ROUTER_TYPE_CHOICES,
        default="auto",
        help=ROUTER_TYPE_HELP,
    )

    # View command
    vw = subparsers.add_parser("view", help="View labels from a file")
    vw.add_argument("input", help="Input file path (.xlsx, .csv, .json)")

    return parser


# ---------------------------------------------------------------------------
# Router type resolution
# ---------------------------------------------------------------------------

def resolve_router_type(requested: str, ip: str) -> str:
    """Resolve the effective router type, running auto-detection when needed.

    Args:
        requested: Value of the --router-type argument ("auto", "kumo", "videohub").
        ip: IP address to probe when requested == "auto".

    Returns:
        "kumo" or "videohub"
    """
    if requested == "kumo":
        return "kumo"
    if requested == "videohub":
        return "videohub"

    # Auto-detect
    console.print(f"[dim]Auto-detecting router type at {ip}...[/dim]")
    detected = detect_router_type(ip)
    console.print(f"[dim]Detected: {'Blackmagic Videohub' if detected == 'videohub' else 'AJA KUMO'}[/dim]")
    return detected


# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

def main() -> None:
    """Main CLI entry point."""
    parser = build_parser()
    args = parser.parse_args()

    if not args.command:
        print_banner()
        parser.print_help()
        sys.exit(0)

    setup_logging(getattr(args, "verbose", False))
    print_banner()

    settings = Settings()
    if hasattr(args, "ip") and args.ip:
        settings.router_ip = args.ip

    try:
        if args.command == "download":
            router_type = resolve_router_type(args.router_type, settings.router_ip)
            if router_type == "videohub":
                manager = VideohubManager(settings)
                success = manager.download_labels(args.output)
            else:
                manager = KumoManager(settings)
                success = asyncio.run(manager.download_labels(args.output))

        elif args.command == "upload":
            router_type = resolve_router_type(args.router_type, settings.router_ip)
            if router_type == "videohub":
                manager = VideohubManager(settings)
                success = manager.upload_labels(args.input, args.test)
            else:
                manager = KumoManager(settings)
                success = asyncio.run(manager.upload_labels(args.input, args.test))

        elif args.command == "status":
            router_type = resolve_router_type(args.router_type, settings.router_ip)
            if router_type == "videohub":
                manager = VideohubManager(settings)
                success = manager.show_status()
            else:
                manager = KumoManager(settings)
                success = asyncio.run(manager.show_status())

        elif args.command == "template":
            # For template command, skip network detection if no explicit type given
            if args.router_type == "auto":
                router_type = "kumo"  # Default, no network needed
            else:
                router_type = args.router_type
            size = getattr(args, "size", 32)
            if router_type == "videohub":
                manager = VideohubManager(settings)
                success = manager.create_template(args.output, size=size)
            else:
                manager = KumoManager(settings)
                success = manager.create_template(args.output)

        elif args.command == "view":
            manager = KumoManager(settings)
            success = manager.view_file(args.input)

        else:
            console.print(f"[red]Unknown command:[/red] {args.command}")
            sys.exit(1)

        sys.exit(0 if success else 1)

    except KeyboardInterrupt:
        console.print("\n[yellow]Operation cancelled.[/yellow]")
        sys.exit(130)
    except Exception as e:
        console.print(f"\n[red bold]Fatal error:[/red bold] {e}")
        logger.exception("Unexpected error")
        sys.exit(1)


if __name__ == "__main__":
    main()
