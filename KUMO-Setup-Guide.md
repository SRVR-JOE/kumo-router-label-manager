# KUMO Router Label Manager Setup Guide
# Professional AV Production Tool for Solotech

## Quick Start Guide

### Option 1: GUI Application (Recommended for first-time users)
1. Run the GUI application:
   ```powershell
   .\KUMO-Label-Manager.ps1
   ```
2. Enter your KUMO router IP address
3. Click "Test Connection"
4. **Download current labels**: Click "Download Current Labels" to pull existing labels from KUMO
5. **OR Create template**: Click "Create Excel Template" to generate a blank template
6. Edit the Excel file with your label names (update the 'New_Label' column)
7. Load the Excel file and click "Upload Labels to KUMO"

### Option 2: Command Line (Recommended for automation)

#### Download Current Labels:
```powershell
.\KUMO-Excel-Updater.ps1 -DownloadLabels -KumoIP "192.168.1.100" -DownloadPath "current_labels.xlsx"
```

#### Create Blank Template:
```powershell
.\KUMO-Excel-Updater.ps1 -CreateTemplate
# Enter path: C:\Production\KUMO_Labels.xlsx
```

#### Test Connection:
```powershell
.\KUMO-Excel-Updater.ps1 -KumoIP "192.168.1.100" -ExcelFile "KUMO_Labels.xlsx" -TestOnly
```

#### Update Labels:
```powershell
.\KUMO-Excel-Updater.ps1 -KumoIP "192.168.1.100" -ExcelFile "KUMO_Labels.xlsx"
```

## Excel Template Structure

Your Excel file should have these columns:
- **Port**: 1-32 (port number)
- **Type**: INPUT or OUTPUT
- **Current_Label**: Current label on the router
- **New_Label**: Your new desired label
- **Notes**: Optional notes

## Example Labels for Live Production

### Input Labels (Cameras & Sources):
- Camera 1 Main
- Camera 2 Wide
- Camera 3 Close
- Camera 4 Overhead
- Playback 1 Pro
- Playback 2 Backup
- Graphics Mac
- LED Wall Feed
- Record ISO

### Output Labels (Destinations):
- Program Mon
- Preview Mon
- Director Mon
- LED Wall Main
- Streaming Enc
- Record Main
- Backstage Mon
- FOH Mon

## Network Requirements

### KUMO Router Network Setup:
- Ensure KUMO is on same network segment
- Default KUMO IP: 192.168.0.100
- Web interface: http://[KUMO_IP]
- Telnet port: 23 (if enabled)

### Firewall Requirements:
- Allow outbound HTTP (port 80) to KUMO
- Allow outbound Telnet (port 23) if using telnet method

## Troubleshooting

### Connection Issues:
1. **Can't connect to KUMO**:
   - Verify IP address
   - Check network cable
   - Try pinging the KUMO: `ping 192.168.1.100`
   - Access web interface manually in browser

2. **Telnet connection fails**:
   - Telnet may be disabled on KUMO
   - Use web interface to enable telnet service
   - Check Windows Telnet client: `dism /online /Enable-Feature /FeatureName:TelnetClient`

3. **REST API fails**:
   - KUMO firmware version may affect API endpoints
   - Try different firmware versions
   - Fallback to telnet method

### Excel Issues:
1. **ImportExcel module missing**:
   ```powershell
   Install-Module ImportExcel -Scope CurrentUser -Force
   ```

2. **Excel file corrupted**:
   - Re-create template
   - Save as .xlsx format
   - Avoid special characters in labels

### Label Update Issues:
1. **Some labels don't update**:
   - Check character limits (usually 8-16 chars)
   - Avoid special characters: / \ : * ? " < > |
   - Use alphanumeric and spaces only

2. **Changes don't persist**:
   - SAVE command may have failed
   - Check KUMO web interface to verify
   - Try manual save via web interface

## Integration with Existing Workflows

### For Excel-Based Documentation:
- Export current labels to match your existing spreadsheets
- Use VLOOKUP to map old/new labels
- Automate with PowerShell and Excel macros

### For Network Documentation:
- Integrate with your existing Netgear switch documentation
- Cross-reference VLAN assignments with router labels
- Export labels for CAD/Vectorworks integration

### For Show Files:
- Create templates for different show types:
  - Concert tours (cameras, playback, LED walls)
  - Corporate events (presentations, cameras, confidence monitors)
  - Festivals (multiple stages, shared resources)

## Advanced Usage

### Batch Processing Multiple Routers:
```powershell
# Process multiple KUMO routers
$routers = @("192.168.1.100", "192.168.1.101", "192.168.1.102")
foreach ($router in $routers) {
    .\KUMO-Excel-Updater.ps1 -KumoIP $router -ExcelFile "Tour_Labels.xlsx"
}
```

### Integration with Tour Management:
```powershell
# Load from master tour spreadsheet
$tourData = Import-Excel "PostMalone_Tour_2025.xlsx" -WorksheetName "VideoRouting"
# Convert to KUMO format and update
```

### Scheduled Updates:
```powershell
# Create scheduled task for daily label verification
# Useful for multi-day events with changing configurations
```

## Security Notes

- Use dedicated network segment for production equipment
- Limit access to KUMO management interfaces
- Document all label changes for show reports
- Backup configurations before major updates

## Support

For issues specific to this tool, check:
1. PowerShell execution policy: `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`
2. Network connectivity to KUMO
3. Excel file format and structure
4. KUMO firmware version compatibility

For AJA KUMO support:
- AJA Technical Support: support@aja.com
- KUMO Manual: Check AJA website for latest documentation
- Firmware updates: https://www.aja.com/support

---
Created for professional live event production environments
Compatible with Solotech workflows and equipment standards
