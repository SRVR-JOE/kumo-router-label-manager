; =============================================================================
; Helix v5.0 - Inno Setup Installer Script
; Publisher: Solotech
; Install target: {commonpf}\Helix
;
; Build with Inno Setup 6.x: https://jrsoftware.org/isinfo.php
; NOTE: The Python CLI backend is NOT included here — install it separately
;       with:  pip install helix-router-manager
; =============================================================================

#define AppName    "Helix"
#define AppVersion "5.0"
#define AppFullVer "5.0.0"
#define Publisher  "Solotech"
#define AppURL     "https://github.com/SRVR-JOE/helix"
#define InstallDir "Helix"

; ---------------------------------------------------------------------------
; [Setup] — global installer configuration
; ---------------------------------------------------------------------------
[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#AppName} v{#AppVersion}
AppVersion={#AppFullVer}
AppVerName={#AppName} v{#AppVersion}
AppPublisher={#Publisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL={#AppURL}

; Default install path — uses Program Files (x86) on 64-bit, Program Files on 32-bit
DefaultDirName={commonpf}\{#InstallDir}
DefaultGroupName={#AppName}
AllowNoIcons=no

; Output
OutputDir=dist
OutputBaseFilename=Helix-v{#AppVersion}-Setup
SetupIconFile=

; Compression
Compression=lzma2/ultra64
SolidCompression=yes
InternalCompressLevel=ultra64

; Wizard appearance
WizardStyle=modern
WizardResizable=no
DisableWelcomePage=no
DisableDirPage=no
DisableProgramGroupPage=no
DisableReadyPage=no

; Privileges — install for all users
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog

; Uninstaller
Uninstallable=yes
UninstallDisplayName={#AppName} v{#AppVersion}
UninstallDisplayIcon={app}\Helix-Label-Manager.ps1

; Minimum OS: Windows 10 (build 10240)
MinVersion=10.0.10240

; ---------------------------------------------------------------------------
; [Languages]
; ---------------------------------------------------------------------------
[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

; ---------------------------------------------------------------------------
; [Tasks] — optional steps the user can opt into during install
; ---------------------------------------------------------------------------
[Tasks]
Name: "desktopicon"; Description: "Create a &Desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

; ---------------------------------------------------------------------------
; [Files] — which files to bundle and where to install them
;
; Exclusions (never included):
;   .git, __pycache__, .env, error*.txt, docs/plans/
;   Python source tree (src/, pyproject.toml, requirements.txt, etc.)
; ---------------------------------------------------------------------------
[Files]
; Core PowerShell GUI
Source: "Helix-Label-Manager.ps1"; DestDir: "{app}"; Flags: ignoreversion

; CLI tool
Source: "Helix-Excel-Updater.ps1"; DestDir: "{app}"; Flags: ignoreversion

; Batch launcher / interactive menu
Source: "Helix-Menu.bat"; DestDir: "{app}"; Flags: ignoreversion

; Documentation
Source: "README.md";          DestDir: "{app}"; Flags: ignoreversion
Source: "Helix-Setup-Guide.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "VERSION.md";          DestDir: "{app}"; Flags: ignoreversion

; Sample data (if present — skip if missing)
Source: "Helix_Labels_Template.csv"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

; ---------------------------------------------------------------------------
; [Icons] — Start Menu and Desktop shortcuts
; ---------------------------------------------------------------------------
[Icons]
; Start Menu — main GUI
Name: "{group}\Helix"; \
    Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
    Parameters: "-ExecutionPolicy Bypass -NonInteractive -File ""{app}\Helix-Label-Manager.ps1"""; \
    WorkingDir: "{app}"; \
    Comment: "Launch Helix Router Label Manager (AJA KUMO, Videohub, Lightware MX2)"

; Start Menu — CLI menu
Name: "{group}\Helix CLI"; \
    Filename: "{app}\Helix-Menu.bat"; \
    WorkingDir: "{app}"; \
    Comment: "Interactive command-line menu for Helix"

; Start Menu — Setup Guide (opens in default Markdown viewer / Notepad)
Name: "{group}\Setup Guide"; \
    Filename: "{app}\Helix-Setup-Guide.md"; \
    WorkingDir: "{app}"; \
    Comment: "Open the Helix setup guide"

; Start Menu — Uninstall
Name: "{group}\Uninstall Helix"; \
    Filename: "{uninstallexe}"

; Desktop shortcut (optional — only created when the task is checked)
Name: "{commondesktop}\Helix"; \
    Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
    Parameters: "-ExecutionPolicy Bypass -NonInteractive -File ""{app}\Helix-Label-Manager.ps1"""; \
    WorkingDir: "{app}"; \
    Comment: "Launch Helix Router Label Manager"; \
    Tasks: desktopicon

; ---------------------------------------------------------------------------
; [Run] — post-install actions (optional)
; ---------------------------------------------------------------------------
[Run]
; Offer to launch the GUI immediately after install finishes
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
    Parameters: "-ExecutionPolicy Bypass -NonInteractive -File ""{app}\Helix-Label-Manager.ps1"""; \
    WorkingDir: "{app}"; \
    Description: "Launch Helix now"; \
    Flags: nowait postinstall skipifsilent unchecked

; ---------------------------------------------------------------------------
; [Code] — Pascal scripting for runtime checks
; ---------------------------------------------------------------------------
[Code]
// Verify PowerShell 5.1+ is available before proceeding.
// If the registry key is missing the installer will still proceed — PS 5.1 ships
// with Windows 10 and later so this is just an informational guard.
function InitializeSetup(): Boolean;
var
  PSVersion: String;
begin
  Result := True;

  if not RegQueryStringValue(HKEY_LOCAL_MACHINE,
      'SOFTWARE\Microsoft\PowerShell\3\PowerShellEngine',
      'PowerShellVersion', PSVersion) then
  begin
    if MsgBox(
        'PowerShell 5.1 or later is required to run Helix.' + #13#10 +
        'It could not be detected on this system.' + #13#10#13#10 +
        'Do you want to continue the installation anyway?',
        mbConfirmation, MB_YESNO) = IDNO then
      Result := False;
  end;
end;
