"""
Command-line interface for Helix Router Label Manager v5.3.0.

Beautiful, fast, and functional CLI powered by Rich.
Supports AJA KUMO, Blackmagic Videohub, and Lightware MX2 matrix routers.
"""
import asyncio
import argparse
import logging
import re
import socket
import sys
import time
from dataclasses import dataclass
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
from .agents.api_agent.router_protocols import KUMO_COLORS, KUMO_DEFAULT_COLOR
from .agents.api_agent.videohub_protocol import (
    VIDEOHUB_PORT,
    VIDEOHUB_TIMEOUT,
    VIDEOHUB_MAX_LABEL_LENGTH,
    VideohubInfo,
    connect_videohub,
    upload_videohub_labels,
)
from .agents.api_agent.lightware_protocol import (
    LIGHTWARE_PORT,
    LIGHTWARE_TIMEOUT,
    LIGHTWARE_MAX_LABEL_LENGTH,
    LightwareInfo,
    connect_lightware,
    upload_lightware_label,
)
from .agents.file_handler import FileHandlerAgent, FileData, PortData
from .models import Label, PortType


console = Console()
logger = logging.getLogger(__name__)

APP_VERSION = "5.3.0"


# ---------------------------------------------------------------------------
# Internal label representation — no port-number cap, works for both routers
# TODO: Migrate to use src.models.label.Label directly
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
    current_label_line2: str = ""
    new_label_line2: Optional[str] = None
    current_color: int = 4
    new_color: Optional[int] = None

    def has_changes(self) -> bool:
        line1 = self.new_label is not None and self.new_label != self.current_label
        line2 = self.new_label_line2 is not None and self.new_label_line2 != self.current_label_line2
        color = self.new_color is not None and self.new_color != self.current_color
        return line1 or line2 or color

    def __str__(self) -> str:
        change = f" -> {self.new_label}" if self.new_label is not None and self.new_label != self.current_label else ""
        return f"Port {self.port_number} ({self.port_type}): {self.current_label}{change}"


def detect_router_type(ip: str) -> str:
    """Auto-detect the router type at the given IP address.

    Probe order:
    1. Lightware LW3 TCP 6107 — send a minimal GET command; if the response
       contains "ProductName" the device is a Lightware MX2.
    2. Videohub TCP 9990 — if the first response line contains
       "PROTOCOL PREAMBLE" the device is a Blackmagic Videohub.
    3. Falls back to assuming KUMO.

    Uses makefile().readline() for reliable line reading — a single recv()
    call is not guaranteed to contain a full line on all platforms.

    Returns:
        "lightware", "videohub", or "kumo"
    """
    # --- Probe Lightware LW3 (port 6107) ---
    lw_sock = None
    try:
        lw_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        lw_sock.settimeout(LIGHTWARE_TIMEOUT)
        lw_sock.connect((ip, LIGHTWARE_PORT))
        # Send a minimal GET command with request ID 0001.
        lw_sock.sendall(b"0001#GET /.ProductName\r\n")
        lw_sock.settimeout(2.0)
        response = b""
        deadline = time.monotonic() + 2.0
        while time.monotonic() < deadline:
            try:
                chunk = lw_sock.recv(1024)
                if not chunk:
                    break
                response += chunk
                if b"}" in response:
                    break
            except socket.timeout:
                break
        if b"ProductName" in response:
            return "lightware"
    except (socket.timeout, socket.error, OSError):
        pass
    finally:
        if lw_sock:
            try: lw_sock.close()
            except OSError: pass

    # --- Probe Videohub (port 9990) ---
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
            except OSError: pass
        if sock:
            try: sock.close()
            except OSError: pass
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
    banner.append("Helix", style="bold purple")
    banner.append(" Router Label Manager ", style="bold white")
    banner.append(f"v{APP_VERSION}", style="dim purple")

    console.print(Panel(
        banner,
        subtitle="[dim]AJA KUMO | Blackmagic Videohub | Lightware MX2[/dim]",
        border_style="purple",
        padding=(0, 2),
    ))


def _color_block(color_id: int) -> str:
    """Return a Rich markup colored block for a KUMO color ID."""
    if color_id in KUMO_COLORS:
        _, idle_hex, _ = KUMO_COLORS[color_id]
        return f"[on {idle_hex}]  [/]"
    return "  "


def display_router_labels_table(
    labels: List[RouterLabel],
    title: str = "Router Labels",
    show_colors: bool = False,
) -> None:
    """Display RouterLabel objects in a Rich table with inputs and outputs side by side."""
    inputs = [l for l in labels if l.port_type == "INPUT"]
    outputs = [l for l in labels if l.port_type == "OUTPUT"]

    input_table = Table(
        title="[bold green]INPUTS (Sources)[/bold green]",
        box=box.SIMPLE,
        border_style="green",
        header_style="bold green",
        show_lines=False,
        padding=(0, 1),
    )
    input_table.add_column("#", style="dim", justify="right", width=3)
    if show_colors:
        input_table.add_column("Color", width=4, justify="center")
    input_table.add_column("Label", style="white", min_width=14)
    input_table.add_column("Line 2", style="dim white", min_width=8)
    input_table.add_column("Change", style="yellow", min_width=10)

    for lbl in sorted(inputs, key=lambda l: l.port_number):
        change_parts = []
        if lbl.new_label is not None and lbl.new_label != lbl.current_label:
            change_parts.append(lbl.new_label)
        if lbl.new_label_line2 is not None and lbl.new_label_line2 != lbl.current_label_line2:
            change_parts.append(f"L2:{lbl.new_label_line2}")
        if lbl.new_color is not None and lbl.new_color != lbl.current_color:
            cname = KUMO_COLORS.get(lbl.new_color, ("?",))[0]
            change_parts.append(f"C:{cname}")
        change = "|".join(change_parts)
        row = [str(lbl.port_number)]
        if show_colors:
            display_color = lbl.new_color if lbl.new_color is not None else lbl.current_color
            row.append(_color_block(display_color))
        row.extend([
            lbl.current_label or "[dim]\u00b7[/dim]",
            lbl.current_label_line2 or "",
            Text(change, style="bold yellow") if change else "",
        ])
        input_table.add_row(*row)

    output_table = Table(
        title="[bold purple]OUTPUTS (Destinations)[/bold purple]",
        box=box.SIMPLE,
        border_style="purple",
        header_style="bold purple",
        show_lines=False,
        padding=(0, 1),
    )
    output_table.add_column("#", style="dim", justify="right", width=3)
    if show_colors:
        output_table.add_column("Color", width=4, justify="center")
    output_table.add_column("Label", style="white", min_width=14)
    output_table.add_column("Line 2", style="dim white", min_width=8)
    output_table.add_column("Change", style="yellow", min_width=10)

    for lbl in sorted(outputs, key=lambda l: l.port_number):
        change_parts = []
        if lbl.new_label is not None and lbl.new_label != lbl.current_label:
            change_parts.append(lbl.new_label)
        if lbl.new_label_line2 is not None and lbl.new_label_line2 != lbl.current_label_line2:
            change_parts.append(f"L2:{lbl.new_label_line2}")
        if lbl.new_color is not None and lbl.new_color != lbl.current_color:
            cname = KUMO_COLORS.get(lbl.new_color, ("?",))[0]
            change_parts.append(f"C:{cname}")
        change = "|".join(change_parts)
        row = [str(lbl.port_number)]
        if show_colors:
            display_color = lbl.new_color if lbl.new_color is not None else lbl.current_color
            row.append(_color_block(display_color))
        row.extend([
            lbl.current_label or "[dim]\u00b7[/dim]",
            lbl.current_label_line2 or "",
            Text(change, style="bold yellow") if change else "",
        ])
        output_table.add_row(*row)

    console.print()
    console.print(Columns([input_table, output_table], padding=1))

    total = len(labels)
    changes = sum(1 for l in labels if l.has_changes())
    summary = (
        f" [dim]Total:[/dim] [bold]{total}[/bold]"
        f" [dim]|[/dim] [dim]In:[/dim] [green]{len(inputs)}[/green]"
        f" [dim]|[/dim] [dim]Out:[/dim] [purple]{len(outputs)}[/purple]"
    )
    if changes:
        summary += f" [dim]|[/dim] [dim]Pending:[/dim] [yellow]{changes}[/yellow]"
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
            current_label_line2=label.current_label_line2,
            new_label_line2=label.new_label_line2,
            current_color=label.current_color,
            new_color=label.new_color,
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
            current_label_line2=port_data.current_label_line2,
            new_label_line2=port_data.new_label_line2,
            current_color=port_data.current_color,
            new_color=port_data.new_color,
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
            current_label_line2=l.current_label_line2,
            new_label_line2=l.new_label_line2,
            current_color=l.current_color,
            new_color=l.new_color,
        )
        for l in labels
    ]


def display_labels_table(labels: List[Label], title: str = "Router Labels") -> None:
    """Display domain Label objects — retained for AJA KUMO backward compatibility."""
    display_router_labels_table(domain_labels_to_router_labels(labels), title, show_colors=True)


def videohub_info_to_router_labels(info: VideohubInfo) -> List[RouterLabel]:
    """Convert a parsed VideohubInfo into a flat RouterLabel list (1-based ports)."""
    router_labels: List[RouterLabel] = []
    for i, text in enumerate(info.input_labels, start=1):
        router_labels.append(RouterLabel(port_number=i, port_type="INPUT", current_label=text))
    for i, text in enumerate(info.output_labels, start=1):
        router_labels.append(RouterLabel(port_number=i, port_type="OUTPUT", current_label=text))
    return router_labels


def lightware_info_to_router_labels(info: LightwareInfo) -> List[RouterLabel]:
    """Convert a parsed LightwareInfo into a flat RouterLabel list (1-based ports)."""
    router_labels: List[RouterLabel] = []
    for port_num in sorted(info.input_labels):
        router_labels.append(RouterLabel(
            port_number=port_num,
            port_type="INPUT",
            current_label=info.input_labels[port_num],
        ))
    for port_num in sorted(info.output_labels):
        router_labels.append(RouterLabel(
            port_number=port_num,
            port_type="OUTPUT",
            current_label=info.output_labels[port_num],
        ))
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
# HelixManager — main application coordinator
# ---------------------------------------------------------------------------

class HelixManager:
    """Main application coordinator for router management."""

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
                f"[dim]Contains ports for inputs and outputs[/dim]",
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
# LightwareManager — Lightware MX2 router support
# ---------------------------------------------------------------------------

class LightwareManager:
    """Application coordinator for Lightware MX2 router management."""

    def __init__(self, settings: Optional[Settings] = None):
        self.settings = settings or Settings()
        self.file_handler = FileHandlerAgent()

    def download_labels(self, output_file: str) -> bool:
        """Download current labels from Lightware MX2 and save to file."""
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
                    f"[purple]Connecting to Lightware at {self.settings.router_ip}...", total=3
                )

                success, info, err = connect_lightware(self.settings.router_ip)
                progress.update(task, advance=1)

                if not success:
                    progress.stop()
                    console.print(f"\n[red bold]Connection failed:[/red bold] {err}")
                    console.print(
                        "[dim]Is this a Lightware MX2?  "
                        "Try --router-type kumo for AJA KUMO routers or "
                        "--router-type videohub for Blackmagic Videohub.[/dim]"
                    )
                    return False

                progress.update(task, description="[purple]Parsing labels from device...")
                labels = lightware_info_to_router_labels(info)
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
        """Upload labels to Lightware MX2 from file."""
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
                        f"Would upload [bold]{len(changes)}[/bold] label changes to Lightware"
                    )
                    display_router_labels_table(labels)
                    return True

                progress.update(
                    task,
                    description=f"[purple]Uploading {len(changes)} labels to Lightware...",
                )
                success_count = 0
                error_count = 0
                error_messages: List[str] = []

                for lbl in changes:
                    ok = upload_lightware_label(
                        self.settings.router_ip,
                        lbl.port_type,
                        lbl.port_number,
                        lbl.new_label or "",
                    )
                    if ok:
                        success_count += 1
                    else:
                        error_count += 1
                        error_messages.append(
                            f"Failed to upload {lbl.port_type} port {lbl.port_number}: "
                            f"{lbl.new_label!r}"
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
                for err in error_messages:
                    console.print(f"  [red]-[/red] {err}")

            return error_count == 0

        except Exception as e:
            console.print(f"\n[red bold]Error:[/red bold] {e}")
            logger.exception("Lightware upload failed")
            return False

    def show_status(self) -> bool:
        """Show Lightware MX2 connection status and device info."""
        with Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            console=console,
        ) as progress:
            progress.add_task(
                f"[purple]Querying Lightware at {self.settings.router_ip}...", total=None
            )
            success, info, err = connect_lightware(self.settings.router_ip)

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

            info_table.add_row("Status", status_text)
            info_table.add_row("Router Type", "Lightware MX2")
            info_table.add_row("Router IP", self.settings.router_ip)
            info_table.add_row("Product Name", info.product_name)
            info_table.add_row(
                "Total Ports",
                f"{info.input_count} inputs + {info.output_count} outputs",
            )
        else:
            info_table.add_row("Status", "[red bold]Disconnected[/red bold]")
            info_table.add_row("Router Type", "Lightware MX2")
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
                "[dim]Is this a Lightware MX2?  "
                "Try --router-type kumo for AJA KUMO routers or "
                "--router-type videohub for Blackmagic Videohub.[/dim]"
            )

        return success

    def create_template(self, output_file: str, size: int = 16) -> bool:
        """Create a Lightware MX2 template file.

        Args:
            output_file: Output file path.
            size: Number of ports per type (4, 8, 16, 32, 48).
                  Capped at 48 to match the maximum MX2 matrix size.
        """
        output_path = Path(output_file)

        supported = {".xlsx", ".csv", ".json"}
        if output_path.suffix.lower() not in supported:
            console.print(
                f"[red]Unsupported format:[/red] {output_path.suffix}\n"
                f"[dim]Supported: {', '.join(supported)}[/dim]"
            )
            return False

        # Cap at 48 to support the largest Lightware MX2 matrix
        capped = min(size, 48)
        labels: List[RouterLabel] = []
        for i in range(1, capped + 1):
            labels.append(RouterLabel(port_number=i, port_type="INPUT", current_label=f"Input {i}"))
        for i in range(1, capped + 1):
            labels.append(RouterLabel(port_number=i, port_type="OUTPUT", current_label=f"Output {i}"))

        try:
            file_data, _ = router_labels_to_filedata(labels)
            self.file_handler.save(output_path, file_data)
            note = ""
            if size > 48:
                note = (
                    f"\n[yellow dim]Note: Template capped at 48 ports "
                    f"(maximum MX2 size). Requested {size}.[/yellow dim]"
                )
            console.print(Panel(
                f"[green bold]Lightware template created:[/green bold] "
                f"[purple]{output_file}[/purple]\n"
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

# ---------------------------------------------------------------------------
# "Like Names" auto-color algorithm
# ---------------------------------------------------------------------------

# Color cycle: skip 4 (Blue, the default) so grouped labels stand out
LIKE_NAMES_COLOR_CYCLE = [1, 2, 3, 5, 6, 7, 8, 9]


def _extract_base_name(label: str) -> str:
    """Extract the base name from a label by stripping trailing digits/separators.

    "CAM 1" -> "CAM", "Monitor-3" -> "Monitor", "DECK_01" -> "DECK"
    """
    stripped = re.sub(r'[\s\d\-_\.]+$', '', label.strip())
    return stripped if stripped else label.strip()


def assign_like_name_colors(labels: List[RouterLabel]) -> Dict[str, int]:
    """Group labels by base name and assign colors.

    Returns:
        Dict mapping base_name (lowercase) -> color_id
    """
    # Group by base name (case-insensitive)
    groups: Dict[str, List[RouterLabel]] = {}
    for lbl in labels:
        if not lbl.current_label.strip():
            continue
        base = _extract_base_name(lbl.current_label).lower()
        groups.setdefault(base, []).append(lbl)

    # Only color groups with 2+ members
    multi_groups = {k: v for k, v in groups.items() if len(v) >= 2}

    # Assign colors cycling through the palette
    color_map: Dict[str, int] = {}
    for i, base_name in enumerate(sorted(multi_groups.keys())):
        color_map[base_name] = LIKE_NAMES_COLOR_CYCLE[i % len(LIKE_NAMES_COLOR_CYCLE)]

    return color_map


def run_like_names(csv_file: str, preview: bool = False) -> bool:
    """Run the like-names auto-color algorithm on a CSV file."""
    csv_path = Path(csv_file)

    if not csv_path.exists():
        console.print(f"[red]File not found:[/red] {csv_file}")
        return False

    try:
        file_handler = FileHandlerAgent()
        file_data = file_handler.load(csv_path)
        labels = filedata_to_labels(file_data)
        router_labels = domain_labels_to_router_labels(labels)

        color_map = assign_like_name_colors(router_labels)

        if not color_map:
            console.print("[yellow]No label groups found with 2+ matching base names.[/yellow]")
            return True

        # Apply colors
        changed = 0
        for lbl in labels:
            base = _extract_base_name(lbl.current_label).lower()
            if base in color_map:
                new_c = color_map[base]
                if new_c != lbl.current_color:
                    lbl.new_color = new_c
                    changed += 1

        # Display groupings
        console.print()
        group_table = Table(
            title="[bold]Like-Name Color Groups[/bold]",
            box=box.ROUNDED,
            border_style="purple",
        )
        group_table.add_column("Base Name", style="white")
        group_table.add_column("Color", width=6, justify="center")
        group_table.add_column("Members", style="dim")

        # Rebuild groups for display
        groups: Dict[str, List[str]] = {}
        for lbl in labels:
            base = _extract_base_name(lbl.current_label).lower()
            if base in color_map:
                groups.setdefault(base, []).append(lbl.current_label)

        for base_name in sorted(color_map.keys()):
            color_id = color_map[base_name]
            cname = KUMO_COLORS.get(color_id, ("?",))[0]
            members = ", ".join(groups.get(base_name, []))
            group_table.add_row(base_name.title(), f"{_color_block(color_id)} {cname}", members)

        console.print(group_table)
        console.print(f"\n[bold]Grouped {changed} labels into {len(color_map)} color groups[/bold]")

        if preview:
            console.print("[yellow]Preview mode - no changes saved.[/yellow]")
        else:
            # Write back
            file_data = labels_to_filedata(labels)
            file_handler.save(csv_path, file_data)
            console.print(f"[green]Saved color assignments to {csv_file}[/green]")

        return True

    except Exception as e:
        console.print(f"[red bold]Error:[/red bold] {e}")
        logger.exception("Like-names failed")
        return False


ROUTER_TYPE_CHOICES = ["auto", "kumo", "videohub", "lightware"]

ROUTER_TYPE_HELP = (
    "Router protocol type.  "
    "'auto' (default) probes TCP 6107 for Lightware LW3, then TCP 9990 for "
    "Videohub PROTOCOL PREAMBLE, and falls back to KUMO. "
    "'kumo' forces AJA KUMO REST/Telnet.  'videohub' forces Blackmagic TCP 9990.  "
    "'lightware' forces Lightware MX2 LW3 TCP 6107."
)


def build_parser() -> argparse.ArgumentParser:
    """Build the argument parser with all commands."""
    parser = argparse.ArgumentParser(
        description="Helix - Professional AV Router Label Manager",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  helix download labels.csv --ip 192.168.1.100\n"
            "  helix download labels.csv --ip 192.168.1.50 --router-type videohub\n"
            "  helix download labels.csv --ip 192.168.1.60 --router-type lightware\n"
            "  helix upload labels.xlsx --ip 192.168.1.100 --test\n"
            "  helix status --ip 192.168.1.100\n"
            "  helix status --ip 192.168.1.50 -t videohub\n"
            "  helix status --ip 192.168.1.60 -t lightware\n"
            "  helix template labels.xlsx\n"
            "  helix template labels.xlsx -t lightware --size 16\n"
            "  helix view labels.csv\n"
            "  helix like-names labels.csv --preview\n"
            "\n"
            "Multi-router:\n"
            "  helix download labels.csv --ip 192.168.100.51 --ip 192.168.100.52\n"
            "  helix download labels.csv --ip 192.168.100.51,192.168.100.52\n"
            "  helix status  (uses default IPs from settings)\n"
        ),
    )
    parser.add_argument(
        "-v", "--verbose", action="store_true", help="Enable verbose logging"
    )

    subparsers = parser.add_subparsers(dest="command", help="Available commands")

    # Download command
    dl = subparsers.add_parser("download", help="Download labels from router")
    dl.add_argument("output", help="Output file path (.xlsx, .csv, .json)")
    dl.add_argument("--ip", action="append", dest="ips", help="Router IP address (repeatable, comma-separated)")
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
    ul.add_argument("--ip", action="append", dest="ips", help="Router IP address (repeatable, comma-separated)")
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
    st.add_argument("--ip", action="append", dest="ips", help="Router IP address (repeatable, comma-separated)")
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

    # Like-names command (KUMO only)
    ln = subparsers.add_parser(
        "like-names",
        help="Auto-assign button colors to labels with matching base names (KUMO only)",
    )
    ln.add_argument("input", help="CSV/Excel file path")
    ln.add_argument(
        "--preview",
        action="store_true",
        help="Preview groupings without saving changes",
    )

    return parser


# ---------------------------------------------------------------------------
# Router type resolution
# ---------------------------------------------------------------------------

def resolve_router_type(requested: str, ip: str) -> str:
    """Resolve the effective router type, running auto-detection when needed.

    Args:
        requested: Value of the --router-type argument
                   ("auto", "kumo", "videohub", "lightware").
        ip: IP address to probe when requested == "auto".

    Returns:
        "kumo", "videohub", or "lightware"
    """
    if requested == "kumo":
        return "kumo"
    if requested == "videohub":
        return "videohub"
    if requested == "lightware":
        return "lightware"

    # Auto-detect
    console.print(f"[dim]Auto-detecting router type at {ip}...[/dim]")
    detected = detect_router_type(ip)
    if detected == "lightware":
        label = "Lightware MX2"
    elif detected == "videohub":
        label = "Blackmagic Videohub"
    else:
        label = "AJA KUMO"
    console.print(f"[dim]Detected: {label}[/dim]")
    return detected


# ---------------------------------------------------------------------------
# Multi-router helpers
# ---------------------------------------------------------------------------

def resolve_ips(args_ips: Optional[List[str]], settings: Settings) -> List[str]:
    """Expand comma-separated IPs, deduplicate, fall back to settings.router_ips."""
    if not args_ips:
        return list(settings.router_ips)
    expanded: List[str] = []
    for entry in args_ips:
        for ip in entry.split(","):
            ip = ip.strip()
            if ip and ip not in expanded:
                expanded.append(ip)
    return expanded


def _per_router_filename(base_path: str, ip: str) -> str:
    """Insert IP before extension: labels.csv -> labels_192.168.100.51.csv"""
    p = Path(base_path)
    return str(p.with_name(f"{p.stem}_{ip}{p.suffix}"))


# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

def _run_for_router(ip: str, router_type_arg: str, command: str, args, base_settings: Settings):
    """Run a single command against one router IP. Returns True on success."""
    settings = Settings(router_ip=ip)
    router_type = resolve_router_type(router_type_arg, ip)

    if command == "download":
        if router_type == "videohub":
            return VideohubManager(settings).download_labels(args.output)
        elif router_type == "lightware":
            return LightwareManager(settings).download_labels(args.output)
        else:
            return asyncio.run(HelixManager(settings).download_labels(args.output))

    elif command == "upload":
        if router_type == "videohub":
            return VideohubManager(settings).upload_labels(args.input, args.test)
        elif router_type == "lightware":
            return LightwareManager(settings).upload_labels(args.input, args.test)
        else:
            return asyncio.run(HelixManager(settings).upload_labels(args.input, args.test))

    elif command == "status":
        if router_type == "videohub":
            return VideohubManager(settings).show_status()
        elif router_type == "lightware":
            return LightwareManager(settings).show_status()
        else:
            return asyncio.run(HelixManager(settings).show_status())

    return False


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
    ips = resolve_ips(getattr(args, "ips", None), settings)
    multi = len(ips) > 1

    try:
        if args.command == "download":
            all_ok = True
            for i, ip in enumerate(ips):
                if multi:
                    if i > 0:
                        console.print()
                    console.print(f"[bold cyan]--- Router: {ip} ---[/bold cyan]")
                    # Per-router output filename
                    orig_output = args.output
                    args.output = _per_router_filename(orig_output, ip)
                ok = _run_for_router(ip, args.router_type, "download", args, settings)
                all_ok = all_ok and ok
                if multi:
                    args.output = orig_output
            success = all_ok

        elif args.command == "upload":
            all_ok = True
            for i, ip in enumerate(ips):
                if multi:
                    if i > 0:
                        console.print()
                    console.print(f"[bold cyan]--- Router: {ip} ---[/bold cyan]")
                    # Try per-router input file first, fall back to exact filename
                    per_router_file = _per_router_filename(args.input, ip)
                    orig_input = args.input
                    if Path(per_router_file).exists():
                        args.input = per_router_file
                ok = _run_for_router(ip, args.router_type, "upload", args, settings)
                all_ok = all_ok and ok
                if multi:
                    args.input = orig_input
            success = all_ok

        elif args.command == "status":
            all_ok = True
            for i, ip in enumerate(ips):
                if multi:
                    if i > 0:
                        console.print()
                    console.print(f"[bold cyan]--- Router: {ip} ---[/bold cyan]")
                try:
                    ok = _run_for_router(ip, args.router_type, "status", args, settings)
                except Exception as e:
                    console.print(f"[red]Error for {ip}:[/red] {e}")
                    ok = False
                all_ok = all_ok and ok
            success = all_ok

        elif args.command == "template":
            # No router connection needed — unchanged
            if args.router_type == "auto":
                router_type = "kumo"
            else:
                router_type = args.router_type
            size = getattr(args, "size", 32)
            if router_type == "videohub":
                manager = VideohubManager(settings)
                success = manager.create_template(args.output, size=size)
            elif router_type == "lightware":
                manager = LightwareManager(settings)
                success = manager.create_template(args.output, size=size)
            else:
                manager = HelixManager(settings)
                success = manager.create_template(args.output)

        elif args.command == "view":
            manager = HelixManager(settings)
            success = manager.view_file(args.input)

        elif args.command == "like-names":
            success = run_like_names(args.input, preview=args.preview)

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
