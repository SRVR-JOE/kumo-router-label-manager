# KUMO Excel Label Updater - Command Line Version
# Simple script for bulk updating KUMO labels from Excel
#
# Usage Examples:
# Download current labels: .\KUMO-Excel-Updater.ps1 -DownloadLabels -KumoIP "192.168.1.100" -DownloadPath "current_labels.xlsx"
# Create template:        .\KUMO-Excel-Updater.ps1 -CreateTemplate
# Update from Excel:      .\KUMO-Excel-Updater.ps1 -KumoIP "192.168.1.100" -ExcelFile "labels.xlsx"
# Test only:              .\KUMO-Excel-Updater.ps1 -KumoIP "192.168.1.100" -ExcelFile "labels.xlsx" -TestOnly

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

# Helper function for Invoke-RestMethod with HTTPS fallback
function Invoke-SecureRestMethod {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Uri,

        [string]$Method = "GET",

        [object]$Body = $null,

        [hashtable]$Headers = @{},

        [int]$TimeoutSec = 10,

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
                ErrorAction = "Stop"
            }
            if ($Body) { $params.Body = $Body }
            if ($Headers.Count -gt 0) { $params.Headers = $Headers }

            return Invoke-RestMethod @params
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
        ErrorAction = "Stop"
    }
    if ($Body) { $params.Body = $Body }
    if ($Headers.Count -gt 0) { $params.Headers = $Headers }

    return Invoke-RestMethod @params
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

    # Detect port count
    $portCount = 32
    try {
        $test33Uri = "http://$IP/config?action=get&configid=0&paramid=eParamID_XPT_Source33_Line_1"
        $test33 = Invoke-SecureWebRequest -Uri $test33Uri -TimeoutSec 3 -UseBasicParsing -ForceHTTP:$ForceHTTP
        $test33Json = $test33.Content | ConvertFrom-Json
        if ($test33Json.value -ne $null) { $portCount = 64 }
    } catch { }
    if ($portCount -eq 32) {
        try {
            $test17Uri = "http://$IP/config?action=get&configid=0&paramid=eParamID_XPT_Source17_Line_1"
            $test17 = Invoke-SecureWebRequest -Uri $test17Uri -TimeoutSec 3 -UseBasicParsing -ForceHTTP:$ForceHTTP
            $test17Json = $test17.Content | ConvertFrom-Json
            if ($test17Json.value -eq $null) { $portCount = 16 }
        } catch { $portCount = 16 }
    }
    Write-Host "  Detected ${portCount}x${portCount} router" -ForegroundColor Green

    # Download source names (inputs) via REST API
    for ($i = 1; $i -le $portCount; $i++) {
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
        for ($i = 1; $i -le $portCount; $i++) {
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
            for ($i = 1; $i -le 32; $i++) {
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
            for ($i = 1; $i -le 32; $i++) {
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
            
            $writer.Close()
            $reader.Close()
            $tcpClient.Close()
            $labelsRetrieved = $true
            
        } catch {
            Write-Warning "Telnet method failed: $($_.Exception.Message)"
        }
    }
    
    # If everything failed, create default template
    if ($allLabels.Count -eq 0) {
        Write-Warning "All download methods failed. Creating default template..."
        
        for ($i = 1; $i -le 32; $i++) {
            $allLabels += [PSCustomObject]@{
                Port = $i
                Type = "INPUT"
                Current_Label = "Input $i"
                New_Label = ""
                Notes = "Default (download failed)"
            }
        }
        
        for ($i = 1; $i -le 32; $i++) {
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

# Function to create Excel template
function New-KumoLabelTemplate {
    param([string]$FilePath)
    
    Write-Host "Creating KUMO Label Template..." -ForegroundColor Green
    
    # Template data structure
    $templateData = @()
    
    # Add inputs (1-32)
    for ($i = 1; $i -le 32; $i++) {
        $templateData += [PSCustomObject]@{
            Port = $i
            Type = "INPUT"
            Current_Label = "Input $i"
            New_Label = "Camera $i"
            Notes = "Update this column with your desired label"
        }
    }
    
    # Add outputs (1-32)
    for ($i = 1; $i -le 32; $i++) {
        $templateData += [PSCustomObject]@{
            Port = $i
            Type = "OUTPUT"
            Current_Label = "Output $i"
            New_Label = "Monitor $i"
            Notes = "Update this column with your desired label"
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
        
        Write-Host "Template created: $FilePath" -ForegroundColor Green
        Write-Host "Instructions:" -ForegroundColor Yellow
        Write-Host "1. Open the Excel file" -ForegroundColor White
        Write-Host "2. Update the 'New_Label' column with your desired names" -ForegroundColor White
        Write-Host "3. Save the file" -ForegroundColor White
        Write-Host "4. Run this script with -KumoIP and -ExcelFile parameters" -ForegroundColor White
        
    } catch {
        Write-Error "Failed to create template: $($_.Exception.Message)"
        
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
        
        # Cleanup
        $writer.Close()
        $reader.Close()
        $tcpClient.Close()
        
        Write-Host "`nTelnet Update Complete: $successCount labels updated" -ForegroundColor Green
        
    } catch {
        Write-Error "Telnet connection failed: $($_.Exception.Message)"
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
    $templatePath = Read-Host "Enter template file path (e.g., C:\temp\KUMO_Template.xlsx)"
    New-KumoLabelTemplate -FilePath $templatePath
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
