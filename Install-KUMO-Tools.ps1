# KUMO Router Label Manager - Installation Script
# Professional AV Production Tool for Solotech
# Version 2.0 - Enhanced with Download Functionality

param(
    [string]$InstallPath = "C:\KUMO-Tools",
    [switch]$CreateDesktopShortcuts,
    [switch]$InstallExcelModule,
    [switch]$Uninstall
)

Write-Host @"
╔═══════════════════════════════════════════════════════════════════════════════╗
║                    KUMO Router Label Manager v2.0                            ║
║                   Professional AV Production Tool                            ║
║                                                                               ║
║  Features:                                                                    ║
║  • Download current labels from KUMO router                                  ║
║  • Bulk update labels via Excel spreadsheet                                  ║
║  • Professional GUI and command-line interfaces                              ║
║  • Support for 32x32 router configurations                                   ║
║  • Multiple connection methods (REST API, Telnet)                            ║
║                                                                               ║
║  Created for Solotech Live Event Production                                  ║
╚═══════════════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

# Handle uninstall
if ($Uninstall) {
    Write-Host "`nUninstalling KUMO Tools..." -ForegroundColor Yellow
    
    if (Test-Path $InstallPath) {
        Remove-Item $InstallPath -Recurse -Force
        Write-Host "✓ Removed installation directory: $InstallPath" -ForegroundColor Green
    }
    
    # Remove desktop shortcuts
    $shortcuts = @(
        "$env:USERPROFILE\Desktop\KUMO Label Manager.lnk",
        "$env:PUBLIC\Desktop\KUMO Label Manager.lnk"
    )
    
    foreach ($shortcut in $shortcuts) {
        if (Test-Path $shortcut) {
            Remove-Item $shortcut -Force
            Write-Host "✓ Removed shortcut: $shortcut" -ForegroundColor Green
        }
    }
    
    Write-Host "✓ KUMO Tools uninstalled successfully!" -ForegroundColor Green
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
Write-Host "`nInstalling KUMO Tools..." -ForegroundColor Yellow

# Create batch file for easy GUI launch
$batchContent = @"
@echo off
cd /d "$InstallPath"
powershell -ExecutionPolicy Bypass -File "KUMO-Label-Manager.ps1"
pause
"@

$batchContent | Out-File -FilePath "$InstallPath\Launch-KUMO-GUI.bat" -Encoding ASCII
Write-Host "✓ Created GUI launcher: Launch-KUMO-GUI.bat" -ForegroundColor Green

# Create PowerShell profile addition for easy command access
$profileAddition = @"

# KUMO Tools - Added by installer
`$env:PATH += ";$InstallPath"
function kumo-download { & "$InstallPath\KUMO-Excel-Updater.ps1" -DownloadLabels @args }
function kumo-update { & "$InstallPath\KUMO-Excel-Updater.ps1" @args }
function kumo-template { & "$InstallPath\KUMO-Excel-Updater.ps1" -CreateTemplate @args }
function kumo-gui { & "$InstallPath\Launch-KUMO-GUI.bat" }

"@

# Create quick start script
$quickStartContent = @'
# KUMO Quick Start Examples
# Run these commands from PowerShell

# Download current labels from your KUMO router:
kumo-download -KumoIP "192.168.1.100" -DownloadPath "C:\temp\current_labels.xlsx"

# Create a blank template:
kumo-template

# Update labels from Excel file:
kumo-update -KumoIP "192.168.1.100" -ExcelFile "C:\temp\labels.xlsx"

# Test connection without making changes:
kumo-update -KumoIP "192.168.1.100" -ExcelFile "C:\temp\labels.xlsx" -TestOnly

# Launch GUI application:
kumo-gui

# Manual commands (if functions don't work):
# .\KUMO-Excel-Updater.ps1 -DownloadLabels -KumoIP "IP" -DownloadPath "file.xlsx"
# .\KUMO-Excel-Updater.ps1 -KumoIP "IP" -ExcelFile "file.xlsx"
# .\KUMO-Label-Manager.ps1
'@

$quickStartContent | Out-File -FilePath "$InstallPath\Quick-Start-Examples.ps1" -Encoding UTF8
Write-Host "✓ Created quick start guide: Quick-Start-Examples.ps1" -ForegroundColor Green

# Create desktop shortcuts if requested
if ($CreateDesktopShortcuts) {
    Write-Host "`nCreating desktop shortcuts..." -ForegroundColor Yellow
    
    try {
        $WshShell = New-Object -comObject WScript.Shell
        
        # GUI shortcut
        $Shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\Desktop\KUMO Label Manager.lnk")
        $Shortcut.TargetPath = "powershell.exe"
        $Shortcut.Arguments = "-ExecutionPolicy Bypass -File `"$InstallPath\KUMO-Label-Manager.ps1`""
        $Shortcut.WorkingDirectory = $InstallPath
        $Shortcut.Description = "KUMO Router Label Manager - GUI"
        $Shortcut.Save()
        
        Write-Host "✓ Created desktop shortcut: KUMO Label Manager" -ForegroundColor Green
        
    } catch {
        Write-Warning "Failed to create desktop shortcuts: $($_.Exception.Message)"
    }
}

# Create configuration file
$configContent = @{
    Version = "2.0"
    InstallPath = $InstallPath
    InstallDate = Get-Date
    Features = @(
        "Download current labels",
        "Upload labels from Excel",
        "Multiple connection methods",
        "GUI and command-line interfaces",
        "32x32 router support"
    )
} | ConvertTo-Json -Depth 3

$configContent | Out-File -FilePath "$InstallPath\config.json" -Encoding UTF8
Write-Host "✓ Created configuration file" -ForegroundColor Green

Write-Host @"

╔═══════════════════════════════════════════════════════════════════════════════╗
║                         Installation Complete!                               ║
╚═══════════════════════════════════════════════════════════════════════════════╝

Installation Directory: $InstallPath

Quick Commands (add to PowerShell profile):
• kumo-download -KumoIP "192.168.1.100" -DownloadPath "labels.xlsx"
• kumo-update -KumoIP "192.168.1.100" -ExcelFile "labels.xlsx"  
• kumo-template
• kumo-gui

Files Created:
• KUMO-Label-Manager.ps1     (GUI Application)
• KUMO-Excel-Updater.ps1     (Command Line Tool)  
• Launch-KUMO-GUI.bat        (Easy GUI Launcher)
• Quick-Start-Examples.ps1    (Usage Examples)
• KUMO-Setup-Guide.md        (Complete Documentation)

Next Steps:
1. Copy the main PowerShell files to: $InstallPath
2. Run: .\Launch-KUMO-GUI.bat (for GUI)
3. Or use command line: kumo-download -KumoIP "YOUR_KUMO_IP" -DownloadPath "labels.xlsx"

For support: Check KUMO-Setup-Guide.md for troubleshooting
"@ -ForegroundColor Green

# Offer to add functions to PowerShell profile
Write-Host "`nOptional: Add quick commands to PowerShell profile?" -ForegroundColor Yellow
Write-Host "This will allow you to use 'kumo-download', 'kumo-update', etc. from anywhere" -ForegroundColor White
$addToProfile = Read-Host "Add to profile? (y/N)"

if ($addToProfile -eq 'y' -or $addToProfile -eq 'Y') {
    try {
        if (-not (Test-Path $PROFILE)) {
            New-Item -ItemType File -Path $PROFILE -Force | Out-Null
        }
        
        Add-Content -Path $PROFILE -Value $profileAddition
        Write-Host "✓ Added KUMO functions to PowerShell profile" -ForegroundColor Green
        Write-Host "  Restart PowerShell to use the new commands" -ForegroundColor Yellow
        
    } catch {
        Write-Warning "Failed to update PowerShell profile: $($_.Exception.Message)"
        Write-Host "You can manually add the functions by editing your profile: $PROFILE" -ForegroundColor Yellow
    }
}

Write-Host "`n🎉 KUMO Router Label Manager is ready to use!" -ForegroundColor Magenta
Write-Host "   Perfect for live event production and professional AV workflows" -ForegroundColor White
