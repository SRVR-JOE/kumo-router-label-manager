"""
Excel file handler using openpyxl.

Produces edit-friendly spreadsheets: download from the router, fill in
the yellow "New_Label" column, then upload back to apply changes.
"""
from pathlib import Path
from typing import Optional
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side, Protection
from openpyxl.worksheet.datavalidation import DataValidation
from openpyxl.utils import get_column_letter

from .schema import FileData, PortData


# ── Shared style constants ──────────────────────────────────────────

_THIN_BORDER = Border(
    left=Side(style="thin", color="B0B0B0"),
    right=Side(style="thin", color="B0B0B0"),
    top=Side(style="thin", color="B0B0B0"),
    bottom=Side(style="thin", color="B0B0B0"),
)

# Header row
_HEADER_FONT = Font(bold=True, color="FFFFFF", size=11)
_HEADER_FILL = PatternFill(start_color="4472C4", end_color="4472C4", fill_type="solid")
_HEADER_ALIGN = Alignment(horizontal="center", vertical="center")

# Read-only data columns (Port, Type, Current_Label)
_READONLY_FILL = PatternFill(start_color="F2F2F2", end_color="F2F2F2", fill_type="solid")
_READONLY_FONT = Font(color="404040", size=11)

# Editable column (New_Label) – light yellow to draw the user's eye
_EDIT_FILL = PatternFill(start_color="FFFDE7", end_color="FFFDE7", fill_type="solid")
_EDIT_FONT = Font(color="000000", size=11)

# New_Label header gets a distinct accent so users know where to type
_EDIT_HEADER_FILL = PatternFill(start_color="FFC107", end_color="FFC107", fill_type="solid")
_EDIT_HEADER_FONT = Font(bold=True, color="000000", size=11)

# Notes column – white background, optional
_NOTES_FILL = PatternFill(start_color="FFFFFF", end_color="FFFFFF", fill_type="solid")
_NOTES_FONT = Font(color="808080", size=10, italic=True)

# Section separator between inputs and outputs
_SECTION_FILL = PatternFill(start_color="D9E2F3", end_color="D9E2F3", fill_type="solid")
_SECTION_FONT = Font(bold=True, color="2E5090", size=11)


class ExcelHandler:
    """Handler for Excel file operations."""

    WORKSHEET_NAME = "KUMO_Labels"
    HEADERS = ["Port", "Type", "Current_Label", "New_Label", "Notes"]

    def __init__(self):
        """Initialize the Excel handler."""
        pass

    # ── Reading ──────────────────────────────────────────────────────

    def read_excel(self, file_path: Path) -> FileData:
        """
        Read Excel file and parse KUMO_Labels worksheet.

        Skips any section-separator rows (merged cells, non-integer port
        values) so that a file exported by this tool round-trips cleanly.
        """
        if not file_path.exists():
            raise FileNotFoundError(f"Excel file not found: {file_path}")

        try:
            workbook = openpyxl.load_workbook(file_path, data_only=True)
        except Exception as e:
            raise ValueError(f"Failed to load Excel file: {e}")

        if self.WORKSHEET_NAME not in workbook.sheetnames:
            raise ValueError(
                f"Worksheet '{self.WORKSHEET_NAME}' not found. "
                f"Available sheets: {workbook.sheetnames}"
            )

        worksheet = workbook[self.WORKSHEET_NAME]
        ports = []

        for row_idx in range(2, worksheet.max_row + 1):
            row = worksheet[row_idx]

            # Skip completely empty rows
            if all(cell.value is None for cell in row):
                continue

            port_value = row[0].value

            # Skip section-separator rows (e.g. "--- OUTPUTS ---")
            if port_value is None:
                continue
            try:
                port_int = int(port_value)
            except (ValueError, TypeError):
                continue

            try:
                current_label = str(row[2].value).strip() if row[2].value else ""
                new_label_raw = row[3].value
                new_label = str(new_label_raw).strip() if new_label_raw is not None and str(new_label_raw).strip() != "" else None
                notes = str(row[4].value).strip() if len(row) > 4 and row[4].value else ""

                port_data = PortData(
                    port=port_int,
                    type=str(row[1].value).strip() if row[1].value else "INPUT",
                    current_label=current_label,
                    new_label=new_label,
                    notes=notes,
                )
                ports.append(port_data)
            except (ValueError, TypeError) as e:
                raise ValueError(f"Invalid data in row {row_idx}: {e}")

        workbook.close()
        return FileData(ports=ports)

    # ── Writing ──────────────────────────────────────────────────────

    def write_excel(
        self,
        file_path: Path,
        data: FileData,
        create_template: bool = False,
    ) -> None:
        """
        Write data to a nicely formatted, edit-friendly Excel file.

        The spreadsheet has two sheets:
          1. **KUMO_Labels** – the data sheet with a highlighted "New_Label"
             column where users enter new names.
          2. **Instructions** – a quick-start guide explaining the workflow.

        Visual cues:
          - Port / Type / Current_Label columns have a grey background
            (read-only – don't change these).
          - New_Label column has a yellow background (edit here).
          - A light-blue separator row divides Inputs from Outputs.
        """
        workbook = Workbook()
        worksheet = workbook.active
        worksheet.title = self.WORKSHEET_NAME

        # ── Headers ──
        for col_idx, header in enumerate(self.HEADERS, start=1):
            cell = worksheet.cell(row=1, column=col_idx, value=header)
            cell.border = _THIN_BORDER
            cell.alignment = _HEADER_ALIGN

            if header == "New_Label":
                cell.font = _EDIT_HEADER_FONT
                cell.fill = _EDIT_HEADER_FILL
            else:
                cell.font = _HEADER_FONT
                cell.fill = _HEADER_FILL

        # ── Data rows ──
        if create_template:
            row_cursor = 2
            # Inputs
            for i in range(1, 33):
                self._write_row(worksheet, row_cursor, i, "INPUT")
                row_cursor += 1
            # Separator
            self._write_section_separator(worksheet, row_cursor, "OUTPUTS (Destinations)")
            row_cursor += 1
            # Outputs
            for i in range(1, 33):
                self._write_row(worksheet, row_cursor, i, "OUTPUT")
                row_cursor += 1
        else:
            inputs = [p for p in data.ports if p.type == "INPUT"]
            outputs = [p for p in data.ports if p.type == "OUTPUT"]
            inputs.sort(key=lambda p: p.port)
            outputs.sort(key=lambda p: p.port)

            row_cursor = 2
            for port_data in inputs:
                self._write_row(
                    worksheet, row_cursor,
                    port_data.port, port_data.type,
                    port_data.current_label,
                    port_data.new_label or "",
                    port_data.notes,
                )
                row_cursor += 1

            if outputs:
                self._write_section_separator(worksheet, row_cursor, "OUTPUTS (Destinations)")
                row_cursor += 1

                for port_data in outputs:
                    self._write_row(
                        worksheet, row_cursor,
                        port_data.port, port_data.type,
                        port_data.current_label,
                        port_data.new_label or "",
                        port_data.notes,
                    )
                    row_cursor += 1

        # ── Data validation for Type column ──
        type_validation = DataValidation(
            type="list",
            formula1='"INPUT,OUTPUT"',
            allow_blank=False,
            showDropDown=True,
        )
        type_validation.error = "Please select INPUT or OUTPUT"
        type_validation.errorTitle = "Invalid Type"
        max_row = worksheet.max_row
        type_validation.add(f"B2:B{max_row}")
        worksheet.add_data_validation(type_validation)

        # ── Column widths ──
        worksheet.column_dimensions["A"].width = 8    # Port
        worksheet.column_dimensions["B"].width = 10   # Type
        worksheet.column_dimensions["C"].width = 30   # Current_Label
        worksheet.column_dimensions["D"].width = 30   # New_Label
        worksheet.column_dimensions["E"].width = 25   # Notes

        # Freeze header row
        worksheet.freeze_panes = "A2"

        # ── Sheet protection: lock everything except New_Label & Notes ──
        # Users can still type in D and E columns; A-C are locked.
        worksheet.protection.sheet = True
        worksheet.protection.password = ""  # no password – just a nudge
        worksheet.protection.enable()

        # ── Instructions sheet ──
        self._write_instructions_sheet(workbook)

        # Save
        try:
            workbook.save(file_path)
        except Exception as e:
            raise ValueError(f"Failed to save Excel file: {e}")
        finally:
            workbook.close()

    # ── Private helpers ──────────────────────────────────────────────

    def _write_row(
        self,
        worksheet,
        row_idx: int,
        port: int,
        port_type: str,
        current_label: str = "",
        new_label: str = "",
        notes: str = "",
    ) -> None:
        """Write a single data row with visual styling."""
        # Col A – Port (read-only)
        cell_a = worksheet.cell(row=row_idx, column=1, value=port)
        cell_a.font = _READONLY_FONT
        cell_a.fill = _READONLY_FILL
        cell_a.alignment = Alignment(horizontal="center")
        cell_a.border = _THIN_BORDER
        cell_a.protection = Protection(locked=True)

        # Col B – Type (read-only)
        cell_b = worksheet.cell(row=row_idx, column=2, value=port_type)
        cell_b.font = _READONLY_FONT
        cell_b.fill = _READONLY_FILL
        cell_b.alignment = Alignment(horizontal="center")
        cell_b.border = _THIN_BORDER
        cell_b.protection = Protection(locked=True)

        # Col C – Current_Label (read-only)
        cell_c = worksheet.cell(row=row_idx, column=3, value=current_label)
        cell_c.font = _READONLY_FONT
        cell_c.fill = _READONLY_FILL
        cell_c.border = _THIN_BORDER
        cell_c.protection = Protection(locked=True)

        # Col D – New_Label (EDITABLE)
        cell_d = worksheet.cell(row=row_idx, column=4, value=new_label)
        cell_d.font = _EDIT_FONT
        cell_d.fill = _EDIT_FILL
        cell_d.border = _THIN_BORDER
        cell_d.protection = Protection(locked=False)

        # Col E – Notes (editable)
        cell_e = worksheet.cell(row=row_idx, column=5, value=notes)
        cell_e.font = _NOTES_FONT
        cell_e.fill = _NOTES_FILL
        cell_e.border = _THIN_BORDER
        cell_e.protection = Protection(locked=False)

    def _write_section_separator(self, worksheet, row_idx: int, title: str) -> None:
        """Write a visual separator row between INPUTS and OUTPUTS."""
        for col in range(1, 6):
            cell = worksheet.cell(row=row_idx, column=col)
            cell.fill = _SECTION_FILL
            cell.border = _THIN_BORDER
            cell.protection = Protection(locked=True)

        label_cell = worksheet.cell(row=row_idx, column=1, value=title)
        label_cell.font = _SECTION_FONT
        label_cell.fill = _SECTION_FILL
        label_cell.alignment = Alignment(horizontal="left")

        # Merge across all columns for the separator
        worksheet.merge_cells(
            start_row=row_idx, start_column=1,
            end_row=row_idx, end_column=5,
        )

    def _write_instructions_sheet(self, workbook: Workbook) -> None:
        """Add an Instructions sheet explaining the round-trip workflow."""
        ws = workbook.create_sheet("Instructions", 0)
        # Move data sheet to first position after writing instructions
        workbook.move_sheet("Instructions", offset=1)

        title_font = Font(bold=True, size=14, color="2E5090")
        heading_font = Font(bold=True, size=12, color="333333")
        body_font = Font(size=11, color="444444")
        step_font = Font(size=11, color="000000")
        highlight_font = Font(bold=True, size=11, color="BF8F00")

        ws.column_dimensions["A"].width = 5
        ws.column_dimensions["B"].width = 80

        rows = [
            (title_font, "KUMO Router Label Manager"),
            (body_font, ""),
            (heading_font, "How to rename your router labels:"),
            (body_font, ""),
            (step_font, "1.  Go to the KUMO_Labels sheet (first tab)."),
            (step_font, '2.  Find the yellow "New_Label" column (column D).'),
            (step_font, "3.  Type the new name you want for each port."),
            (step_font, "4.  Leave New_Label blank for ports you don't want to change."),
            (step_font, "5.  Save this file (Ctrl+S / Cmd+S)."),
            (step_font, "6.  Run the upload command:"),
            (body_font, ""),
            (highlight_font, '     kumo-cli upload "this_file.xlsx" --ip <router-ip>'),
            (body_font, ""),
            (step_font, "Tip: use --test first to preview changes without writing to the router:"),
            (body_font, ""),
            (highlight_font, '     kumo-cli upload "this_file.xlsx" --ip <router-ip> --test'),
            (body_font, ""),
            (heading_font, "Column Guide:"),
            (body_font, ""),
            (body_font, "  Port            Port number on the router (do not edit)"),
            (body_font, "  Type            INPUT or OUTPUT (do not edit)"),
            (body_font, "  Current_Label   Name currently on the router (do not edit)"),
            (highlight_font, "  New_Label       YOUR NEW NAME  <-- type here"),
            (body_font, "  Notes           Optional notes for your reference"),
            (body_font, ""),
            (heading_font, "Important:"),
            (body_font, ""),
            (body_font, "  - Max label length: 50 characters."),
            (body_font, "  - Only rows where New_Label is filled in (and different"),
            (body_font, "    from Current_Label) will be changed on the router."),
            (body_font, "  - Grey columns are locked to prevent accidental edits."),
        ]

        for idx, (font, text) in enumerate(rows, start=1):
            cell = ws.cell(row=idx, column=2, value=text)
            cell.font = font
