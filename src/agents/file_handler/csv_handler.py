"""
CSV file handler using pandas.
"""
from pathlib import Path
import pandas as pd

from .schema import FileData, PortData


class CSVHandler:
    """Handler for CSV file operations."""

    COLUMNS = ["Port", "Type", "Current_Label", "New_Label", "Notes"]

    def __init__(self):
        """Initialize the CSV handler."""
        pass

    def read_csv(self, file_path: Path) -> FileData:
        """
        Read CSV file and parse data.

        Args:
            file_path: Path to CSV file

        Returns:
            FileData object with parsed data

        Raises:
            FileNotFoundError: If file doesn't exist
            ValueError: If data is invalid
        """
        if not file_path.exists():
            raise FileNotFoundError(f"CSV file not found: {file_path}")

        try:
            # Read CSV with UTF-8 encoding
            df = pd.read_csv(
                file_path,
                encoding="utf-8",
                dtype={
                    "Port": int,
                    "Type": str,
                    "Current_Label": str,
                    "New_Label": str,
                    "Notes": str,
                },
                keep_default_na=False,  # Don't convert empty strings to NaN
            )
        except Exception as e:
            raise ValueError(f"Failed to read CSV file: {e}")

        # Validate columns
        if not all(col in df.columns for col in self.COLUMNS):
            missing = set(self.COLUMNS) - set(df.columns)
            raise ValueError(
                f"CSV missing required columns: {missing}. "
                f"Expected: {self.COLUMNS}"
            )

        ports = []
        for idx, row in df.iterrows():
            try:
                # Handle NaN values
                current_label = row["Current_Label"] if pd.notna(row["Current_Label"]) else ""
                new_label = row["New_Label"] if pd.notna(row["New_Label"]) else None
                notes = row["Notes"] if pd.notna(row["Notes"]) else ""

                port_data = PortData(
                    port=int(row["Port"]),
                    type=str(row["Type"]).strip(),
                    current_label=str(current_label).strip(),
                    new_label=str(new_label).strip() if new_label else None,
                    notes=str(notes).strip(),
                )
                ports.append(port_data)
            except (ValueError, TypeError) as e:
                raise ValueError(f"Invalid data in row {idx + 2}: {e}")

        return FileData(ports=ports)

    def write_csv(self, file_path: Path, data: FileData) -> None:
        """
        Write data to CSV file.

        Args:
            file_path: Path to save CSV file
            data: FileData object to write

        Raises:
            ValueError: If data is invalid
        """
        # Convert to pandas DataFrame
        rows = []
        for port_data in data.ports:
            rows.append({
                "Port": port_data.port,
                "Type": port_data.type,
                "Current_Label": port_data.current_label,
                "New_Label": port_data.new_label or "",
                "Notes": port_data.notes,
            })

        df = pd.DataFrame(rows, columns=self.COLUMNS)

        try:
            # Write CSV with UTF-8 encoding and proper escaping
            df.to_csv(
                file_path,
                index=False,
                encoding="utf-8",
                quoting=1,  # QUOTE_ALL - escape all fields
                escapechar="\\",
                lineterminator="\n",
            )
        except Exception as e:
            raise ValueError(f"Failed to write CSV file: {e}")

    def create_template_csv(self, file_path: Path) -> None:
        """
        Create a template CSV file with 64 rows (32 inputs + 32 outputs).

        Args:
            file_path: Path to save template CSV file
        """
        rows = []

        # Create 32 inputs
        for i in range(1, 33):
            rows.append({
                "Port": i,
                "Type": "INPUT",
                "Current_Label": "",
                "New_Label": "",
                "Notes": "",
            })

        # Create 32 outputs
        for i in range(1, 33):
            rows.append({
                "Port": i,
                "Type": "OUTPUT",
                "Current_Label": "",
                "New_Label": "",
                "Notes": "",
            })

        df = pd.DataFrame(rows, columns=self.COLUMNS)

        try:
            df.to_csv(
                file_path,
                index=False,
                encoding="utf-8",
                quoting=1,
                escapechar="\\",
                lineterminator="\n",
            )
        except Exception as e:
            raise ValueError(f"Failed to create template CSV: {e}")
