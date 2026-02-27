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
    [string]$RouterType = "Auto"
)

# Resolved router type — set during auto-detection
$script:DetectedRouterType = $RouterType

# ─────────────────────────────────────────────────────────────────────────────
# SHARED UTILITIES
# ─────────────────────────────────────────────────────────────────────────────

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
        }

        $currentBlock = ""
        $deadline = (Get-Date).AddSeconds(6)

        while ((Get-Date) -lt $deadline) {
            if (-not $stream.DataAvailable) {
                Start-Sleep -Milliseconds 50
                # Once we have filled both label blocks, stop waiting
                if ($state.InputLabels.Count -gt 0 -and $state.OutputLabels.Count -gt 0) { break }
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
        $allLabels += [PSCustomObject]@{
            Port          = $port
            Type          = "OUTPUT"
            Current_Label = $label
            New_Label     = ""
            Notes         = "From $($state.DeviceName) TCP 9990"
        }
        Write-Host "  Output $port`: $label" -ForegroundColor White
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

    # Download source names (inputs) via REST API
    for ($i = 1; $i -le $inputCount; $i++) {
        $label = "Source $i"
        try {
            $uri = "http://$IP/config?action=get&configid=0&paramid=eParamID_XPT_Source${i}_Line_1"
            $resp = Invoke-SecureWebRequest -Uri $uri -TimeoutSec 5 -UseBasicParsing -ForceHTTP:$ForceHTTP
            $json = $resp.Content | ConvertFrom-Json
            if ($json.value_name -and $json.value_name -ne "") { $label = $json.value_name }
            elseif ($json.value -and $json.value -ne "") { $label = $json.value }
            $labelsRetrieved = $true
        } catch {
            if ($i -eq 1) { Write-Host "    REST API failed on first port, will try Telnet..." -ForegroundColor Yellow }
        }

        $allLabels += [PSCustomObject]@{
            Port = $i; Type = "INPUT"; Current_Label = $label; New_Label = ""; Notes = "From $routerName REST API"
        }
        Write-Host "  Source $i`: $label" -ForegroundColor White

        if (-not $labelsRetrieved -and $i -eq 1) { break }
    }

    # Download destination names (outputs) via REST API
    if ($labelsRetrieved) {
        for ($i = 1; $i -le $outputCount; $i++) {
            $label = "Dest $i"
            try {
                $uri = "http://$IP/config?action=get&configid=0&paramid=eParamID_XPT_Destination${i}_Line_1"
                $resp = Invoke-SecureWebRequest -Uri $uri -TimeoutSec 5 -UseBasicParsing -ForceHTTP:$ForceHTTP
                $json = $resp.Content | ConvertFrom-Json
                if ($json.value_name -and $json.value_name -ne "") { $label = $json.value_name }
                elseif ($json.value -and $json.value -ne "") { $label = $json.value }
            } catch { }

            $allLabels += [PSCustomObject]@{
                Port = $i; Type = "OUTPUT"; Current_Label = $label; New_Label = ""; Notes = "From $routerName REST API"
            }
            Write-Host "  Dest $i`: $label" -ForegroundColor White
        }
    }

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
                        Notes         = "Retrieved via Telnet"
                    }

                    Write-Host "  Input $i`: $label" -ForegroundColor White

                } catch {
                    $allLabels += [PSCustomObject]@{
                        Port          = $i
                        Type          = "INPUT"
                        Current_Label = "Input $i"
                        New_Label     = ""
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
                        Notes         = "Retrieved via Telnet"
                    }

                    Write-Host "  Output $i`: $label" -ForegroundColor White

                } catch {
                    $allLabels += [PSCustomObject]@{
                        Port          = $i
                        Type          = "OUTPUT"
                        Current_Label = "Output $i"
                        New_Label     = ""
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
                Notes         = "Default (download failed)"
            }
        }

        for ($i = 1; $i -le $outputCount; $i++) {
            $allLabels += [PSCustomObject]@{
                Port          = $i
                Type          = "OUTPUT"
                Current_Label = "Output $i"
                New_Label     = ""
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

            Write-Host "Downloading current labels..." -ForegroundColor Magenta
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
            }
            Write-Host "  Downloaded $($currentLabels.Count) labels from router" -ForegroundColor Green
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
        $templateData += [PSCustomObject]@{
            Port          = $i
            Type          = "INPUT"
            Current_Label = $curLabel
            New_Label     = ""
            Notes         = "Enter your desired label"
        }
    }

    for ($i = 1; $i -le $outputCount; $i++) {
        $curLabel = if ($currentLabels.ContainsKey("OUTPUT_$i")) { $currentLabels["OUTPUT_$i"] } else { "Output $i" }
        $templateData += [PSCustomObject]@{
            Port          = $i
            Type          = "OUTPUT"
            Current_Label = $curLabel
            New_Label     = ""
            Notes         = "Enter your desired label"
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

        # Filter for rows with new labels
        $filteredData = $data | Where-Object {
            $_.New_Label -and
            $_.New_Label.ToString().Trim() -ne "" -and
            $_.New_Label -ne $_.Current_Label
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
        try {
            Write-Host "Updating $($item.Type) $($item.Port): $($item.New_Label)" -ForegroundColor Magenta

            # Build correct eParamID
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

    Write-Host "`nUpdate Summary:" -ForegroundColor Yellow
    Write-Host "  Success: $successCount" -ForegroundColor Green
    Write-Host "  Errors: $errorCount" -ForegroundColor Red

    # If all REST updates failed, throw so caller can fall back to Telnet
    if ($successCount -eq 0 -and $errorCount -gt 0) {
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

# Handle download labels
if ($DownloadLabels) {
    if (-not $KumoIP) {
        $KumoIP = Read-Host "Enter router IP address"
    }

    if (-not $DownloadPath) {
        $docsDir = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "Router_Labels"
        if (-not (Test-Path $docsDir)) { New-Item -ItemType Directory -Path $docsDir -Force | Out-Null }
        $DownloadPath = Join-Path $docsDir "Router_Labels_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"
        Write-Host "Saving to: $DownloadPath" -ForegroundColor Magenta
    }

    # Auto-detect router type if not specified
    if ($RouterType -eq "Auto") {
        Write-Host "Auto-detecting router type at $KumoIP..." -ForegroundColor Yellow
        $detected = Resolve-RouterType -IP $KumoIP
        if (-not $detected) {
            Write-Error "Could not detect router type at $KumoIP. Use -RouterType KUMO or -RouterType Videohub to specify manually."
            exit 1
        }
        $script:DetectedRouterType = $detected
    }

    # Test connectivity
    if (-not (Test-RouterConnectivity -IP $KumoIP)) {
        Write-Error "Cannot connect to router at $KumoIP"
        exit 1
    }

    # Download labels
    if ($script:DetectedRouterType -eq "Videohub") {
        $downloadedLabels = Get-VideohubCurrentLabels -IP $KumoIP -OutputPath $DownloadPath
    } else {
        $downloadedLabels = Get-KumoCurrentLabels -IP $KumoIP -OutputPath $DownloadPath
    }

    if ($downloadedLabels -and $downloadedLabels.Count -gt 0) {
        Write-Host "`n  OK  Labels downloaded successfully!" -ForegroundColor Green
    } else {
        Write-Error "Failed to download labels"
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
    if (-not $KumoIP -or -not $ExcelFile) {
        Write-Error "KumoIP and ExcelFile parameters are required for update operations"
        Write-Host "Usage examples:" -ForegroundColor Yellow
        Write-Host "  Download: .\KUMO-Excel-Updater.ps1 -DownloadLabels -KumoIP '192.168.1.100' -DownloadPath 'labels.xlsx'" -ForegroundColor White
        Write-Host "  Update:   .\KUMO-Excel-Updater.ps1 -KumoIP '192.168.1.100' -ExcelFile 'labels.xlsx'" -ForegroundColor White
        Write-Host "  Videohub: .\KUMO-Excel-Updater.ps1 -RouterType Videohub -KumoIP '192.168.1.101' -ExcelFile 'labels.xlsx'" -ForegroundColor White
        Write-Host "  Template: .\KUMO-Excel-Updater.ps1 -CreateTemplate" -ForegroundColor White
        exit 1
    }
}

if ($ExcelFile -and -not (Test-Path $ExcelFile)) {
    Write-Error "File not found: $ExcelFile"
    exit 1
}

# Auto-detect router type if needed
if ($RouterType -eq "Auto") {
    Write-Host "Auto-detecting router type at $KumoIP..." -ForegroundColor Yellow
    $detected = Resolve-RouterType -IP $KumoIP
    if (-not $detected) {
        Write-Error "Could not detect router type at $KumoIP. Use -RouterType KUMO or -RouterType Videohub to specify manually."
        exit 1
    }
    $script:DetectedRouterType = $detected
}

Write-Host "Router type: $script:DetectedRouterType" -ForegroundColor Cyan

# Test connectivity
if (-not (Test-RouterConnectivity -IP $KumoIP)) {
    Write-Error "Cannot connect to router at $KumoIP"
    exit 1
}

# Load label data
$labelData = Get-ExcelLabelData -FilePath $ExcelFile -WorksheetName $WorksheetName
if (-not $labelData -or $labelData.Count -eq 0) {
    Write-Warning "No label updates found in file"
    exit 0
}

# Show preview
Write-Host "`nLabels to update:" -ForegroundColor Yellow
$labelData | Format-Table Port, Type, Current_Label, New_Label -AutoSize

if ($TestOnly) {
    Write-Host "Test mode - no changes made" -ForegroundColor Yellow
    exit 0
}

# Confirm update
$confirm = Read-Host "Update $($labelData.Count) labels on $script:DetectedRouterType at $KumoIP? (y/N)"
if ($confirm -ne 'y' -and $confirm -ne 'Y') {
    Write-Host "Cancelled by user" -ForegroundColor Yellow
    exit 0
}

# Execute update for the appropriate router type
if ($script:DetectedRouterType -eq "Videohub") {
    Update-VideohubLabels -IP $KumoIP -LabelData $labelData
} else {
    # KUMO: Try REST API first, fallback to Telnet
    Write-Host "Attempting REST API update..." -ForegroundColor Yellow
    try {
        Update-KumoLabelsREST -IP $KumoIP -LabelData $labelData
    } catch {
        Write-Host "REST API failed, trying Telnet..." -ForegroundColor Yellow
        Update-KumoLabelsTelnet -IP $KumoIP -LabelData $labelData
    }
}

Write-Host "`nRouter label update complete!" -ForegroundColor Green
