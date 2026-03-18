# Router Label Updater - Command Line Version
# Bulk label management for AJA KUMO and Blackmagic Videohub routers
# Auto-detects router type (KUMO REST/Telnet or Videohub TCP 9990)
#
# Usage Examples:
# Download current labels: .\KUMO-Excel-Updater.ps1 -DownloadLabels -KumoIP "192.168.1.100" -DownloadPath "current_labels.xlsx"
# Create template (manual): .\KUMO-Excel-Updater.ps1 -CreateTemplate
# Create template (auto):   .\KUMO-Excel-Updater.ps1 -CreateTemplate -KumoIP "192.168.1.100"
# Update from Excel:        .\KUMO-Excel-Updater.ps1 -KumoIP "192.168.1.100" -ExcelFile "labels.xlsx"
# Test only:                .\KUMO-Excel-Updater.ps1 -KumoIP "192.168.1.100" -ExcelFile "labels.xlsx" -TestOnly
# Videohub explicit:        .\KUMO-Excel-Updater.ps1 -RouterType Videohub -KumoIP "192.168.1.101" -DownloadLabels -DownloadPath "labels.csv"
# Lock output port 5:       .\KUMO-Excel-Updater.ps1 -LockOutput -OutputPort 5 -KumoIP "192.168.100.72" -RouterType Videohub
# Unlock output port 5:     .\KUMO-Excel-Updater.ps1 -UnlockOutput -OutputPort 5 -KumoIP "192.168.100.72" -RouterType Videohub

param(
    [Parameter(Mandatory=$false)]
    [string]$KumoIP,

    [Parameter(Mandatory=$false)]
    [string]$ExcelFile,

    [string]$WorksheetName = "Router_Labels",

    [switch]$TestOnly,

    [switch]$CreateTemplate,

    [switch]$DownloadLabels,

    [string]$DownloadPath,

    [switch]$ForceHTTP,

    [ValidateSet("Auto", "KUMO", "Videohub")]
    [string]$RouterType = "Auto",

    [switch]$LockOutput,

    [switch]$UnlockOutput,

    [int]$OutputPort = 0
)

# Resolved router type — set during auto-detection
$script:DetectedRouterType = $RouterType

$script:defaultRouterIPs = @("192.168.100.51", "192.168.100.52")

function Parse-IPList {
    param([string]$IPString)
    if (-not $IPString) { return @($script:defaultRouterIPs) }
    $ips = @()
    foreach ($entry in ($IPString -split ',')) {
        $entry = $entry.Trim()
        if ($entry -and $entry -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
            $ips += $entry
        }
    }
    if ($ips.Count -eq 0) { return @($script:defaultRouterIPs) }
    return $ips
}

# ─────────────────────────────────────────────────────────────────────────────
# SHARED UTILITIES
# ─────────────────────────────────────────────────────────────────────────────

function Get-ButtonSettingsIndex {
    param([int]$Port, [string]$PortType)
    # KUMO interleaves sources and destinations in blocks of 16:
    #   Src 1-16 -> 1-16,  Dst 1-16 -> 17-32,
    #   Src 17-32 -> 33-48, Dst 17-32 -> 49-64, etc.
    $block = [math]::Floor(($Port - 1) / 16)
    $offset = ($Port - 1) % 16
    $idx = $block * 32 + $offset + 1
    if ($PortType.ToUpper() -eq "OUTPUT") { $idx += 16 }
    return $idx
}

# Add dropdown data validation to the New_Color column in an Excel file
function Add-ColorDropdown {
    param(
        [string]$FilePath,
        [string]$Sheet = "Router_Labels"
    )

    try {
        $pkg = Open-ExcelPackage -Path $FilePath
        $ws = $pkg.Workbook.Worksheets[$Sheet]
        if (-not $ws) { Close-ExcelPackage $pkg -NoSave; return }

        # Find the New_Color column header (row 1)
        $colIdx = $null
        for ($c = 1; $c -le $ws.Dimension.End.Column; $c++) {
            if ($ws.Cells[1, $c].Text -eq "New_Color") { $colIdx = $c; break }
        }
        if (-not $colIdx) { Close-ExcelPackage $pkg -NoSave; return }

        # Apply dropdown validation to all data rows
        $lastRow = $ws.Dimension.End.Row
        if ($lastRow -lt 2) { Close-ExcelPackage $pkg -NoSave; return }

        $range = [OfficeOpenXml.ExcelRange]$ws.Cells[2, $colIdx, $lastRow, $colIdx]
        $validation = $ws.DataValidations.AddListValidation($range.Address)
        $validation.ShowErrorMessage = $true
        $validation.ErrorTitle = "Invalid Color"
        $validation.Error = "Please select a color from 1-9."
        $validation.Formula.Values.Add("") | Out-Null
        $validation.Formula.Values.Add("1 - Red") | Out-Null
        $validation.Formula.Values.Add("2 - Orange") | Out-Null
        $validation.Formula.Values.Add("3 - Yellow") | Out-Null
        $validation.Formula.Values.Add("4 - Blue") | Out-Null
        $validation.Formula.Values.Add("5 - Teal") | Out-Null
        $validation.Formula.Values.Add("6 - Light Green") | Out-Null
        $validation.Formula.Values.Add("7 - Indigo") | Out-Null
        $validation.Formula.Values.Add("8 - Purple") | Out-Null
        $validation.Formula.Values.Add("9 - Pink") | Out-Null

        Close-ExcelPackage $pkg
    } catch {
        Write-Warning "Could not add color dropdown: $($_.Exception.Message)"
    }
}

# Helper function to make secure web requests with HTTPS fallback
function Invoke-SecureWebRequest {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Uri,

        [string]$Method = "GET",

        [object]$Body = $null,

        [hashtable]$Headers = @{},

        [int]$TimeoutSec = 10,

        [switch]$UseBasicParsing,

        [switch]$ForceHTTP
    )

    # Try HTTPS first unless ForceHTTP is specified
    if (-not $ForceHTTP) {
        $httpsUri = $Uri -replace "^http://", "https://"
        try {
            $params = @{
                Uri = $httpsUri
                Method = $Method
                TimeoutSec = $TimeoutSec
                UseBasicParsing = $UseBasicParsing
                ErrorAction = "Stop"
            }
            if ($Body) { $params.Body = $Body }
            if ($Headers.Count -gt 0) { $params.Headers = $Headers }

            return Invoke-WebRequest @params
        }
        catch {
            Write-Verbose "HTTPS failed, falling back to HTTP: $_"
        }
    }

    # Fall back to HTTP
    $params = @{
        Uri = $Uri
        Method = $Method
        TimeoutSec = $TimeoutSec
        UseBasicParsing = $UseBasicParsing
        ErrorAction = "Stop"
    }
    if ($Body) { $params.Body = $Body }
    if ($Headers.Count -gt 0) { $params.Headers = $Headers }

    return Invoke-WebRequest @params
}

# ─────────────────────────────────────────────────────────────────────────────
# ROUTER TYPE AUTO-DETECTION
# ─────────────────────────────────────────────────────────────────────────────

# Returns "Videohub", "KUMO", or $null if neither responds
function Resolve-RouterType {
    param([string]$IP)

    # 1. Try Videohub TCP 9990 first (2-second timeout)
    Write-Host "  Probing Videohub TCP 9990..." -ForegroundColor Gray
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $connectTask = $tcpClient.ConnectAsync($IP, 9990)
        if ($connectTask.Wait(2000) -and $tcpClient.Connected) {
            $tcpClient.Close()
            Write-Host "  -> Videohub detected (TCP 9990 responded)" -ForegroundColor Green
            return "Videohub"
        }
    } catch { }
    finally {
        try { if ($tcpClient) { $tcpClient.Close() } } catch { }
    }

    # 2. Try KUMO HTTP
    Write-Host "  Probing KUMO HTTP..." -ForegroundColor Gray
    try {
        $uri = "http://$IP/config?action=get&configid=0&paramid=eParamID_SysName"
        $resp = Invoke-SecureWebRequest -Uri $uri -TimeoutSec 3 -UseBasicParsing -ForceHTTP:$ForceHTTP
        if ($resp.StatusCode -lt 400) {
            Write-Host "  -> KUMO detected (REST API responded)" -ForegroundColor Green
            return "KUMO"
        }
    } catch { }

    return $null
}

# ─────────────────────────────────────────────────────────────────────────────
# CONNECTIVITY TESTS
# ─────────────────────────────────────────────────────────────────────────────

function Test-RouterConnectivity {
    param([string]$IP)

    Write-Host "Testing connection to router at $IP..." -ForegroundColor Yellow

    if ($script:DetectedRouterType -eq "Videohub") {
        return Test-VideohubConnectivity -IP $IP
    } else {
        return Test-KumoConnectivity -IP $IP
    }
}

function Test-KumoConnectivity {
    param([string]$IP)

    Write-Host "Testing connection to KUMO at $IP..." -ForegroundColor Yellow

    # Test web interface (port 80)
    try {
        $response = Invoke-SecureWebRequest -Uri "http://$IP" -TimeoutSec 10 -UseBasicParsing -ForceHTTP:$ForceHTTP
        Write-Host "  OK  Web interface accessible" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "  FAIL  Cannot reach web interface on port 80" -ForegroundColor Red
    }

    # Test telnet port
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.ConnectAsync($IP, 23).Wait(5000)
        if ($tcpClient.Connected) {
            Write-Host "  OK  Telnet port 23 accessible" -ForegroundColor Green
            $tcpClient.Close()
            return $true
        }
    } catch {
        Write-Host "  FAIL  Cannot reach telnet port 23" -ForegroundColor Red
    }

    return $false
}

function Test-VideohubConnectivity {
    param([string]$IP)

    Write-Host "Testing connection to Videohub at $IP..." -ForegroundColor Yellow

    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $connectTask = $tcpClient.ConnectAsync($IP, 9990)
        if ($connectTask.Wait(5000) -and $tcpClient.Connected) {
            Write-Host "  OK  Videohub TCP 9990 accessible" -ForegroundColor Green
            $tcpClient.Close()
            return $true
        }
    } catch { }
    finally {
        try { if ($tcpClient) { $tcpClient.Close() } } catch { }
    }

    Write-Host "  FAIL  Cannot reach Videohub port 9990" -ForegroundColor Red
    return $false
}

# ─────────────────────────────────────────────────────────────────────────────
# VIDEOHUB FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

# Reads the full Videohub state dump and returns a parsed hashtable:
#   .DeviceName, .InputCount, .OutputCount, .InputLabels[], .OutputLabels[]
function Get-VideohubState {
    param([string]$IP)

    $tcpClient = $null
    $stream = $null
    $reader = $null

    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.Connect($IP, 9990)
        $tcpClient.ReceiveTimeout = 4000
        $stream = $tcpClient.GetStream()
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII)

        $state = @{
            DeviceName   = "Videohub"
            InputCount   = 0
            OutputCount  = 0
            InputLabels  = @()
            OutputLabels = @()
            OutputLocks  = @()
        }

        $currentBlock = ""
        $deadline = (Get-Date).AddSeconds(6)

        while ((Get-Date) -lt $deadline) {
            if (-not $stream.DataAvailable) {
                Start-Sleep -Milliseconds 50
                # Once we have filled both label blocks and output locks, stop waiting
                if ($state.InputLabels.Count -gt 0 -and $state.OutputLabels.Count -gt 0 -and $state.OutputLocks.Count -gt 0) { break }
                continue
            }

            $line = $reader.ReadLine()
            if ($null -eq $line) { break }

            $trimmed = $line.Trim()

            # Detect block headers
            if ($trimmed -match "^([\w\s]+):$") {
                $currentBlock = $matches[1].Trim()
                continue
            }

            # Empty line ends a block
            if ($trimmed -eq "") {
                $currentBlock = ""
                continue
            }

            switch ($currentBlock) {
                "VIDEOHUB DEVICE" {
                    if ($trimmed -match "^Device present:\s*(.+)") { }
                    elseif ($trimmed -match "^Model name:\s*(.+)") { $state.DeviceName = $matches[1].Trim() }
                    elseif ($trimmed -match "^Video inputs:\s*(\d+)") { $state.InputCount = [int]$matches[1] }
                    elseif ($trimmed -match "^Video outputs:\s*(\d+)") { $state.OutputCount = [int]$matches[1] }
                }
                "INPUT LABELS" {
                    # Format: "0 Label text"
                    if ($trimmed -match "^(\d+)\s+(.*)$") {
                        $idx = [int]$matches[1]
                        $lbl = $matches[2].Trim()
                        # Expand array if needed
                        while ($state.InputLabels.Count -le $idx) { $state.InputLabels += "" }
                        $state.InputLabels[$idx] = $lbl
                    }
                }
                "OUTPUT LABELS" {
                    if ($trimmed -match "^(\d+)\s+(.*)$") {
                        $idx = [int]$matches[1]
                        $lbl = $matches[2].Trim()
                        while ($state.OutputLabels.Count -le $idx) { $state.OutputLabels += "" }
                        $state.OutputLabels[$idx] = $lbl
                    }
                }
                "VIDEO OUTPUT LOCKS" {
                    # Format: "0 U" or "0 O" or "0 L"
                    if ($trimmed -match "^(\d+)\s+([UOL])$") {
                        $idx = [int]$matches[1]
                        $lockVal = $matches[2]
                        while ($state.OutputLocks.Count -le $idx) { $state.OutputLocks += "U" }
                        $state.OutputLocks[$idx] = $lockVal
                    }
                }
            }
        }

        return $state

    } finally {
        try { if ($reader)    { $reader.Close() }    } catch { }
        try { if ($stream)    { $stream.Close() }    } catch { }
        try { if ($tcpClient) { $tcpClient.Close() } } catch { }
    }
}

function Get-VideohubCurrentLabels {
    param(
        [string]$IP,
        [string]$OutputPath
    )

    Write-Host "Downloading current labels from Videohub at $IP..." -ForegroundColor Yellow
    Write-Host "Connecting TCP 9990..." -ForegroundColor Magenta

    $state = Get-VideohubState -IP $IP

    $allLabels = @()

    Write-Host "  Router: $($state.DeviceName)" -ForegroundColor Green
    Write-Host "  Inputs: $($state.InputCount)  Outputs: $($state.OutputCount)" -ForegroundColor Green

    # Inputs — Videohub 0-based, convert to 1-based for CSV
    $effectiveInputCount = if ($state.InputCount -gt 0) { $state.InputCount } else { $state.InputLabels.Count }
    for ($z = 0; $z -lt $effectiveInputCount; $z++) {
        $port = $z + 1
        $label = if ($z -lt $state.InputLabels.Count -and $state.InputLabels[$z] -ne "") {
            $state.InputLabels[$z]
        } else {
            "Input $port"
        }
        $allLabels += [PSCustomObject]@{
            Port          = $port
            Type          = "INPUT"
            Current_Label = $label
            New_Label     = ""
            Current_Color = 4
            New_Color     = $null
            Lock_Status   = ""
            Notes         = "From $($state.DeviceName) TCP 9990"
        }
        Write-Host "  Input $port`: $label" -ForegroundColor White
    }

    # Outputs
    $effectiveOutputCount = if ($state.OutputCount -gt 0) { $state.OutputCount } else { $state.OutputLabels.Count }
    for ($z = 0; $z -lt $effectiveOutputCount; $z++) {
        $port = $z + 1
        $label = if ($z -lt $state.OutputLabels.Count -and $state.OutputLabels[$z] -ne "") {
            $state.OutputLabels[$z]
        } else {
            "Output $port"
        }
        $lockState = if ($z -lt $state.OutputLocks.Count) { $state.OutputLocks[$z] } else { "U" }
        $allLabels += [PSCustomObject]@{
            Port          = $port
            Type          = "OUTPUT"
            Current_Label = $label
            New_Label     = ""
            Current_Color = 4
            New_Color     = $null
            Lock_Status   = $lockState
            Notes         = "From $($state.DeviceName) TCP 9990"
        }
        $lockDisp = switch ($lockState) { "O" { " [LOCKED]" } "L" { " [LOCKED-OTHER]" } default { "" } }
        Write-Host "  Output $port`: $label$lockDisp" -ForegroundColor White
    }

    if ($allLabels.Count -eq 0) {
        Write-Warning "No labels retrieved. Check that TCP 9990 is reachable and the device is a Videohub."
        return $null
    }

    # Save to file
    Write-Host "`nSaving labels to file..." -ForegroundColor Yellow
    try {
        if ($OutputPath -match "\.xlsx$") {
            if (Get-Module -ListAvailable -Name ImportExcel) {
                Import-Module ImportExcel
                $allLabels | Export-Excel -Path $OutputPath -WorksheetName $WorksheetName -AutoSize -TableStyle Medium6 -FreezeTopRow
                Add-ColorDropdown -FilePath $OutputPath -Sheet $WorksheetName
                Write-Host "  OK  Excel file created: $OutputPath" -ForegroundColor Green
            } else {
                $csvPath = $OutputPath -replace "\.xlsx$", ".csv"
                $allLabels | Export-Csv -Path $csvPath -NoTypeInformation
                Write-Host "  OK  CSV file created (Excel module not available): $csvPath" -ForegroundColor Yellow
                $OutputPath = $csvPath
            }
        } else {
            $allLabels | Export-Csv -Path $OutputPath -NoTypeInformation
            Write-Host "  OK  CSV file created: $OutputPath" -ForegroundColor Green
        }

        Write-Host "`nDownload Summary:" -ForegroundColor Yellow
        Write-Host "  Router: $($state.DeviceName)" -ForegroundColor White
        Write-Host "  Total labels: $($allLabels.Count)" -ForegroundColor White
        Write-Host "  Inputs: $(($allLabels | Where-Object Type -eq 'INPUT').Count)" -ForegroundColor White
        Write-Host "  Outputs: $(($allLabels | Where-Object Type -eq 'OUTPUT').Count)" -ForegroundColor White
        Write-Host "  File: $OutputPath" -ForegroundColor White
        Write-Host "`nNext steps:" -ForegroundColor Yellow
        Write-Host "1. Open the file and edit the 'New_Label' column" -ForegroundColor White
        Write-Host "2. Run update command: .\KUMO-Excel-Updater.ps1 -RouterType Videohub -KumoIP '$IP' -ExcelFile '$OutputPath'" -ForegroundColor White

        return $allLabels

    } catch {
        Write-Error "Failed to save file: $($_.Exception.Message)"
        return $null
    }
}

# Sends INPUT LABELS and OUTPUT LABELS blocks to Videohub over TCP 9990
# LabelData: array of PSCustomObjects with Port (1-based), Type, New_Label
function Update-VideohubLabels {
    param(
        [string]$IP,
        [array]$LabelData
    )

    Write-Host "Updating Videohub labels via TCP 9990..." -ForegroundColor Yellow

    $tcpClient = $null
    $stream    = $null
    $writer    = $null
    $reader    = $null

    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.Connect($IP, 9990)
        $tcpClient.ReceiveTimeout = 5000
        $stream = $tcpClient.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream, [System.Text.Encoding]::ASCII)
        $writer.AutoFlush = $false
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII)

        # Drain the initial state dump (wait up to 3s for it to stop arriving)
        $drain = (Get-Date).AddSeconds(3)
        while ((Get-Date) -lt $drain) {
            if ($stream.DataAvailable) { $reader.ReadLine() | Out-Null; $drain = (Get-Date).AddSeconds(0.5) }
            else { Start-Sleep -Milliseconds 50 }
        }

        $successCount = 0
        $errorCount   = 0

        # Group by type so we send one block per type
        $inputs  = $LabelData | Where-Object { $_.Type.ToUpper() -eq "INPUT" }
        $outputs = $LabelData | Where-Object { $_.Type.ToUpper() -eq "OUTPUT" }

        foreach ($group in @(@{Block="INPUT LABELS:"; Items=$inputs}, @{Block="OUTPUT LABELS:"; Items=$outputs})) {
            if (-not $group.Items -or $group.Items.Count -eq 0) { continue }

            Write-Host "Sending $($group.Block)..." -ForegroundColor Magenta

            $sb = New-Object System.Text.StringBuilder
            $sb.Append("$($group.Block)`n") | Out-Null

            foreach ($item in $group.Items) {
                # Convert 1-based port to 0-based Videohub index
                $idx = $item.Port - 1
                $lbl = $item.New_Label.ToString().Trim()
                Write-Host "  [$($item.Type) $($item.Port)] -> $lbl" -ForegroundColor White
                $sb.Append("$idx $lbl`n") | Out-Null
            }

            # Block must be terminated by a blank line
            $sb.Append("`n") | Out-Null

            $writer.Write($sb.ToString())
            $writer.Flush()

            # Wait for ACK — Videohub replies "ACK\n\n" for valid blocks
            $ackDeadline = (Get-Date).AddSeconds(5)
            $ackReceived = $false
            $response    = ""
            while ((Get-Date) -lt $ackDeadline) {
                if ($stream.DataAvailable) {
                    $line = $reader.ReadLine()
                    $response += $line + "`n"
                    if ($response.Trim() -eq "ACK") { $ackReceived = $true; break }
                } else {
                    Start-Sleep -Milliseconds 100
                }
            }

            if ($ackReceived) {
                Write-Host "  OK  ACK received for $($group.Block)" -ForegroundColor Green
                $successCount += $group.Items.Count
            } else {
                Write-Host "  WARN  No ACK received (response: $($response.Trim()))" -ForegroundColor Yellow
                # Still count as partial — device may not always send ACK on older firmware
                $successCount += $group.Items.Count
            }
        }

        Write-Host "`nVideohub Update Summary:" -ForegroundColor Yellow
        Write-Host "  Labels sent: $successCount" -ForegroundColor Green
        Write-Host "  Errors: $errorCount" -ForegroundColor $(if ($errorCount -gt 0) { "Red" } else { "Green" })

    } catch {
        Write-Error "Videohub TCP connection failed: $($_.Exception.Message)"
    } finally {
        try { if ($writer)    { $writer.Close() }    } catch { }
        try { if ($reader)    { $reader.Close() }    } catch { }
        try { if ($tcpClient) { $tcpClient.Close() } } catch { }
    }
}

# Sets or clears a Videohub output port lock over TCP 9990
function Set-VideohubOutputLock {
    param(
        [string]$IP,
        [int]$Port1Based,  # 1-based port number
        [ValidateSet("O","U")][string]$LockState
    )

    $port0 = $Port1Based - 1
    $tcpClient = $null
    $stream    = $null
    $writer    = $null
    $reader    = $null

    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.Connect($IP, 9990)
        $tcpClient.ReceiveTimeout = 5000
        $stream = $tcpClient.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream, [System.Text.Encoding]::ASCII)
        $writer.AutoFlush = $true
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII)

        # Drain initial state dump
        $drain = (Get-Date).AddSeconds(3)
        while ((Get-Date) -lt $drain) {
            if ($stream.DataAvailable) { $reader.ReadLine() | Out-Null; $drain = (Get-Date).AddSeconds(0.5) }
            else { Start-Sleep -Milliseconds 50 }
        }

        $command = "VIDEO OUTPUT LOCKS:`n$port0 $LockState`n`n"
        $writer.Write($command)

        # Wait for ACK
        $ackDeadline = (Get-Date).AddSeconds(5)
        $ackReceived = $false
        $response    = ""
        while ((Get-Date) -lt $ackDeadline) {
            if ($stream.DataAvailable) {
                $line = $reader.ReadLine()
                $response += $line + "`n"
                if ($response.Trim() -eq "ACK") { $ackReceived = $true; break }
            } else {
                Start-Sleep -Milliseconds 100
            }
        }

        $action = if ($LockState -eq "O") { "locked" } else { "unlocked" }
        if ($ackReceived) {
            Write-Host "  OK  Output $Port1Based $action successfully" -ForegroundColor Green
        } else {
            Write-Host "  Output $Port1Based $action (no ACK received: $($response.Trim()))" -ForegroundColor Yellow
        }

    } catch {
        Write-Error "Videohub lock command failed: $($_.Exception.Message)"
    } finally {
        try { if ($writer)    { $writer.Close() }    } catch { }
        try { if ($reader)    { $reader.Close() }    } catch { }
        try { if ($stream)    { $stream.Close() }    } catch { }
        try { if ($tcpClient) { $tcpClient.Close() } } catch { }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# KUMO FUNCTIONS (unchanged)
# ─────────────────────────────────────────────────────────────────────────────

# Function to download current labels from KUMO
function Get-KumoCurrentLabels {
    param(
        [string]$IP,
        [string]$OutputPath
    )

    Write-Host "Downloading current labels from KUMO at $IP..." -ForegroundColor Yellow

    $allLabels = @()
    $labelsRetrieved = $false

    # Method 1: AJA KUMO REST API (correct /config?action=get&paramid= endpoints)
    Write-Host "Querying KUMO REST API..." -ForegroundColor Magenta

    # Get router name
    try {
        $nameUri = "http://$IP/config?action=get&configid=0&paramid=eParamID_SysName"
        $nameResp = Invoke-SecureWebRequest -Uri $nameUri -TimeoutSec 5 -UseBasicParsing -ForceHTTP:$ForceHTTP
        $nameJson = $nameResp.Content | ConvertFrom-Json
        $routerName = if ($nameJson.value) { $nameJson.value } else { "KUMO" }
        Write-Host "  Router name: $routerName" -ForegroundColor Green
    } catch {
        $routerName = "KUMO"
    }

    # Detect router model using shared function
    $modelInfo = Get-KumoRouterModel -IP $IP
    $inputCount = $modelInfo.InputCount
    $outputCount = $modelInfo.OutputCount
    $modelName = $modelInfo.Model
    $fwInfo = if ($modelInfo.Firmware) { " | FW $($modelInfo.Firmware)" } else { "" }
    Write-Host "  Detected: $modelName `($inputCount in / $outputCount out`)$fwInfo" -ForegroundColor Green

    # Download all labels via parallel REST API requests (runspace pool)
    Write-Host "  Downloading labels in parallel..." -ForegroundColor Cyan
    $maxParallel = 24

    $fetchScript = {
        param([string]$Uri)
        try {
            $r = Invoke-WebRequest -Uri $Uri -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
            $j = $r.Content | ConvertFrom-Json
            if ($j.value_name -and $j.value_name -ne "") { return $j.value_name }
            if ($j.value -and $j.value -ne "") { return $j.value }
            return ""
        } catch { return $null }
    }

    $pool = [RunspaceFactory]::CreateRunspacePool(1, $maxParallel)
    $pool.Open()
    $jobs = [System.Collections.ArrayList]::new()
    $baseUri = "http://$IP/config?action=get&configid=0&paramid="

    # Queue all input + output label requests (Line 1 AND Line 2)
    for ($i = 1; $i -le $inputCount; $i++) {
        $ps1 = [PowerShell]::Create().AddScript($fetchScript).AddArgument("${baseUri}eParamID_XPT_Source${i}_Line_1")
        $ps1.RunspacePool = $pool
        $jobs.Add(@{ PS = $ps1; Handle = $ps1.BeginInvoke(); Port = $i; Type = "INPUT"; Line = 1; Default = "Source $i" }) | Out-Null
        $ps2 = [PowerShell]::Create().AddScript($fetchScript).AddArgument("${baseUri}eParamID_XPT_Source${i}_Line_2")
        $ps2.RunspacePool = $pool
        $jobs.Add(@{ PS = $ps2; Handle = $ps2.BeginInvoke(); Port = $i; Type = "INPUT"; Line = 2; Default = "" }) | Out-Null
    }
    for ($i = 1; $i -le $outputCount; $i++) {
        $ps1 = [PowerShell]::Create().AddScript($fetchScript).AddArgument("${baseUri}eParamID_XPT_Destination${i}_Line_1")
        $ps1.RunspacePool = $pool
        $jobs.Add(@{ PS = $ps1; Handle = $ps1.BeginInvoke(); Port = $i; Type = "OUTPUT"; Line = 1; Default = "Dest $i" }) | Out-Null
        $ps2 = [PowerShell]::Create().AddScript($fetchScript).AddArgument("${baseUri}eParamID_XPT_Destination${i}_Line_2")
        $ps2.RunspacePool = $pool
        $jobs.Add(@{ PS = $ps2; Handle = $ps2.BeginInvoke(); Port = $i; Type = "OUTPUT"; Line = 2; Default = "" }) | Out-Null
    }

    # Collect results into lookup, then build allLabels
    $failCount = 0
    $labelLookup = @{}
    foreach ($job in $jobs) {
        try { $label = $job.PS.EndInvoke($job.Handle) } catch { $label = $null }
        $job.PS.Dispose()

        if ($label -eq $null) { $label = $job.Default; if ($job.Line -eq 1) { $failCount++ } }
        elseif ($label -eq "") { $label = $job.Default }
        else { $labelsRetrieved = $true }

        $labelLookup["$($job.Type)_$($job.Port)_$($job.Line)"] = $label
    }
    $pool.Close(); $pool.Dispose()

    # Download button colors in parallel (KUMO only)
    $colorLookup = @{}
    try {
        Write-Host "  Downloading button colors..." -ForegroundColor Cyan
        $colorPool = [RunspaceFactory]::CreateRunspacePool(1, $maxParallel)
        $colorPool.Open()
        $colorJobs = [System.Collections.ArrayList]::new()

        $colorFetchScript = {
            param([string]$Uri)
            try {
                $r = Invoke-WebRequest -Uri $Uri -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
                $raw = $r.Content
                # Router returns malformed JSON (unescaped inner braces), so try
                # JSON parse first, then fall back to raw regex on the full response
                $j = $null
                try { $j = $raw | ConvertFrom-Json } catch { }
                if ($j) {
                    $val = if ($j.value) { $j.value } else { "" }
                    if ($val -match '"classes"\s*:\s*"color_(\d+)"') {
                        return [int]$matches[1]
                    }
                }
                # Fallback: search raw response text for color_N pattern
                if ($raw -match 'color_(\d+)') {
                    $cid = [int]$matches[1]
                    if ($cid -ge 1 -and $cid -le 9) { return $cid }
                }
                return 4
            } catch { return 4 }
        }

        for ($i = 1; $i -le $inputCount; $i++) {
            $cBtnIdx = Get-ButtonSettingsIndex -Port $i -PortType "INPUT"
            $ps = [PowerShell]::Create().AddScript($colorFetchScript).AddArgument("${baseUri}eParamID_Button_Settings_$cBtnIdx")
            $ps.RunspacePool = $colorPool
            $colorJobs.Add(@{ PS = $ps; Handle = $ps.BeginInvoke(); Port = $i; Type = "INPUT" }) | Out-Null
        }
        for ($i = 1; $i -le $outputCount; $i++) {
            $cBtnIdx = Get-ButtonSettingsIndex -Port $i -PortType "OUTPUT"
            $ps = [PowerShell]::Create().AddScript($colorFetchScript).AddArgument("${baseUri}eParamID_Button_Settings_$cBtnIdx")
            $ps.RunspacePool = $colorPool
            $colorJobs.Add(@{ PS = $ps; Handle = $ps.BeginInvoke(); Port = $i; Type = "OUTPUT" }) | Out-Null
        }

        foreach ($cj in $colorJobs) {
            try { $colorVal = $cj.PS.EndInvoke($cj.Handle) } catch { $colorVal = 4 }
            $cj.PS.Dispose()
            if ($colorVal -is [System.Collections.ObjectModel.Collection[psobject]]) { $colorVal = $colorVal[0] }
            if ($colorVal -lt 1 -or $colorVal -gt 9) { $colorVal = 4 }
            $colorLookup["$($cj.Type)_$($cj.Port)"] = [int]$colorVal
        }
        $colorPool.Close(); $colorPool.Dispose()
        Write-Host "  Downloaded $($colorLookup.Count) button colors" -ForegroundColor Green
    } catch {
        Write-Warning "Color download failed (non-fatal): $($_.Exception.Message)"
    }

    # Build allLabels with both Line 1 and Line 2
    for ($i = 1; $i -le $inputCount; $i++) {
        $l1 = $labelLookup["INPUT_${i}_1"]; $l2 = $labelLookup["INPUT_${i}_2"]
        $curColor = if ($colorLookup.ContainsKey("INPUT_$i")) { $colorLookup["INPUT_$i"] } else { 4 }
        $allLabels += [PSCustomObject]@{
            Port = $i; Type = "INPUT"; Current_Label = $l1; Current_Label_Line2 = $l2
            New_Label = ""; New_Label_Line2 = ""; Current_Color = $curColor; New_Color = $null
            Notes = "From $routerName REST API"
        }
        $line2Disp = if ($l2) { " | $l2" } else { "" }
        Write-Host "  INPUT $i`: $l1$line2Disp" -ForegroundColor White
    }
    for ($i = 1; $i -le $outputCount; $i++) {
        $l1 = $labelLookup["OUTPUT_${i}_1"]; $l2 = $labelLookup["OUTPUT_${i}_2"]
        $curColor = if ($colorLookup.ContainsKey("OUTPUT_$i")) { $colorLookup["OUTPUT_$i"] } else { 4 }
        $allLabels += [PSCustomObject]@{
            Port = $i; Type = "OUTPUT"; Current_Label = $l1; Current_Label_Line2 = $l2
            New_Label = ""; New_Label_Line2 = ""; Current_Color = $curColor; New_Color = $null
            Notes = "From $routerName REST API"
        }
        $line2Disp = if ($l2) { " | $l2" } else { "" }
        Write-Host "  OUTPUT $i`: $l1$line2Disp" -ForegroundColor White
    }

    if ($failCount -gt ($inputCount + $outputCount) / 2) { $labelsRetrieved = $false }

    # Method 3: Try Telnet if REST completely failed
    if (-not $labelsRetrieved -or $allLabels.Count -eq 0) {
        Write-Host "Attempting Telnet method..." -ForegroundColor Magenta

        try {
            $tcpClient = New-Object System.Net.Sockets.TcpClient
            $tcpClient.Connect($IP, 23)
            $stream = $tcpClient.GetStream()
            $writer = New-Object System.IO.StreamWriter($stream)
            $reader = New-Object System.IO.StreamReader($stream)

            Start-Sleep -Seconds 2  # Wait for initial prompt

            # Clear any initial data
            while ($stream.DataAvailable) {
                $reader.ReadLine() | Out-Null
            }

            # Query input labels via Telnet
            for ($i = 1; $i -le $inputCount; $i++) {
                try {
                    $writer.WriteLine("LABEL INPUT $i ?")
                    $writer.Flush()
                    Start-Sleep -Milliseconds 300

                    $response = ""
                    $timeout = 0
                    while (-not $stream.DataAvailable -and $timeout -lt 10) {
                        Start-Sleep -Milliseconds 100
                        $timeout++
                    }

                    if ($stream.DataAvailable) {
                        $response = $reader.ReadLine()
                    }

                    # Parse telnet response - look for quoted label
                    $label = if ($response -and $response -match '"([^"]+)"') {
                        $matches[1]
                    } elseif ($response -and $response -match "Input $i\s+(.+)") {
                        $matches[1].Trim()
                    } else {
                        "Input $i"
                    }

                    $allLabels += [PSCustomObject]@{
                        Port          = $i
                        Type          = "INPUT"
                        Current_Label = $label
                        New_Label     = ""
                        Current_Color = 4
                        New_Color     = $null
                        Notes         = "Retrieved via Telnet"
                    }

                    Write-Host "  Input $i`: $label" -ForegroundColor White

                } catch {
                    $allLabels += [PSCustomObject]@{
                        Port          = $i
                        Type          = "INPUT"
                        Current_Label = "Input $i"
                        New_Label     = ""
                        Current_Color = 4
                        New_Color     = $null
                        Notes         = "Default (telnet query failed)"
                    }
                }
            }

            # Query output labels via Telnet
            for ($i = 1; $i -le $outputCount; $i++) {
                try {
                    $writer.WriteLine("LABEL OUTPUT $i ?")
                    $writer.Flush()
                    Start-Sleep -Milliseconds 300

                    $response = ""
                    $timeout = 0
                    while (-not $stream.DataAvailable -and $timeout -lt 10) {
                        Start-Sleep -Milliseconds 100
                        $timeout++
                    }

                    if ($stream.DataAvailable) {
                        $response = $reader.ReadLine()
                    }

                    # Parse telnet response
                    $label = if ($response -and $response -match '"([^"]+)"') {
                        $matches[1]
                    } elseif ($response -and $response -match "Output $i\s+(.+)") {
                        $matches[1].Trim()
                    } else {
                        "Output $i"
                    }

                    $allLabels += [PSCustomObject]@{
                        Port          = $i
                        Type          = "OUTPUT"
                        Current_Label = $label
                        New_Label     = ""
                        Current_Color = 4
                        New_Color     = $null
                        Notes         = "Retrieved via Telnet"
                    }

                    Write-Host "  Output $i`: $label" -ForegroundColor White

                } catch {
                    $allLabels += [PSCustomObject]@{
                        Port          = $i
                        Type          = "OUTPUT"
                        Current_Label = "Output $i"
                        New_Label     = ""
                        Current_Color = 4
                        New_Color     = $null
                        Notes         = "Default (telnet query failed)"
                    }
                }
            }

            $labelsRetrieved = $true

        } catch {
            Write-Warning "Telnet method failed: $($_.Exception.Message)"
        } finally {
            try { if ($writer) { $writer.Close() } } catch {}
            try { if ($reader) { $reader.Close() } } catch {}
            try { if ($tcpClient) { $tcpClient.Close() } } catch {}
        }
    }

    # If everything failed, create default template
    if ($allLabels.Count -eq 0) {
        Write-Warning "All download methods failed. Creating default template..."

        for ($i = 1; $i -le $inputCount; $i++) {
            $allLabels += [PSCustomObject]@{
                Port          = $i
                Type          = "INPUT"
                Current_Label = "Input $i"
                New_Label     = ""
                Current_Color = 4
                New_Color     = $null
                Notes         = "Default (download failed)"
            }
        }

        for ($i = 1; $i -le $outputCount; $i++) {
            $allLabels += [PSCustomObject]@{
                Port          = $i
                Type          = "OUTPUT"
                Current_Label = "Output $i"
                New_Label     = ""
                Current_Color = 4
                New_Color     = $null
                Notes         = "Default (download failed)"
            }
        }
    }

    # Save to file
    Write-Host "`nSaving labels to file..." -ForegroundColor Yellow

    try {
        if ($OutputPath -match "\.xlsx$") {
            # Try Excel export
            if (Get-Module -ListAvailable -Name ImportExcel) {
                Import-Module ImportExcel
                $allLabels | Export-Excel -Path $OutputPath -WorksheetName $WorksheetName -AutoSize -TableStyle Medium6 -FreezeTopRow
                Add-ColorDropdown -FilePath $OutputPath -Sheet $WorksheetName
                Write-Host "  OK  Excel file created: $OutputPath" -ForegroundColor Green
            } else {
                # Fallback to CSV
                $csvPath = $OutputPath -replace "\.xlsx$", ".csv"
                $allLabels | Export-Csv -Path $csvPath -NoTypeInformation
                Write-Host "  OK  CSV file created (Excel module not available): $csvPath" -ForegroundColor Yellow
                $OutputPath = $csvPath
            }
        } else {
            # CSV export
            $allLabels | Export-Csv -Path $OutputPath -NoTypeInformation
            Write-Host "  OK  CSV file created: $OutputPath" -ForegroundColor Green
        }

        Write-Host "`nDownload Summary:" -ForegroundColor Yellow
        Write-Host "  Total labels: $($allLabels.Count)" -ForegroundColor White
        Write-Host "  Inputs: $(($allLabels | Where-Object Type -eq 'INPUT').Count)" -ForegroundColor White
        Write-Host "  Outputs: $(($allLabels | Where-Object Type -eq 'OUTPUT').Count)" -ForegroundColor White
        Write-Host "  File: $OutputPath" -ForegroundColor White
        Write-Host "`nNext steps:" -ForegroundColor Yellow
        Write-Host "1. Open the file and edit the 'New_Label' column" -ForegroundColor White
        Write-Host "2. Run update command: .\KUMO-Excel-Updater.ps1 -KumoIP '$IP' -ExcelFile '$OutputPath'" -ForegroundColor White

        return $allLabels

    } catch {
        Write-Error "Failed to save file: $($_.Exception.Message)"
        return $null
    }
}

# Function to detect KUMO router model from port probing
function Get-KumoRouterModel {
    param([string]$IP)

    $inputCount = 32
    $outputCount = 32
    $modelName = "KUMO 3232"
    $firmware = ""

    # Get firmware version
    try {
        $fwUri = "http://$IP/config?action=get&configid=0&paramid=eParamID_SWVersion"
        $fwResp = Invoke-SecureWebRequest -Uri $fwUri -TimeoutSec 5 -UseBasicParsing -ForceHTTP:$ForceHTTP
        $fwJson = $fwResp.Content | ConvertFrom-Json
        if ($fwJson.value) { $firmware = $fwJson.value }
    } catch { }

    # Probe Source33 for 64-port router
    try {
        $uri = "http://$IP/config?action=get&configid=0&paramid=eParamID_XPT_Source33_Line_1"
        $resp = Invoke-SecureWebRequest -Uri $uri -TimeoutSec 3 -UseBasicParsing -ForceHTTP:$ForceHTTP
        $json = $resp.Content | ConvertFrom-Json
        if ($json.value -ne $null -and $json.value -ne "") {
            $inputCount = 64; $outputCount = 64
        }
    } catch { }

    if ($inputCount -lt 64) {
        # Probe Source17 for 32-port vs 16-port
        try {
            $uri = "http://$IP/config?action=get&configid=0&paramid=eParamID_XPT_Source17_Line_1"
            $resp = Invoke-SecureWebRequest -Uri $uri -TimeoutSec 3 -UseBasicParsing -ForceHTTP:$ForceHTTP
            $json = $resp.Content | ConvertFrom-Json
            if ($json.value -eq $null -or $json.value -eq "") {
                $inputCount = 16; $outputCount = 16
            }
        } catch {
            $inputCount = 16; $outputCount = 16
        }
    }

    # For 16-input routers, differentiate KUMO 1604 (4 outputs) vs KUMO 1616 (16 outputs)
    if ($inputCount -eq 16) {
        try {
            $uri = "http://$IP/config?action=get&configid=0&paramid=eParamID_XPT_Destination5_Line_1"
            $resp = Invoke-SecureWebRequest -Uri $uri -TimeoutSec 3 -UseBasicParsing -ForceHTTP:$ForceHTTP
            $json = $resp.Content | ConvertFrom-Json
            if ($json.value -eq $null -or $json.value -eq "") {
                $outputCount = 4  # Only 4 outputs = KUMO 1604
            }
        } catch {
            $outputCount = 4  # If probe fails assume smaller model
        }
    }

    # Determine model name
    $modelName = switch ("$inputCount`x$outputCount") {
        "16x4"  { "KUMO 1604" }
        "16x16" { "KUMO 1616" }
        "32x32" { "KUMO 3232" }
        "64x64" { "KUMO 6464" }
        default { "KUMO ${inputCount}x${outputCount}" }
    }

    return @{
        Model       = $modelName
        InputCount  = $inputCount
        OutputCount = $outputCount
        Firmware    = $firmware
    }
}

# Function to create Excel template
function New-RouterLabelTemplate {
    param(
        [string]$FilePath,
        [string]$RouterIP = ""
    )

    $inputCount = 32
    $outputCount = 32
    $modelName = ""
    $currentLabels = @{}  # Hash of "TYPE_PORT" -> label
    $currentLabelsLine2 = @{}  # Hash of "TYPE_PORT" -> line 2 label

    # If IP provided, auto-detect router type and download current labels
    if ($RouterIP -and $RouterIP -ne "") {

        if ($script:DetectedRouterType -eq "Videohub") {
            Write-Host "Connecting to Videohub at $RouterIP to read current labels..." -ForegroundColor Magenta
            $vhState = Get-VideohubState -IP $RouterIP
            $inputCount  = if ($vhState.InputCount  -gt 0) { $vhState.InputCount  } else { $vhState.InputLabels.Count }
            $outputCount = if ($vhState.OutputCount -gt 0) { $vhState.OutputCount } else { $vhState.OutputLabels.Count }
            $modelName   = $vhState.DeviceName
            Write-Host "  Detected: $modelName ($inputCount in / $outputCount out)" -ForegroundColor Green

            for ($z = 0; $z -lt $vhState.InputLabels.Count; $z++) {
                if ($vhState.InputLabels[$z] -ne "") { $currentLabels["INPUT_$($z+1)"] = $vhState.InputLabels[$z] }
            }
            for ($z = 0; $z -lt $vhState.OutputLabels.Count; $z++) {
                if ($vhState.OutputLabels[$z] -ne "") { $currentLabels["OUTPUT_$($z+1)"] = $vhState.OutputLabels[$z] }
            }

        } else {
            Write-Host "Connecting to KUMO at $RouterIP to auto-detect model..." -ForegroundColor Magenta

            $modelInfo   = Get-KumoRouterModel -IP $RouterIP
            $inputCount  = $modelInfo.InputCount
            $outputCount = $modelInfo.OutputCount
            $modelName   = $modelInfo.Model
            $fwVersion   = $modelInfo.Firmware

            Write-Host "  Detected: $modelName ($inputCount in / $outputCount out)" -ForegroundColor Green
            if ($fwVersion) { Write-Host "  Firmware: $fwVersion" -ForegroundColor Green }

            Write-Host "Downloading current labels (Line 1 & Line 2)..." -ForegroundColor Magenta
            $currentLabelsLine2 = @{}
            for ($i = 1; $i -le $inputCount; $i++) {
                try {
                    $uri  = "http://$RouterIP/config?action=get&configid=0&paramid=eParamID_XPT_Source${i}_Line_1"
                    $resp = Invoke-SecureWebRequest -Uri $uri -TimeoutSec 5 -UseBasicParsing -ForceHTTP:$ForceHTTP
                    $json = $resp.Content | ConvertFrom-Json
                    $lbl  = if ($json.value_name -and $json.value_name -ne "") { $json.value_name }
                            elseif ($json.value -and $json.value -ne "")      { $json.value }
                            else { $null }
                    if ($lbl) { $currentLabels["INPUT_$i"] = $lbl }
                } catch { }
                try {
                    $uri2  = "http://$RouterIP/config?action=get&configid=0&paramid=eParamID_XPT_Source${i}_Line_2"
                    $resp2 = Invoke-SecureWebRequest -Uri $uri2 -TimeoutSec 5 -UseBasicParsing -ForceHTTP:$ForceHTTP
                    $json2 = $resp2.Content | ConvertFrom-Json
                    $lbl2  = if ($json2.value_name -and $json2.value_name -ne "") { $json2.value_name }
                             elseif ($json2.value -and $json2.value -ne "")      { $json2.value }
                             else { $null }
                    if ($lbl2) { $currentLabelsLine2["INPUT_$i"] = $lbl2 }
                } catch { }
            }
            for ($i = 1; $i -le $outputCount; $i++) {
                try {
                    $uri  = "http://$RouterIP/config?action=get&configid=0&paramid=eParamID_XPT_Destination${i}_Line_1"
                    $resp = Invoke-SecureWebRequest -Uri $uri -TimeoutSec 5 -UseBasicParsing -ForceHTTP:$ForceHTTP
                    $json = $resp.Content | ConvertFrom-Json
                    $lbl  = if ($json.value_name -and $json.value_name -ne "") { $json.value_name }
                            elseif ($json.value -and $json.value -ne "")      { $json.value }
                            else { $null }
                    if ($lbl) { $currentLabels["OUTPUT_$i"] = $lbl }
                } catch { }
                try {
                    $uri2  = "http://$RouterIP/config?action=get&configid=0&paramid=eParamID_XPT_Destination${i}_Line_2"
                    $resp2 = Invoke-SecureWebRequest -Uri $uri2 -TimeoutSec 5 -UseBasicParsing -ForceHTTP:$ForceHTTP
                    $json2 = $resp2.Content | ConvertFrom-Json
                    $lbl2  = if ($json2.value_name -and $json2.value_name -ne "") { $json2.value_name }
                             elseif ($json2.value -and $json2.value -ne "")      { $json2.value }
                             else { $null }
                    if ($lbl2) { $currentLabelsLine2["OUTPUT_$i"] = $lbl2 }
                } catch { }
            }
            Write-Host "  Downloaded $($currentLabels.Count) Line 1 + $($currentLabelsLine2.Count) Line 2 labels from router" -ForegroundColor Green
        }

    } else {
        # No IP provided — ask user to choose router model
        Write-Host ""
        Write-Host "No router IP provided. Choose your router model:" -ForegroundColor Yellow
        Write-Host "  1. KUMO 1604         (16 inputs /  4 outputs)" -ForegroundColor White
        Write-Host "  2. KUMO 1616         (16 inputs / 16 outputs)" -ForegroundColor White
        Write-Host "  3. KUMO 3232         (32 inputs / 32 outputs)" -ForegroundColor White
        Write-Host "  4. KUMO 6464         (64 inputs / 64 outputs)" -ForegroundColor White
        Write-Host "  5. Videohub 12x12    (12 inputs / 12 outputs)" -ForegroundColor White
        Write-Host "  6. Videohub 40x40    (40 inputs / 40 outputs)" -ForegroundColor White
        Write-Host "  7. Custom size" -ForegroundColor White
        $choice = Read-Host "Enter choice (1-7, default 3)"
        switch ($choice) {
            "1" { $inputCount = 16; $outputCount = 4;  $modelName = "KUMO 1604" }
            "2" { $inputCount = 16; $outputCount = 16; $modelName = "KUMO 1616" }
            "3" { $inputCount = 32; $outputCount = 32; $modelName = "KUMO 3232" }
            "4" { $inputCount = 64; $outputCount = 64; $modelName = "KUMO 6464" }
            "5" { $inputCount = 12; $outputCount = 12; $modelName = "Videohub 12x12" }
            "6" { $inputCount = 40; $outputCount = 40; $modelName = "Videohub 40x40" }
            "7" {
                $inputCount  = [int](Read-Host "Input count")
                $outputCount = [int](Read-Host "Output count")
                $modelName   = "Custom ${inputCount}x${outputCount}"
            }
            default { $inputCount = 32; $outputCount = 32; $modelName = "KUMO 3232" }
        }
        Write-Host "  Creating template for: $modelName ($inputCount in / $outputCount out)" -ForegroundColor Green
    }

    Write-Host "Creating $modelName Label Template..." -ForegroundColor Green

    $templateData = @()

    for ($i = 1; $i -le $inputCount; $i++) {
        $curLabel = if ($currentLabels.ContainsKey("INPUT_$i")) { $currentLabels["INPUT_$i"] } else { "Input $i" }
        $curLine2 = if ($currentLabelsLine2 -and $currentLabelsLine2.ContainsKey("INPUT_$i")) { $currentLabelsLine2["INPUT_$i"] } else { "" }
        $templateData += [PSCustomObject]@{
            Port                = $i
            Type                = "INPUT"
            Current_Label       = $curLabel
            Current_Label_Line2 = $curLine2
            New_Label           = ""
            New_Label_Line2     = ""
            Current_Color       = 4
            New_Color           = ""
            Notes               = "Enter your desired label"
        }
    }

    for ($i = 1; $i -le $outputCount; $i++) {
        $curLabel = if ($currentLabels.ContainsKey("OUTPUT_$i")) { $currentLabels["OUTPUT_$i"] } else { "Output $i" }
        $curLine2 = if ($currentLabelsLine2 -and $currentLabelsLine2.ContainsKey("OUTPUT_$i")) { $currentLabelsLine2["OUTPUT_$i"] } else { "" }
        $templateData += [PSCustomObject]@{
            Port                = $i
            Type                = "OUTPUT"
            Current_Label       = $curLabel
            Current_Label_Line2 = $curLine2
            New_Label           = ""
            New_Label_Line2     = ""
            Current_Color       = 4
            New_Color           = ""
            Notes               = "Enter your desired label"
        }
    }

    # Export to Excel (requires ImportExcel module)
    try {
        if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
            Write-Warning "ImportExcel module not found. Installing..."
            Install-Module ImportExcel -Scope CurrentUser -Force
        }

        Import-Module ImportExcel
        $templateData | Export-Excel -Path $FilePath -WorksheetName $WorksheetName -AutoSize -TableStyle Medium6 -FreezeTopRow
        Add-ColorDropdown -FilePath $FilePath -Sheet $WorksheetName

        Write-Host "`nTemplate created: $FilePath" -ForegroundColor Green
        Write-Host "  Model: $modelName ($inputCount inputs / $outputCount outputs)" -ForegroundColor White
        Write-Host "  Total rows: $($templateData.Count)" -ForegroundColor White
        Write-Host "`nInstructions:" -ForegroundColor Yellow
        Write-Host "1. Open the Excel file" -ForegroundColor White
        Write-Host "2. Fill in the 'New_Label' column with your desired names" -ForegroundColor White
        Write-Host "3. Leave New_Label blank for ports you don't want to change" -ForegroundColor White
        Write-Host "4. Save the file" -ForegroundColor White
        Write-Host "5. Upload: .\KUMO-Excel-Updater.ps1 -KumoIP '<IP>' -ExcelFile '$FilePath'" -ForegroundColor White

    } catch {
        Write-Error "Failed to create Excel template: $($_.Exception.Message)"

        # Fallback: Create CSV template
        $csvPath = $FilePath -replace "\.xlsx$", ".csv"
        $templateData | Export-Csv -Path $csvPath -NoTypeInformation
        Write-Host "Created CSV template instead: $csvPath" -ForegroundColor Yellow
    }
}

# Alias for backward compatibility
function New-KumoLabelTemplate {
    param([string]$FilePath, [string]$KumoIP = "")
    New-RouterLabelTemplate -FilePath $FilePath -RouterIP $KumoIP
}

# Function to load Excel data
function Get-ExcelLabelData {
    param(
        [string]$FilePath,
        [string]$WorksheetName
    )

    Write-Host "Loading label data from $FilePath..." -ForegroundColor Yellow

    try {
        if (Get-Module -ListAvailable -Name ImportExcel) {
            Import-Module ImportExcel
            $data = Import-Excel -Path $FilePath -WorksheetName $WorksheetName
        } else {
            # Try CSV as fallback
            if ($FilePath -match "\.csv$") {
                $data = Import-Csv -Path $FilePath
            } else {
                throw "ImportExcel module required for .xlsx files. Install with: Install-Module ImportExcel"
            }
        }

        # Normalize New_Color dropdown values ("3 - Yellow" -> "3")
        foreach ($row in $data) {
            if ($row.PSObject.Properties.Name -contains "New_Color" -and $row.New_Color) {
                $raw = $row.New_Color.ToString().Trim()
                if ($raw -match '^\s*(\d)\s*[-–]\s*\w') { $row.New_Color = $matches[1] }
            }
        }

        # Filter for rows with new labels (Line 1, Line 2, or Color)
        $filteredData = $data | Where-Object {
            ($_.New_Label -and
             $_.New_Label.ToString().Trim() -ne "" -and
             $_.New_Label -ne $_.Current_Label) -or
            ($_.PSObject.Properties.Name -contains "New_Label_Line2" -and
             $_.New_Label_Line2 -and
             $_.New_Label_Line2.ToString().Trim() -ne "" -and
             $_.New_Label_Line2 -ne $_.Current_Label_Line2) -or
            ($_.PSObject.Properties.Name -contains "New_Color" -and
             $_.New_Color -ne $null -and
             $_.New_Color.ToString().Trim() -ne "" -and
             $_.New_Color.ToString() -ne $_.Current_Color.ToString())
        }

        Write-Host "Found $($filteredData.Count) labels to update" -ForegroundColor Green
        return $filteredData

    } catch {
        Write-Error "Failed to load label data: $($_.Exception.Message)"
        return $null
    }
}

# Function to update KUMO labels via REST API
function Update-KumoLabelsREST {
    param(
        [string]$IP,
        [array]$LabelData
    )

    Write-Host "Updating KUMO labels via REST API..." -ForegroundColor Yellow
    Write-Host "Using AJA KUMO /config?action=set endpoint" -ForegroundColor Gray

    $successCount = 0
    $errorCount = 0

    foreach ($item in $LabelData) {
        # Upload Line 1 if changed
        if ($item.New_Label -and $item.New_Label.ToString().Trim() -ne "" -and $item.New_Label -ne $item.Current_Label) {
            try {
                Write-Host "Updating $($item.Type) $($item.Port) Line 1: $($item.New_Label)" -ForegroundColor Magenta

                $paramId = if ($item.Type.ToUpper() -eq "INPUT") {
                    "eParamID_XPT_Source$($item.Port)_Line_1"
                } else {
                    "eParamID_XPT_Destination$($item.Port)_Line_1"
                }

                $encoded = [System.Uri]::EscapeDataString($item.New_Label.ToString())
                $uri = "http://$IP/config?action=set&configid=0&paramid=$paramId&value=$encoded"

                try {
                    $response = Invoke-SecureWebRequest -Uri $uri -TimeoutSec 5 -UseBasicParsing -ForceHTTP:$ForceHTTP
                    $successCount++
                    Write-Host "  OK  Success" -ForegroundColor Green
                } catch {
                    throw "REST API set failed: $($_.Exception.Message)"
                }

            } catch {
                $errorCount++
                Write-Host "  FAIL  $($_.Exception.Message)" -ForegroundColor Red
            }
        }

        # Upload Line 2 if changed
        $hasLine2 = $item.PSObject.Properties.Name -contains "New_Label_Line2"
        if ($hasLine2 -and $item.New_Label_Line2 -and $item.New_Label_Line2.ToString().Trim() -ne "" -and $item.New_Label_Line2 -ne $item.Current_Label_Line2) {
            try {
                Write-Host "Updating $($item.Type) $($item.Port) Line 2: $($item.New_Label_Line2)" -ForegroundColor Magenta

                $paramId2 = if ($item.Type.ToUpper() -eq "INPUT") {
                    "eParamID_XPT_Source$($item.Port)_Line_2"
                } else {
                    "eParamID_XPT_Destination$($item.Port)_Line_2"
                }

                $encoded2 = [System.Uri]::EscapeDataString($item.New_Label_Line2.ToString())
                $uri2 = "http://$IP/config?action=set&configid=0&paramid=$paramId2&value=$encoded2"

                try {
                    $response = Invoke-SecureWebRequest -Uri $uri2 -TimeoutSec 5 -UseBasicParsing -ForceHTTP:$ForceHTTP
                    $successCount++
                    Write-Host "  OK  Success" -ForegroundColor Green
                } catch {
                    throw "REST API set Line 2 failed: $($_.Exception.Message)"
                }

            } catch {
                $errorCount++
                Write-Host "  FAIL  $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }

    # Upload changed button colors (KUMO only)
    $colorChangeCount = 0
    foreach ($item in $LabelData) {
        $hasNewColor = $item.PSObject.Properties.Name -contains "New_Color"
        if ($hasNewColor -and $item.New_Color -ne $null -and $item.New_Color.ToString().Trim() -ne "") {
            $newColorId = [int]$item.New_Color
            $curColorId = if ($item.PSObject.Properties.Name -contains "Current_Color" -and $item.Current_Color) { [int]$item.Current_Color } else { 4 }
            if ($newColorId -ne $curColorId -and $newColorId -ge 1 -and $newColorId -le 9) {
                try {
                    $btnIdx = Get-ButtonSettingsIndex -Port ([int]$item.Port) -PortType $item.Type
                    $colorJson = "{\`"classes\`":\`"color_$newColorId\`"}"
                    $encodedColor = [System.Uri]::EscapeDataString($colorJson)
                    $colorUri = "http://$IP/config?action=set&configid=0&paramid=eParamID_Button_Settings_$btnIdx&value=$encodedColor"

                    Write-Host "  Setting $($item.Type) $($item.Port) color -> $newColorId" -ForegroundColor Magenta
                    $response = Invoke-SecureWebRequest -Uri $colorUri -TimeoutSec 5 -UseBasicParsing -ForceHTTP:$ForceHTTP
                    $colorChangeCount++
                    Write-Host "  OK  Color set" -ForegroundColor Green
                } catch {
                    Write-Host "  FAIL  Color set failed: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
    }

    Write-Host "`nUpdate Summary:" -ForegroundColor Yellow
    Write-Host "  Labels: $successCount" -ForegroundColor Green
    if ($colorChangeCount -gt 0) { Write-Host "  Colors: $colorChangeCount" -ForegroundColor Green }
    Write-Host "  Errors: $errorCount" -ForegroundColor Red

    # If all REST updates failed, throw so caller can fall back to Telnet
    if ($successCount -eq 0 -and $errorCount -gt 0 -and $colorChangeCount -eq 0) {
        throw "All REST API updates failed ($errorCount errors)"
    }
}

# Function to update KUMO labels via Telnet
function Update-KumoLabelsTelnet {
    param(
        [string]$IP,
        [array]$LabelData
    )

    Write-Host "Updating KUMO labels via Telnet..." -ForegroundColor Yellow

    try {
        # Create telnet client
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.Connect($IP, 23)
        $stream = $tcpClient.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $reader = New-Object System.IO.StreamReader($stream)

        # Wait for initial prompt
        Start-Sleep -Seconds 2

        $successCount = 0
        foreach ($item in $LabelData) {
            try {
                # Validate Telnet command parameters
                $validTypes = @("INPUT", "OUTPUT")
                if ($item.Type.ToUpper() -notin $validTypes) {
                    Write-ErrorLog "WARN" "Invalid port type '$($item.Type)' for port $($item.Port) — skipping"
                    continue
                }
                if ($item.Port -lt 1 -or $item.Port -gt 256) {
                    Write-ErrorLog "WARN" "Invalid port number '$($item.Port)' — skipping"
                    continue
                }

                $command = "LABEL $($item.Type) $($item.Port) `"$($item.New_Label)`""
                Write-Host "Sending: $command" -ForegroundColor Magenta

                $writer.WriteLine($command)
                $writer.Flush()
                Start-Sleep -Milliseconds 500

                $successCount++
                Write-Host "  OK  Success" -ForegroundColor Green

            } catch {
                Write-Host "  FAIL  $($_.Exception.Message)" -ForegroundColor Red
            }
        }

        # Save configuration
        $writer.WriteLine("SAVE")
        $writer.Flush()
        Start-Sleep -Seconds 2

        Write-Host "`nTelnet Update Complete: $successCount labels updated" -ForegroundColor Green

    } catch {
        Write-Error "Telnet connection failed: $($_.Exception.Message)"
    } finally {
        # Cleanup resources
        try { if ($writer) { $writer.Close() } } catch {}
        try { if ($reader) { $reader.Close() } } catch {}
        try { if ($tcpClient) { $tcpClient.Close() } } catch {}
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN EXECUTION
# ─────────────────────────────────────────────────────────────────────────────

Write-Host "Router Label Updater" -ForegroundColor Magenta
Write-Host "====================" -ForegroundColor Magenta
Write-Host "AJA KUMO (REST/Telnet) and Blackmagic Videohub (TCP 9990)" -ForegroundColor Gray
Write-Host ""

# Handle lock/unlock output port (Videohub only)
if ($LockOutput -or $UnlockOutput) {
    if ($LockOutput -and $UnlockOutput) {
        Write-Error "Cannot specify both -LockOutput and -UnlockOutput at the same time."
        exit 1
    }
    if ($OutputPort -lt 1) {
        Write-Error "You must specify -OutputPort (1-based port number) for lock operations."
        exit 1
    }
    $ipList = Parse-IPList -IPString $KumoIP
    if ($ipList.Count -eq 0) {
        Write-Error "No valid IP addresses provided."
        exit 1
    }
    $ip = $ipList[0]

    # Auto-detect router type
    $script:DetectedRouterType = $RouterType
    if ($RouterType -eq "Auto") {
        Write-Host "Auto-detecting router type at $ip..." -ForegroundColor Yellow
        $detected = Resolve-RouterType -IP $ip
        if (-not $detected) {
            Write-Error "Could not detect router type at $ip"
            exit 1
        }
        $script:DetectedRouterType = $detected
    }

    if ($script:DetectedRouterType -ne "Videohub") {
        Write-Error "Output lock commands are only supported on Blackmagic Videohub routers."
        exit 1
    }

    $lockState = if ($LockOutput) { "O" } else { "U" }
    $action    = if ($LockOutput) { "Locking" } else { "Unlocking" }
    Write-Host "$action output port $OutputPort on Videohub at $ip..." -ForegroundColor Yellow

    Set-VideohubOutputLock -IP $ip -Port1Based $OutputPort -LockState $lockState
    exit 0
}

# Handle download labels
if ($DownloadLabels) {
    $ipList = Parse-IPList -IPString $KumoIP
    if ($ipList.Count -eq 0) {
        Write-Error "No valid IP addresses provided."
        exit 1
    }

    $docsDir = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "Router_Labels"
    if (-not (Test-Path $docsDir)) { New-Item -ItemType Directory -Path $docsDir -Force | Out-Null }

    $multi = ($ipList.Count -gt 1)
    $anySuccess = $false

    foreach ($ip in $ipList) {
        Write-Host "`n--- Router: $ip ---" -ForegroundColor Cyan

        # Ping check: 4 attempts, skip to next IP if all fail
        $pingOk = $false
        for ($pa = 1; $pa -le 4; $pa++) {
            Write-Host "  Pinging $ip ($pa/4)..." -ForegroundColor DarkGray -NoNewline
            try {
                if (Test-Connection -ComputerName $ip -Count 1 -Quiet -ErrorAction SilentlyContinue) {
                    Write-Host " OK" -ForegroundColor Green
                    $pingOk = $true; break
                }
            } catch { }
            Write-Host " no response" -ForegroundColor Yellow
        }
        if (-not $pingOk) {
            Write-Warning "No response from $ip after 4 pings -- skipping."
            continue
        }

        # Determine output path per router
        if ($DownloadPath) {
            if ($multi) {
                $ext = [System.IO.Path]::GetExtension($DownloadPath)
                $base = [System.IO.Path]::GetFileNameWithoutExtension($DownloadPath)
                $dir = [System.IO.Path]::GetDirectoryName($DownloadPath)
                if (-not $dir) { $dir = "." }
                $outPath = Join-Path $dir "${base}_${ip}${ext}"
            } else {
                $outPath = $DownloadPath
            }
        } else {
            if ($multi) {
                $outPath = Join-Path $docsDir "Router_Labels_${ip}_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"
            } else {
                $outPath = Join-Path $docsDir "Router_Labels_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"
            }
            Write-Host "Saving to: $outPath" -ForegroundColor Magenta
        }

        # Auto-detect router type
        $script:DetectedRouterType = $RouterType
        if ($RouterType -eq "Auto") {
            Write-Host "Auto-detecting router type at $ip..." -ForegroundColor Yellow
            $detected = Resolve-RouterType -IP $ip
            if (-not $detected) {
                Write-Warning "Could not detect router type at $ip -- skipping."
                continue
            }
            $script:DetectedRouterType = $detected
        }

        if (-not (Test-RouterConnectivity -IP $ip)) {
            Write-Warning "Cannot connect to router at $ip -- skipping."
            continue
        }

        if ($script:DetectedRouterType -eq "Videohub") {
            $downloadedLabels = Get-VideohubCurrentLabels -IP $ip -OutputPath $outPath
        } else {
            $downloadedLabels = Get-KumoCurrentLabels -IP $ip -OutputPath $outPath
        }

        if ($downloadedLabels -and $downloadedLabels.Count -gt 0) {
            Write-Host "  OK  Labels downloaded from $ip!" -ForegroundColor Green
            $anySuccess = $true
        } else {
            Write-Warning "Failed to download labels from $ip"
        }
    }

    if ($anySuccess) {
        Write-Host "`n  OK  Download complete!" -ForegroundColor Green
    } else {
        Write-Error "Failed to download labels from any router"
        exit 1
    }

    exit 0
}

# Handle template creation
if ($CreateTemplate) {
    $docsDir = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "Router_Labels"
    if (-not (Test-Path $docsDir)) { New-Item -ItemType Directory -Path $docsDir -Force | Out-Null }
    $defaultPath = Join-Path $docsDir "Router_Template_$(Get-Date -Format 'yyyyMMdd_HHmm').xlsx"

    $templatePath = Read-Host "Enter template file path (default: $defaultPath)"
    if (-not $templatePath -or $templatePath.Trim() -eq "") { $templatePath = $defaultPath }

    $templateIP = ""
    if ($KumoIP) {
        $templateIP = $KumoIP
        # Auto-detect type for template generation
        if ($RouterType -eq "Auto") {
            Write-Host "Auto-detecting router type at $templateIP..." -ForegroundColor Yellow
            $detected = Resolve-RouterType -IP $templateIP
            if ($detected) { $script:DetectedRouterType = $detected }
        }
    } else {
        $useRouter = Read-Host "Connect to a router to auto-detect model and download current labels? (y/N)"
        if ($useRouter -eq 'y' -or $useRouter -eq 'Y') {
            $templateIP = Read-Host "Enter router IP address"
            Write-Host "Auto-detecting router type at $templateIP..." -ForegroundColor Yellow
            $detected = Resolve-RouterType -IP $templateIP
            if ($detected) { $script:DetectedRouterType = $detected }
        }
    }

    New-RouterLabelTemplate -FilePath $templatePath -RouterIP $templateIP
    exit
}

# Validate parameters for update operations
if (-not $DownloadLabels -and -not $CreateTemplate) {
    if (-not $ExcelFile) {
        Write-Error "ExcelFile parameter is required for update operations"
        Write-Host "Usage examples:" -ForegroundColor Yellow
        Write-Host "  Download: .\KUMO-Excel-Updater.ps1 -DownloadLabels -KumoIP '192.168.100.51,192.168.100.52'" -ForegroundColor White
        Write-Host "  Update:   .\KUMO-Excel-Updater.ps1 -KumoIP '192.168.100.51' -ExcelFile 'labels.xlsx'" -ForegroundColor White
        Write-Host "  Multi:    .\KUMO-Excel-Updater.ps1 -KumoIP '192.168.100.51,192.168.100.52' -ExcelFile 'labels.xlsx'" -ForegroundColor White
        Write-Host "  Template: .\KUMO-Excel-Updater.ps1 -CreateTemplate" -ForegroundColor White
        exit 1
    }
}

if ($ExcelFile -and -not (Test-Path $ExcelFile)) {
    Write-Error "File not found: $ExcelFile"
    exit 1
}

# Load label data (once, shared across routers)
$labelData = Get-ExcelLabelData -FilePath $ExcelFile -WorksheetName $WorksheetName
if (-not $labelData -or $labelData.Count -eq 0) {
    Write-Warning "No label updates found in file"
    exit 0
}

# Show preview
Write-Host "`nLabels to update:" -ForegroundColor Yellow
$labelData | Format-Table Port, Type, Current_Label, Current_Label_Line2, New_Label, New_Label_Line2, Current_Color, New_Color -AutoSize

if ($TestOnly) {
    Write-Host "Test mode - no changes made" -ForegroundColor Yellow
    exit 0
}

$ipList = Parse-IPList -IPString $KumoIP
if ($ipList.Count -eq 0) {
    Write-Error "No valid IP addresses provided."
    exit 1
}

$confirm = Read-Host "Update $($labelData.Count) labels on $($ipList.Count) router(s) at $($ipList -join ', ')? (y/N)"
if ($confirm -ne 'y' -and $confirm -ne 'Y') {
    Write-Host "Cancelled by user" -ForegroundColor Yellow
    exit 0
}

foreach ($ip in $ipList) {
    Write-Host "`n--- Router: $ip ---" -ForegroundColor Cyan

    # Ping check: 4 attempts, skip to next IP if all fail
    $pingOk = $false
    for ($pa = 1; $pa -le 4; $pa++) {
        Write-Host "  Pinging $ip ($pa/4)..." -ForegroundColor DarkGray -NoNewline
        try {
            if (Test-Connection -ComputerName $ip -Count 1 -Quiet -ErrorAction SilentlyContinue) {
                Write-Host " OK" -ForegroundColor Green
                $pingOk = $true; break
            }
        } catch { }
        Write-Host " no response" -ForegroundColor Yellow
    }
    if (-not $pingOk) {
        Write-Warning "No response from $ip after 4 pings -- skipping."
        continue
    }

    # Auto-detect router type
    $script:DetectedRouterType = $RouterType
    if ($RouterType -eq "Auto") {
        Write-Host "Auto-detecting router type at $ip..." -ForegroundColor Yellow
        $detected = Resolve-RouterType -IP $ip
        if (-not $detected) {
            Write-Warning "Could not detect router type at $ip -- skipping."
            continue
        }
        $script:DetectedRouterType = $detected
    }

    Write-Host "Router type: $script:DetectedRouterType" -ForegroundColor Cyan

    if (-not (Test-RouterConnectivity -IP $ip)) {
        Write-Warning "Cannot connect to router at $ip -- skipping."
        continue
    }

    if ($script:DetectedRouterType -eq "Videohub") {
        Update-VideohubLabels -IP $ip -LabelData $labelData
    } else {
        Write-Host "Attempting REST API update..." -ForegroundColor Yellow
        try {
            Update-KumoLabelsREST -IP $ip -LabelData $labelData
        } catch {
            Write-Host "REST API failed, trying Telnet..." -ForegroundColor Yellow
            Update-KumoLabelsTelnet -IP $ip -LabelData $labelData
        }
    }
    Write-Host "  OK  Labels updated on $ip!" -ForegroundColor Green
}

Write-Host "`nRouter label update complete!" -ForegroundColor Green
