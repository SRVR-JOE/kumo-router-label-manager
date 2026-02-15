@echo off
title KUMO Router Label Manager - Solotech Production Tools

echo.
echo  ╔═══════════════════════════════════════════════════════════════════════════════╗
echo  ║                    KUMO Router Label Manager v2.0                            ║
echo  ║                   Professional AV Production Tool                            ║
echo  ╚═══════════════════════════════════════════════════════════════════════════════╝
echo.

:menu
echo  Please select an option:
echo.
echo  [1] Launch GUI Application
echo  [2] Download Current Labels (Command Line)
echo  [3] Create New Template
echo  [4] Update Labels from Excel
echo  [5] Test Connection Only
echo  [6] View Quick Examples
echo  [9] Exit
echo.

set /p choice="Enter your choice (1-6, 9): "

if "%choice%"=="1" goto gui
if "%choice%"=="2" goto download
if "%choice%"=="3" goto template
if "%choice%"=="4" goto update
if "%choice%"=="5" goto test
if "%choice%"=="6" goto examples
if "%choice%"=="9" goto exit

echo Invalid choice. Please try again.
pause
goto menu

:gui
echo.
echo Launching GUI Application...
powershell -ExecutionPolicy Bypass -File "KUMO-Label-Manager.ps1"
goto menu

:download
echo.
set /p kumo_ip="Enter KUMO IP address (e.g., 192.168.1.100): "
set /p output_file="Enter output file path (e.g., C:\temp\labels.xlsx): "
echo.
echo Downloading current labels from %kumo_ip%...
powershell -ExecutionPolicy Bypass -File "KUMO-Excel-Updater.ps1" -DownloadLabels -KumoIP "%kumo_ip%" -DownloadPath "%output_file%"
pause
goto menu

:template
echo.
set /p template_file="Enter template file path (e.g., C:\temp\template.xlsx): "
echo.
echo Creating template file...
powershell -ExecutionPolicy Bypass -File "KUMO-Excel-Updater.ps1" -CreateTemplate
pause
goto menu

:update
echo.
set /p kumo_ip="Enter KUMO IP address (e.g., 192.168.1.100): "
set /p excel_file="Enter Excel file path (e.g., C:\temp\labels.xlsx): "
echo.
echo Updating labels on %kumo_ip% from %excel_file%...
powershell -ExecutionPolicy Bypass -File "KUMO-Excel-Updater.ps1" -KumoIP "%kumo_ip%" -ExcelFile "%excel_file%"
pause
goto menu

:test
echo.
set /p kumo_ip="Enter KUMO IP address (e.g., 192.168.1.100): "
set /p excel_file="Enter Excel file path (e.g., C:\temp\labels.xlsx): "
echo.
echo Testing connection and validating file...
powershell -ExecutionPolicy Bypass -File "KUMO-Excel-Updater.ps1" -KumoIP "%kumo_ip%" -ExcelFile "%excel_file%" -TestOnly
pause
goto menu

:examples
echo.
echo  ╔═══════════════════════════════════════════════════════════════════════════════╗
echo  ║                            Quick Examples                                     ║
echo  ╚═══════════════════════════════════════════════════════════════════════════════╝
echo.
echo  PowerShell Commands:
echo.
echo  Download current labels:
echo    .\KUMO-Excel-Updater.ps1 -DownloadLabels -KumoIP "192.168.1.100" -DownloadPath "labels.xlsx"
echo.
echo  Update from Excel file:
echo    .\KUMO-Excel-Updater.ps1 -KumoIP "192.168.1.100" -ExcelFile "labels.xlsx"
echo.
echo  Test only (no changes):
echo    .\KUMO-Excel-Updater.ps1 -KumoIP "192.168.1.100" -ExcelFile "labels.xlsx" -TestOnly
echo.
echo  Create template:
echo    .\KUMO-Excel-Updater.ps1 -CreateTemplate
echo.
echo  Batch multiple routers:
echo    $routers = @("192.168.1.100", "192.168.1.101")
echo    foreach ($ip in $routers) {
echo        .\KUMO-Excel-Updater.ps1 -KumoIP $ip -ExcelFile "tour_labels.xlsx"
echo    }
echo.
pause
goto menu

:exit
echo.
echo Thank you for using KUMO Router Label Manager!
echo For support, check the KUMO-Setup-Guide.md file.
pause
exit
