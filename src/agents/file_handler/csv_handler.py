"""
CSV file handler using pandas.
"""
import logging
from pathlib import Path
import pandas as pd

from .schema import FileData, PortData

logger = logging.getLogger(__name__)


class CSVHandler:
    """Handler for CSV file operations."""

    COLUMNS = ["Port", "Type", "Current_Label", "Current_Label_Line2", "New_Label", "New_Label_Line2", "Current_Color", "New_Color", "Notes"]
    REQUIRED_COLUMNS = ["Port", "Type", "Current_Label", "New_Label", "Notes"]

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
            dtype_map = {
                "Port": int,
                "Type": str,
                "Current_Label": str,
                "New_Label": str,
                "Current_Label_Line2": str,
                "New_Label_Line2": str,
                "Current_Color": str,
                "New_Color": str,
                "Notes": str,
            }
            df = pd.read_csv(
                file_path,
                encoding="utf-8",
                dtype=dtype_map,
                keep_default_na=False,  # Don't convert empty strings to NaN
            )
        except (pd.errors.ParserError, UnicodeDecodeError, OSError) as e:
            logger.error("Failed to read CSV file '%s': %s", file_path, e)
            raise ValueError(f"Failed to read CSV file: {e}")

        # Validate required columns (Line 2 columns are optional for backward compat)
        if not all(col in df.columns for col in self.REQUIRED_COLUMNS):
            missing = set(self.REQUIRED_COLUMNS) - set(df.columns)
            logger.warning("CSV '%s' missing required columns: %s", file_path, missing)
            raise ValueError(
                f"CSV missing required columns: {missing}. "
                f"Expected: {self.REQUIRED_COLUMNS}"
            )

        ports = []
        for idx, row in df.iterrows():
            try:
                # Handle NaN values
                current_label = row["Current_Label"] if pd.notna(row["Current_Label"]) else ""
                new_label = row["New_Label"] if pd.notna(row["New_Label"]) else None
                current_label_line2 = row.get("Current_Label_Line2", "")
                if pd.isna(current_label_line2):
                    current_label_line2 = ""
                new_label_line2 = row.get("New_Label_Line2", None)
                if pd.isna(new_label_line2) or (isinstance(new_label_line2, str) and new_label_line2.strip() == ""):
                    new_label_line2 = None
                notes = row["Notes"] if pd.notna(row["Notes"]) else ""

                # Parse color fields (optional for backward compat)
                raw_cur_color = row.get("Current_Color", "")
                raw_new_color = row.get("New_Color", "")
                try:
                    current_color = int(raw_cur_color) if str(raw_cur_color).strip() else 4
                except (ValueError, TypeError):
                    logger.warning("Invalid Current_Color value '%s' in row %d, defaulting to 4", raw_cur_color, idx + 2)
                    current_color = 4
                try:
                    new_color_val = int(raw_new_color) if str(raw_new_color).strip() else None
                except (ValueError, TypeError):
                    logger.warning("Invalid New_Color value '%s' in row %d, ignoring", raw_new_color, idx + 2)
                    new_color_val = None

                port_data = PortData(
                    port=int(row["Port"]),
                    type=str(row["Type"]).strip(),
                    current_label=str(current_label).strip(),
                    new_label=str(new_label).strip() if new_label else None,
                    current_label_line2=str(current_label_line2).strip(),
                    new_label_line2=str(new_label_line2).strip() if new_label_line2 else None,
                    current_color=current_color,
                    new_color=new_color_val,
                    notes=str(notes).strip(),
                )
                ports.append(port_data)
            except (ValueError, TypeError) as e:
                logger.error("Invalid data in row %d of '%s': %s", idx + 2, file_path, e)
                raise ValueError(f"Invalid data in row {idx + 2}: {e}")

        logger.info("Read %d records from CSV '%s'", len(ports), file_path)
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
                "Current_Label_Line2": port_data.current_label_line2,
                "New_Label": port_data.new_label or "",
                "New_Label_Line2": port_data.new_label_line2 or "",
                "Current_Color": port_data.current_color,
                "New_Color": port_data.new_color if port_data.new_color is not None else "",
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
                lineterminator="\n",
            )
            logger.info("Wrote %d records to CSV '%s'", len(data.ports), file_path)
        except OSError as e:
            logger.error("Failed to write CSV file '%s': %s", file_path, e)
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
                "Current_Label_Line2": "",
                "New_Label": "",
                "New_Label_Line2": "",
                "Current_Color": 4,
                "New_Color": "",
                "Notes": "",
            })

        # Create 32 outputs
        for i in range(1, 33):
            rows.append({
                "Port": i,
                "Type": "OUTPUT",
                "Current_Label": "",
                "Current_Label_Line2": "",
                "New_Label": "",
                "New_Label_Line2": "",
                "Current_Color": 4,
                "New_Color": "",
                "Notes": "",
            })

        df = pd.DataFrame(rows, columns=self.COLUMNS)

        try:
            df.to_csv(
                file_path,
                index=False,
                encoding="utf-8",
                quoting=1,
                lineterminator="\n",
            )
            logger.info("Created template CSV '%s'", file_path)
        except OSError as e:
            logger.error("Failed to create template CSV '%s': %s", file_path, e)
            raise ValueError(f"Failed to create template CSV: {e}")
