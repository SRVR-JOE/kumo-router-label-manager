"""Tests for CSV, Excel, and JSON file handler round-trips.

All file I/O is performed inside pytest's `tmp_path` fixture so tests are
completely self-contained and leave no artifacts on the filesystem.

Coverage targets:
- CSVHandler: write then read roundtrip, special characters, template creation
- ExcelHandler: write then read roundtrip, template creation, missing worksheet
- JSONHandler: write then read roundtrip (flat and nested), template creation
- PortData / FileData schema validation (via schema.py)
- Edge cases: empty port lists, None new_label, unicode labels
"""

from pathlib import Path

import pytest

from src.agents.file_handler.csv_handler import CSVHandler
from src.agents.file_handler.excel_handler import ExcelHandler
from src.agents.file_handler.json_handler import JSONHandler
from src.agents.file_handler.schema import FileData, PortData


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------


def make_port_data(**kwargs) -> PortData:
    """Create a PortData with sensible defaults, overridable via kwargs."""
    defaults = {
        "port": 1,
        "type": "INPUT",
        "current_label": "CAM 1",
        "new_label": None,
        "notes": "",
    }
    defaults.update(kwargs)
    return PortData(**defaults)


def make_file_data(ports: list) -> FileData:
    return FileData(ports=ports)


# ---------------------------------------------------------------------------
# PortData / FileData schema (schema.py)
# ---------------------------------------------------------------------------


class TestPortDataSchema:
    """PortData Pydantic model validation — these run without touching the disk."""

    def test_valid_input_port(self):
        p = PortData(port=1, type="INPUT", current_label="CAM 1")
        assert p.port == 1
        assert p.type == "INPUT"

    def test_valid_output_port(self):
        p = PortData(port=1, type="OUTPUT", current_label="MON A")
        assert p.type == "OUTPUT"

    def test_port_type_normalised_to_uppercase(self):
        p = PortData(port=1, type="input")
        assert p.type == "INPUT"

    def test_port_0_rejected(self):
        with pytest.raises(Exception):  # pydantic ValidationError
            PortData(port=0, type="INPUT")

    def test_port_121_rejected(self):
        with pytest.raises(Exception):
            PortData(port=121, type="INPUT")

    def test_invalid_type_rejected(self):
        with pytest.raises(Exception):
            PortData(port=1, type="INOUT")

    def test_label_whitespace_is_stripped(self):
        p = PortData(port=1, type="INPUT", current_label="  CAM 1  ")
        assert p.current_label == "CAM 1"

    def test_none_new_label_allowed(self):
        p = PortData(port=1, type="INPUT", new_label=None)
        assert p.new_label is None


class TestFileDataSchema:
    """FileData Pydantic model — duplicate detection and helpers."""

    def test_get_inputs_filters_correctly(self):
        fd = FileData(ports=[
            PortData(port=1, type="INPUT"),
            PortData(port=1, type="OUTPUT"),
            PortData(port=2, type="INPUT"),
        ])
        inputs = fd.get_inputs()
        assert all(p.type == "INPUT" for p in inputs)
        assert len(inputs) == 2

    def test_get_outputs_filters_correctly(self):
        fd = FileData(ports=[
            PortData(port=1, type="INPUT"),
            PortData(port=1, type="OUTPUT"),
        ])
        outputs = fd.get_outputs()
        assert len(outputs) == 1
        assert outputs[0].type == "OUTPUT"

    def test_get_port_by_number_and_type(self):
        fd = FileData(ports=[
            PortData(port=5, type="INPUT", current_label="SRC 5"),
        ])
        found = fd.get_port(5, "INPUT")
        assert found is not None
        assert found.current_label == "SRC 5"

    def test_get_port_returns_none_for_missing_port(self):
        fd = FileData(ports=[PortData(port=1, type="INPUT")])
        assert fd.get_port(99) is None

    def test_duplicate_port_type_combo_rejected(self):
        """Same (port, type) tuple twice must raise a validation error."""
        with pytest.raises(Exception):
            FileData(ports=[
                PortData(port=1, type="INPUT"),
                PortData(port=1, type="INPUT"),
            ])

    def test_same_port_number_different_types_allowed(self):
        """Input 1 and Output 1 are distinct and must be accepted."""
        fd = FileData(ports=[
            PortData(port=1, type="INPUT"),
            PortData(port=1, type="OUTPUT"),
        ])
        assert len(fd.ports) == 2

    def test_empty_ports_list_allowed(self):
        fd = FileData(ports=[])
        assert len(fd.ports) == 0


# ---------------------------------------------------------------------------
# CSVHandler
# ---------------------------------------------------------------------------


class TestCSVHandlerRoundtrip:
    def test_basic_roundtrip(self, tmp_path: Path):
        csv_path = tmp_path / "labels.csv"
        handler = CSVHandler()

        original = FileData(ports=[
            PortData(port=1, type="INPUT", current_label="CAM 1", notes="main"),
            PortData(port=2, type="INPUT", current_label="CAM 2", new_label="CAM 2 HD"),
            PortData(port=1, type="OUTPUT", current_label="PGM"),
        ])
        handler.write_csv(csv_path, original)
        restored = handler.read_csv(csv_path)

        assert len(restored.ports) == len(original.ports)

    def test_port_numbers_preserved(self, tmp_path: Path):
        csv_path = tmp_path / "labels.csv"
        handler = CSVHandler()

        original = FileData(ports=[
            PortData(port=10, type="INPUT", current_label="SRC 10"),
        ])
        handler.write_csv(csv_path, original)
        restored = handler.read_csv(csv_path)

        assert restored.ports[0].port == 10

    def test_port_type_preserved(self, tmp_path: Path):
        csv_path = tmp_path / "labels.csv"
        handler = CSVHandler()

        original = FileData(ports=[
            PortData(port=1, type="OUTPUT", current_label="MON"),
        ])
        handler.write_csv(csv_path, original)
        restored = handler.read_csv(csv_path)

        assert restored.ports[0].type == "OUTPUT"

    def test_current_label_preserved(self, tmp_path: Path):
        csv_path = tmp_path / "labels.csv"
        handler = CSVHandler()

        original = FileData(ports=[
            PortData(port=1, type="INPUT", current_label="Studio Camera A"),
        ])
        handler.write_csv(csv_path, original)
        restored = handler.read_csv(csv_path)

        assert restored.ports[0].current_label == "Studio Camera A"

    def test_new_label_preserved_when_set(self, tmp_path: Path):
        csv_path = tmp_path / "labels.csv"
        handler = CSVHandler()

        original = FileData(ports=[
            PortData(port=1, type="INPUT", current_label="OLD", new_label="NEW"),
        ])
        handler.write_csv(csv_path, original)
        restored = handler.read_csv(csv_path)

        assert restored.ports[0].new_label == "NEW"

    def test_notes_preserved(self, tmp_path: Path):
        csv_path = tmp_path / "labels.csv"
        handler = CSVHandler()

        original = FileData(ports=[
            PortData(port=1, type="INPUT", notes="rack unit 3"),
        ])
        handler.write_csv(csv_path, original)
        restored = handler.read_csv(csv_path)

        assert restored.ports[0].notes == "rack unit 3"

    def test_special_characters_in_label(self, tmp_path: Path):
        """Commas, quotes, and unicode must survive a CSV roundtrip."""
        csv_path = tmp_path / "special.csv"
        handler = CSVHandler()

        label_text = 'CAM, "A" — Studio'
        original = FileData(ports=[
            PortData(port=1, type="INPUT", current_label=label_text),
        ])
        handler.write_csv(csv_path, original)
        restored = handler.read_csv(csv_path)

        assert restored.ports[0].current_label == label_text

    def test_read_nonexistent_file_raises_file_not_found(self, tmp_path: Path):
        handler = CSVHandler()
        with pytest.raises(FileNotFoundError):
            handler.read_csv(tmp_path / "does_not_exist.csv")


class TestCSVHandlerTemplate:
    def test_template_creates_file(self, tmp_path: Path):
        csv_path = tmp_path / "template.csv"
        handler = CSVHandler()
        handler.create_template_csv(csv_path)
        assert csv_path.exists()

    def test_template_has_64_rows(self, tmp_path: Path):
        csv_path = tmp_path / "template.csv"
        handler = CSVHandler()
        handler.create_template_csv(csv_path)
        restored = handler.read_csv(csv_path)
        assert len(restored.ports) == 64

    def test_template_has_32_inputs(self, tmp_path: Path):
        csv_path = tmp_path / "template.csv"
        handler = CSVHandler()
        handler.create_template_csv(csv_path)
        restored = handler.read_csv(csv_path)
        assert len(restored.get_inputs()) == 32

    def test_template_has_32_outputs(self, tmp_path: Path):
        csv_path = tmp_path / "template.csv"
        handler = CSVHandler()
        handler.create_template_csv(csv_path)
        restored = handler.read_csv(csv_path)
        assert len(restored.get_outputs()) == 32


# ---------------------------------------------------------------------------
# ExcelHandler
# ---------------------------------------------------------------------------


class TestExcelHandlerRoundtrip:
    def test_basic_roundtrip(self, tmp_path: Path):
        xlsx_path = tmp_path / "labels.xlsx"
        handler = ExcelHandler()

        original = FileData(ports=[
            PortData(port=1, type="INPUT", current_label="CAM 1"),
            PortData(port=2, type="INPUT", current_label="CAM 2"),
            PortData(port=1, type="OUTPUT", current_label="PGM"),
        ])
        handler.write_excel(xlsx_path, original)
        restored = handler.read_excel(xlsx_path)

        assert len(restored.ports) == len(original.ports)

    def test_port_number_preserved(self, tmp_path: Path):
        xlsx_path = tmp_path / "labels.xlsx"
        handler = ExcelHandler()

        original = FileData(ports=[
            PortData(port=5, type="INPUT", current_label="SRC 5"),
        ])
        handler.write_excel(xlsx_path, original)
        restored = handler.read_excel(xlsx_path)

        assert restored.ports[0].port == 5

    def test_port_type_preserved(self, tmp_path: Path):
        xlsx_path = tmp_path / "labels.xlsx"
        handler = ExcelHandler()

        original = FileData(ports=[
            PortData(port=1, type="OUTPUT", current_label="OUT"),
        ])
        handler.write_excel(xlsx_path, original)
        restored = handler.read_excel(xlsx_path)

        assert restored.ports[0].type == "OUTPUT"

    def test_current_label_preserved(self, tmp_path: Path):
        xlsx_path = tmp_path / "labels.xlsx"
        handler = ExcelHandler()

        original = FileData(ports=[
            PortData(port=1, type="INPUT", current_label="Robotic CAM"),
        ])
        handler.write_excel(xlsx_path, original)
        restored = handler.read_excel(xlsx_path)

        assert restored.ports[0].current_label == "Robotic CAM"

    def test_special_characters_in_label(self, tmp_path: Path):
        """Unicode and punctuation must survive an Excel roundtrip."""
        xlsx_path = tmp_path / "special.xlsx"
        handler = ExcelHandler()

        label_text = "CAM — Ünïcödé"
        original = FileData(ports=[
            PortData(port=1, type="INPUT", current_label=label_text),
        ])
        handler.write_excel(xlsx_path, original)
        restored = handler.read_excel(xlsx_path)

        assert restored.ports[0].current_label == label_text

    def test_read_nonexistent_file_raises_file_not_found(self, tmp_path: Path):
        handler = ExcelHandler()
        with pytest.raises(FileNotFoundError):
            handler.read_excel(tmp_path / "missing.xlsx")

    def test_read_missing_worksheet_raises_value_error(self, tmp_path: Path):
        """A workbook without the expected worksheet name must raise ValueError."""
        import openpyxl
        xlsx_path = tmp_path / "wrong_sheet.xlsx"
        wb = openpyxl.Workbook()
        wb.active.title = "WrongName"
        wb.save(xlsx_path)
        wb.close()

        handler = ExcelHandler()
        with pytest.raises(ValueError, match="KUMO_Labels"):
            handler.read_excel(xlsx_path)


class TestExcelHandlerTemplate:
    def test_template_creates_file(self, tmp_path: Path):
        xlsx_path = tmp_path / "template.xlsx"
        handler = ExcelHandler()
        empty_data = FileData(ports=[])
        handler.write_excel(xlsx_path, empty_data, create_template=True)
        assert xlsx_path.exists()

    def test_template_has_64_rows(self, tmp_path: Path):
        xlsx_path = tmp_path / "template.xlsx"
        handler = ExcelHandler()
        empty_data = FileData(ports=[])
        handler.write_excel(xlsx_path, empty_data, create_template=True)
        restored = handler.read_excel(xlsx_path)
        assert len(restored.ports) == 64

    def test_template_has_32_inputs(self, tmp_path: Path):
        xlsx_path = tmp_path / "template.xlsx"
        handler = ExcelHandler()
        empty_data = FileData(ports=[])
        handler.write_excel(xlsx_path, empty_data, create_template=True)
        restored = handler.read_excel(xlsx_path)
        assert len(restored.get_inputs()) == 32

    def test_template_has_32_outputs(self, tmp_path: Path):
        xlsx_path = tmp_path / "template.xlsx"
        handler = ExcelHandler()
        empty_data = FileData(ports=[])
        handler.write_excel(xlsx_path, empty_data, create_template=True)
        restored = handler.read_excel(xlsx_path)
        assert len(restored.get_outputs()) == 32


# ---------------------------------------------------------------------------
# JSONHandler
# ---------------------------------------------------------------------------


class TestJSONHandlerNestedRoundtrip:
    """nested=True (default) splits inputs and outputs into separate keys."""

    def test_basic_roundtrip_nested(self, tmp_path: Path):
        json_path = tmp_path / "labels.json"
        handler = JSONHandler()

        original = FileData(ports=[
            PortData(port=1, type="INPUT", current_label="CAM 1"),
            PortData(port=1, type="OUTPUT", current_label="PGM"),
        ])
        handler.write_json(json_path, original, nested=True)
        restored = handler.read_json(json_path)

        assert len(restored.ports) == len(original.ports)

    def test_nested_file_contains_inputs_and_outputs_keys(self, tmp_path: Path):
        import json as _json
        json_path = tmp_path / "labels.json"
        handler = JSONHandler()

        original = FileData(ports=[PortData(port=1, type="INPUT")])
        handler.write_json(json_path, original, nested=True)

        with open(json_path) as f:
            raw = _json.load(f)

        assert "inputs" in raw
        assert "outputs" in raw

    def test_current_label_preserved_nested(self, tmp_path: Path):
        json_path = tmp_path / "labels.json"
        handler = JSONHandler()

        original = FileData(ports=[
            PortData(port=1, type="INPUT", current_label="Studio A"),
        ])
        handler.write_json(json_path, original, nested=True)
        restored = handler.read_json(json_path)

        assert restored.ports[0].current_label == "Studio A"

    def test_port_number_preserved_nested(self, tmp_path: Path):
        json_path = tmp_path / "labels.json"
        handler = JSONHandler()

        original = FileData(ports=[PortData(port=12, type="INPUT")])
        handler.write_json(json_path, original, nested=True)
        restored = handler.read_json(json_path)

        assert restored.ports[0].port == 12


class TestJSONHandlerFlatRoundtrip:
    """nested=False uses a single 'ports' array."""

    def test_basic_roundtrip_flat(self, tmp_path: Path):
        json_path = tmp_path / "labels_flat.json"
        handler = JSONHandler()

        original = FileData(ports=[
            PortData(port=1, type="INPUT", current_label="CAM 1"),
            PortData(port=2, type="INPUT", current_label="CAM 2"),
        ])
        handler.write_json(json_path, original, nested=False)
        restored = handler.read_json(json_path)

        assert len(restored.ports) == 2

    def test_flat_file_contains_ports_key(self, tmp_path: Path):
        import json as _json
        json_path = tmp_path / "labels_flat.json"
        handler = JSONHandler()

        original = FileData(ports=[PortData(port=1, type="INPUT")])
        handler.write_json(json_path, original, nested=False)

        with open(json_path) as f:
            raw = _json.load(f)

        assert "ports" in raw
        assert "inputs" not in raw

    def test_current_label_preserved_flat(self, tmp_path: Path):
        json_path = tmp_path / "labels_flat.json"
        handler = JSONHandler()

        original = FileData(ports=[
            PortData(port=3, type="OUTPUT", current_label="Preview"),
        ])
        handler.write_json(json_path, original, nested=False)
        restored = handler.read_json(json_path)

        assert restored.ports[0].current_label == "Preview"


class TestJSONHandlerSpecialCases:
    def test_unicode_label_preserved(self, tmp_path: Path):
        json_path = tmp_path / "unicode.json"
        handler = JSONHandler()

        label_text = "カメラ 1 — Studio"
        original = FileData(ports=[
            PortData(port=1, type="INPUT", current_label=label_text),
        ])
        handler.write_json(json_path, original)
        restored = handler.read_json(json_path)

        assert restored.ports[0].current_label == label_text

    def test_read_nonexistent_file_raises_file_not_found(self, tmp_path: Path):
        handler = JSONHandler()
        with pytest.raises(FileNotFoundError):
            handler.read_json(tmp_path / "missing.json")

    def test_read_invalid_json_raises_value_error(self, tmp_path: Path):
        bad_json = tmp_path / "bad.json"
        bad_json.write_text("this is not json", encoding="utf-8")
        handler = JSONHandler()
        with pytest.raises(ValueError, match="JSON"):
            handler.read_json(bad_json)

    def test_read_json_without_ports_or_inputs_keys_raises_value_error(
        self, tmp_path: Path
    ):
        import json as _json
        json_path = tmp_path / "no_ports.json"
        json_path.write_text(_json.dumps({"unknown_key": []}), encoding="utf-8")
        handler = JSONHandler()
        with pytest.raises(ValueError):
            handler.read_json(json_path)

    def test_none_new_label_written_and_read_back_as_none(self, tmp_path: Path):
        json_path = tmp_path / "labels.json"
        handler = JSONHandler()

        original = FileData(ports=[
            PortData(port=1, type="INPUT", current_label="CAM", new_label=None),
        ])
        handler.write_json(json_path, original)
        restored = handler.read_json(json_path)

        assert restored.ports[0].new_label is None


class TestJSONHandlerTemplate:
    def test_template_creates_file(self, tmp_path: Path):
        json_path = tmp_path / "template.json"
        handler = JSONHandler()
        handler.create_template_json(json_path)
        assert json_path.exists()

    def test_template_has_64_ports(self, tmp_path: Path):
        json_path = tmp_path / "template.json"
        handler = JSONHandler()
        handler.create_template_json(json_path)
        restored = handler.read_json(json_path)
        assert len(restored.ports) == 64

    def test_template_has_32_inputs(self, tmp_path: Path):
        json_path = tmp_path / "template.json"
        handler = JSONHandler()
        handler.create_template_json(json_path)
        restored = handler.read_json(json_path)
        assert len(restored.get_inputs()) == 32

    def test_template_has_32_outputs(self, tmp_path: Path):
        json_path = tmp_path / "template.json"
        handler = JSONHandler()
        handler.create_template_json(json_path)
        restored = handler.read_json(json_path)
        assert len(restored.get_outputs()) == 32

    def test_flat_template_uses_ports_key(self, tmp_path: Path):
        import json as _json
        json_path = tmp_path / "flat_template.json"
        handler = JSONHandler()
        handler.create_template_json(json_path, nested=False)

        with open(json_path) as f:
            raw = _json.load(f)

        assert "ports" in raw
