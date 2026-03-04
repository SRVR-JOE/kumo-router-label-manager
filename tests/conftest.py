"""Shared pytest fixtures for the KUMO Router Label Manager test suite.

This module provides common fixtures used across multiple test modules,
including pre-built Label/FileData objects and a fresh EventBus instance.
"""

import asyncio
import pytest

from src.models.label import Label, PortType
from src.models.events import EventType
from src.coordinator.event_bus import EventBus
from src.agents.file_handler.schema import FileData, PortData


# ---------------------------------------------------------------------------
# pytest-asyncio configuration
# ---------------------------------------------------------------------------

# Tell pytest-asyncio to automatically apply the asyncio marker to every
# async test function in the suite, so individual tests don't each need the
# @pytest.mark.asyncio decorator.
pytest_plugins = ("pytest_asyncio",)


# ---------------------------------------------------------------------------
# Label fixtures
# ---------------------------------------------------------------------------


@pytest.fixture()
def sample_input_label() -> Label:
    """A valid INPUT label on port 1 with no pending change."""
    return Label(
        port_number=1,
        port_type=PortType.INPUT,
        current_label="CAM 1",
    )


@pytest.fixture()
def sample_output_label() -> Label:
    """A valid OUTPUT label on port 2 with a pending new label."""
    return Label(
        port_number=2,
        port_type=PortType.OUTPUT,
        current_label="MONITOR A",
        new_label="MONITOR B",
    )


@pytest.fixture()
def boundary_labels() -> list:
    """Labels at the minimum (port 1) and maximum (port 120) valid port numbers."""
    return [
        Label(port_number=1, port_type=PortType.INPUT, current_label="Min Port"),
        Label(port_number=120, port_type=PortType.OUTPUT, current_label="Max Port"),
    ]


# ---------------------------------------------------------------------------
# FileData / PortData fixtures
# ---------------------------------------------------------------------------


@pytest.fixture()
def sample_port_data_list() -> list:
    """A small list of PortData objects covering both port types."""
    return [
        PortData(port=1, type="INPUT", current_label="CAM 1", new_label=None, notes=""),
        PortData(port=2, type="INPUT", current_label="CAM 2", new_label="CAM 2 HD", notes="renamed"),
        PortData(port=1, type="OUTPUT", current_label="PGM", new_label=None, notes="program output"),
        PortData(port=2, type="OUTPUT", current_label="PVW", new_label=None, notes=""),
    ]


@pytest.fixture()
def sample_file_data(sample_port_data_list) -> FileData:
    """FileData wrapping the sample port list."""
    return FileData(ports=sample_port_data_list)


# ---------------------------------------------------------------------------
# EventBus fixture
# ---------------------------------------------------------------------------


@pytest.fixture()
def event_bus() -> EventBus:
    """A fresh EventBus instance for each test.

    The bus is NOT started (self._running is False) unless a test explicitly
    calls await event_bus.start().  This keeps individual tests self-contained.
    """
    return EventBus(max_queue_size=100)
