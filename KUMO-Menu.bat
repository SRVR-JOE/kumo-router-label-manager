@echo off
title Router Label Manager - Solotech Production Tools

echo.
echo  ╔═══════════════════════════════════════════════════════════════════════════════╗
echo  ║                       Router Label Manager v4.0                              ║
echo  ║                  AJA KUMO ^& Blackmagic Videohub                             ║
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
set /p kumo_ip="Enter router IP address (e.g., 192.168.1.100): "
set /p output_file="Enter output file path (e.g., C:\temp\labels.xlsx): "
echo.
echo Downloading current labels from %kumo_ip% (router type auto-detected)...
powershell -ExecutionPolicy Bypass -File "KUMO-Excel-Updater.ps1" -DownloadLabels -KumoIP "%kumo_ip%" -DownloadPath "%output_file%"
pause
goto menu

:template
echo.
set /p template_file="Enter output file path (e.g., C:\temp\template.xlsx): "
echo.
echo Creating template file...
powershell -ExecutionPolicy Bypass -File "KUMO-Excel-Updater.ps1" -CreateTemplate -DownloadPath "%template_file%"
pause
goto menu

:update
echo.
set /p kumo_ip="Enter router IP address (e.g., 192.168.1.100): "
set /p excel_file="Enter label file path (e.g., C:\temp\labels.xlsx): "
echo.
echo Updating labels on %kumo_ip% from %excel_file% (router type auto-detected)...
powershell -ExecutionPolicy Bypass -File "KUMO-Excel-Updater.ps1" -KumoIP "%kumo_ip%" -ExcelFile "%excel_file%"
pause
goto menu

:test
echo.
set /p kumo_ip="Enter router IP address (e.g., 192.168.1.100): "
set /p excel_file="Enter label file path (e.g., C:\temp\labels.xlsx): "
echo.
echo Testing connection and validating file...
powershell -ExecutionPolicy Bypass -File "KUMO-Excel-Updater.ps1" -KumoIP "%kumo_ip%" -ExcelFile "%excel_file%" -TestOnly
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
echo  Download labels from KUMO or Videohub:
echo    .\KUMO-Excel-Updater.ps1 -DownloadLabels -KumoIP "192.168.1.100" -DownloadPath "labels.xlsx"
echo.
echo  Download from Videohub (explicit):
echo    .\KUMO-Excel-Updater.ps1 -RouterType Videohub -DownloadLabels -KumoIP "192.168.1.101" -DownloadPath "vh.csv"
echo.
echo  Update from Excel/CSV file:
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
echo Thank you for using Router Label Manager!
echo Supports AJA KUMO and Blackmagic Videohub routers.
echo For support, check the README.md file.
pause
exit
