"""
File Handler Agent for managing CSV, Excel, and JSON files.

Provides unified interface for loading and saving port data across multiple formats.
"""
from pathlib import Path
from typing import Optional, Literal, Union
from datetime import datetime

from .schema import FileData, PortData
from .excel_handler import ExcelHandler
from .csv_handler import CSVHandler
from .json_handler import JSONHandler
from ...models.events import FileEvent, EventType


FileFormat = Literal["excel", "csv", "json"]


class FileHandlerAgent:
    """
    Main agent for handling file operations across multiple formats.

    Supports:
    - Excel (.xlsx) files with KUMO_Labels worksheet
    - CSV files with proper encoding and escaping
    - JSON files with nested or flat structure

    Events emitted:
    - file.loaded: When a file is successfully loaded
    - file.saved: When a file is successfully saved
    """

    def __init__(self, event_bus=None):
        """
        Initialize the File Handler Agent.

        Args:
            event_bus: Optional event bus for emitting events
        """
        self.event_bus = event_bus
        self.excel_handler = ExcelHandler()
        self.csv_handler = CSVHandler()
        self.json_handler = JSONHandler()

        self._last_loaded_file: Optional[Path] = None
        self._last_loaded_format: Optional[FileFormat] = None

    def load(
        self,
        file_path: Union[str, Path],
        file_format: Optional[FileFormat] = None,
    ) -> FileData:
        """
        Load file data from any supported format.

        Auto-detects format from extension if not specified.

        Args:
            file_path: Path to file
            file_format: Optional format override ('excel', 'csv', 'json')

        Returns:
            FileData object with loaded data

        Raises:
            FileNotFoundError: If file doesn't exist
            ValueError: If format is unsupported or data is invalid
        """
        file_path = Path(file_path)

        # Auto-detect format from extension
        if file_format is None:
            file_format = self._detect_format(file_path)

        # Load using appropriate handler
        try:
            if file_format == "excel":
                data = self.excel_handler.read_excel(file_path)
            elif file_format == "csv":
                data = self.csv_handler.read_csv(file_path)
            elif file_format == "json":
                data = self.json_handler.read_json(file_path)
            else:
                raise ValueError(f"Unsupported file format: {file_format}")

            # Track loaded file
            self._last_loaded_file = file_path
            self._last_loaded_format = file_format

            # Emit event
            self._emit_event("file.loaded", {
                "file_path": str(file_path),
                "format": file_format,
                "port_count": len(data.ports),
                "input_count": len(data.get_inputs()),
                "output_count": len(data.get_outputs()),
                "timestamp": datetime.now().isoformat(),
            })

            return data

        except Exception as e:
            self._emit_event("file.load_failed", {
                "file_path": str(file_path),
                "format": file_format,
                "error": str(e),
                "timestamp": datetime.now().isoformat(),
            })
            raise

    def save(
        self,
        file_path: Union[str, Path],
        data: FileData,
        file_format: Optional[FileFormat] = None,
        **kwargs,
    ) -> None:
        """
        Save file data to any supported format.

        Auto-detects format from extension if not specified.

        Args:
            file_path: Path to save file
            data: FileData object to save
            file_format: Optional format override ('excel', 'csv', 'json')
            **kwargs: Additional format-specific options:
                - create_template (Excel): Create 64-row template
                - nested (JSON): Use nested structure
                - pretty (JSON): Pretty print with indentation

        Raises:
            ValueError: If format is unsupported or data is invalid
        """
        file_path = Path(file_path)

        # Auto-detect format from extension
        if file_format is None:
            file_format = self._detect_format(file_path)

        # Ensure parent directory exists
        file_path.parent.mkdir(parents=True, exist_ok=True)

        # Save using appropriate handler
        try:
            if file_format == "excel":
                create_template = kwargs.get("create_template", False)
                self.excel_handler.write_excel(file_path, data, create_template)
            elif file_format == "csv":
                self.csv_handler.write_csv(file_path, data)
            elif file_format == "json":
                nested = kwargs.get("nested", True)
                pretty = kwargs.get("pretty", True)
                self.json_handler.write_json(file_path, data, nested, pretty)
            else:
                raise ValueError(f"Unsupported file format: {file_format}")

            # Emit event
            self._emit_event("file.saved", {
                "file_path": str(file_path),
                "format": file_format,
                "port_count": len(data.ports),
                "timestamp": datetime.now().isoformat(),
            })

        except Exception as e:
            self._emit_event("file.save_failed", {
                "file_path": str(file_path),
                "format": file_format,
                "error": str(e),
                "timestamp": datetime.now().isoformat(),
            })
            raise

    def create_template(
        self,
        file_path: Union[str, Path],
        file_format: Optional[FileFormat] = None,
    ) -> None:
        """
        Create a template file with 64 ports (32 inputs + 32 outputs).

        Args:
            file_path: Path to save template file
            file_format: Optional format override

        Raises:
            ValueError: If format is unsupported
        """
        file_path = Path(file_path)

        # Auto-detect format from extension
        if file_format is None:
            file_format = self._detect_format(file_path)

        # Ensure parent directory exists
        file_path.parent.mkdir(parents=True, exist_ok=True)

        # Create template using appropriate handler
        if file_format == "excel":
            # Create empty data and use template flag
            empty_data = FileData(ports=[])
            self.excel_handler.write_excel(file_path, empty_data, create_template=True)
        elif file_format == "csv":
            self.csv_handler.create_template_csv(file_path)
        elif file_format == "json":
            self.json_handler.create_template_json(file_path, nested=True)
        else:
            raise ValueError(f"Unsupported file format: {file_format}")

        self._emit_event("file.template_created", {
            "file_path": str(file_path),
            "format": file_format,
            "timestamp": datetime.now().isoformat(),
        })

    def _detect_format(self, file_path: Path) -> FileFormat:
        """
        Detect file format from extension.

        Args:
            file_path: Path to file

        Returns:
            Detected format

        Raises:
            ValueError: If extension is not recognized
        """
        suffix = file_path.suffix.lower()

        if suffix in [".xlsx", ".xls"]:
            return "excel"
        elif suffix == ".csv":
            return "csv"
        elif suffix == ".json":
            return "json"
        else:
            raise ValueError(
                f"Unsupported file extension: {suffix}. "
                f"Supported: .xlsx, .csv, .json"
            )

    def _emit_event(self, event_name: str, data: dict) -> None:
        """Emit event to event bus if available.

        Uses fire-and-forget for async event buses, or direct call for sync ones.
        """
        if self.event_bus:
            try:
                event = FileEvent(
                    file_path=data.get("file_path", ""),
                    operation=event_name,
                    data=data
                )
                if hasattr(self.event_bus, "publish"):
                    import asyncio
                    try:
                        loop = asyncio.get_running_loop()
                        loop.create_task(self.event_bus.publish(event))
                    except RuntimeError:
                        # No running event loop - skip async publish
                        pass
            except Exception:
                pass

    @property
    def last_loaded_file(self) -> Optional[Path]:
        """Get the last loaded file path."""
        return self._last_loaded_file

    @property
    def last_loaded_format(self) -> Optional[FileFormat]:
        """Get the last loaded file format."""
        return self._last_loaded_format


# Export public API
__all__ = [
    "FileHandlerAgent",
    "FileData",
    "PortData",
    "FileFormat",
    "ExcelHandler",
    "CSVHandler",
    "JSONHandler",
]
