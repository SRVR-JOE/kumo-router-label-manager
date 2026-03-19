# Helix Deployment Script
# Copies all files to target directory and sets up complete package
# Supports AJA KUMO, Blackmagic Videohub, and Lightware MX2 routers

param(
    [Parameter(Mandatory=$true)]
    [string]$TargetDirectory,

    [switch]$CreateZip,
    [switch]$InstallAfterDeploy
)

Write-Host "Helix Deployment Script v5.0" -ForegroundColor Magenta
Write-Host "AJA KUMO, Blackmagic Videohub, and Lightware MX2 support" -ForegroundColor Gray
Write-Host "Deploying complete package to: $TargetDirectory" -ForegroundColor Yellow

# Create target directory
if (-not (Test-Path $TargetDirectory)) {
    New-Item -ItemType Directory -Path $TargetDirectory -Force | Out-Null
    Write-Host "✓ Created directory: $TargetDirectory" -ForegroundColor Green
}

# File list to deploy
$files = @(
    @{ Source = "Helix-Label-Manager.ps1"; Desc = "GUI Application" },
    @{ Source = "Helix-Excel-Updater.ps1"; Desc = "Command Line Tool" },
    @{ Source = "Install-Helix-Tools.ps1"; Desc = "Installation Script" },
    @{ Source = "Helix-Setup-Guide.md"; Desc = "Setup Documentation" },
    @{ Source = "Helix_Labels_Template.csv"; Desc = "Sample Template" },
    @{ Source = "Helix-Menu.bat"; Desc = "Interactive Menu" },
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
# Helix PowerShell Launcher
# AJA KUMO, Blackmagic Videohub, and Lightware MX2 support
Set-Location -Path "$TargetDirectory"

Write-Host "Helix v5.0" -ForegroundColor Magenta
Write-Host "AJA KUMO / Blackmagic Videohub / Lightware MX2" -ForegroundColor Gray
Write-Host "Quick Commands:" -ForegroundColor Yellow
Write-Host "  gui       - Launch GUI application"
Write-Host "  download  - Download current labels (auto-detects router type)"
Write-Host "  template  - Create new template"
Write-Host "  help      - Show detailed help"
Write-Host ""

function gui {
    & ".\Helix-Label-Manager.ps1"
}

function download {
    param(`$ip, `$file, `$type = "Auto")
    if (-not `$ip) { `$ip = Read-Host "Router IP Address" }
    if (-not `$file) { `$file = "downloaded_labels.xlsx" }
    & ".\Helix-Excel-Updater.ps1" -DownloadLabels -KumoIP `$ip -DownloadPath `$file -RouterType `$type
}

function template {
    & ".\Helix-Excel-Updater.ps1" -CreateTemplate
}

function help {
    Get-Content ".\README.md" | Select-Object -First 60
    Write-Host "For complete documentation, see: README.md and Helix-Setup-Guide.md"
}

Write-Host "Ready! Type 'gui' to start or 'help' for more options." -ForegroundColor Green
"@

$psLauncher | Out-File -FilePath (Join-Path $TargetDirectory "helix.ps1") -Encoding UTF8
Write-Host "✓ Created PowerShell launcher: helix.ps1" -ForegroundColor Green

# Create start script
$startScript = @"
@echo off
cd /d "$TargetDirectory"
echo Helix v5.0
echo AJA KUMO, Blackmagic Videohub, and Lightware MX2
echo.
echo Choose your interface:
echo [1] GUI Application
echo [2] Command Menu
echo [3] PowerShell Environment
echo.
set /p choice="Enter choice (1-3): "

if "%choice%"=="1" (
    powershell -ExecutionPolicy RemoteSigned -File "Helix-Label-Manager.ps1"
) else if "%choice%"=="2" (
    call "Helix-Menu.bat"
) else if "%choice%"=="3" (
    powershell -ExecutionPolicy RemoteSigned -File "helix.ps1" -NoExit
) else (
    echo Invalid choice
    pause
)
"@

$startScript | Out-File -FilePath (Join-Path $TargetDirectory "Start-Helix.bat") -Encoding ASCII
Write-Host "✓ Created batch launcher: Start-Helix.bat" -ForegroundColor Green

# Create package information file
$packageInfo = @{
    Name = "Helix"
    Version = "5.0.0"
    DeploymentDate = Get-Date
    TargetDirectory = $TargetDirectory
    Files = $files.Count
    SupportedRouters = @("AJA KUMO 1604", "AJA KUMO 1616", "AJA KUMO 3232", "AJA KUMO 6464", "Blackmagic Videohub (all models)", "Lightware MX2 (all models)")
    Features = @(
        "Download current labels from AJA KUMO / Videohub / Lightware MX2 routers",
        "Upload labels from Excel spreadsheet or CSV",
        "AJA KUMO: REST API and Telnet fallback",
        "Blackmagic Videohub: TCP 9990 protocol with block-based label sets",
        "Lightware MX2: LW3 protocol on TCP 6107",
        "Auto-detects router type on connect",
        "Professional GUI and command-line interfaces",
        "Batch processing for multiple routers",
        "Complete documentation and examples"
    )
    QuickStart = @{
        GUI = "Start-Helix.bat or Helix-Label-Manager.ps1"
        CommandLine = "Helix-Excel-Updater.ps1 -DownloadLabels -KumoIP 'IP' -DownloadPath 'file.xlsx'"
        Menu = "Helix-Menu.bat"
        Installation = "Install-Helix-Tools.ps1"
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
    $installerPath = Join-Path $TargetDirectory "Install-Helix-Tools.ps1"
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
Supported Routers: AJA KUMO, Blackmagic Videohub, and Lightware MX2
"@ -ForegroundColor Green

if ($CreateZip) {
    Write-Host "ZIP Archive: $TargetDirectory.zip" -ForegroundColor Green
}

Write-Host @"

Quick Start Options:
• Double-click: Start-Helix.bat
• PowerShell: .\helix.ps1
• Direct GUI: .\Helix-Label-Manager.ps1
• Installation: .\Install-Helix-Tools.ps1

Package Contents:
• GUI Application with download functionality
• Command-line tool with auto router-type detection
• Complete documentation and examples
• Professional installer and launchers
• Sample templates for live events

Router Support:
• AJA KUMO 1604 / 1616 / 3232 / 6464 (REST API + Telnet)
• Blackmagic Videohub all models (TCP 9990)
• Lightware MX2 (LW3 protocol on TCP 6107)
• Router type is auto-detected on connect

Next Steps:
1. Test the tools with your router
2. Create your first label template
3. Download existing labels from your router
4. Customize for your production needs

For support: Check README.md and Helix-Setup-Guide.md
"@ -ForegroundColor White

Write-Host "`nHelix v5.0 - Ready for Professional Live Event Production!" -ForegroundColor Magenta
