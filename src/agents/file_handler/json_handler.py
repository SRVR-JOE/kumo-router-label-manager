"""
JSON file handler for nested structure.
"""
from pathlib import Path
import json
from typing import Any, Dict

from .schema import FileData, PortData


class JSONHandler:
    """Handler for JSON file operations."""

    def __init__(self):
        """Initialize the JSON handler."""
        pass

    def read_json(self, file_path: Path) -> FileData:
        """
        Read JSON file and parse data.

        Supports both flat and nested structures:
        - Flat: {"ports": [{"port": 1, "type": "INPUT", ...}, ...]}
        - Nested: {"inputs": [...], "outputs": [...]}

        Args:
            file_path: Path to JSON file

        Returns:
            FileData object with parsed data

        Raises:
            FileNotFoundError: If file doesn't exist
            ValueError: If data is invalid
        """
        if not file_path.exists():
            raise FileNotFoundError(f"JSON file not found: {file_path}")

        try:
            with open(file_path, "r", encoding="utf-8") as f:
                data = json.load(f)
        except json.JSONDecodeError as e:
            raise ValueError(f"Invalid JSON format: {e}")
        except Exception as e:
            raise ValueError(f"Failed to read JSON file: {e}")

        ports = []

        # Handle nested structure (inputs/outputs)
        if "inputs" in data or "outputs" in data:
            ports.extend(self._parse_port_list(data.get("inputs", []), "INPUT"))
            ports.extend(self._parse_port_list(data.get("outputs", []), "OUTPUT"))

        # Handle flat structure (ports array)
        elif "ports" in data:
            for idx, port_dict in enumerate(data["ports"]):
                try:
                    port_data = self._parse_port_dict(port_dict)
                    ports.append(port_data)
                except (ValueError, TypeError, KeyError) as e:
                    raise ValueError(f"Invalid port data at index {idx}: {e}")

        else:
            raise ValueError(
                "JSON must contain either 'ports' array or 'inputs'/'outputs' objects"
            )

        return FileData(ports=ports)

    def write_json(
        self,
        file_path: Path,
        data: FileData,
        nested: bool = True,
        pretty: bool = True,
    ) -> None:
        """
        Write data to JSON file.

        Args:
            file_path: Path to save JSON file
            data: FileData object to write
            nested: If True, use nested structure (inputs/outputs)
                   If False, use flat structure (ports array)
            pretty: If True, format with indentation

        Raises:
            ValueError: If data is invalid
        """
        if nested:
            # Create nested structure
            json_data = {
                "inputs": [],
                "outputs": [],
            }

            for port_data in data.ports:
                port_dict = self._port_to_dict(port_data)
                if port_data.type == "INPUT":
                    json_data["inputs"].append(port_dict)
                else:
                    json_data["outputs"].append(port_dict)

        else:
            # Create flat structure
            json_data = {
                "ports": [self._port_to_dict(port_data) for port_data in data.ports]
            }

        try:
            with open(file_path, "w", encoding="utf-8") as f:
                if pretty:
                    json.dump(json_data, f, indent=2, ensure_ascii=False)
                    f.write("\n")  # Add trailing newline
                else:
                    json.dump(json_data, f, ensure_ascii=False)
        except Exception as e:
            raise ValueError(f"Failed to write JSON file: {e}")

    def _parse_port_list(
        self,
        port_list: list[Dict[str, Any]],
        default_type: str,
    ) -> list[PortData]:
        """Parse a list of port dictionaries."""
        ports = []
        for idx, port_dict in enumerate(port_list):
            try:
                # Use default type if not specified
                if "type" not in port_dict:
                    port_dict["type"] = default_type

                port_data = self._parse_port_dict(port_dict)
                ports.append(port_data)
            except (ValueError, TypeError, KeyError) as e:
                raise ValueError(
                    f"Invalid {default_type.lower()} data at index {idx}: {e}"
                )
        return ports

    def _parse_port_dict(self, port_dict: Dict[str, Any]) -> PortData:
        """Parse a single port dictionary into PortData."""
        return PortData(
            port=int(port_dict.get("port", 0)),
            type=str(port_dict.get("type", "INPUT")),
            current_label=str(port_dict.get("current_label", "")),
            new_label=port_dict.get("new_label"),
            notes=str(port_dict.get("notes", "")),
        )

    def _port_to_dict(self, port_data: PortData) -> Dict[str, Any]:
        """Convert PortData to dictionary."""
        return {
            "port": port_data.port,
            "type": port_data.type,
            "current_label": port_data.current_label,
            "new_label": port_data.new_label or "",
            "notes": port_data.notes,
        }

    def create_template_json(
        self,
        file_path: Path,
        nested: bool = True,
    ) -> None:
        """
        Create a template JSON file with 64 ports (32 inputs + 32 outputs).

        Args:
            file_path: Path to save template JSON file
            nested: If True, use nested structure
        """
        ports = []

        # Create 32 inputs
        for i in range(1, 33):
            ports.append(
                PortData(
                    port=i,
                    type="INPUT",
                    current_label="",
                    new_label=None,
                    notes="",
                )
            )

        # Create 32 outputs
        for i in range(33, 65):
            ports.append(
                PortData(
                    port=i,
                    type="OUTPUT",
                    current_label="",
                    new_label=None,
                    notes="",
                )
            )

        data = FileData(ports=ports)
        self.write_json(file_path, data, nested=nested, pretty=True)
