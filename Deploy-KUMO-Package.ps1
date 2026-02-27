# KUMO Tools Deployment Script
# Copies all files to target directory and sets up complete package

param(
    [Parameter(Mandatory=$true)]
    [string]$TargetDirectory,
    
    [switch]$CreateZip,
    [switch]$InstallAfterDeploy
)

Write-Host "KUMO Tools Deployment Script v2.0" -ForegroundColor Magenta
Write-Host "Deploying complete package to: $TargetDirectory" -ForegroundColor Yellow

# Create target directory
if (-not (Test-Path $TargetDirectory)) {
    New-Item -ItemType Directory -Path $TargetDirectory -Force | Out-Null
    Write-Host "✓ Created directory: $TargetDirectory" -ForegroundColor Green
}

# File list to deploy
$files = @(
    @{ Source = "KUMO-Label-Manager.ps1"; Desc = "GUI Application" },
    @{ Source = "KUMO-Excel-Updater.ps1"; Desc = "Command Line Tool" },
    @{ Source = "Install-KUMO-Tools.ps1"; Desc = "Installation Script" },
    @{ Source = "KUMO-Setup-Guide.md"; Desc = "Setup Documentation" },
    @{ Source = "KUMO_Labels_Template.csv"; Desc = "Sample Template" },
    @{ Source = "KUMO-Menu.bat"; Desc = "Interactive Menu" },
    @{ Source = "README.md"; Desc = "Main Documentation" },
    @{ Source = "VERSION.md"; Desc = "Version Information" }
)

# Copy files
Write-Host "`nCopying files..." -ForegroundColor Yellow
foreach ($file in $files) {
    $sourcePath = $file.Source
    $targetPath = Join-Path $TargetDirectory $file.Source
    
    if (Test-Path $sourcePath) {
        Copy-Item $sourcePath $targetPath -Force
        Write-Host "✓ $($file.Source) - $($file.Desc)" -ForegroundColor Green
    } else {
        Write-Warning "Missing file: $sourcePath"
    }
}

# Create launcher scripts
Write-Host "`nCreating launcher scripts..." -ForegroundColor Yellow

# PowerShell launcher
$psLauncher = @"
# KUMO Tools PowerShell Launcher
Set-Location -Path "$TargetDirectory"

Write-Host "KUMO Router Label Manager v2.0" -ForegroundColor Magenta
Write-Host "Quick Commands:" -ForegroundColor Yellow
Write-Host "  gui       - Launch GUI application"
Write-Host "  download  - Download current labels"
Write-Host "  template  - Create new template"
Write-Host "  help      - Show detailed help"
Write-Host ""

function gui { 
    & ".\KUMO-Label-Manager.ps1" 
}

function download {
    param($ip, $file)
    if (-not $ip) { $ip = Read-Host "KUMO IP Address" }
    if (-not $file) { $file = "downloaded_labels.xlsx" }
    & ".\KUMO-Excel-Updater.ps1" -DownloadLabels -KumoIP $ip -DownloadPath $file
}

function template {
    & ".\KUMO-Excel-Updater.ps1" -CreateTemplate
}

function help {
    Get-Content ".\README.md" | Select-Object -First 50
    Write-Host "For complete documentation, see: README.md and KUMO-Setup-Guide.md"
}

Write-Host "Ready! Type 'gui' to start or 'help' for more options." -ForegroundColor Green
"@

$psLauncher | Out-File -FilePath (Join-Path $TargetDirectory "kumo.ps1") -Encoding UTF8
Write-Host "✓ Created PowerShell launcher: kumo.ps1" -ForegroundColor Green

# Create start script
$startScript = @"
@echo off
cd /d "$TargetDirectory"
echo KUMO Router Label Manager v2.0
echo.
echo Choose your interface:
echo [1] GUI Application
echo [2] Command Menu  
echo [3] PowerShell Environment
echo.
set /p choice="Enter choice (1-3): "

if "%choice%"=="1" (
    powershell -ExecutionPolicy Bypass -File "KUMO-Label-Manager.ps1"
) else if "%choice%"=="2" (
    call "KUMO-Menu.bat"
) else if "%choice%"=="3" (
    powershell -ExecutionPolicy Bypass -File "kumo.ps1" -NoExit
) else (
    echo Invalid choice
    pause
)
"@

$startScript | Out-File -FilePath (Join-Path $TargetDirectory "Start-KUMO-Tools.bat") -Encoding ASCII
Write-Host "✓ Created batch launcher: Start-KUMO-Tools.bat" -ForegroundColor Green

# Create package information file
$packageInfo = @{
    Name = "KUMO Router Label Manager"
    Version = "2.0.0"
    DeploymentDate = Get-Date
    TargetDirectory = $TargetDirectory
    Files = $files.Count
    Features = @(
        "Download current labels from KUMO router",
        "Upload labels from Excel spreadsheet", 
        "Professional GUI and command-line interfaces",
        "Support for 32x32 router configurations",
        "Multiple connection methods with fallback",
        "Batch processing for multiple routers",
        "Complete documentation and examples"
    )
    QuickStart = @{
        GUI = "Start-KUMO-Tools.bat or KUMO-Label-Manager.ps1"
        CommandLine = "KUMO-Excel-Updater.ps1 -DownloadLabels -KumoIP 'IP' -DownloadPath 'file.xlsx'"
        Menu = "KUMO-Menu.bat"
        Installation = "Install-KUMO-Tools.ps1"
    }
} | ConvertTo-Json -Depth 3

$packageInfo | Out-File -FilePath (Join-Path $TargetDirectory "package-info.json") -Encoding UTF8
Write-Host "✓ Created package info: package-info.json" -ForegroundColor Green

# Create ZIP file if requested
if ($CreateZip) {
    Write-Host "`nCreating ZIP archive..." -ForegroundColor Yellow
    $zipPath = "$TargetDirectory.zip"
    
    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force
    }
    
    try {
        # Use .NET compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($TargetDirectory, $zipPath)
        Write-Host "✓ Created ZIP archive: $zipPath" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to create ZIP: $($_.Exception.Message)"
        Write-Host "You can create the ZIP manually from: $TargetDirectory" -ForegroundColor Yellow
    }
}

# Run installer if requested
if ($InstallAfterDeploy) {
    Write-Host "`nRunning installation..." -ForegroundColor Yellow
    $installerPath = Join-Path $TargetDirectory "Install-KUMO-Tools.ps1"
    if (Test-Path $installerPath) {
        & $installerPath -InstallPath $TargetDirectory -CreateDesktopShortcuts
    } else {
        Write-Warning "Installer not found at: $installerPath"
    }
}

# Display summary
Write-Host @"

╔═══════════════════════════════════════════════════════════════════════════════╗
║                          Deployment Complete!                                ║  
╚═══════════════════════════════════════════════════════════════════════════════╝

Package Location: $TargetDirectory
Files Deployed: $($files.Count + 4) (including launchers)
"@ -ForegroundColor Green

if ($CreateZip) {
    Write-Host "ZIP Archive: $TargetDirectory.zip" -ForegroundColor Green
}

Write-Host @"

Quick Start Options:
• Double-click: Start-KUMO-Tools.bat
• PowerShell: .\kumo.ps1  
• Direct GUI: .\KUMO-Label-Manager.ps1
• Installation: .\Install-KUMO-Tools.ps1

Package Contents:
• GUI Application with download functionality
• Command-line tool for automation
• Complete documentation and examples
• Professional installer and launchers
• Sample templates for live events

Next Steps:
1. Test the tools with your KUMO router
2. Create your first label template
3. Download existing labels from your router
4. Customize for your production needs

For support: Check README.md and KUMO-Setup-Guide.md
"@ -ForegroundColor White

Write-Host "`n🎉 KUMO Tools v2.0 - Ready for Professional Live Event Production!" -ForegroundColor Magenta
