# KUMO Excel Label Updater - Command Line Version
# Simple script for bulk updating KUMO labels from Excel
# Auto-detects KUMO model (1604/1616/3232/6464) and handles asymmetric port counts
#
# Usage Examples:
# Download current labels: .\KUMO-Excel-Updater.ps1 -DownloadLabels -KumoIP "192.168.1.100" -DownloadPath "current_labels.xlsx"
# Create template (manual): .\KUMO-Excel-Updater.ps1 -CreateTemplate
# Create template (auto):   .\KUMO-Excel-Updater.ps1 -CreateTemplate -KumoIP "192.168.1.100"
# Update from Excel:        .\KUMO-Excel-Updater.ps1 -KumoIP "192.168.1.100" -ExcelFile "labels.xlsx"
# Test only:                .\KUMO-Excel-Updater.ps1 -KumoIP "192.168.1.100" -ExcelFile "labels.xlsx" -TestOnly

param(
    [Parameter(Mandatory=$false)]
    [string]$KumoIP,

    [Parameter(Mandatory=$false)]
    [string]$ExcelFile,

    [string]$WorksheetName = "KUMO_Labels",

    [switch]$TestOnly,

    [switch]$CreateTemplate,

    [switch]$DownloadLabels,

    [string]$DownloadPath,

    [switch]$ForceHTTP
)

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
    Write-Host "Querying KUMO REST API..." -ForegroundColor Cyan

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
        Write-Host "Attempting Telnet method..." -ForegroundColor Cyan
        
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
                        Port = $i
                        Type = "INPUT"
                        Current_Label = $label
                        New_Label = ""
                        Notes = "Retrieved via Telnet"
                    }
                    
                    Write-Host "  Input $i`: $label" -ForegroundColor White
                    
                } catch {
                    $allLabels += [PSCustomObject]@{
                        Port = $i
                        Type = "INPUT"
                        Current_Label = "Input $i"
                        New_Label = ""
                        Notes = "Default (telnet query failed)"
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
                        Port = $i
                        Type = "OUTPUT"
                        Current_Label = $label
                        New_Label = ""
                        Notes = "Retrieved via Telnet"
                    }
                    
                    Write-Host "  Output $i`: $label" -ForegroundColor White
                    
                } catch {
                    $allLabels += [PSCustomObject]@{
                        Port = $i
                        Type = "OUTPUT"
                        Current_Label = "Output $i"
                        New_Label = ""
                        Notes = "Default (telnet query failed)"
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
                Port = $i
                Type = "INPUT"
                Current_Label = "Input $i"
                New_Label = ""
                Notes = "Default (download failed)"
            }
        }

        for ($i = 1; $i -le $outputCount; $i++) {
            $allLabels += [PSCustomObject]@{
                Port = $i
                Type = "OUTPUT"
                Current_Label = "Output $i"
                New_Label = ""
                Notes = "Default (download failed)"
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
                Write-Host "✓ Excel file created: $OutputPath" -ForegroundColor Green
            } else {
                # Fallback to CSV
                $csvPath = $OutputPath -replace "\.xlsx$", ".csv"
                $allLabels | Export-Csv -Path $csvPath -NoTypeInformation
                Write-Host "✓ CSV file created (Excel module not available): $csvPath" -ForegroundColor Yellow
                $OutputPath = $csvPath
            }
        } else {
            # CSV export
            $allLabels | Export-Csv -Path $OutputPath -NoTypeInformation
            Write-Host "✓ CSV file created: $OutputPath" -ForegroundColor Green
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

# Helper to probe a single KUMO param and return value or $null
function Get-KumoProbeValue {
    param([string]$IP, [string]$ParamId)
    try {
        $uri = "http://$IP/config?action=get&configid=0&paramid=$ParamId"
        $resp = Invoke-SecureWebRequest -Uri $uri -TimeoutSec 3 -UseBasicParsing -ForceHTTP:$ForceHTTP
        $json = $resp.Content | ConvertFrom-Json
        if ($json.value_name -and $json.value_name -ne "") { return $json.value_name }
        if ($json.value -and $json.value -ne "") { return $json.value }
        return $null
    } catch { return $null }
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

    # The AJA KUMO REST API may return values for non-existent ports.
    # Use a canary probe (Source100, which never exists) to detect this behavior.
    $canaryValue = Get-KumoProbeValue -IP $IP -ParamId "eParamID_XPT_Source100_Line_1"

    if ($canaryValue -ne $null) {
        # API returns phantom values for non-existent ports.
        # Compare probed values to the canary — real ports differ from the default.
        Write-Host "  API returns phantom port values — using comparison detection..." -ForegroundColor Gray

        $probe33 = Get-KumoProbeValue -IP $IP -ParamId "eParamID_XPT_Source33_Line_1"
        if ($probe33 -ne $null -and $probe33 -ne $canaryValue) {
            # Source33 differs from canary — might be 64-port. Confirm with Source64.
            $probe64 = Get-KumoProbeValue -IP $IP -ParamId "eParamID_XPT_Source64_Line_1"
            if ($probe64 -ne $null -and $probe64 -ne $canaryValue) {
                $inputCount = 64; $outputCount = 64
            }
            # else: Source33 real but Source64 phantom → 32-port (default)
        } else {
            # Source33 matches canary — phantom port, router is 16 or 32
            $probe17 = Get-KumoProbeValue -IP $IP -ParamId "eParamID_XPT_Source17_Line_1"
            if ($probe17 -ne $null -and $probe17 -ne $canaryValue) {
                $inputCount = 32; $outputCount = 32
            } else {
                $inputCount = 16; $outputCount = 16
            }
        }
    } else {
        # Canary returned null — API correctly rejects non-existent ports.
        # Use simple existence probing.
        $probe33 = Get-KumoProbeValue -IP $IP -ParamId "eParamID_XPT_Source33_Line_1"
        if ($probe33 -ne $null) { $inputCount = 64; $outputCount = 64 }
        if ($inputCount -ne 64) {
            $probe17 = Get-KumoProbeValue -IP $IP -ParamId "eParamID_XPT_Source17_Line_1"
            if ($probe17 -eq $null) { $inputCount = 16; $outputCount = 16 }
        }
    }

    # For 16-input routers, differentiate KUMO 1604 (4 outputs) vs KUMO 1616 (16 outputs)
    if ($inputCount -eq 16) {
        $destCanary = Get-KumoProbeValue -IP $IP -ParamId "eParamID_XPT_Destination100_Line_1"
        $testDest5 = Get-KumoProbeValue -IP $IP -ParamId "eParamID_XPT_Destination5_Line_1"
        if ($destCanary -ne $null) {
            if ($testDest5 -eq $null -or $testDest5 -eq $destCanary) { $outputCount = 4 }
        } else {
            if ($testDest5 -eq $null) { $outputCount = 4 }
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
        Model = $modelName
        InputCount = $inputCount
        OutputCount = $outputCount
        Firmware = $firmware
    }
}

# Function to create Excel template
function New-KumoLabelTemplate {
    param(
        [string]$FilePath,
        [string]$KumoIP = ""
    )

    $inputCount = 32
    $outputCount = 32
    $modelName = ""
    $currentLabels = @{}  # Hash of "TYPE_PORT" -> label

    # If IP provided, auto-detect router model and download current labels
    if ($KumoIP -and $KumoIP -ne "") {
        Write-Host "Connecting to KUMO at $KumoIP to auto-detect model..." -ForegroundColor Cyan

        # Detect model
        $modelInfo = Get-KumoRouterModel -IP $KumoIP
        $inputCount = $modelInfo.InputCount
        $outputCount = $modelInfo.OutputCount
        $modelName = $modelInfo.Model
        $fwVersion = $modelInfo.Firmware

        Write-Host "  Detected: $modelName `($inputCount in / $outputCount out`)" -ForegroundColor Green
        if ($fwVersion) { Write-Host "  Firmware: $fwVersion" -ForegroundColor Green }

        # Download current labels
        Write-Host "Downloading current labels..." -ForegroundColor Cyan
        for ($i = 1; $i -le $inputCount; $i++) {
            try {
                $uri = "http://$KumoIP/config?action=get&configid=0&paramid=eParamID_XPT_Source${i}_Line_1"
                $resp = Invoke-SecureWebRequest -Uri $uri -TimeoutSec 5 -UseBasicParsing -ForceHTTP:$ForceHTTP
                $json = $resp.Content | ConvertFrom-Json
                $lbl = if ($json.value_name -and $json.value_name -ne "") { $json.value_name }
                       elseif ($json.value -and $json.value -ne "") { $json.value }
                       else { $null }
                if ($lbl) { $currentLabels["INPUT_$i"] = $lbl }
            } catch { }
        }
        for ($i = 1; $i -le $outputCount; $i++) {
            try {
                $uri = "http://$KumoIP/config?action=get&configid=0&paramid=eParamID_XPT_Destination${i}_Line_1"
                $resp = Invoke-SecureWebRequest -Uri $uri -TimeoutSec 5 -UseBasicParsing -ForceHTTP:$ForceHTTP
                $json = $resp.Content | ConvertFrom-Json
                $lbl = if ($json.value_name -and $json.value_name -ne "") { $json.value_name }
                       elseif ($json.value -and $json.value -ne "") { $json.value }
                       else { $null }
                if ($lbl) { $currentLabels["OUTPUT_$i"] = $lbl }
            } catch { }
        }
        Write-Host "  Downloaded $($currentLabels.Count) labels from router" -ForegroundColor Green

    } else {
        # No IP provided - ask user to choose router model
        Write-Host ""
        Write-Host "No KUMO IP provided. Choose your router model:" -ForegroundColor Yellow
        Write-Host "  1. KUMO 1604  `(16 inputs / 4 outputs`)" -ForegroundColor White
        Write-Host "  2. KUMO 1616  `(16 inputs / 16 outputs`)" -ForegroundColor White
        Write-Host "  3. KUMO 3232  `(32 inputs / 32 outputs`)" -ForegroundColor White
        Write-Host "  4. KUMO 6464  `(64 inputs / 64 outputs`)" -ForegroundColor White
        $choice = Read-Host "Enter choice `(1-4, default 3`)"
        switch ($choice) {
            "1" { $inputCount = 16; $outputCount = 4;  $modelName = "KUMO 1604" }
            "2" { $inputCount = 16; $outputCount = 16; $modelName = "KUMO 1616" }
            "4" { $inputCount = 64; $outputCount = 64; $modelName = "KUMO 6464" }
            default { $inputCount = 32; $outputCount = 32; $modelName = "KUMO 3232" }
        }
        Write-Host "  Creating template for: $modelName `($inputCount in / $outputCount out`)" -ForegroundColor Green
    }

    Write-Host "Creating $modelName Label Template..." -ForegroundColor Green

    # Template data structure
    $templateData = @()

    # Add inputs
    for ($i = 1; $i -le $inputCount; $i++) {
        $curLabel = if ($currentLabels.ContainsKey("INPUT_$i")) { $currentLabels["INPUT_$i"] } else { "Input $i" }
        $templateData += [PSCustomObject]@{
            Port = $i
            Type = "INPUT"
            Current_Label = $curLabel
            New_Label = ""
            Notes = "Enter your desired label"
        }
    }

    # Add outputs
    for ($i = 1; $i -le $outputCount; $i++) {
        $curLabel = if ($currentLabels.ContainsKey("OUTPUT_$i")) { $currentLabels["OUTPUT_$i"] } else { "Output $i" }
        $templateData += [PSCustomObject]@{
            Port = $i
            Type = "OUTPUT"
            Current_Label = $curLabel
            New_Label = ""
            Notes = "Enter your desired label"
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
        Write-Host "  Model: $modelName `($inputCount inputs / $outputCount outputs`)" -ForegroundColor White
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

# Function to test KUMO connectivity
function Test-KumoConnectivity {
    param([string]$IP)
    
    Write-Host "Testing connection to KUMO at $IP..." -ForegroundColor Yellow
    
    # Test web interface (port 80)
    try {
        $response = Invoke-SecureWebRequest -Uri "http://$IP" -TimeoutSec 10 -UseBasicParsing -ForceHTTP:$ForceHTTP
        Write-Host "✓ Web interface accessible" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "✗ Cannot reach web interface on port 80" -ForegroundColor Red
    }
    
    # Test telnet port
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.ConnectAsync($IP, 23).Wait(5000)
        if ($tcpClient.Connected) {
            Write-Host "✓ Telnet port 23 accessible" -ForegroundColor Green
            $tcpClient.Close()
            return $true
        }
    } catch {
        Write-Host "✗ Cannot reach telnet port 23" -ForegroundColor Red
    }
    
    return $false
}

# Function to load Excel data
function Get-ExcelLabelData {
    param(
        [string]$FilePath,
        [string]$WorksheetName
    )
    
    Write-Host "Loading Excel data from $FilePath..." -ForegroundColor Yellow
    
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
        Write-Error "Failed to load Excel data: $($_.Exception.Message)"
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
            Write-Host "Updating $($item.Type) $($item.Port): $($item.New_Label)" -ForegroundColor Cyan

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
                Write-Host "  ✓ Success" -ForegroundColor Green
            } catch {
                throw "REST API set failed: $($_.Exception.Message)"
            }

        } catch {
            $errorCount++
            Write-Host "  ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
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
                Write-Host "Sending: $command" -ForegroundColor Cyan
                
                $writer.WriteLine($command)
                $writer.Flush()
                Start-Sleep -Milliseconds 500
                
                $successCount++
                Write-Host "  ✓ Success" -ForegroundColor Green
                
            } catch {
                Write-Host "  ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
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

# Main execution
Write-Host "KUMO Excel Label Updater" -ForegroundColor Magenta
Write-Host "========================" -ForegroundColor Magenta

# Handle download labels
if ($DownloadLabels) {
    if (-not $KumoIP) {
        $KumoIP = Read-Host "Enter KUMO IP address"
    }
    
    if (-not $DownloadPath) {
        $docsDir = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "KUMO_Labels"
        if (-not (Test-Path $docsDir)) { New-Item -ItemType Directory -Path $docsDir -Force | Out-Null }
        $DownloadPath = Join-Path $docsDir "KUMO_Labels_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"
        Write-Host "Saving to: $DownloadPath" -ForegroundColor Cyan
    }
    
    # Test connectivity
    if (-not (Test-KumoConnectivity -IP $KumoIP)) {
        Write-Error "Cannot connect to KUMO at $KumoIP"
        exit 1
    }
    
    # Download labels
    $downloadedLabels = Get-KumoCurrentLabels -IP $KumoIP -OutputPath $DownloadPath
    
    if ($downloadedLabels -and $downloadedLabels.Count -gt 0) {
        Write-Host "`n✓ Labels downloaded successfully!" -ForegroundColor Green
    } else {
        Write-Error "Failed to download labels"
        exit 1
    }
    
    exit 0
}

# Handle template creation
if ($CreateTemplate) {
    # Default output path
    $docsDir = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "KUMO_Labels"
    if (-not (Test-Path $docsDir)) { New-Item -ItemType Directory -Path $docsDir -Force | Out-Null }
    $defaultPath = Join-Path $docsDir "KUMO_Template_$(Get-Date -Format 'yyyyMMdd_HHmm').xlsx"

    $templatePath = Read-Host "Enter template file path (default: $defaultPath)"
    if (-not $templatePath -or $templatePath.Trim() -eq "") { $templatePath = $defaultPath }

    # Optionally connect to router for auto-detect
    $templateIP = ""
    if ($KumoIP) {
        $templateIP = $KumoIP
    } else {
        $useRouter = Read-Host "Connect to a KUMO router to auto-detect model and download current labels? (y/N)"
        if ($useRouter -eq 'y' -or $useRouter -eq 'Y') {
            $templateIP = Read-Host "Enter KUMO IP address"
        }
    }

    New-KumoLabelTemplate -FilePath $templatePath -KumoIP $templateIP
    exit
}

# Validate parameters
if (-not $DownloadLabels -and -not $CreateTemplate) {
    if (-not $KumoIP -or -not $ExcelFile) {
        Write-Error "KumoIP and ExcelFile parameters are required for update operations"
        Write-Host "Usage examples:" -ForegroundColor Yellow
        Write-Host "  Download: .\KUMO-Excel-Updater.ps1 -DownloadLabels -KumoIP '192.168.1.100' -DownloadPath 'labels.xlsx'" -ForegroundColor White
        Write-Host "  Update: .\KUMO-Excel-Updater.ps1 -KumoIP '192.168.1.100' -ExcelFile 'labels.xlsx'" -ForegroundColor White
        Write-Host "  Template: .\KUMO-Excel-Updater.ps1 -CreateTemplate" -ForegroundColor White
        exit 1
    }
}

if ($ExcelFile -and -not (Test-Path $ExcelFile)) {
    Write-Error "Excel file not found: $ExcelFile"
    exit 1
}

# Test connectivity
if (-not (Test-KumoConnectivity -IP $KumoIP)) {
    Write-Error "Cannot connect to KUMO at $KumoIP"
    exit 1
}

# Load Excel data
$labelData = Get-ExcelLabelData -FilePath $ExcelFile -WorksheetName $WorksheetName
if (-not $labelData -or $labelData.Count -eq 0) {
    Write-Warning "No label updates found in Excel file"
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
$confirm = Read-Host "Update $($labelData.Count) labels? (y/N)"
if ($confirm -ne 'y' -and $confirm -ne 'Y') {
    Write-Host "Cancelled by user" -ForegroundColor Yellow
    exit 0
}

# Try REST API first, fallback to Telnet
Write-Host "Attempting REST API update..." -ForegroundColor Yellow
try {
    Update-KumoLabelsREST -IP $KumoIP -LabelData $labelData
} catch {
    Write-Host "REST API failed, trying Telnet..." -ForegroundColor Yellow
    Update-KumoLabelsTelnet -IP $KumoIP -LabelData $labelData
}

Write-Host "`nKUMO label update complete!" -ForegroundColor Green
