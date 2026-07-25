# Helix v5.0

**Professional AV Production Tool for Live Events**

Manage labels and crosspoints on broadcast video routers. Supports **AJA KUMO**, **Blackmagic Videohub**, and **Lightware MX2** hardware. The tools auto-detect which type of router you are connected to.

## Repository Structure

This repository contains **three independent implementations** of the Helix label manager. Each has different capabilities and maturity levels:

1. **PowerShell/WinForms** (repo root: `Helix-*.ps1`) — Production-ready GUI and CLI tools
2. **Electron/React** (in `electron/`) — Desktop app with modern UI (in development)
3. **Python CLI** (in `src/`) — Command-line tool with event-driven architecture (framework stage)

The **PowerShell tools are the only implementation currently shipped by the installer** (`installer.iss`). Users running `Helix-Label-Manager.ps1` are using the PowerShell/WinForms implementation.

### Implementation Status

| Feature | PowerShell | Electron | Python |
|---------|-----------|----------|--------|
| GUI Application | ✅ Full-featured | 🔄 In progress | ❌ Not implemented |
| CLI Tool | ✅ Production | 🔄 In progress | 🔄 Basic |
| AJA KUMO REST API | ✅ Full | ✅ Full | ✅ Full |
| KUMO Telnet fallback | ✅ Integrated | ❌ Orphaned* | ✅ Integrated |
| HTTPS-first fallback | ✅ Yes | ❌ HTTP only | ❌ HTTP only |
| Auto-backup CSV | ✅ Before upload | ❌ No | ❌ No |
| Videohub support | ✅ Full | ✅ Full | ✅ Full |
| Lightware MX2 support | ✅ Full | ✅ Full | ✅ Full |

*Electron has a Telnet client (`electron/src/main/protocols/kumo-telnet.ts`) but it is not imported or used by the router agent.

## Overview

Complete solution for managing video router labels across AJA KUMO, Videohub, and Lightware MX2 hardware. Designed for professional live event production environments like concerts, tours, and corporate events.

### Supported Hardware

**AJA KUMO**
- KUMO 1604 (16 inputs / 4 outputs)
- KUMO 1616 (16 inputs / 16 outputs)
- KUMO 3232 (32 inputs / 32 outputs)
- KUMO 6464 (64 inputs / 64 outputs)

**Blackmagic Videohub**
- Videohub Smart 12x12
- Videohub Smart 20x20
- Videohub 40x40
- Videohub Studio
- Universal Videohub 72 / 288
- Any Videohub model with TCP 9990 control port

**Lightware MX2**
- All MX2 models with LW3 protocol support (TCP 6107)

## Quick Start (PowerShell/WinForms)

### Launch the GUI

```powershell
.\Helix-Label-Manager.ps1
```

### Workflow
1. Enter your router IP and click **Connect** (all router types supported)
2. Click **Download from Router** to pull current labels
3. Edit labels directly in the grid (click the yellow "New Label" column)
4. Use **Find & Replace** or **Auto-Number** for bulk edits
5. Click **Upload Changes to Router** when ready
   - A backup CSV is automatically saved to Documents before upload

### PowerShell Command Line

```powershell
# Download current labels (router type auto-detected)
.\Helix-Excel-Updater.ps1 -DownloadLabels -KumoIP "192.168.1.100" -DownloadPath "labels.csv"

# Force a specific router type
.\Helix-Excel-Updater.ps1 -RouterType Videohub -DownloadLabels -KumoIP "192.168.1.101" -DownloadPath "vh_labels.csv"
.\Helix-Excel-Updater.ps1 -RouterType KUMO    -DownloadLabels -KumoIP "192.168.1.100" -DownloadPath "kumo_labels.csv"

# Upload from file (router type auto-detected)
.\Helix-Excel-Updater.ps1 -KumoIP "192.168.1.100" -ExcelFile "labels.csv"

# Dry run (test without uploading)
.\Helix-Excel-Updater.ps1 -KumoIP "192.168.1.100" -ExcelFile "labels.csv" -TestOnly
```

## Build & Run (Electron App)

The Electron app is currently in development. To build and run from source:

```bash
# From the electron/ directory
cd electron

# Install dependencies
npm ci

# Run in development mode
npm run dev

# Build for production
npm run build
```

**Requirements:**
- Node.js 20.x (specified in `.nvmrc`)
- npm 10.8.2 or higher

The built app will be in `electron/out/` after running `npm run build`.

## Build & Run (Python CLI)

The Python CLI is a framework for integration and programmatic access. It is not feature-complete.

```bash
# Install in development mode
pip install -e .

# Run CLI commands
helix download labels.csv --ip 192.168.1.100
helix upload labels.xlsx --ip 192.168.1.100 --test
helix status --ip 192.168.1.100
```

**Requirements:**
- Python 3.8+ (tested with 3.11 and 3.12)
- See `pyproject.toml` for dependencies

## Connection Protocols

### AJA KUMO

**PowerShell Implementation:**
1. **REST API** — per-port HTTP queries with HTTPS-first fallback to HTTP
2. **Telnet** — automatic fallback to port 23 if REST fails

**Electron & Python Implementations:**
1. **REST API** — per-port HTTP queries (HTTP only, no HTTPS fallback)
2. **Telnet** — Python has fallback chain; Electron's Telnet client exists but is not integrated

### Blackmagic Videohub — TCP 9990

On connect, Videohub sends a text-based state dump:

```
VIDEOHUB DEVICE:
Model name: Smart Videohub 12x12
Video inputs: 12
Video outputs: 12

INPUT LABELS:
0 Camera 1
1 Camera 2
...
```

To write labels, the tool sends a labeled block and waits for ACK. Videohub uses **0-based** port indexing internally; all implementations convert automatically to 1-based for user-facing tools.

### Lightware MX2 — LW3 Protocol (TCP 6107)

Uses the LW3 protocol to communicate with Lightware MX2 matrix routers.

### Auto-Detection Logic

When auto-detection is enabled (default):
1. Probe Lightware LW3 TCP 6107
2. Probe Videohub TCP 9990 (2-second timeout)
3. If no response, assume AJA KUMO REST API
4. Error if none responds — specify router type manually

## File Format

Works with CSV (recommended) or Excel (.xlsx). Columns:

| Column | Description |
|--------|-------------|
| Port | Port number (1-based for all router types) |
| Type | INPUT or OUTPUT |
| Current_Label | What is on the router now |
| New_Label | Your desired label (leave blank to skip) |
| Notes | Optional documentation |

Labels must be 50 characters or fewer for AJA KUMO. The tools warn if labels exceed this limit.

## Batch Operations (PowerShell Only)

### Find & Replace
Replace text across all labels at once. Options:
- Apply to New_Label column only, or copy Current → New first
- Filter by Inputs only, Outputs only, or All

### Auto-Number
Generate sequential labels:
- Set a prefix (e.g., "Camera ", "Monitor ", "Feed ")
- Set a start number
- Apply to Inputs, Outputs, Both, or Selected rows

### Multi-Router Batch

```powershell
# Batch across mixed router fleet — type auto-detected per IP
$routers = @("192.168.1.100", "192.168.1.101", "192.168.1.102")
foreach ($ip in $routers) {
    .\Helix-Excel-Updater.ps1 -KumoIP $ip -ExcelFile "TourLabels.csv"
}
```

## Requirements

### PowerShell (GUI and CLI tools)
- **Windows 10/11** with **PowerShell 5.1+**
- Network access to router:
  - AJA KUMO: port 80 (REST), port 23 (Telnet fallback)
  - Videohub: port 9990 (TCP)
  - Lightware MX2: port 6107 (TCP)
- Optional: ImportExcel PowerShell module for .xlsx support

```powershell
# Install Excel support (optional)
Install-Module ImportExcel -Scope CurrentUser -Force
```

### Electron (Desktop App)
- Node.js 20.x
- npm 10.8.2 or higher

### Python (CLI)
- Python 3.8 or higher
- Dependencies listed in `pyproject.toml`

## Troubleshooting

**Can't connect to AJA KUMO?**
- Verify the IP address is correct
- Check you are on the same network segment
- Try `ping <router-ip>` from PowerShell
- Ensure the KUMO web interface is accessible (port 80)
- For PowerShell: if REST fails, verify Telnet is enabled on the KUMO and port 23 is accessible

**Can't connect to Videohub?**
- Verify TCP port 9990 is not blocked by a firewall
- Confirm the Videohub is powered on and network-reachable
- Try `Test-NetConnection <router-ip> -Port 9990` from PowerShell
- Use `-RouterType Videohub` (PowerShell) to skip auto-detection

**Auto-detection picks the wrong type?**
- PowerShell: Use `-RouterType KUMO`, `-RouterType Videohub`, or `-RouterType Lightware` to force the correct type

**PowerShell won't run the script?**
```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**AJA KUMO labels not updating?**
- Some KUMO models have shorter character limits (8-16 chars)
- Check the firmware version and API compatibility
- For PowerShell: try enabling Telnet in the KUMO web interface as a fallback

**Videohub labels not updating?**
- Older Videohub firmware may not send an ACK — the tool proceeds anyway
- Ensure no other software is holding the TCP 9990 connection open

## Version History

### v5.0 (Current)
- Multi-router support: AJA KUMO, Blackmagic Videohub, and Lightware MX2
- PowerShell/WinForms: Crosspoint matrix view, inline editing, search, batch operations, auto-backup
- Electron: Modern React UI with grid-based label editing
- Python: Event-driven architecture for integration
- Auto-detection of router type
- Input validation and error logging

### v4.0
- Redesigned GUI with inline editing, tabs, search, and batch tools
- Find & Replace and Auto-Number for bulk label management
- Automatic backup before uploads
- Resizable window with improved dark theme
- Blackmagic Videohub TCP 9990 support
- Auto-detection of router type

### v2.0
- Download labels from router
- HTTPS-first with HTTP fallback (PowerShell only)
- REST + Telnet fallback chain (PowerShell only)
- PowerShell 5.1 compatibility fixes

### v1.0
- Basic label upload from Excel
- GUI and CLI interfaces
- 32x32 router support

---

**GitHub**: https://github.com/SRVR-JOE/helix  
**Created for professional live event production environments**
