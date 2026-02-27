# Blackmagic Videohub Support — Design Document

## Goal
Add Blackmagic Videohub matrix router support to the KUMO Label Manager, using the same UI and features. Auto-detect router type on connect, with manual override dropdown.

## Architecture: Protocol Adapter Pattern

### RouterAdapter Interface
```
RouterAdapter (abstract)
  ├── Connect(ip, port) → RouterInfo
  ├── DownloadLabels() → Label[]
  ├── UploadLabel(port, type, label) → bool
  ├── GetMaxLabelLength() → int
  ├── GetPortBase() → int (0 or 1)
  ├── Disconnect()
  └── Properties: ModelName, FriendlyName, Firmware, InputCount, OutputCount

KumoAdapter : RouterAdapter
  - REST API on port 80 (eParamID_* params)
  - Telnet fallback on port 23
  - 1-based ports, 50-char label limit
  - Per-port sequential download/upload

VideohubAdapter : RouterAdapter
  - TCP socket on port 9990
  - Text-based block protocol
  - 0-based ports (adapter translates to 1-based for UI)
  - Bulk download (initial state dump), bulk upload (single block)
  - No character limit (set to 255 as safe max)
```

### Auto-Detection Flow
1. Try Videohub TCP 9990 first (fast — instant response on connect)
2. If no response in 2s, try KUMO HTTP port 80
3. If manual override is set, skip detection and use selected protocol

### Data Model Changes
- `$global:routerType` — "KUMO" or "Videohub"
- `$global:routerAdapter` — active adapter instance
- `$global:maxLabelLength` — from adapter (50 for KUMO, 255 for Videohub)
- Port display always 1-based in UI regardless of protocol

### UI Changes
- Sidebar: ComboBox dropdown `[Auto-detect | AJA KUMO | BMD Videohub]` above IP field
- Char limit display adapts to `$global:maxLabelLength`
- Template model picker adds Videohub models
- App title/banner changes from "KUMO Label Manager" to "Router Label Manager"
- Banner subtitle shows both supported router families

### Videohub Protocol Implementation
- TCP port 9990, persistent connection
- On connect: parse PROTOCOL PREAMBLE, VIDEOHUB DEVICE, INPUT LABELS, OUTPUT LABELS blocks
- Labels: `INPUT LABELS:\n0 Label Text\n\n`
- Upload: `INPUT LABELS:\n<index> <label>\n\n` → wait for ACK
- Zero-based indexing in protocol, translated to 1-based in adapter
- PING keepalive every 30s

### Files to Create/Modify
- KUMO-Label-Manager.ps1 — refactor all network code into adapter pattern
- src/cli.py — update banner, add Videohub support to Python CLI

### Videohub Models for Template Picker
- Videohub 10x10, 20x20, 40x40, 80x80, 120x120
- Smart Videohub CleanSwitch 12x12
- Micro Videohub 16x16
