"""
Command-line interface for KUMO Router Label Manager v3.0.

Beautiful, fast, and functional CLI powered by Rich.
"""
import asyncio
import argparse
import logging
import sys
from pathlib import Path
from typing import Optional, List

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
    banner.append("KUMO", style="bold cyan")
    banner.append(" Router Label Manager ", style="bold white")
    banner.append(f"v{APP_VERSION}", style="dim cyan")

    console.print(Panel(
        banner,
        subtitle="[dim]AJA KUMO 16x16 / 32x32 / 64x64[/dim]",
        border_style="cyan",
        padding=(0, 2),
    ))


def labels_to_filedata(labels: List[Label]) -> FileData:
    """Convert Label objects to FileData for file saving."""
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
    """Convert FileData to Label objects for upload."""
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


def display_labels_table(labels: List[Label], title: str = "Router Labels") -> None:
    """Display labels in a Rich table with inputs and outputs side by side."""
    inputs = [l for l in labels if l.port_type == PortType.INPUT]
    outputs = [l for l in labels if l.port_type == PortType.OUTPUT]

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

    for label in sorted(inputs, key=lambda l: l.port_number):
        change = label.new_label if label.has_changes() else ""
        change_style = "bold yellow" if change else "dim"
        input_table.add_row(
            str(label.port_number),
            label.current_label or "[dim italic]empty[/dim italic]",
            Text(change, style=change_style) if change else Text("-", style="dim"),
        )

    output_table = Table(
        title="[bold blue]OUTPUTS (Destinations)[/bold blue]",
        box=box.ROUNDED,
        border_style="blue",
        header_style="bold blue",
        show_lines=False,
        padding=(0, 1),
    )
    output_table.add_column("#", style="dim", justify="right", width=4)
    output_table.add_column("Label", style="white", min_width=20)
    output_table.add_column("Change", style="yellow", min_width=15)

    for label in sorted(outputs, key=lambda l: l.port_number):
        change = label.new_label if label.has_changes() else ""
        change_style = "bold yellow" if change else "dim"
        output_table.add_row(
            str(label.port_number),
            label.current_label or "[dim italic]empty[/dim italic]",
            Text(change, style=change_style) if change else Text("-", style="dim"),
        )

    console.print()
    console.print(Columns([input_table, output_table], padding=2))
    console.print()

    # Summary line
    total = len(labels)
    changes = sum(1 for l in labels if l.has_changes())
    summary = (
        f"  [dim]Total:[/dim] [bold]{total}[/bold] labels"
        f"  [dim]|[/dim]  [dim]Inputs:[/dim] [green]{len(inputs)}[/green]"
        f"  [dim]|[/dim]  [dim]Outputs:[/dim] [blue]{len(outputs)}[/blue]"
    )
    if changes:
        summary += f"  [dim]|[/dim]  [dim]Pending changes:[/dim] [yellow]{changes}[/yellow]"
    console.print(summary)


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
                    f"[cyan]Connecting to {self.settings.router_ip}...", total=3
                )
                await self.api_agent.connect()
                progress.update(task, advance=1)

                progress.update(task, description="[cyan]Downloading labels (parallel)...")
                labels = await self.api_agent.download_labels()
                progress.update(task, advance=1)

                progress.update(
                    task,
                    description=f"[cyan]Saving to {output_path.name}...",
                )
                file_data = labels_to_filedata(labels)
                self.file_handler.save(output_path, file_data)
                progress.update(task, advance=1)

            console.print()
            display_labels_table(labels, title=f"Labels from {self.settings.router_ip}")
            console.print()
            console.print(Panel(
                f"[green bold]Saved {len(labels)} labels to [cyan]{output_file}[/cyan][/green bold]",
                border_style="green",
                padding=(0, 2),
            ))

            # Show next-step instructions for Excel files
            if output_path.suffix.lower() == ".xlsx":
                console.print()
                console.print(
                    "[dim]To rename labels:[/dim]\n"
                    f'  1. Open [cyan]{output_file}[/cyan] in Excel\n'
                    '  2. Type new names in the yellow [bold]New_Label[/bold] column\n'
                    "  3. Save the file, then run:\n"
                    f'     [bold]kumo-cli upload "{output_file}" --ip {self.settings.router_ip}[/bold]'
                )

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
                    f"[cyan]Loading {input_path.name}...", total=3
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
                    description=f"[cyan]Connecting to {self.settings.router_ip}...",
                )
                await self.api_agent.connect()
                progress.update(task, advance=1)

                progress.update(
                    task,
                    description=f"[cyan]Uploading {len(changes)} labels (parallel)...",
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
        """Show router connection status and info."""
        try:
            with Progress(
                SpinnerColumn(),
                TextColumn("[progress.description]{task.description}"),
                console=console,
            ) as progress:
                progress.add_task(
                    f"[cyan]Querying {self.settings.router_ip}...", total=None
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
                border_style="cyan",
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
                title="[bold cyan]Router Status[/bold cyan]",
                border_style="cyan",
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
                f"[green bold]Template created:[/green bold] [cyan]{output_file}[/cyan]\n"
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


def build_parser() -> argparse.ArgumentParser:
    """Build the argument parser with all commands."""
    parser = argparse.ArgumentParser(
        description="KUMO Router Label Manager - Professional AV Production Tool",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  kumo-cli download labels.csv --ip 192.168.1.100\n"
            "  kumo-cli upload labels.xlsx --ip 192.168.1.100 --test\n"
            "  kumo-cli status --ip 192.168.1.100\n"
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
    dl.add_argument("--ip", help="KUMO router IP address")

    # Upload command
    ul = subparsers.add_parser("upload", help="Upload labels to router")
    ul.add_argument("input", help="Input file path (.xlsx, .csv, .json)")
    ul.add_argument("--ip", help="KUMO router IP address")
    ul.add_argument("--test", action="store_true", help="Dry run (show changes only)")

    # Status command
    st = subparsers.add_parser("status", help="Show router connection status and info")
    st.add_argument("--ip", help="KUMO router IP address")

    # Template command
    tp = subparsers.add_parser("template", help="Create a template file")
    tp.add_argument("output", help="Template file path (.xlsx, .csv, .json)")

    # View command
    vw = subparsers.add_parser("view", help="View labels from a file")
    vw.add_argument("input", help="Input file path (.xlsx, .csv, .json)")

    return parser


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

    manager = KumoManager(settings)

    try:
        if args.command == "download":
            success = asyncio.run(manager.download_labels(args.output))
        elif args.command == "upload":
            success = asyncio.run(manager.upload_labels(args.input, args.test))
        elif args.command == "status":
            success = asyncio.run(manager.show_status())
        elif args.command == "template":
            success = manager.create_template(args.output)
        elif args.command == "view":
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
