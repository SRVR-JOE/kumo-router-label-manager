# Lightware MX2 HDMI Matrix Support Design

**Date:** 2026-02-27
**Status:** Approved

## Overview

Add Lightware MX2 HDMI matrix router support as a third protocol adapter, following the same discriminated-union dispatch pattern used for Videohub. Uses the LW3 protocol over TCP port 6107, targeting the MX2 device family.

## Protocol Specification

### Connection
- **Transport:** TCP/IP to port 6107
- **Encoding:** ASCII, CR+LF line terminators
- **Authentication:** None by default
- **Handshake:** None required -- send commands immediately after TCP connect

### Command Format
Every command is prefixed with a 4-digit zero-padded request ID:
```
NNNN#COMMAND\r\n
```

### Response Format
Multiline responses are wrapped in curly braces with the matching request ID:
```
{NNNN
pw /path.Property=value
}
```

Response line prefixes:
- `pw` -- read-write property (value follows `=`)
- `pr` -- read-only property
- `mO` -- method call OK
- `pE` -- property error
- `nE` -- node error

### MX2 Tree Paths

| Function | Command |
|----------|---------|
| Device ID | `GET /.ProductName` |
| Input count | `GET /MEDIA/XP/VIDEO.SourcePortCount` |
| Output count | `GET /MEDIA/XP/VIDEO.DestinationPortCount` |
| All labels | `GET /MEDIA/NAMES/VIDEO.*` |
| Set input label | `SET /MEDIA/NAMES/VIDEO.I1=1;Label Text` |
| Set output label | `SET /MEDIA/NAMES/VIDEO.O1=1;Label Text` |
| Crosspoint state | `GET /MEDIA/XP/VIDEO.DestinationConnectionList` |
| Switch route | `CALL /MEDIA/XP/VIDEO:switch(I1:O1)` |

### Port Indexing
- 1-based: `I1`, `I2`, ..., `IN` for inputs; `O1`, `O2`, ..., `ON` for outputs
- Same as KUMO (unlike Videohub which is 0-based)

### Label Format (MX2)
Labels from `/MEDIA/NAMES/VIDEO` use `number;name` format:
```
pw /MEDIA/NAMES/VIDEO.I1=1;Camera 1
pw /MEDIA/NAMES/VIDEO.O1=1;Projector
```

### Keepalive
No dedicated ping command. Use periodic `GET /.ProductName` every 25 seconds.

### Max Label Length
255 characters (safe default, same as Videohub).

## Architecture

### Approach
Same discriminated-union dispatch pattern as KUMO/Videohub. Each dispatch site gets an `elseif ($global:routerType -eq "Lightware")` branch.

### PowerShell Globals
```
$global:lightwareTcp      -- System.Net.Sockets.TcpClient
$global:lightwareWriter   -- System.IO.StreamWriter
$global:lightwareReader   -- System.IO.StreamReader
$global:lightwareSendId   -- [int] request ID counter (0-9998)
```

### New PowerShell Functions

#### Send-LW3Command
Helper that frames a command with a request ID, sends it, reads the multiline response block, and returns parsed lines.

#### Connect-LightwareRouter
1. Create TcpClient, connect to IP:6107
2. Create StreamWriter/StreamReader (ASCII encoding)
3. Send `GET /.ProductName` -- parse model name
4. Send `GET /MEDIA/XP/VIDEO.SourcePortCount` -- parse input count
5. Send `GET /MEDIA/XP/VIDEO.DestinationPortCount` -- parse output count
6. Return info hashtable: `@{ RouterType="Lightware"; RouterName=...; RouterModel=...; InputCount=...; OutputCount=...; Firmware="" }`

#### Download-LightwareLabels
1. Send `GET /MEDIA/NAMES/VIDEO.*`
2. Parse each `pw` response line matching `/MEDIA/NAMES/VIDEO.(I|O)(\d+)=\d+;(.+)`
3. Return hashtable: `@{ InputLabels=@{}; OutputLabels=@{}; InputCount=N; OutputCount=N }`

#### Upload-LightwareLabel
1. For each changed label: `SET /MEDIA/NAMES/VIDEO.<type><port>=1;<label>`
2. Check response for `pw` (success) vs `pE` (error)
3. Return boolean success

### Dispatch Point Changes

| Location | Change |
|----------|--------|
| `Connect-Router` (~line 733) | Add Lightware TCP 6107 probe before Videohub |
| `Download-RouterLabels` (~line 781) | Add `elseif "Lightware"` branch |
| `Upload-RouterLabels` (~line 841) | Add `elseif "Lightware"` branch |
| Router type dropdown (~line 1026) | Add `"Lightware MX2"` to items |
| `maxLabelLength` (~line 1975) | Add Lightware case = 255 |
| Connection error dialog (~line 2014) | Add port 6107 to help text |
| Template model picker (~line 2473) | Add MX2 models |
| Template switch (~line 2506) | Add MX2 model cases |
| Keepalive timer (~line 2805) | Add Lightware keepalive logic |
| FormClosing (~line 2826) | Add Lightware TCP cleanup |
| Upload confirm dialog | Add "Lightware" to type string |
| Worksheet name dispatch | Add "Lightware" sheet name |

### Auto-Detection Waterfall
```
1. Try TCP 6107 (Lightware LW3) -- fastest handshake
2. Try TCP 9990 (Videohub)
3. Try HTTP 80 (KUMO REST)
4. Fail with error listing all three ports
```

### Python CLI Changes

#### New Class: LightwareManager
- `connect(ip)` -- TCP to 6107, identify device, get port counts
- `download_labels(ip)` -- GET all labels, return structured list
- `upload_label(ip, port_type, port_num, label)` -- SET individual label
- `send_command(command)` -- frame with ID, parse multiline response

#### Dispatch Changes
- `ROUTER_TYPE_CHOICES`: add `"lightware"`
- `resolve_router_type()`: add Lightware TCP 6107 probe
- `main()`: add `elif lightware` dispatch branch

### Template Models
```
MX2-4x4 (4 in / 4 out)
MX2-8x4 (8 in / 4 out)
MX2-8x8 (8 in / 8 out)
MX2-16x16 (16 in / 16 out)
MX2-24x24 (24 in / 24 out)
MX2-32x32 (32 in / 32 out)
MX2-48x48 (48 in / 48 out)
```

## Constraints

- All PS1 code MUST use only ASCII characters (no em-dashes, box-drawing chars, etc.)
- Windows PowerShell interprets .ps1 as Windows-1252; non-ASCII causes parse errors
- Port numbers remain 1-based throughout (no index translation needed, unlike Videohub)
- No GENERAL device support initially -- only MX2 tree paths
