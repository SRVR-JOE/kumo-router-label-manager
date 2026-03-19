@echo off
title Helix - Solotech Production Tools

echo.
echo  ╔═══════════════════════════════════════════════════════════════════════════════╗
echo  ║                            Helix v5.5                                        ║
echo  ║            AJA KUMO ^& Blackmagic Videohub ^& Lightware MX2                  ║
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
powershell -ExecutionPolicy RemoteSigned -File "Helix-Label-Manager.ps1"
goto menu

:download
echo.
set /p router_ip="Enter router IP address (e.g., 192.168.1.100): "
set /p output_file="Enter output file path (e.g., C:\temp\labels.xlsx): "
echo.
echo Downloading current labels from %router_ip% (router type auto-detected)...
powershell -ExecutionPolicy RemoteSigned -File "Helix-Excel-Updater.ps1" -DownloadLabels -KumoIP "%router_ip%" -DownloadPath "%output_file%"
pause
goto menu

:template
echo.
set /p template_file="Enter output file path (e.g., C:\temp\template.xlsx): "
echo.
echo Creating template file...
powershell -ExecutionPolicy RemoteSigned -File "Helix-Excel-Updater.ps1" -CreateTemplate -DownloadPath "%template_file%"
pause
goto menu

:update
echo.
set /p router_ip="Enter router IP address (e.g., 192.168.1.100): "
set /p excel_file="Enter label file path (e.g., C:\temp\labels.xlsx): "
echo.
echo Updating labels on %router_ip% from %excel_file% (router type auto-detected)...
powershell -ExecutionPolicy RemoteSigned -File "Helix-Excel-Updater.ps1" -KumoIP "%router_ip%" -ExcelFile "%excel_file%"
pause
goto menu

:test
echo.
set /p router_ip="Enter router IP address (e.g., 192.168.1.100): "
set /p excel_file="Enter label file path (e.g., C:\temp\labels.xlsx): "
echo.
echo Testing connection and validating file...
powershell -ExecutionPolicy RemoteSigned -File "Helix-Excel-Updater.ps1" -KumoIP "%router_ip%" -ExcelFile "%excel_file%" -TestOnly
pause
goto menu

:examples
echo.
echo  ╔═══════════════════════════════════════════════════════════════════════════════╗
echo  ║                            Quick Examples                                    ║
echo  ╚═══════════════════════════════════════════════════════════════════════════════╝
echo.
echo  PowerShell Commands (router type auto-detected):
echo.
echo  Download labels from any supported router:
echo    .\Helix-Excel-Updater.ps1 -DownloadLabels -KumoIP "192.168.1.100" -DownloadPath "labels.xlsx"
echo.
echo  Download from Videohub (explicit):
echo    .\Helix-Excel-Updater.ps1 -RouterType Videohub -DownloadLabels -KumoIP "192.168.1.101" -DownloadPath "vh.csv"
echo.
echo  Update from Excel/CSV file:
echo    .\Helix-Excel-Updater.ps1 -KumoIP "192.168.1.100" -ExcelFile "labels.xlsx"
echo.
echo  Test only (no changes):
echo    .\Helix-Excel-Updater.ps1 -KumoIP "192.168.1.100" -ExcelFile "labels.xlsx" -TestOnly
echo.
echo  Create template:
echo    .\Helix-Excel-Updater.ps1 -CreateTemplate
echo.
echo  Batch multiple routers:
echo    $routers = @("192.168.1.100", "192.168.1.101")
echo    foreach ($ip in $routers) {
echo        .\Helix-Excel-Updater.ps1 -KumoIP $ip -ExcelFile "tour_labels.xlsx"
echo    }
echo.
pause
goto menu

:exit
echo.
echo Thank you for using Helix!
echo Supports AJA KUMO, Blackmagic Videohub, and Lightware MX2 routers.
echo For support, check the README.md file.
pause
exit
