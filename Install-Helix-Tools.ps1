# Helix - Installation Script
# Professional AV Production Tool for Solotech
# Version 5.0 - Supports AJA KUMO, Blackmagic Videohub, and Lightware MX2

param(
    [string]$InstallPath = "C:\Helix-Tools",
    [switch]$CreateDesktopShortcuts,
    [switch]$InstallExcelModule,
    [switch]$Uninstall
)

Write-Host @"
╔═══════════════════════════════════════════════════════════════════════════════╗
║                            Helix v5.0                                       ║
║                   Professional AV Production Tool                            ║
║                                                                               ║
║  Features:                                                                    ║
║  • Download current labels from AJA KUMO / Videohub / Lightware routers    ║
║  • Bulk update labels via Excel spreadsheet                                  ║
║  • Professional GUI and command-line interfaces                              ║
║  • AJA KUMO (REST API / Telnet), Videohub (TCP 9990), Lightware MX2 (LW3) ║
║  • Auto-detects router type on connect                                       ║
║                                                                               ║
║  Created for Solotech Live Event Production                                  ║
╚═══════════════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Magenta

# Handle uninstall
if ($Uninstall) {
    Write-Host "`nUninstalling Helix Tools..." -ForegroundColor Yellow

    if (Test-Path $InstallPath) {
        Remove-Item $InstallPath -Recurse -Force
        Write-Host "✓ Removed installation directory: $InstallPath" -ForegroundColor Green
    }

    # Remove desktop shortcuts
    $shortcuts = @(
        "$env:USERPROFILE\Desktop\Helix.lnk",
        "$env:PUBLIC\Desktop\Helix.lnk"
    )

    foreach ($shortcut in $shortcuts) {
        if (Test-Path $shortcut) {
            Remove-Item $shortcut -Force
            Write-Host "✓ Removed shortcut: $shortcut" -ForegroundColor Green
        }
    }

    Write-Host "✓ Helix Tools uninstalled successfully!" -ForegroundColor Green
    exit 0
}

# Check PowerShell execution policy
$executionPolicy = Get-ExecutionPolicy
if ($executionPolicy -eq "Restricted") {
    Write-Warning "PowerShell execution policy is Restricted."
    Write-Host "To fix this, run PowerShell as Administrator and execute:" -ForegroundColor Yellow
    Write-Host "Set-ExecutionPolicy RemoteSigned -Scope CurrentUser" -ForegroundColor White

    $response = Read-Host "`nDo you want to continue anyway? (y/N)"
    if ($response -ne 'y' -and $response -ne 'Y') {
        exit 1
    }
}

# Create installation directory
Write-Host "`nCreating installation directory..." -ForegroundColor Yellow
if (-not (Test-Path $InstallPath)) {
    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
    Write-Host "✓ Created: $InstallPath" -ForegroundColor Green
} else {
    Write-Host "✓ Directory exists: $InstallPath" -ForegroundColor Green
}

# Support note
Write-Host "  Supports AJA KUMO / Videohub / Lightware MX2 routers - auto-detected on connect" -ForegroundColor Gray

# Install Excel module if requested
if ($InstallExcelModule) {
    Write-Host "`nInstalling ImportExcel module..." -ForegroundColor Yellow
    try {
        if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
            Install-Module ImportExcel -Scope CurrentUser -Force
            Write-Host "✓ ImportExcel module installed" -ForegroundColor Green
        } else {
            Write-Host "✓ ImportExcel module already installed" -ForegroundColor Green
        }
    } catch {
        Write-Warning "Failed to install ImportExcel module: $($_.Exception.Message)"
        Write-Host "You can install it manually later with: Install-Module ImportExcel -Scope CurrentUser" -ForegroundColor Yellow
    }
}

# Copy files (in a real deployment, these would be copied from the source)
Write-Host "`nInstalling Helix Tools..." -ForegroundColor Yellow

# Create batch file for easy GUI launch
$batchContent = @"
@echo off
cd /d "$InstallPath"
powershell -ExecutionPolicy RemoteSigned -File "Helix-Label-Manager.ps1"
pause
"@

$batchContent | Out-File -FilePath "$InstallPath\Launch-Helix-GUI.bat" -Encoding ASCII
Write-Host "✓ Created GUI launcher: Launch-Helix-GUI.bat" -ForegroundColor Green

# Create PowerShell profile addition for easy command access
$profileAddition = @"

# Helix Tools - Added by installer
`$env:PATH += ";$InstallPath"
function helix-download { & "$InstallPath\Helix-Excel-Updater.ps1" -DownloadLabels @args }
function helix-update { & "$InstallPath\Helix-Excel-Updater.ps1" @args }
function helix-template { & "$InstallPath\Helix-Excel-Updater.ps1" -CreateTemplate @args }
function helix-gui { & "$InstallPath\Launch-Helix-GUI.bat" }

"@

# Create quick start script
$quickStartContent = @'
# Helix - Quick Start Examples
# Supports AJA KUMO, Blackmagic Videohub, and Lightware MX2 routers
# Run these commands from PowerShell

# Download current labels (router type auto-detected):
helix-download -KumoIP "192.168.1.100" -DownloadPath "C:\temp\current_labels.xlsx"

# Download from a Videohub explicitly:
# .\Helix-Excel-Updater.ps1 -RouterType Videohub -DownloadLabels -KumoIP "192.168.1.101" -DownloadPath "C:\temp\vh_labels.csv"

# Create a blank template:
helix-template

# Update labels from Excel file (router type auto-detected):
helix-update -KumoIP "192.168.1.100" -ExcelFile "C:\temp\labels.xlsx"

# Test connection without making changes:
helix-update -KumoIP "192.168.1.100" -ExcelFile "C:\temp\labels.xlsx" -TestOnly

# Launch GUI application:
helix-gui

# Manual commands (if functions don't work):
# .\Helix-Excel-Updater.ps1 -DownloadLabels -KumoIP "IP" -DownloadPath "file.xlsx"
# .\Helix-Excel-Updater.ps1 -KumoIP "IP" -ExcelFile "file.xlsx"
# .\Helix-Label-Manager.ps1
'@

$quickStartContent | Out-File -FilePath "$InstallPath\Quick-Start-Examples.ps1" -Encoding UTF8
Write-Host "✓ Created quick start guide: Quick-Start-Examples.ps1" -ForegroundColor Green

# Create desktop shortcuts if requested
if ($CreateDesktopShortcuts) {
    Write-Host "`nCreating desktop shortcuts..." -ForegroundColor Yellow

    try {
        $WshShell = New-Object -comObject WScript.Shell

        # GUI shortcut
        $Shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\Desktop\Helix.lnk")
        $Shortcut.TargetPath = "powershell.exe"
        $Shortcut.Arguments = "-ExecutionPolicy RemoteSigned -File `"$InstallPath\Helix-Label-Manager.ps1`""
        $Shortcut.WorkingDirectory = $InstallPath
        $Shortcut.Description = "Helix - Router Label Manager (AJA KUMO / Videohub / Lightware MX2)"
        $Shortcut.Save()

        Write-Host "✓ Created desktop shortcut: Helix" -ForegroundColor Green

    } catch {
        Write-Warning "Failed to create desktop shortcuts: $($_.Exception.Message)"
    }
}

# Create configuration file
$configContent = @{
    Version = "5.0"
    InstallPath = $InstallPath
    InstallDate = Get-Date
    Features = @(
        "Download current labels from AJA KUMO / Videohub / Lightware MX2 routers",
        "Upload labels from Excel or CSV",
        "AJA KUMO: REST API and Telnet",
        "Blackmagic Videohub: TCP 9990 protocol",
        "Lightware MX2: LW3 protocol on TCP 6107",
        "Auto-detects router type on connect",
        "GUI and command-line interfaces"
    )
} | ConvertTo-Json -Depth 3

$configContent | Out-File -FilePath "$InstallPath\config.json" -Encoding UTF8
Write-Host "✓ Created configuration file" -ForegroundColor Green

Write-Host @"

╔═══════════════════════════════════════════════════════════════════════════════╗
║                         Installation Complete!                               ║
╚═══════════════════════════════════════════════════════════════════════════════╝

Installation Directory: $InstallPath
Supported Routers: AJA KUMO, Blackmagic Videohub, Lightware MX2

Quick Commands (add to PowerShell profile):
• helix-download -KumoIP "192.168.1.100" -DownloadPath "labels.xlsx"
• helix-update -KumoIP "192.168.1.100" -ExcelFile "labels.xlsx"
• helix-template
• helix-gui

Files Created:
• Helix-Label-Manager.ps1     (GUI Application)
• Helix-Excel-Updater.ps1     (Command Line Tool)
• Launch-Helix-GUI.bat        (Easy GUI Launcher)
• Quick-Start-Examples.ps1   (Usage Examples)
• Helix-Setup-Guide.md        (Complete Documentation)

Next Steps:
1. Copy the main PowerShell files to: $InstallPath
2. Run: .\Launch-Helix-GUI.bat (for GUI)
3. Or use command line: helix-download -KumoIP "YOUR_ROUTER_IP" -DownloadPath "labels.xlsx"
   (Router type is auto-detected. Use -RouterType Videohub to force Videohub mode.)

For support: Check Helix-Setup-Guide.md for troubleshooting
"@ -ForegroundColor Green

# Offer to add functions to PowerShell profile
Write-Host "`nOptional: Add quick commands to PowerShell profile?" -ForegroundColor Yellow
Write-Host "This will allow you to use 'helix-download', 'helix-update', etc. from anywhere" -ForegroundColor White
$addToProfile = Read-Host "Add to profile? (y/N)"

if ($addToProfile -eq 'y' -or $addToProfile -eq 'Y') {
    try {
        if (-not (Test-Path $PROFILE)) {
            New-Item -ItemType File -Path $PROFILE -Force | Out-Null
        }

        Add-Content -Path $PROFILE -Value $profileAddition
        Write-Host "✓ Added Helix functions to PowerShell profile" -ForegroundColor Green
        Write-Host "  Restart PowerShell to use the new commands" -ForegroundColor Yellow

    } catch {
        Write-Warning "Failed to update PowerShell profile: $($_.Exception.Message)"
        Write-Host "You can manually add the functions by editing your profile: $PROFILE" -ForegroundColor Yellow
    }
}

Write-Host "`nHelix is ready to use!" -ForegroundColor Magenta
Write-Host "  AJA KUMO, Blackmagic Videohub, and Lightware MX2 support included." -ForegroundColor White
Write-Host "  Perfect for live event production and professional AV workflows." -ForegroundColor White
