# Python Components Setup Guide

This guide explains how to set up and use the Python components of the KUMO Router Label Manager.

## Current Status

The Python components provide an event-driven agent architecture for managing KUMO routers. The PowerShell tools are **production-ready** and fully functional. The Python components are provided as an architectural framework for advanced integration scenarios.

## Installation

### 1. Install Python (3.8 or higher)

Download from https://www.python.org/downloads/

### 2. Install Dependencies

```bash
# Install the package in development mode
pip install -e .

# Or install dependencies directly
pip install -r requirements.txt
```

### 3. Configure Environment

```bash
# Copy the example environment file
copy .env.example .env

# Edit .env with your KUMO router settings
notepad .env
```

## Usage

### Command-Line Interface

The Python CLI provides basic functionality:

```bash
# Download labels from router
python -m src.cli download output.xlsx --ip 192.168.1.100

# Upload labels to router
python -m src.cli upload input.xlsx --ip 192.168.1.100

# Test mode (dry run)
python -m src.cli upload input.xlsx --ip 192.168.1.100 --test
```

### Python API

Use the components programmatically:

```python
import asyncio
from src.config.settings import Settings
from src.coordinator.event_bus import EventBus
from src.agents.api_agent import APIAgent

async def main():
    # Create components
    settings = Settings()
    event_bus = EventBus()
    api_agent = APIAgent(
        router_ip="192.168.1.100",
        event_bus=event_bus
    )

    # Connect and download labels
    await api_agent.connect()
    labels = await api_agent.download_all_labels()

    print(f"Downloaded {len(labels)} labels")

    for label in labels:
        print(f"{label.port_type.value} {label.port_number}: {label.label_text}")

    await api_agent.disconnect()

if __name__ == "__main__":
    asyncio.run(main())
```

## Architecture

### Components

- **EventBus**: Async publish/subscribe system for inter-agent communication
- **APIAgent**: Handles REST and Telnet communication with KUMO routers
- **FileHandlerAgent**: Manages CSV, Excel, and JSON file operations
- **Models**: Data structures (Label, Router, Events)

### Event Flow

1. Agents subscribe to specific EventTypes via the EventBus
2. Events are published asynchronously and queued per subscriber
3. Each agent processes events in its own event loop

## Integration with PowerShell

The Python and PowerShell components are currently independent. To integrate:

1. **Option 1**: Call Python CLI from PowerShell
   ```powershell
   python -m src.cli download output.xlsx --ip $KumoIP
   ```

2. **Option 2**: Use Python as a library service
   - Create a REST API wrapper around Python components
   - Call from PowerShell via Invoke-RestMethod

3. **Option 3**: Direct subprocess calls
   ```powershell
   $result = & python -m src.cli download "labels.json" --ip $KumoIP
   ```

## Development

### Running Tests

```bash
# Install dev dependencies
pip install -e ".[dev]"

# Run tests (when available)
pytest tests/
```

### Code Quality

```bash
# Format code
black src/

# Type checking
mypy src/
```

## Known Issues

See the main README.md for a complete list of known issues, including:

- Event bus async/await issues (fixed)
- Thread safety in EventBus (fixed)
- Missing concrete agent implementations
- File handler integration needs work

## Comparison: PowerShell vs Python

| Feature | PowerShell | Python |
|---------|-----------|--------|
| GUI Application | ✅ Full-featured | ❌ Not implemented |
| CLI Tool | ✅ Production ready | ⚠️ Basic functionality |
| REST API Client | ✅ Working | ✅ Working |
| Telnet Client | ✅ Working | ✅ Working |
| Excel Support | ✅ Full support | ⚠️ Partial |
| Event System | ❌ N/A | ✅ Implemented |
| Status | **PRODUCTION READY** | **DEVELOPMENT** |

## Recommendation

**For production use, use the PowerShell tools.** They are fully tested and production-ready.

The Python components are provided for:
- Advanced integration scenarios
- Custom automation workflows
- Programmatic access to KUMO routers
- Building custom tools and services
