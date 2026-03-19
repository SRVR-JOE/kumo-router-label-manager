# Helix v5.0

**Professional AV Production Tool for Live Events**

Supports **AJA KUMO**, **Blackmagic Videohub**, and **Lightware MX2** routers. The command-line tool auto-detects which type of router you are connected to, so the same workflow applies to all.

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

### What's New in v5.0

- **Multi-router support** - AJA KUMO, Blackmagic Videohub, and Lightware MX2
- **Crosspoint matrix view** - Visual matrix display for routing connections
- **Inline editing** - Click any New Label cell to type directly in the grid
- **Filter tabs** - Switch between All / Inputs / Outputs / Changed views
- **Search** - Find labels by name or port number instantly
- **Find & Replace** - Batch rename with scope control (inputs only, outputs only, copy current labels)
- **Auto-Number** - Generate sequential labels like "Camera 1", "Camera 2"... with custom prefix and start number
- **Auto backup** - Labels are backed up to a CSV before every upload
- **Character count** - Live validation showing chars used vs limit
- **CSV-first** - No Excel dependency required; CSV works out of the box
- **Resizable window** - Scale the UI to fit your monitor
- **Improved progress** - Per-port status during download and upload
- **Security hardening** - HTTPS-first with HTTP fallback, input validation

## Quick Start

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

### Command Line

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

### Python CLI

```bash
pip install -e .
helix download labels.csv --ip 192.168.1.100
helix upload labels.xlsx --ip 192.168.1.100 --test
helix status --ip 192.168.1.100
```

## Connection Protocols

### AJA KUMO — REST API + Telnet
1. **REST API** (per-port GET) — queries each port individually via HTTP
2. **Telnet port 23** — last resort, sends `LABEL INPUT n ?` / `LABEL OUTPUT n ?` commands

All HTTP requests try HTTPS first, then fall back to HTTP automatically.

### Blackmagic Videohub — TCP 9990
On connect, the Videohub sends a full text-based state dump over TCP port 9990:

```
VIDEOHUB DEVICE:
Model name: Smart Videohub 12x12
Video inputs: 12
Video outputs: 12

INPUT LABELS:
0 Camera 1
1 Camera 2
...

OUTPUT LABELS:
0 Program
1 Preview
...
```

To write labels, the script sends a labeled block and waits for an ACK:

```
INPUT LABELS:
0 New Camera Name

```

Videohub uses **0-based** port indexing. The script converts automatically — your CSV/Excel files always use **1-based** port numbers regardless of router type.

### Lightware MX2 — LW3 Protocol (TCP 6107)
Uses the LW3 protocol to communicate with Lightware MX2 matrix routers.

### Auto-Detection Logic
When `-RouterType Auto` (the default) is used:
1. Probe Lightware LW3 TCP 6107
2. Probe Videohub TCP 9990 (2-second timeout)
3. If no response, probe AJA KUMO REST API
4. Error if none responds — use `-RouterType` to specify manually

## File Format

Works with CSV (recommended) or Excel (.xlsx). Columns:

| Column | Description |
|--------|-------------|
| Port | Port number (1-based for all router types) |
| Type | INPUT or OUTPUT |
| Current_Label | What is on the router now |
| New_Label | Your desired label (leave blank to skip) |
| Notes | Optional documentation |

Labels must be 50 characters or fewer for AJA KUMO. The app warns you if any labels exceed this limit.

## Batch Operations

### Find & Replace
Replace text across all labels at once. Options:
- Apply to New_Label column only, or copy Current -> New first
- Filter by Inputs only, Outputs only, or All

### Auto-Number
Generate sequential labels:
- Set a prefix (e.g., "Camera ", "Monitor ", "Feed ")
- Set a start number
- Apply to Inputs, Outputs, Both, or Selected rows

### Multi-Router Batch (Mixed Fleet)

```powershell
# Batch across mixed router fleet — type auto-detected per IP
$routers = @("192.168.1.100", "192.168.1.101", "192.168.1.102")
foreach ($ip in $routers) {
    .\Helix-Excel-Updater.ps1 -KumoIP $ip -ExcelFile "TourLabels.csv"
}
```

## Requirements

- **Windows 10/11** with **PowerShell 5.1+**
- Network access to router:
  - AJA KUMO: port 80 (HTTP REST), port 23 (Telnet fallback)
  - Videohub: port 9990 (TCP)
  - Lightware MX2: port 6107 (TCP)
- Optional: ImportExcel PowerShell module for .xlsx support

```powershell
# Install Excel support (optional)
Install-Module ImportExcel -Scope CurrentUser -Force
```

## Troubleshooting

**Can't connect to AJA KUMO?**
- Verify the IP address is correct
- Check you are on the same network segment
- Try `ping <router-ip>` from PowerShell
- Ensure the KUMO web interface is accessible (port 80)

**Can't connect to Videohub?**
- Verify TCP port 9990 is not blocked by a firewall
- Confirm the Videohub is powered on and network-reachable
- Try `Test-NetConnection <router-ip> -Port 9990` from PowerShell
- Use `-RouterType Videohub` to skip auto-detection

**Auto-detection picks the wrong type?**
- Use `-RouterType KUMO` or `-RouterType Videohub` or `-RouterType Lightware` to force the correct type

**PowerShell won't run the script?**
```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**AJA KUMO labels not updating?**
- Some KUMO models have shorter character limits (8-16 chars)
- Check the firmware version and API compatibility
- Try enabling Telnet in the KUMO web interface

**Videohub labels not updating?**
- Older Videohub firmware may not send an ACK — the script proceeds anyway
- Ensure no other software is holding the TCP 9990 connection open

## Version History

### v5.0 (Current)
- Multi-router support: AJA KUMO, Blackmagic Videohub, and Lightware MX2
- Crosspoint matrix view for routing connections
- Security hardening (HTTPS-first with HTTP fallback, input validation)
- Comprehensive error logging to error-log.txt for remote debugging
- Redesigned GUI with inline editing, tabs, search, and batch tools
- Find & Replace and Auto-Number for bulk label management
- Automatic backup before uploads
- Live character count validation
- CSV-first approach (no Excel dependency)
- Resizable window with improved dark theme
- Auto-detection of router type
- `-RouterType` parameter for manual override

### v4.0
- Redesigned GUI with inline editing, tabs, search, and batch tools
- Find & Replace and Auto-Number for bulk label management
- Automatic backup before uploads
- Resizable window with improved dark theme
- Blackmagic Videohub TCP 9990 support
- Auto-detection of router type

### v2.0
- Download labels from router
- HTTPS-first with HTTP fallback
- REST + Telnet fallback chain
- PowerShell 5.1 compatibility fixes

### v1.0
- Basic label upload from Excel
- GUI and CLI interfaces
- 32x32 router support

---

**GitHub**: https://github.com/SRVR-JOE/helix
**Created for professional live event production environments**
