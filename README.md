# KUMO Router Label Manager v3.0

**Professional AV Production Tool for Live Events**

## Overview

Complete solution for managing AJA KUMO router labels. Designed for professional live event production environments like concerts, tours, and corporate events.

### What's New in v3.0

- **Inline editing** - Click any New Label cell to type directly in the grid
- **Filter tabs** - Switch between All / Inputs / Outputs / Changed views
- **Search** - Find labels by name or port number instantly
- **Find & Replace** - Batch rename with scope control (inputs only, outputs only, copy current labels)
- **Auto-Number** - Generate sequential labels like "Camera 1", "Camera 2"... with custom prefix and start number
- **Auto backup** - Labels are backed up to a CSV before every upload
- **Character count** - Live validation showing chars used vs 50-char limit
- **CSV-first** - No Excel dependency required; CSV works out of the box
- **Resizable window** - Scale the UI to fit your monitor
- **Improved progress** - Per-port status during download and upload

## Quick Start

### Launch the GUI
```powershell
.\KUMO-Label-Manager.ps1
```

### Workflow
1. Enter your KUMO router IP and click **Connect**
2. Click **Download from Router** to pull current labels
3. Edit labels directly in the grid (click the yellow "New Label" column)
4. Use **Find & Replace** or **Auto-Number** for bulk edits
5. Click **Upload Changes to Router** when ready

### Command Line
```powershell
# Download current labels
.\KUMO-Excel-Updater.ps1 -DownloadLabels -KumoIP "192.168.1.100" -DownloadPath "labels.csv"

# Upload from file
.\KUMO-Excel-Updater.ps1 -KumoIP "192.168.1.100" -ExcelFile "labels.csv"

# Dry run (test without uploading)
.\KUMO-Excel-Updater.ps1 -KumoIP "192.168.1.100" -ExcelFile "labels.csv" -TestOnly
```

## File Format

Works with CSV (recommended) or Excel (.xlsx). Columns:

| Column | Description |
|--------|-------------|
| Port | Port number (1-32) |
| Type | INPUT or OUTPUT |
| Current_Label | What's on the router now |
| New_Label | Your desired label (leave blank to skip) |
| Notes | Optional documentation |

Labels must be 50 characters or fewer. The app warns you if any labels exceed this limit.

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

### Multi-Router Batch
```powershell
$routers = @("192.168.1.100", "192.168.1.101", "192.168.1.102")
foreach ($ip in $routers) {
    .\KUMO-Excel-Updater.ps1 -KumoIP $ip -ExcelFile "TourLabels.csv"
}
```

## Connection Methods

The tool tries multiple methods to communicate with your KUMO:

1. **REST API** (bulk) - Fastest, gets all labels in one request
2. **REST API** (per-port) - Falls back to querying each port individually
3. **Telnet** - Last resort, sends LABEL commands over port 23

All HTTP requests try HTTPS first, falling back to HTTP automatically.

## Requirements

- **Windows 10/11** with **PowerShell 5.1+**
- Network access to KUMO router (port 80 for HTTP, port 23 for Telnet)
- Optional: ImportExcel PowerShell module for .xlsx support

```powershell
# Install Excel support (optional)
Install-Module ImportExcel -Scope CurrentUser -Force
```

## Troubleshooting

**Can't connect?**
- Verify the IP address is correct
- Check you're on the same network segment
- Try `ping <router-ip>` from PowerShell

**PowerShell won't run the script?**
```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**Labels not updating?**
- Some KUMO models have shorter character limits (8-16 chars)
- Check the firmware version and API compatibility
- Try enabling Telnet in the KUMO web interface

## Version History

### v3.0 (Current)
- Redesigned GUI with inline editing, tabs, search, and batch tools
- Find & Replace and Auto-Number for bulk label management
- Automatic backup before uploads
- Live character count validation
- CSV-first approach (no Excel dependency)
- Resizable window with improved dark theme

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

**Created for professional live event production environments**
