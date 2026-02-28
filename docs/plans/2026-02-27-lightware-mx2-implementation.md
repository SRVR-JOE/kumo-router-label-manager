# Lightware MX2 Support Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Lightware MX2 HDMI matrix router support as a third protocol adapter using LW3 protocol over TCP port 6107.

**Architecture:** Same discriminated-union dispatch pattern as KUMO/Videohub. New Lightware-specific functions (`Send-LW3Command`, `Connect-LightwareRouter`, `Download-LightwareLabels`) are added alongside existing KUMO/Videohub functions. Each of ~15 dispatch sites gets a new `"Lightware"` branch.

**Tech Stack:** PowerShell 5.1 (WinForms GUI), Python 3.x (Rich CLI), LW3 protocol over TCP/IP

**CRITICAL CONSTRAINT:** All PS1 code MUST use only ASCII characters. No em-dashes, box-drawing chars, curly quotes, or any non-ASCII. Windows PowerShell reads .ps1 as Windows-1252.

---

### Task 1: Add PowerShell LW3 Protocol Core Functions

**Files:**
- Modify: `KUMO-Label-Manager.ps1` -- insert new functions after line 605 (after `Upload-KumoLabels-Telnet`, before `Connect-VideohubRouter`)

**Step 1: Add Send-LW3Command helper function**

Insert after line 605 (after the closing `}` of `Upload-KumoLabels-Telnet`):

```powershell
# --- Lightware LW3 Protocol Functions ----------------------------------------

function Send-LW3Command {
    param([string]$Command)
    # Sends an LW3 command with a request ID and reads the multiline response.
    # Returns an array of response lines (without the {id and } wrappers).
    # Throws on timeout or connection error.

    if ($global:lightwareSendId -ge 9998) { $global:lightwareSendId = 0 }
    else { $global:lightwareSendId++ }
    $id = $global:lightwareSendId.ToString("D4")

    $global:lightwareWriter.Write("$id#$Command`r`n")
    $global:lightwareWriter.Flush()

    # Read multiline response wrapped in {NNNN ... }
    $lines = [System.Collections.Generic.List[string]]::new()
    $deadline = [DateTime]::Now.AddSeconds(5)
    $inBlock = $false

    while ([DateTime]::Now -lt $deadline) {
        $stream = $global:lightwareTcp.GetStream()
        if ($stream.DataAvailable) {
            $line = $global:lightwareReader.ReadLine()
            if ($line -eq $null) { break }

            if (-not $inBlock) {
                if ($line -eq "{$id") { $inBlock = $true; continue }
            } else {
                if ($line -eq "}") { return $lines.ToArray() }
                $lines.Add($line)
            }
        } else {
            Start-Sleep -Milliseconds 20
        }
    }

    if ($lines.Count -gt 0) { return $lines.ToArray() }
    throw "LW3 command timed out: $Command"
}
```

**Step 2: Add Connect-LightwareRouter function**

Insert immediately after `Send-LW3Command`:

```powershell
function Connect-LightwareRouter {
    param([string]$IP, [int]$Port = 6107)
    # Opens a persistent TCP connection to a Lightware MX2 router via LW3 protocol.
    # Returns info hashtable or throws on failure.

    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.ReceiveTimeout = 5000
    $tcp.SendTimeout    = 5000
    $tcp.Connect($IP, $Port)

    $stream = $tcp.GetStream()
    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII)
    $writer = New-Object System.IO.StreamWriter($stream, [System.Text.Encoding]::ASCII)
    $writer.AutoFlush = $false

    $global:lightwareTcp    = $tcp
    $global:lightwareWriter = $writer
    $global:lightwareReader = $reader
    $global:lightwareSendId = 0

    # Get product name
    $resp = Send-LW3Command "GET /.ProductName"
    $productName = "Lightware MX2"
    foreach ($line in $resp) {
        if ($line -match '\.ProductName=(.+)$') {
            $productName = $matches[1].Trim()
        }
    }

    # Get port counts
    $inputCount = 0
    $outputCount = 0

    $resp = Send-LW3Command "GET /MEDIA/XP/VIDEO.SourcePortCount"
    foreach ($line in $resp) {
        if ($line -match 'SourcePortCount=(\d+)') {
            $inputCount = [int]$matches[1]
        }
    }

    $resp = Send-LW3Command "GET /MEDIA/XP/VIDEO.DestinationPortCount"
    foreach ($line in $resp) {
        if ($line -match 'DestinationPortCount=(\d+)') {
            $outputCount = [int]$matches[1]
        }
    }

    if ($inputCount -eq 0 -or $outputCount -eq 0) {
        throw "Could not determine port counts from Lightware device at $IP"
    }

    return @{
        RouterType    = "Lightware"
        RouterName    = $productName
        RouterModel   = "Lightware $productName"
        Firmware      = ""
        InputCount    = $inputCount
        OutputCount   = $outputCount
    }
}
```

**Step 3: Add Download-LightwareLabels function**

Insert immediately after `Connect-LightwareRouter`:

```powershell
function Download-LightwareLabels {
    param([string]$IP, [int]$Port = 6107)
    # Downloads all port labels from a Lightware MX2 via LW3 protocol.
    # Re-connects if needed. Returns info hashtable with label dictionaries.

    if ($global:lightwareTcp -ne $null) {
        try { $global:lightwareWriter.Dispose() } catch { }
        try { $global:lightwareReader.Dispose() } catch { }
        try { $global:lightwareTcp.Close() } catch { }
        $global:lightwareTcp    = $null
        $global:lightwareWriter = $null
        $global:lightwareReader = $null
    }

    $info = Connect-LightwareRouter -IP $IP -Port $Port

    # Get all labels from /MEDIA/NAMES/VIDEO
    $resp = Send-LW3Command "GET /MEDIA/NAMES/VIDEO.*"

    $inputLabels  = @{}
    $outputLabels = @{}

    foreach ($line in $resp) {
        # Format: pw /MEDIA/NAMES/VIDEO.I1=1;Label Text
        if ($line -match '/MEDIA/NAMES/VIDEO\.(I|O)(\d+)=\d+;(.*)$') {
            $portType  = $matches[1]
            $portNum   = [int]$matches[2]
            $labelText = $matches[3].Trim()
            if ($portType -eq "I") {
                $inputLabels[$portNum] = $labelText
            } else {
                $outputLabels[$portNum] = $labelText
            }
        }
    }

    return @{
        RouterType    = "Lightware"
        RouterName    = $info.RouterName
        RouterModel   = $info.RouterModel
        InputCount    = $info.InputCount
        OutputCount   = $info.OutputCount
        InputLabels   = $inputLabels
        OutputLabels  = $outputLabels
    }
}
```

**Step 4: Add Upload-LightwareLabels function**

Insert immediately after `Download-LightwareLabels`:

```powershell
function Upload-LightwareLabel {
    param([string]$Type, [int]$Port, [string]$Label)
    # Uploads a single label to the Lightware MX2 via LW3 SET command.
    # Returns $true on success, $false on error.

    $prefix = if ($Type -eq "INPUT") { "I" } else { "O" }
    $cmd = "SET /MEDIA/NAMES/VIDEO.$prefix$Port=1;$Label"

    try {
        $resp = Send-LW3Command $cmd
        foreach ($line in $resp) {
            if ($line -match 'pE|nE') { return $false }
        }
        return $true
    } catch {
        return $false
    }
}
```

**Step 5: Verify file is still pure ASCII**

Run: `LC_ALL=C grep -n '[^ -~]' KUMO-Label-Manager.ps1 | head -20`
Expected: No output (no non-ASCII characters)

**Step 6: Commit**

```bash
git add KUMO-Label-Manager.ps1
git commit -m "feat: add Lightware LW3 protocol core functions"
```

---

### Task 2: Wire Lightware Into PowerShell Dispatch Points (Connection & Download)

**Files:**
- Modify: `KUMO-Label-Manager.ps1`

**Step 1: Add Lightware globals near the top**

Find the global variable declarations (around line 200-250, near `$global:videohubTcp`) and add:

```powershell
$global:lightwareTcp    = $null
$global:lightwareWriter = $null
$global:lightwareReader = $null
$global:lightwareSendId = 0
```

**Step 2: Add Lightware to Connect-Router auto-detection (~line 733)**

In `Connect-Router`, add a Lightware probe BEFORE the Videohub probe. Insert before `if ($RouterType -eq "Videohub" -or $RouterType -eq "Auto")`:

```powershell
    if ($RouterType -eq "Lightware" -or $RouterType -eq "Auto") {
        try {
            $testTcp = New-Object System.Net.Sockets.TcpClient
            $connectResult = $testTcp.BeginConnect($IP, 6107, $null, $null)
            $waited = $connectResult.AsyncWaitHandle.WaitOne(2000)
            if ($waited) {
                try {
                    $testTcp.EndConnect($connectResult)
                    if ($testTcp.Connected) {
                        $testTcp.Close()
                        $info = Connect-LightwareRouter -IP $IP -Port 6107
                        return $info
                    }
                } catch {
                    $global:lightwareTcp = $null; $global:lightwareWriter = $null; $global:lightwareReader = $null
                }
                try { $testTcp.Close() } catch { }
            } else {
                try { $testTcp.EndConnect($connectResult) } catch { }
                try { $testTcp.Close() } catch { }
            }
        } catch {
            # Lightware not available
        }

        if ($RouterType -eq "Lightware") {
            throw "Cannot connect to Lightware router at $IP on port 6107."
        }
    }
```

**Step 3: Add Lightware branch to Download-RouterLabels (~line 781)**

In `Download-RouterLabels`, change the `if/else` to `if/elseif/else`. After the Videohub block (around `if ($ProgressCallback) { & $ProgressCallback 100 }`), add before the `else` (KUMO):

```powershell
        } elseif ($global:routerType -eq "Lightware") {
            if ($ProgressCallback) { & $ProgressCallback 50 }
            $info = Download-LightwareLabels -IP $IP -Port 6107

            $inputLabels  = $info.InputLabels
            $outputLabels = $info.OutputLabels
            $inputCount   = $info.InputCount
            $outputCount  = $info.OutputCount
            $global:routerInputCount  = $inputCount
            $global:routerOutputCount = $outputCount

            for ($i = 1; $i -le $inputCount; $i++) {
                $label = if ($inputLabels.ContainsKey($i)) { $inputLabels[$i] } else { "Input $i" }
                $global:allLabels.Add([PSCustomObject]@{
                    Port = $i; Type = "INPUT"; Current_Label = $label; New_Label = ""; Notes = "From Lightware"
                }) | Out-Null
            }
            for ($i = 1; $i -le $outputCount; $i++) {
                $label = if ($outputLabels.ContainsKey($i)) { $outputLabels[$i] } else { "Output $i" }
                $global:allLabels.Add([PSCustomObject]@{
                    Port = $i; Type = "OUTPUT"; Current_Label = $label; New_Label = ""; Notes = "From Lightware"
                }) | Out-Null
            }
            if ($ProgressCallback) { & $ProgressCallback 100 }
```

Note: Lightware uses 1-based port numbers directly (no `$i - 1` translation needed, unlike Videohub).

**Step 4: Update error message in Connect-Router (~line 774)**

Change the KUMO fallback error message to mention all three protocols:

```powershell
            throw "Could not connect to $IP -- no Lightware (TCP/6107), Videohub (TCP/9990), or KUMO (HTTP/80) response detected. Verify the IP address and that the router is powered on."
```

**Step 5: Commit**

```bash
git add KUMO-Label-Manager.ps1
git commit -m "feat: wire Lightware into Connect-Router and Download-RouterLabels"
```

---

### Task 3: Wire Lightware Into PowerShell Dispatch Points (Upload)

**Files:**
- Modify: `KUMO-Label-Manager.ps1`

**Step 1: Add Lightware branch to Upload-RouterLabels (~line 841)**

Change the existing `if/else` to `if/elseif/else`. After the Videohub block (ends with `return @{ ... }`), add before the `else` (KUMO):

```powershell
    } elseif ($global:routerType -eq "Lightware") {
        $successLabels = [System.Collections.Generic.List[object]]::new()
        $errorCount = 0
        $doneCount = 0

        # Ensure connection is alive
        if ($global:lightwareWriter -eq $null -or $global:lightwareTcp -eq $null -or -not $global:lightwareTcp.Connected) {
            try { Connect-LightwareRouter -IP $IP -Port 6107 | Out-Null } catch {
                return @{ SuccessCount = 0; ErrorCount = $Changes.Count; SuccessLabels = $successLabels }
            }
        }

        foreach ($item in $Changes) {
            $ok = Upload-LightwareLabel -Type $item.Type -Port $item.Port -Label $item.New_Label.Trim()
            if ($ok) { $successLabels.Add($item) } else { $errorCount++ }
            $doneCount++
            if ($ProgressCallback) { & $ProgressCallback $doneCount }
        }

        return @{ SuccessCount = $successLabels.Count; ErrorCount = $errorCount; SuccessLabels = $successLabels }
```

**Step 2: Commit**

```bash
git add KUMO-Label-Manager.ps1
git commit -m "feat: wire Lightware into Upload-RouterLabels"
```

---

### Task 4: Wire Lightware Into PowerShell UI Dispatch Points

**Files:**
- Modify: `KUMO-Label-Manager.ps1`

**Step 1: Add "Lightware MX2" to router type dropdown (~line 1026)**

Change:
```powershell
$cboRouterType.Items.AddRange(@("Auto-detect", "AJA KUMO", "BMD Videohub"))
```
To:
```powershell
$cboRouterType.Items.AddRange(@("Auto-detect", "AJA KUMO", "BMD Videohub", "Lightware MX2"))
```

**Step 2: Map dropdown selection to router type string in connect handler**

Find where the connect handler maps dropdown text to router type (near line 1940-1950). The current code likely does something like:
```powershell
$selectedType = switch ($cboRouterType.Text) {
    "AJA KUMO"      { "KUMO" }
    "BMD Videohub"  { "Videohub" }
    default         { "Auto" }
}
```

Add the Lightware case:
```powershell
    "Lightware MX2"  { "Lightware" }
```

**Step 3: Update maxLabelLength dispatch (~line 1975)**

Change:
```powershell
$global:maxLabelLength = if ($info.RouterType -eq "Videohub") { 255 } else { 50 }
```
To:
```powershell
$global:maxLabelLength = if ($info.RouterType -eq "Videohub" -or $info.RouterType -eq "Lightware") { 255 } else { 50 }
```

**Step 4: Update connection error dialog (~line 2014)**

Change the help text to mention port 6107:
```
"- Port 80 (KUMO), 9990 (Videohub), or 6107 (Lightware) is accessible"
```

**Step 5: Update upload confirm dialog (~line 2725)**

Change:
```powershell
$routerTypeLabel = if ($global:routerType -eq "Videohub") { "Blackmagic Videohub" } else { "KUMO" }
```
To:
```powershell
$routerTypeLabel = switch ($global:routerType) {
    "Videohub"  { "Blackmagic Videohub" }
    "Lightware" { "Lightware MX2" }
    default     { "KUMO" }
}
```

**Step 6: Update worksheet name dispatch (~line 2173 and ~line 2559)**

Find both places where worksheet names are set and change from:
```powershell
$saveWsName = if ($global:routerType -eq "Videohub") { "Videohub_Labels" } else { "KUMO_Labels" }
```
To:
```powershell
$saveWsName = switch ($global:routerType) {
    "Videohub"  { "Videohub_Labels" }
    "Lightware" { "Lightware_Labels" }
    default     { "KUMO_Labels" }
}
```

Do the same for the template worksheet name dispatch (~line 2559).

**Step 7: Commit**

```bash
git add KUMO-Label-Manager.ps1
git commit -m "feat: wire Lightware into UI dispatch points"
```

---

### Task 5: Add Lightware Template Models and Keepalive/Cleanup

**Files:**
- Modify: `KUMO-Label-Manager.ps1`

**Step 1: Add MX2 models to template model picker (~line 2473)**

After the Videohub models in the `$modelCombo.Items.AddRange()` call, add:

```powershell
            "MX2-4x4 (4 in / 4 out)",
            "MX2-8x4 (8 in / 4 out)",
            "MX2-8x8 (8 in / 8 out)",
            "MX2-16x16 (16 in / 16 out)",
            "MX2-24x24 (24 in / 24 out)",
            "MX2-32x32 (32 in / 32 out)",
            "MX2-48x48 (48 in / 48 out)"
```

**Step 2: Add MX2 cases to template switch (~line 2506)**

Add cases for the new model indices (after the last Videohub case):

```powershell
            11 { $inCount = 4;  $outCount = 4;  $modelName = "MX2-4x4" }
            12 { $inCount = 8;  $outCount = 4;  $modelName = "MX2-8x4" }
            13 { $inCount = 8;  $outCount = 8;  $modelName = "MX2-8x8" }
            14 { $inCount = 16; $outCount = 16; $modelName = "MX2-16x16" }
            15 { $inCount = 24; $outCount = 24; $modelName = "MX2-24x24" }
            16 { $inCount = 32; $outCount = 32; $modelName = "MX2-32x32" }
            17 { $inCount = 48; $outCount = 48; $modelName = "MX2-48x48" }
```

**Step 3: Add Lightware keepalive to timer tick handler (~line 2805)**

Change the keepalive timer tick handler to also handle Lightware. After the existing Videohub block, add:

```powershell
    if ($global:routerType -eq "Lightware" -and $global:routerConnected -and $global:lightwareWriter) {
        try {
            Send-LW3Command "GET /.ProductName" | Out-Null
        } catch {
            $global:routerConnected = $false
            $keepaliveTimer.Stop()
            $connIndicator.State = [ConnectionIndicator+ConnectionState]::Disconnected
            $connIndicator.StatusText = "Connection lost"
            $connectButton.Text = "Connect"
            $btnDownload.Enabled = $false
            $btnUpload.Enabled = $false
            Set-StatusMessage "Lightware connection lost" "Danger"
        }
    }
```

**Step 4: Start keepalive after Lightware connect (~line 2001)**

Change:
```powershell
if ($global:routerType -eq "Videohub" -and $keepaliveTimer -ne $null) { $keepaliveTimer.Start() }
```
To:
```powershell
if (($global:routerType -eq "Videohub" -or $global:routerType -eq "Lightware") -and $keepaliveTimer -ne $null) { $keepaliveTimer.Start() }
```

**Step 5: Resume keepalive after upload (~line 2797)**

Change:
```powershell
if ($global:routerType -eq "Videohub" -and $global:routerConnected -and $keepaliveTimer -ne $null) { $keepaliveTimer.Start() }
```
To:
```powershell
if (($global:routerType -eq "Videohub" -or $global:routerType -eq "Lightware") -and $global:routerConnected -and $keepaliveTimer -ne $null) { $keepaliveTimer.Start() }
```

**Step 6: Add Lightware TCP cleanup to FormClosing (~line 2826)**

After the existing Videohub cleanup block, add:

```powershell
    if ($global:lightwareTcp -ne $null) {
        try { $global:lightwareWriter.Dispose() } catch { }
        try { $global:lightwareReader.Dispose() } catch { }
        try { $global:lightwareTcp.Close() } catch { }
        $global:lightwareTcp    = $null
        $global:lightwareWriter = $null
        $global:lightwareReader = $null
    }
```

**Step 7: Update Lightware disconnect in Download-RouterLabels catch block (~line 832)**

After the existing Videohub null check, add:

```powershell
        if ($global:routerType -eq "Lightware" -and $global:lightwareTcp -eq $null) {
            $global:routerConnected = $false
        }
```

**Step 8: Verify ASCII purity**

Run: `LC_ALL=C grep -n '[^ -~]' KUMO-Label-Manager.ps1 | head -20`
Expected: No output

**Step 9: Commit**

```bash
git add KUMO-Label-Manager.ps1
git commit -m "feat: add Lightware templates, keepalive, and cleanup"
```

---

### Task 6: Update Version Header

**Files:**
- Modify: `KUMO-Label-Manager.ps1` line 1-2

**Step 1: Update header comment**

Change:
```powershell
# Router Label Manager v4.0
# Supports AJA KUMO and Blackmagic Videohub matrix routers.
```
To:
```powershell
# Router Label Manager v5.0
# Supports AJA KUMO, Blackmagic Videohub, and Lightware MX2 matrix routers.
```

**Step 2: Update form title (~line 939)**

Change:
```powershell
$form.Text = "Router Label Manager v4.0"
```
To:
```powershell
$form.Text = "Router Label Manager v5.0"
```

**Step 3: Commit**

```bash
git add KUMO-Label-Manager.ps1
git commit -m "chore: bump version to 5.0 with Lightware support"
```

---

### Task 7: Add Lightware LW3 Protocol to Python CLI

**Files:**
- Modify: `src/cli.py`

**Step 1: Add Lightware constants and data class**

After the Videohub constants (around line 39-40), add:

```python
# Lightware LW3 TCP port
LIGHTWARE_PORT = 6107
LIGHTWARE_TIMEOUT = 2.0
LIGHTWARE_MAX_LABEL_LENGTH = 255
```

After the `VideohubInfo` dataclass (around line 82), add:

```python
@dataclass
class LightwareInfo:
    """Information returned by a Lightware MX2 device on connect."""

    product_name: str = "Lightware MX2"
    input_count: int = 0
    output_count: int = 0
    input_labels: Dict[int, str] = field(default_factory=dict)
    output_labels: Dict[int, str] = field(default_factory=dict)
```

**Step 2: Add LW3 protocol functions**

After the `detect_router_type` function (around line 385), add:

```python
# ---------------------------------------------------------------------------
# Lightware LW3 protocol
# ---------------------------------------------------------------------------

def _lw3_send_command(sock: socket.socket, command: str, send_id: List[int]) -> List[str]:
    """Send an LW3 command and read the multiline response.

    Args:
        sock: Connected TCP socket.
        command: LW3 command string (e.g. "GET /.ProductName").
        send_id: Mutable list with a single int element [counter].

    Returns:
        List of response lines (without the {id and } wrappers).
    """
    if send_id[0] >= 9998:
        send_id[0] = 0
    else:
        send_id[0] += 1
    id_str = f"{send_id[0]:04d}"

    sock.sendall(f"{id_str}#{command}\r\n".encode("ascii"))

    lines: List[str] = []
    buf = b""
    sock.settimeout(5.0)
    in_block = False
    deadline = __import__("time").time() + 5.0

    while __import__("time").time() < deadline:
        try:
            chunk = sock.recv(4096)
            if not chunk:
                break
            buf += chunk
        except socket.timeout:
            break

        while b"\r\n" in buf:
            line_bytes, buf = buf.split(b"\r\n", 1)
            line = line_bytes.decode("ascii", errors="replace")

            if not in_block:
                if line == "{" + id_str:
                    in_block = True
            else:
                if line == "}":
                    return lines
                lines.append(line)

    if lines:
        return lines
    raise TimeoutError(f"LW3 command timed out: {command}")


def connect_lightware(ip: str, port: int = LIGHTWARE_PORT) -> Tuple[bool, Optional[LightwareInfo], Optional[str]]:
    """Connect to a Lightware MX2 and retrieve device info and labels.

    Returns:
        Tuple of (success, info_or_None, error_message_or_None).
    """
    sock = None
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(LIGHTWARE_TIMEOUT)
        sock.connect((ip, port))

        send_id = [0]
        info = LightwareInfo()

        # Get product name
        resp = _lw3_send_command(sock, "GET /.ProductName", send_id)
        for line in resp:
            import re
            m = re.search(r"\.ProductName=(.+)$", line)
            if m:
                info.product_name = m.group(1).strip()

        # Get port counts
        resp = _lw3_send_command(sock, "GET /MEDIA/XP/VIDEO.SourcePortCount", send_id)
        for line in resp:
            m = re.search(r"SourcePortCount=(\d+)", line)
            if m:
                info.input_count = int(m.group(1))

        resp = _lw3_send_command(sock, "GET /MEDIA/XP/VIDEO.DestinationPortCount", send_id)
        for line in resp:
            m = re.search(r"DestinationPortCount=(\d+)", line)
            if m:
                info.output_count = int(m.group(1))

        # Get all labels
        resp = _lw3_send_command(sock, "GET /MEDIA/NAMES/VIDEO.*", send_id)
        for line in resp:
            m = re.match(r"p[wr]\s+/MEDIA/NAMES/VIDEO\.(I|O)(\d+)=\d+;(.*)$", line)
            if m:
                port_type = m.group(1)
                port_num = int(m.group(2))
                label_text = m.group(3).strip()
                if port_type == "I":
                    info.input_labels[port_num] = label_text
                else:
                    info.output_labels[port_num] = label_text

        return True, info, None

    except Exception as e:
        return False, None, str(e)
    finally:
        if sock:
            try:
                sock.close()
            except Exception:
                pass


def lightware_info_to_router_labels(info: LightwareInfo) -> List[RouterLabel]:
    """Convert LightwareInfo into a list of RouterLabel objects."""
    labels: List[RouterLabel] = []
    for i in range(1, info.input_count + 1):
        label_text = info.input_labels.get(i, f"Input {i}")
        labels.append(RouterLabel(port_number=i, port_type="INPUT", current_label=label_text))
    for i in range(1, info.output_count + 1):
        label_text = info.output_labels.get(i, f"Output {i}")
        labels.append(RouterLabel(port_number=i, port_type="OUTPUT", current_label=label_text))
    return labels


def upload_lightware_label(ip: str, port_type: str, port_num: int, label: str) -> bool:
    """Upload a single label to a Lightware MX2.

    Returns True on success, False on error.
    """
    sock = None
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(LIGHTWARE_TIMEOUT)
        sock.connect((ip, LIGHTWARE_PORT))

        send_id = [0]
        prefix = "I" if port_type == "INPUT" else "O"
        cmd = f"SET /MEDIA/NAMES/VIDEO.{prefix}{port_num}=1;{label}"
        resp = _lw3_send_command(sock, cmd, send_id)

        for line in resp:
            if "pE" in line or "nE" in line:
                return False
        return True

    except Exception:
        return False
    finally:
        if sock:
            try:
                sock.close()
            except Exception:
                pass
```

**Step 3: Commit**

```bash
git add src/cli.py
git commit -m "feat: add Lightware LW3 protocol functions to Python CLI"
```

---

### Task 8: Add LightwareManager Class and Wire Into Python Dispatch

**Files:**
- Modify: `src/cli.py`

**Step 1: Add LightwareManager class**

After the `VideohubManager` class (around line 1092), add:

```python
# ---------------------------------------------------------------------------
# LightwareManager -- Lightware MX2 router support
# ---------------------------------------------------------------------------

class LightwareManager:
    """Application coordinator for Lightware MX2 router management."""

    def __init__(self, settings: Optional[Settings] = None):
        self.settings = settings or Settings()
        self.file_handler = FileHandlerAgent()

    def download_labels(self, output_file: str) -> bool:
        """Download current labels from Lightware MX2 and save to file."""
        output_path = Path(output_file)

        supported = {".xlsx", ".csv", ".json"}
        if output_path.suffix.lower() not in supported:
            console.print(
                f"[red]Unsupported format:[/red] {output_path.suffix}\n"
                f"[dim]Supported: {', '.join(supported)}[/dim]"
            )
            return False

        try:
            with Progress(
                SpinnerColumn(),
                TextColumn("[progress.description]{task.description}"),
                BarColumn(bar_width=30),
                TaskProgressColumn(),
                console=console,
            ) as progress:
                task = progress.add_task(
                    f"[purple]Connecting to Lightware at {self.settings.router_ip}...", total=3
                )

                success, info, err = connect_lightware(self.settings.router_ip)
                progress.update(task, advance=1)

                if not success:
                    progress.stop()
                    console.print(f"\n[red bold]Connection failed:[/red bold] {err}")
                    console.print(
                        "[dim]Is this a Lightware MX2?  "
                        "Try --router-type kumo or --router-type videohub.[/dim]"
                    )
                    return False

                progress.update(task, description="[purple]Parsing labels...")
                labels = lightware_info_to_router_labels(info)
                progress.update(task, advance=1)

                progress.update(task, description=f"[purple]Saving to {output_path.name}...")
                file_data, skipped = router_labels_to_filedata(labels)
                self.file_handler.save(output_path, file_data)
                progress.update(task, advance=1)

            console.print()
            display_router_labels_table(labels, title=f"Labels from {self.settings.router_ip}")
            console.print()

            save_msg = (
                f"[green bold]Saved {len(file_data.ports)} labels to "
                f"[purple]{output_file}[/purple][/green bold]"
            )
            if skipped:
                save_msg += (
                    f"\n[yellow dim]Note: {skipped} labels beyond port 120 were not saved "
                    f"(file format limit).[/yellow dim]"
                )
            console.print(Panel(save_msg, border_style="green", padding=(0, 2)))
            return True
        except Exception as e:
            console.print(f"[red bold]Error:[/red bold] {e}")
            return False

    def upload_labels(self, input_file: str, test_mode: bool = False) -> bool:
        """Upload labels to Lightware MX2 from file."""
        input_path = Path(input_file)

        if not input_path.exists():
            console.print(f"[red]File not found:[/red] {input_file}")
            return False

        try:
            with Progress(
                SpinnerColumn(),
                TextColumn("[progress.description]{task.description}"),
                BarColumn(bar_width=30),
                TaskProgressColumn(),
                console=console,
            ) as progress:
                task = progress.add_task(
                    f"[purple]Loading {input_path.name}...", total=3
                )

                file_data = self.file_handler.load(input_path)
                progress.update(task, advance=1)

                labels = filedata_to_router_labels(file_data)
                changes = [l for l in labels if l.has_changes()]

                if not changes:
                    progress.stop()
                    console.print("[yellow]No label changes found in file.[/yellow]")
                    return True

                if test_mode:
                    progress.stop()
                    console.print(
                        Panel(
                            f"[yellow bold]DRY RUN -- {len(changes)} labels would be uploaded[/yellow bold]",
                            border_style="yellow",
                        )
                    )
                    display_changes_table(changes)
                    return True

                progress.update(task, description="[purple]Uploading labels...")
                success_count = 0
                error_count = 0
                for lbl in changes:
                    ok = upload_lightware_label(
                        self.settings.router_ip,
                        lbl.port_type,
                        lbl.port_number,
                        lbl.new_label.strip(),
                    )
                    if ok:
                        success_count += 1
                    else:
                        error_count += 1
                progress.update(task, advance=1)

                progress.update(task, description="[purple]Done")
                progress.update(task, advance=1)

            console.print()
            if error_count == 0:
                console.print(Panel(
                    f"[green bold]Successfully uploaded {success_count} labels to "
                    f"Lightware MX2 at {self.settings.router_ip}[/green bold]",
                    border_style="green",
                    padding=(0, 2),
                ))
            else:
                console.print(Panel(
                    f"[yellow bold]Uploaded {success_count} labels, {error_count} failed[/yellow bold]",
                    border_style="yellow",
                    padding=(0, 2),
                ))
            return error_count == 0
        except Exception as e:
            console.print(f"[red bold]Error:[/red bold] {e}")
            return False

    def show_status(self) -> bool:
        """Show Lightware MX2 connection status and device info."""
        with Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            console=console,
        ) as progress:
            progress.add_task(
                f"[purple]Querying Lightware at {self.settings.router_ip}...", total=None
            )
            success, info, err = connect_lightware(self.settings.router_ip)

        console.print()

        info_table = Table(
            box=box.ROUNDED,
            border_style="purple",
            show_header=False,
            padding=(0, 2),
        )
        info_table.add_column("Property", style="dim", width=20)
        info_table.add_column("Value", style="bold")

        if success and info is not None:
            info_table.add_row("Status", "[green bold]Connected[/green bold]")
            info_table.add_row("Router Type", "Lightware MX2")
            info_table.add_row("Router IP", self.settings.router_ip)
            info_table.add_row("Model", info.product_name)
            info_table.add_row(
                "Total Ports",
                f"{info.input_count} inputs + {info.output_count} outputs",
            )
        else:
            info_table.add_row("Status", "[red bold]Disconnected[/red bold]")
            info_table.add_row("Router Type", "Lightware MX2")
            info_table.add_row("Router IP", self.settings.router_ip)
            info_table.add_row("Error", err or "Unknown error")

        console.print(Panel(
            info_table,
            title="[bold purple]Router Status[/bold purple]",
            border_style="purple",
            padding=(1, 1),
        ))

        if not success:
            console.print(
                "[dim]Is this a Lightware MX2?  "
                "Try --router-type kumo or --router-type videohub.[/dim]"
            )

        return success

    def create_template(self, output_file: str, size: int = 16) -> bool:
        """Create a Lightware MX2 template file."""
        output_path = Path(output_file)

        supported = {".xlsx", ".csv", ".json"}
        if output_path.suffix.lower() not in supported:
            console.print(
                f"[red]Unsupported format:[/red] {output_path.suffix}\n"
                f"[dim]Supported: {', '.join(supported)}[/dim]"
            )
            return False

        capped = min(size, 48)
        labels: List[RouterLabel] = []
        for i in range(1, capped + 1):
            labels.append(RouterLabel(port_number=i, port_type="INPUT", current_label=f"Input {i}"))
        for i in range(1, capped + 1):
            labels.append(RouterLabel(port_number=i, port_type="OUTPUT", current_label=f"Output {i}"))

        try:
            file_data, _ = router_labels_to_filedata(labels)
            self.file_handler.save(output_path, file_data)
            console.print(Panel(
                f"[green bold]Lightware MX2 template created:[/green bold] [purple]{output_file}[/purple]\n"
                f"[dim]Contains {capped * 2} ports ({capped} inputs + {capped} outputs)[/dim]",
                border_style="green",
                padding=(0, 2),
            ))
            return True
        except Exception as e:
            console.print(f"[red bold]Error:[/red bold] {e}")
            return False
```

**Step 2: Update ROUTER_TYPE_CHOICES (~line 1099)**

Change:
```python
ROUTER_TYPE_CHOICES = ["auto", "kumo", "videohub"]
```
To:
```python
ROUTER_TYPE_CHOICES = ["auto", "kumo", "videohub", "lightware"]
```

**Step 3: Update ROUTER_TYPE_HELP (~line 1101)**

Change to:
```python
ROUTER_TYPE_HELP = (
    "Router protocol type.  "
    "'auto' (default) probes TCP 6107 (Lightware), TCP 9990 (Videohub), "
    "then HTTP 80 (KUMO). "
    "'kumo' forces AJA KUMO REST/Telnet.  'videohub' forces Blackmagic TCP.  "
    "'lightware' forces Lightware LW3 TCP."
)
```

**Step 4: Update detect_router_type (~line 353)**

Add Lightware probe before the Videohub probe:

```python
def detect_router_type(ip: str) -> str:
    """Auto-detect whether the device is a Lightware, Videohub, or KUMO."""
    # Try Lightware LW3 first (TCP 6107)
    sock = None
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(2.0)
        sock.connect((ip, LIGHTWARE_PORT))
        # If we can connect to 6107, try a quick GET command
        sock.sendall(b"0001#GET /.ProductName\r\n")
        sock.settimeout(2.0)
        data = sock.recv(4096)
        response = data.decode("ascii", errors="replace")
        if "ProductName" in response:
            return "lightware"
    except (socket.timeout, socket.error, OSError):
        pass
    finally:
        if sock:
            try: sock.close()
            except: pass

    # Try Videohub (TCP 9990)
    sock = None
    sock_file = None
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(2.0)
        sock.connect((ip, VIDEOHUB_PORT))
        sock_file = sock.makefile("r", encoding="utf-8", errors="replace")
        first_line = sock_file.readline()
        if "PROTOCOL PREAMBLE" in first_line:
            return "videohub"
    except (socket.timeout, socket.error, OSError):
        pass
    finally:
        if sock_file:
            try: sock_file.close()
            except: pass
        if sock:
            try: sock.close()
            except: pass
    return "kumo"
```

**Step 5: Update resolve_router_type (~line 1199)**

Add Lightware case:

```python
def resolve_router_type(requested: str, ip: str) -> str:
    if requested == "kumo":
        return "kumo"
    if requested == "videohub":
        return "videohub"
    if requested == "lightware":
        return "lightware"

    # Auto-detect
    console.print(f"[dim]Auto-detecting router type at {ip}...[/dim]")
    detected = detect_router_type(ip)
    type_names = {"videohub": "Blackmagic Videohub", "lightware": "Lightware MX2", "kumo": "AJA KUMO"}
    console.print(f"[dim]Detected: {type_names.get(detected, detected)}[/dim]")
    return detected
```

**Step 6: Update main() dispatch (~line 1244)**

Change each command's dispatch to include Lightware. For example, download:

```python
        if args.command == "download":
            router_type = resolve_router_type(args.router_type, settings.router_ip)
            if router_type == "lightware":
                manager = LightwareManager(settings)
                success = manager.download_labels(args.output)
            elif router_type == "videohub":
                manager = VideohubManager(settings)
                success = manager.download_labels(args.output)
            else:
                manager = KumoManager(settings)
                success = asyncio.run(manager.download_labels(args.output))
```

Do the same for upload, status, and template commands.

**Step 7: Update CLI module docstring (line 2-5)**

Change to:
```python
"""
Command-line interface for Router Label Manager v3.0.

Beautiful, fast, and functional CLI powered by Rich.
Supports AJA KUMO, Blackmagic Videohub, and Lightware MX2 matrix routers.
"""
```

**Step 8: Update CLI examples in build_parser epilog**

Add a Lightware example:
```python
            "  kumo-cli download labels.csv --ip 192.168.1.60 --router-type lightware\n"
```

**Step 9: Commit**

```bash
git add src/cli.py
git commit -m "feat: add LightwareManager and wire into CLI dispatch"
```

---

### Task 9: Final ASCII Purity Check and Push

**Files:**
- Verify: `KUMO-Label-Manager.ps1`
- Verify: `src/cli.py`

**Step 1: Check PS1 for non-ASCII**

Run: `LC_ALL=C grep -n '[^ -~]' KUMO-Label-Manager.ps1 | head -20`
Expected: No output

**Step 2: Check Python for syntax errors**

Run: `python3 -m py_compile src/cli.py`
Expected: No errors

**Step 3: Push to remote**

Run: `git push origin master`

---

### Task 10: Run Code Review Agent

**Step 1: Launch code review**

Dispatch a code review agent to review all changes made in Tasks 1-8 for:
- Logic errors in LW3 response parsing
- Missing dispatch point updates
- Encoding violations (non-ASCII in PS1)
- Error handling gaps
- Consistency with existing KUMO/Videohub patterns

**Step 2: Fix any findings and commit**
