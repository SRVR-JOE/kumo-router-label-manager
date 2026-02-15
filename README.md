# KUMO Router Label Manager v2.0

**Professional AV Production Tool for Live Events**

## 🎯 Overview

Complete solution for managing AJA KUMO router labels via Excel spreadsheets. Designed for professional live event production environments like concerts, tours, and corporate events.

### ✨ Key Features

- **📥 Download Current Labels** - Pull existing labels from your KUMO router
- **📊 Excel Integration** - Bulk edit labels in familiar spreadsheet format  
- **🚀 Multiple Interfaces** - GUI application and command-line tools
- **🔄 Smart Connection** - REST API with Telnet fallback
- **🎛️ 32x32 Support** - Full support for KUMO 32x32 routers
- **⚡ Batch Processing** - Update multiple routers in sequence
- **🛡️ Safe Updates** - Test mode and connection validation

## 📦 Package Contents

```
KUMO-Tools/
├── Install-KUMO-Tools.ps1      # Installation script
├── KUMO-Label-Manager.ps1      # GUI application (main tool)
├── KUMO-Excel-Updater.ps1      # Command-line tool
├── KUMO-Setup-Guide.md         # Complete documentation
├── KUMO_Labels_Template.csv    # Sample template with pro labels
├── Launch-KUMO-GUI.bat         # Easy GUI launcher
├── Quick-Start-Examples.ps1    # Usage examples
└── README.md                   # This file
```

## 🚀 Quick Start

### Installation
```powershell
# Run the installer
.\Install-KUMO-Tools.ps1 -InstallPath "C:\KUMO-Tools" -CreateDesktopShortcuts -InstallExcelModule
```

### Download Your Current Labels
```powershell
# GUI Method
.\KUMO-Label-Manager.ps1
# 1. Enter IP, click "Test Connection"
# 2. Click "Download Current Labels"
# 3. Edit the Excel file, then upload changes

# Command Line Method
.\KUMO-Excel-Updater.ps1 -DownloadLabels -KumoIP "192.168.1.100" -DownloadPath "current.xlsx"
```

### Update Labels
```powershell
# After editing your Excel file
.\KUMO-Excel-Updater.ps1 -KumoIP "192.168.1.100" -ExcelFile "current.xlsx"
```

## 🎛️ Perfect for Live Events

### Concert Tours
- **Inputs**: Camera 1 Main, Camera 2 Wide, Playback 1 Pro, LED Wall Feed
- **Outputs**: Program Mon, IMAG Left/Right, Streaming Enc, Record Main

### Corporate Events  
- **Inputs**: Presenter Cam, Laptop 1/2, Confidence Mon Return
- **Outputs**: Main Screen, Confidence Mon, Stream Encoder, Record

### Multi-Day Festivals
- **Stage A/B/C configurations**
- **Shared resources**: Graphics, Playback, Streaming
- **Quick changeovers** between acts

## 💡 Advanced Usage

### Batch Multiple Routers
```powershell
$routers = @("192.168.1.100", "192.168.1.101", "192.168.1.102") 
foreach ($ip in $routers) {
    .\KUMO-Excel-Updater.ps1 -KumoIP $ip -ExcelFile "TourLabels.xlsx"
}
```

### Integration with Show Documentation
```powershell
# Export for CAD systems
$labels = Import-Csv "KUMO_Labels.csv"
$labels | Export-Csv "Vectorworks_Import.csv" -NoTypeInformation

# Create show reports
$labels | Where-Object {$_.New_Label -ne ""} | 
    Format-Table Port, Type, New_Label -AutoSize | 
    Out-File "ShowFile_VideoRouting.txt"
```

### Scheduled Verification
```powershell
# Daily label verification during multi-day events
$downloaded = .\KUMO-Excel-Updater.ps1 -DownloadLabels -KumoIP "192.168.1.100" -DownloadPath "verify.xlsx"
# Compare with master template and alert on changes
```

## 🔧 Technical Requirements

### System Requirements
- **Windows 10/11** or **Windows Server 2016+**
- **PowerShell 5.1** or **PowerShell 7+**
- **.NET Framework 4.5+**
- **Network access** to KUMO router

### Network Requirements
- **HTTP (port 80)** - For REST API access
- **Telnet (port 23)** - For fallback communication  
- **Same network segment** or **routed access** to KUMO IP

### Optional Dependencies
- **ImportExcel module** - For .xlsx support (auto-installed)
- **Excel/Office** - Not required (uses ImportExcel instead)

## 🛠️ Troubleshooting

### Connection Issues
```powershell
# Test basic connectivity
ping 192.168.1.100
telnet 192.168.1.100 23

# Check Windows features
dism /online /Enable-Feature /FeatureName:TelnetClient
```

### PowerShell Issues
```powershell
# Fix execution policy
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser

# Install missing modules
Install-Module ImportExcel -Scope CurrentUser -Force
```

### KUMO Router Issues
- **Enable telnet service** via KUMO web interface
- **Check firmware version** (affects API endpoints)
- **Verify network settings** in KUMO configuration

## 📋 Excel Template Format

| Port | Type   | Current_Label | New_Label     | Notes              |
|------|--------|---------------|---------------|--------------------|
| 1    | INPUT  | Input 1       | Camera 1 Main | Main stage camera  |
| 2    | INPUT  | Input 2       | Camera 2 Wide | Wide stage shot    |
| 1    | OUTPUT | Output 1      | Program Mon   | Main program mon   |
| 2    | OUTPUT | Output 2      | LED Wall Main | Primary LED wall   |

### Column Descriptions
- **Port**: 1-32 (port number)
- **Type**: INPUT or OUTPUT  
- **Current_Label**: What's currently on the router
- **New_Label**: Your desired label (what gets uploaded)
- **Notes**: Optional documentation

## 🎪 Production Workflows

### Pre-Show Setup
1. **Download** current router labels
2. **Document** in master show file
3. **Plan** label changes for different segments
4. **Test** connections and verify functionality

### During Show
1. **Quick updates** between acts/segments
2. **Batch changes** for scene transitions  
3. **Verify** critical paths remain labeled
4. **Document** any emergency changes

### Post-Show  
1. **Export** final configuration
2. **Archive** for future shows
3. **Create templates** for similar events
4. **Update** master equipment documentation

## 🔐 Security & Best Practices

### Network Security
- Use **dedicated production network** segment
- **Limit access** to KUMO management interfaces
- **Document** all configuration changes
- **Backup** configurations before major updates

### Change Management
- **Test** changes on backup router when possible
- **Verify** critical signal paths after updates
- **Coordinate** with all production departments
- **Maintain** change logs for show reports

### Data Backup
- **Export** labels before each show
- **Archive** configurations by date/event
- **Store** templates for different show types
- **Sync** with master equipment database

## 📞 Support

### Tool-Specific Issues
- Check **KUMO-Setup-Guide.md** for detailed troubleshooting
- Verify **PowerShell execution policy** settings
- Test **network connectivity** to KUMO router
- Review **Excel file format** and structure

### AJA KUMO Support
- **AJA Technical Support**: support@aja.com
- **Product manuals**: https://www.aja.com/support
- **Firmware updates**: https://www.aja.com/support
- **User forums**: AJA community forums

### Live Event Production
- Integrate with existing **show documentation** workflows
- Coordinate with **video engineering** and **systems teams**
- Follow **venue-specific** network and equipment policies
- Maintain **backup procedures** for critical shows

---

## 📜 Version History

### v2.0 (Current)
- ✅ **Download current labels** from KUMO router
- ✅ **Enhanced GUI** with live preview and progress tracking
- ✅ **Multiple connection methods** (REST API + Telnet)
- ✅ **Improved error handling** and connection validation
- ✅ **Professional installer** with desktop shortcuts
- ✅ **Batch processing** capabilities for multiple routers

### v1.0 
- ✅ **Basic label upload** functionality
- ✅ **Excel template** generation
- ✅ **Command-line** and **GUI** interfaces
- ✅ **32x32 router support**

---

**Created for professional live event production environments**  
**Compatible with Solotech workflows and industry standards**

🎤 *Perfect for concerts, tours, festivals, and corporate events*
