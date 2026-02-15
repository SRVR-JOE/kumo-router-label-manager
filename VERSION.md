# KUMO Router Label Manager - Version Information

## Current Version: 2.0.0
**Release Date**: February 14, 2026  
**Build**: Production Release  
**Compatibility**: AJA KUMO 16x16, 32x32, 64x64 routers

---

## Changelog

### Version 2.0.0 - February 14, 2026
**Major Update - Download Functionality Added**

#### ✨ New Features
- **📥 Download Current Labels**: Pull existing labels directly from KUMO router
- **🔄 Smart Connection Methods**: Multiple API endpoints with automatic fallback
- **📊 Enhanced GUI**: Live preview grid with progress tracking
- **⚡ Batch Operations**: Process multiple routers in sequence
- **🛠️ Professional Installer**: Automated setup with desktop shortcuts
- **📋 Comprehensive Templates**: Pre-configured labels for live events

#### 🔧 Improvements
- **Better Error Handling**: Detailed error messages and recovery suggestions
- **Connection Validation**: Test connectivity before making changes
- **Multiple File Formats**: Excel (.xlsx) and CSV (.csv) support
- **Progress Tracking**: Visual feedback during long operations
- **Professional UI**: Dark theme optimized for production environments

#### 🐛 Bug Fixes
- Fixed telnet connection timeout issues
- Improved Excel file parsing reliability
- Better handling of special characters in labels
- Enhanced PowerShell execution policy detection

#### 📝 Documentation
- Complete setup guide with troubleshooting
- Professional workflow examples
- Network configuration requirements
- Security best practices

---

### Version 1.0.0 - Initial Release
**Basic Functionality**

#### ✨ Features
- Upload labels from Excel spreadsheet
- GUI and command-line interfaces  
- Template generation
- 32x32 router support
- REST API and Telnet connectivity

---

## Technical Specifications

### Supported KUMO Models
- **KUMO 1616** - 16x16 SDI router
- **KUMO 3232** - 32x32 SDI router  
- **KUMO 6464** - 64x64 SDI router (via KUMO CP2)
- **KUMO 1616-12G** - 12G-SDI support
- **KUMO 3232-12G** - 12G-SDI support
- **KUMO 6464-12G** - 12G-SDI support

### Connection Methods
1. **REST API** (Primary)
   - HTTP requests to KUMO web interface
   - Bulk operations when supported
   - Individual port queries as fallback

2. **Telnet** (Fallback)
   - Direct command interface
   - Port 23 connectivity
   - Compatible with all firmware versions

3. **Configuration Export/Import**
   - Web interface backup/restore
   - Manual file editing capability

### System Requirements
- **Operating System**: Windows 10/11, Windows Server 2016+
- **PowerShell**: Version 5.1 or later
- **Network**: HTTP/Telnet access to KUMO router
- **Memory**: 100MB available RAM
- **Storage**: 50MB available disk space

### Dependencies
- **ImportExcel Module** (optional, auto-installed)
- **.NET Framework 4.5+**
- **Windows PowerShell ISE** (optional, for editing)

---

## Compatibility Matrix

| KUMO Model | Firmware | REST API | Telnet | Download | Upload |
|------------|----------|----------|--------|----------|--------|
| 1616       | 4.0+     | ✅       | ✅     | ✅       | ✅     |
| 3232       | 4.0+     | ✅       | ✅     | ✅       | ✅     |
| 6464       | 4.0+     | ✅       | ✅     | ✅       | ✅     |
| 1616-12G   | 4.5+     | ✅       | ✅     | ✅       | ✅     |
| 3232-12G   | 4.5+     | ✅       | ✅     | ✅       | ✅     |
| 6464-12G   | 4.5+     | ✅       | ✅     | ✅       | ✅     |

**Note**: Older firmware versions may have limited REST API support but telnet fallback ensures compatibility.

---

## Known Issues

### Version 2.0.0
- **Excel Large Files**: Files >5MB may load slowly
- **Network Latency**: High latency connections may timeout  
- **Character Limits**: Some KUMO models limit label length to 8-16 characters
- **Special Characters**: Avoid / \ : * ? " < > | in labels

### Workarounds
- Use CSV format for large datasets
- Increase timeout values for slow networks
- Check character limits in KUMO manual
- Test special characters on non-critical ports first

---

## Planned Features

### Version 2.1 (Planned)
- **Scheduled Updates**: Automated label synchronization
- **Multi-Router Dashboard**: Centralized management interface
- **Label Templates Library**: Predefined templates for different event types
- **Change History**: Track label modifications over time
- **Network Discovery**: Automatic KUMO router detection

### Version 2.2 (Future)
- **API Integration**: Third-party control system integration
- **Web Interface**: Browser-based management portal
- **Mobile App**: iOS/Android companion app
- **Cloud Sync**: Cloud-based configuration backup

---

## Support Information

### Technical Support
- **Documentation**: KUMO-Setup-Guide.md
- **Examples**: Quick-Start-Examples.ps1  
- **Templates**: KUMO_Labels_Template.csv
- **Installation**: Install-KUMO-Tools.ps1

### Contact Information
- **AJA Support**: support@aja.com
- **Product Manuals**: https://www.aja.com/support
- **Firmware Updates**: https://www.aja.com/support
- **Community Forums**: AJA User Forums

### Professional Services
- **Custom Integration**: Available for enterprise deployments
- **Training Services**: On-site training for production teams
- **Consulting**: Workflow optimization and best practices
- **Support Contracts**: Extended support options available

---

**© 2026 - Created for Professional Live Event Production**  
**Compatible with Solotech workflows and industry standards**
