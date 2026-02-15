# KUMO Router Label Manager v3.0
# Redesigned for easier label management with inline editing,
# batch rename tools, input/output tabs, and backup support.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ─── HTTPS Helper Functions ──────────────────────────────────────────────────

function Invoke-SecureWebRequest {
    param(
        [Parameter(Mandatory=$true)][string]$Uri,
        [string]$Method = "GET",
        [object]$Body = $null,
        [hashtable]$Headers = @{},
        [int]$TimeoutSec = 10,
        [switch]$UseBasicParsing,
        [switch]$ForceHTTP
    )
    if (-not $ForceHTTP) {
        $httpsUri = $Uri -replace "^http://", "https://"
        try {
            $p = @{ Uri=$httpsUri; Method=$Method; TimeoutSec=$TimeoutSec; UseBasicParsing=$UseBasicParsing; ErrorAction="Stop" }
            if ($Body) { $p.Body = $Body }
            if ($Headers.Count -gt 0) { $p.Headers = $Headers }
            return Invoke-WebRequest @p
        } catch { Write-Verbose "HTTPS failed, falling back to HTTP: $_" }
    }
    $p = @{ Uri=$Uri; Method=$Method; TimeoutSec=$TimeoutSec; UseBasicParsing=$UseBasicParsing; ErrorAction="Stop" }
    if ($Body) { $p.Body = $Body }
    if ($Headers.Count -gt 0) { $p.Headers = $Headers }
    return Invoke-WebRequest @p
}

# ─── Color Theme ─────────────────────────────────────────────────────────────

$clrBg        = [System.Drawing.Color]::FromArgb(30, 30, 34)
$clrPanel     = [System.Drawing.Color]::FromArgb(42, 42, 48)
$clrField     = [System.Drawing.Color]::FromArgb(55, 55, 62)
$clrBorder    = [System.Drawing.Color]::FromArgb(70, 70, 78)
$clrText      = [System.Drawing.Color]::White
$clrDimText   = [System.Drawing.Color]::FromArgb(160, 160, 170)
$clrAccent    = [System.Drawing.Color]::FromArgb(0, 122, 255)
$clrSuccess   = [System.Drawing.Color]::FromArgb(52, 199, 89)
$clrWarning   = [System.Drawing.Color]::FromArgb(255, 204, 0)
$clrDanger    = [System.Drawing.Color]::FromArgb(255, 69, 58)
$clrChanged   = [System.Drawing.Color]::FromArgb(255, 214, 10)

# ─── AJA KUMO REST API Helpers ────────────────────────────────────────────────
# The real KUMO REST API uses /config?action=get|set&paramid=eParamID_*&configid=0
# NOT the fake /api/inputs/1 endpoints that were here before.

function Get-KumoParam {
    param([string]$IP, [string]$ParamId)
    $uri = "http://$IP/config?action=get&configid=0&paramid=$ParamId"
    try {
        $r = Invoke-SecureWebRequest -Uri $uri -TimeoutSec 5 -UseBasicParsing
        $json = $r.Content | ConvertFrom-Json
        if ($json.value_name -and $json.value_name -ne "") { return $json.value_name }
        if ($json.value -and $json.value -ne "") { return $json.value }
        return $null
    } catch { return $null }
}

function Set-KumoParam {
    param([string]$IP, [string]$ParamId, [string]$Value)
    $encoded = [System.Uri]::EscapeDataString($Value)
    $uri = "http://$IP/config?action=set&configid=0&paramid=$ParamId&value=$encoded"
    try {
        $r = Invoke-SecureWebRequest -Uri $uri -TimeoutSec 5 -UseBasicParsing
        return $true
    } catch { return $false }
}

function Get-DocumentsPath {
    $docs = [Environment]::GetFolderPath("MyDocuments")
    $kumoDir = Join-Path $docs "KUMO_Labels"
    if (-not (Test-Path $kumoDir)) { New-Item -ItemType Directory -Path $kumoDir -Force | Out-Null }
    return $kumoDir
}

# ─── Global State ────────────────────────────────────────────────────────────

$global:kumoConnected  = $false
$global:allLabels      = [System.Collections.ArrayList]::new()
$global:backupLabels   = $null
$global:currentFilter  = "ALL"
$global:routerName     = ""
$global:routerPortCount = 32

# ─── Main Form ───────────────────────────────────────────────────────────────

$form = New-Object System.Windows.Forms.Form
$form.Text = "KUMO Router Label Manager v3.0"
$form.Size = New-Object System.Drawing.Size(920, 720)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "Sizable"
$form.MinimumSize = New-Object System.Drawing.Size(800, 600)
$form.BackColor = $clrBg
$form.ForeColor = $clrText
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

# ─── Top Bar: Connection ─────────────────────────────────────────────────────

$topPanel = New-Object System.Windows.Forms.Panel
$topPanel.Dock = "Top"
$topPanel.Height = 70
$topPanel.BackColor = $clrPanel
$topPanel.Padding = New-Object System.Windows.Forms.Padding(16, 10, 16, 10)
# NOTE: topPanel is added to the form AFTER all other docked controls
# WinForms Dock order: last-added Top panel appears at the very top
# So we add them in visual order: bottom first, top last

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "KUMO Label Manager"
$titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$titleLabel.ForeColor = $clrAccent
$titleLabel.Location = New-Object System.Drawing.Point(16, 8)
$titleLabel.AutoSize = $true
$topPanel.Controls.Add($titleLabel)

$ipLabel = New-Object System.Windows.Forms.Label
$ipLabel.Text = "Router IP:"
$ipLabel.Location = New-Object System.Drawing.Point(16, 40)
$ipLabel.Size = New-Object System.Drawing.Size(65, 20)
$ipLabel.ForeColor = $clrDimText
$topPanel.Controls.Add($ipLabel)

$ipTextBox = New-Object System.Windows.Forms.TextBox
$ipTextBox.Text = "192.168.1.100"
$ipTextBox.Location = New-Object System.Drawing.Point(82, 37)
$ipTextBox.Size = New-Object System.Drawing.Size(140, 24)
$ipTextBox.BackColor = $clrField
$ipTextBox.ForeColor = $clrText
$ipTextBox.BorderStyle = "FixedSingle"
$topPanel.Controls.Add($ipTextBox)

$connectButton = New-Object System.Windows.Forms.Button
$connectButton.Text = "Connect"
$connectButton.Location = New-Object System.Drawing.Point(230, 35)
$connectButton.Size = New-Object System.Drawing.Size(90, 28)
$connectButton.BackColor = $clrAccent
$connectButton.ForeColor = $clrText
$connectButton.FlatStyle = "Flat"
$connectButton.FlatAppearance.BorderSize = 0
$connectButton.Cursor = "Hand"
$topPanel.Controls.Add($connectButton)

$statusDot = New-Object System.Windows.Forms.Label
$statusDot.Text = [char]0x25CF
$statusDot.Font = New-Object System.Drawing.Font("Segoe UI", 12)
$statusDot.ForeColor = $clrDimText
$statusDot.Location = New-Object System.Drawing.Point(328, 37)
$statusDot.Size = New-Object System.Drawing.Size(20, 20)
$topPanel.Controls.Add($statusDot)

$statusText = New-Object System.Windows.Forms.Label
$statusText.Text = "Not connected"
$statusText.ForeColor = $clrDimText
$statusText.Location = New-Object System.Drawing.Point(348, 40)
$statusText.Size = New-Object System.Drawing.Size(200, 20)
$topPanel.Controls.Add($statusText)

# ─── Toolbar: File & Batch Operations ────────────────────────────────────────

$toolPanel = New-Object System.Windows.Forms.Panel
$toolPanel.Dock = "Top"
$toolPanel.Height = 44
$toolPanel.BackColor = $clrPanel
$toolPanel.Padding = New-Object System.Windows.Forms.Padding(12, 6, 12, 6)
# NOTE: toolPanel added to form later for correct dock order

# Separator line between top and toolbar
$sep1 = New-Object System.Windows.Forms.Label
$sep1.Dock = "Top"
$sep1.Height = 1
$sep1.BackColor = $clrBorder
# NOTE: sep1 added to form later for correct dock order

$btnDownload = New-Object System.Windows.Forms.Button
$btnDownload.Text = "Download from Router"
$btnDownload.Location = New-Object System.Drawing.Point(12, 7)
$btnDownload.Size = New-Object System.Drawing.Size(145, 28)
$btnDownload.BackColor = $clrAccent
$btnDownload.ForeColor = $clrText
$btnDownload.FlatStyle = "Flat"
$btnDownload.FlatAppearance.BorderSize = 0
$btnDownload.Cursor = "Hand"
$btnDownload.Enabled = $false
$toolPanel.Controls.Add($btnDownload)

$btnOpenFile = New-Object System.Windows.Forms.Button
$btnOpenFile.Text = "Open File..."
$btnOpenFile.Location = New-Object System.Drawing.Point(165, 7)
$btnOpenFile.Size = New-Object System.Drawing.Size(90, 28)
$btnOpenFile.BackColor = $clrField
$btnOpenFile.ForeColor = $clrText
$btnOpenFile.FlatStyle = "Flat"
$btnOpenFile.FlatAppearance.BorderColor = $clrBorder
$btnOpenFile.Cursor = "Hand"
$toolPanel.Controls.Add($btnOpenFile)

$btnSaveFile = New-Object System.Windows.Forms.Button
$btnSaveFile.Text = "Save File..."
$btnSaveFile.Location = New-Object System.Drawing.Point(263, 7)
$btnSaveFile.Size = New-Object System.Drawing.Size(90, 28)
$btnSaveFile.BackColor = $clrField
$btnSaveFile.ForeColor = $clrText
$btnSaveFile.FlatStyle = "Flat"
$btnSaveFile.FlatAppearance.BorderColor = $clrBorder
$btnSaveFile.Cursor = "Hand"
$toolPanel.Controls.Add($btnSaveFile)

# Separator
$sepTool = New-Object System.Windows.Forms.Label
$sepTool.Text = "|"
$sepTool.ForeColor = $clrBorder
$sepTool.Location = New-Object System.Drawing.Point(362, 12)
$sepTool.Size = New-Object System.Drawing.Size(10, 20)
$toolPanel.Controls.Add($sepTool)

$btnFindReplace = New-Object System.Windows.Forms.Button
$btnFindReplace.Text = "Find && Replace"
$btnFindReplace.Location = New-Object System.Drawing.Point(376, 7)
$btnFindReplace.Size = New-Object System.Drawing.Size(110, 28)
$btnFindReplace.BackColor = $clrField
$btnFindReplace.ForeColor = $clrText
$btnFindReplace.FlatStyle = "Flat"
$btnFindReplace.FlatAppearance.BorderColor = $clrBorder
$btnFindReplace.Cursor = "Hand"
$toolPanel.Controls.Add($btnFindReplace)

$btnAutoNumber = New-Object System.Windows.Forms.Button
$btnAutoNumber.Text = "Auto-Number"
$btnAutoNumber.Location = New-Object System.Drawing.Point(494, 7)
$btnAutoNumber.Size = New-Object System.Drawing.Size(100, 28)
$btnAutoNumber.BackColor = $clrField
$btnAutoNumber.ForeColor = $clrText
$btnAutoNumber.FlatStyle = "Flat"
$btnAutoNumber.FlatAppearance.BorderColor = $clrBorder
$btnAutoNumber.Cursor = "Hand"
$toolPanel.Controls.Add($btnAutoNumber)

$btnClearNew = New-Object System.Windows.Forms.Button
$btnClearNew.Text = "Clear All New"
$btnClearNew.Location = New-Object System.Drawing.Point(602, 7)
$btnClearNew.Size = New-Object System.Drawing.Size(100, 28)
$btnClearNew.BackColor = $clrField
$btnClearNew.ForeColor = $clrText
$btnClearNew.FlatStyle = "Flat"
$btnClearNew.FlatAppearance.BorderColor = $clrBorder
$btnClearNew.Cursor = "Hand"
$toolPanel.Controls.Add($btnClearNew)

# ─── Filter Tabs + Search ────────────────────────────────────────────────────

$filterPanel = New-Object System.Windows.Forms.Panel
$filterPanel.Dock = "Top"
$filterPanel.Height = 40
$filterPanel.BackColor = $clrBg
$filterPanel.Padding = New-Object System.Windows.Forms.Padding(12, 6, 12, 6)
# NOTE: filterPanel added to form later for correct dock order

$tabAll = New-Object System.Windows.Forms.Button
$tabAll.Text = "All Ports"
$tabAll.Tag = "ALL"
$tabAll.Location = New-Object System.Drawing.Point(12, 6)
$tabAll.Size = New-Object System.Drawing.Size(80, 26)
$tabAll.BackColor = $clrAccent
$tabAll.ForeColor = $clrText
$tabAll.FlatStyle = "Flat"
$tabAll.FlatAppearance.BorderSize = 0
$tabAll.Cursor = "Hand"
$filterPanel.Controls.Add($tabAll)

$tabInputs = New-Object System.Windows.Forms.Button
$tabInputs.Text = "Inputs"
$tabInputs.Tag = "INPUT"
$tabInputs.Location = New-Object System.Drawing.Point(98, 6)
$tabInputs.Size = New-Object System.Drawing.Size(70, 26)
$tabInputs.BackColor = $clrField
$tabInputs.ForeColor = $clrText
$tabInputs.FlatStyle = "Flat"
$tabInputs.FlatAppearance.BorderSize = 0
$tabInputs.Cursor = "Hand"
$filterPanel.Controls.Add($tabInputs)

$tabOutputs = New-Object System.Windows.Forms.Button
$tabOutputs.Text = "Outputs"
$tabOutputs.Tag = "OUTPUT"
$tabOutputs.Location = New-Object System.Drawing.Point(174, 6)
$tabOutputs.Size = New-Object System.Drawing.Size(75, 26)
$tabOutputs.BackColor = $clrField
$tabOutputs.ForeColor = $clrText
$tabOutputs.FlatStyle = "Flat"
$tabOutputs.FlatAppearance.BorderSize = 0
$tabOutputs.Cursor = "Hand"
$filterPanel.Controls.Add($tabOutputs)

$tabChanged = New-Object System.Windows.Forms.Button
$tabChanged.Text = "Changed"
$tabChanged.Tag = "CHANGED"
$tabChanged.Location = New-Object System.Drawing.Point(255, 6)
$tabChanged.Size = New-Object System.Drawing.Size(75, 26)
$tabChanged.BackColor = $clrField
$tabChanged.ForeColor = $clrText
$tabChanged.FlatStyle = "Flat"
$tabChanged.FlatAppearance.BorderSize = 0
$tabChanged.Cursor = "Hand"
$filterPanel.Controls.Add($tabChanged)

$searchBox = New-Object System.Windows.Forms.TextBox
$searchBox.Text = ""
$searchBox.Location = New-Object System.Drawing.Point(355, 7)
$searchBox.Size = New-Object System.Drawing.Size(180, 24)
$searchBox.BackColor = $clrField
$searchBox.ForeColor = $clrDimText
$searchBox.BorderStyle = "FixedSingle"
$filterPanel.Controls.Add($searchBox)

# Watermark for search
$searchWatermark = "Search labels..."
$searchBox.Text = $searchWatermark
$searchBox.ForeColor = $clrDimText

$changesCount = New-Object System.Windows.Forms.Label
$changesCount.Text = "0 changes pending"
$changesCount.ForeColor = $clrDimText
$changesCount.Location = New-Object System.Drawing.Point(545, 10)
$changesCount.Size = New-Object System.Drawing.Size(150, 20)
$filterPanel.Controls.Add($changesCount)

# ─── Data Grid (Editable) ────────────────────────────────────────────────────

$dataGrid = New-Object System.Windows.Forms.DataGridView
$dataGrid.Dock = "Fill"
$dataGrid.BackgroundColor = $clrBg
$dataGrid.ForeColor = $clrText
$dataGrid.GridColor = $clrBorder
$dataGrid.BorderStyle = "None"
$dataGrid.CellBorderStyle = "SingleHorizontal"
$dataGrid.AllowUserToAddRows = $false
$dataGrid.AllowUserToDeleteRows = $false
$dataGrid.AllowUserToResizeRows = $false
$dataGrid.SelectionMode = "FullRowSelect"
$dataGrid.MultiSelect = $true
$dataGrid.RowHeadersVisible = $false
$dataGrid.AutoSizeColumnsMode = "Fill"
$dataGrid.EnableHeadersVisualStyles = $false
$dataGrid.ColumnHeadersHeight = 34
$dataGrid.RowTemplate.Height = 28
$dataGrid.DefaultCellStyle.BackColor = $clrBg
$dataGrid.DefaultCellStyle.ForeColor = $clrText
$dataGrid.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(0, 88, 200)
$dataGrid.DefaultCellStyle.SelectionForeColor = $clrText
$dataGrid.DefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(4, 2, 4, 2)
$dataGrid.AlternatingRowsDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(36, 36, 40)
$dataGrid.ColumnHeadersDefaultCellStyle.BackColor = $clrPanel
$dataGrid.ColumnHeadersDefaultCellStyle.ForeColor = $clrDimText
$dataGrid.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$dataGrid.ColumnHeadersDefaultCellStyle.Alignment = "MiddleLeft"
$dataGrid.ColumnHeadersDefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(4, 0, 0, 0)

# Define columns
$colPort = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colPort.Name = "Port"
$colPort.HeaderText = "Port"
$colPort.ReadOnly = $true
$colPort.FillWeight = 8
$colPort.MinimumWidth = 50

$colType = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colType.Name = "Type"
$colType.HeaderText = "Type"
$colType.ReadOnly = $true
$colType.FillWeight = 12
$colType.MinimumWidth = 65

$colCurrent = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colCurrent.Name = "Current_Label"
$colCurrent.HeaderText = "Current Label (on router)"
$colCurrent.ReadOnly = $true
$colCurrent.FillWeight = 30
$colCurrent.MinimumWidth = 120
$colCurrent.DefaultCellStyle.ForeColor = $clrDimText

$colNew = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colNew.Name = "New_Label"
$colNew.HeaderText = "New Label (click to edit)"
$colNew.ReadOnly = $false
$colNew.FillWeight = 30
$colNew.MinimumWidth = 120
$colNew.DefaultCellStyle.ForeColor = $clrChanged
$colNew.DefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)

$colStatus = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colStatus.Name = "Status"
$colStatus.HeaderText = "Status"
$colStatus.ReadOnly = $true
$colStatus.FillWeight = 12
$colStatus.MinimumWidth = 60

$colCharCount = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colCharCount.Name = "Chars"
$colCharCount.HeaderText = "Chars"
$colCharCount.ReadOnly = $true
$colCharCount.FillWeight = 8
$colCharCount.MinimumWidth = 45
$colCharCount.DefaultCellStyle.Alignment = "MiddleCenter"

$dataGrid.Columns.Add($colPort)
$dataGrid.Columns.Add($colType)
$dataGrid.Columns.Add($colCurrent)
$dataGrid.Columns.Add($colNew)
$dataGrid.Columns.Add($colStatus)
$dataGrid.Columns.Add($colCharCount)

# NOTE: dataGrid added to form later for correct dock order

# ─── Bottom Bar: Upload + Progress ───────────────────────────────────────────

$bottomPanel = New-Object System.Windows.Forms.Panel
$bottomPanel.Dock = "Bottom"
$bottomPanel.Height = 56
$bottomPanel.BackColor = $clrPanel
$bottomPanel.Padding = New-Object System.Windows.Forms.Padding(16, 10, 16, 10)
# NOTE: bottomPanel added to form later for correct dock order

$btnUpload = New-Object System.Windows.Forms.Button
$btnUpload.Text = "Upload Changes to Router"
$btnUpload.Location = New-Object System.Drawing.Point(16, 12)
$btnUpload.Size = New-Object System.Drawing.Size(190, 32)
$btnUpload.BackColor = $clrDanger
$btnUpload.ForeColor = $clrText
$btnUpload.FlatStyle = "Flat"
$btnUpload.FlatAppearance.BorderSize = 0
$btnUpload.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$btnUpload.Cursor = "Hand"
$btnUpload.Enabled = $false
$bottomPanel.Controls.Add($btnUpload)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(220, 18)
$progressBar.Size = New-Object System.Drawing.Size(300, 20)
$progressBar.Style = "Continuous"
$bottomPanel.Controls.Add($progressBar)

$progressLabel = New-Object System.Windows.Forms.Label
$progressLabel.Text = ""
$progressLabel.ForeColor = $clrDimText
$progressLabel.Location = New-Object System.Drawing.Point(530, 20)
$progressLabel.Size = New-Object System.Drawing.Size(250, 20)
$bottomPanel.Controls.Add($progressLabel)

# ─── Add Controls to Form (correct WinForms dock order) ──────────────────────
# WinForms processes Dock in reverse Z-order: last-added Top panel is at very top
# So we add: Bottom first, then Fill, then Top panels from bottom-to-top

$form.Controls.Add($bottomPanel)    # Dock=Bottom - goes to bottom
$form.Controls.Add($dataGrid)       # Dock=Fill - fills remaining space
$form.Controls.Add($filterPanel)    # Dock=Top - appears below toolbar
$form.Controls.Add($toolPanel)      # Dock=Top - appears below separator
$form.Controls.Add($sep1)           # Dock=Top - appears below topPanel
$form.Controls.Add($topPanel)       # Dock=Top - at the very top (added last)

# ─── Helper Functions ─────────────────────────────────────────────────────────

function Populate-Grid {
    $dataGrid.Rows.Clear()
    $searchTerm = ""
    if ($searchBox.Text -ne $searchWatermark) { $searchTerm = $searchBox.Text.Trim().ToLower() }

    foreach ($lbl in $global:allLabels) {
        # Filter by tab
        if ($global:currentFilter -eq "INPUT" -and $lbl.Type -ne "INPUT") { continue }
        if ($global:currentFilter -eq "OUTPUT" -and $lbl.Type -ne "OUTPUT") { continue }
        if ($global:currentFilter -eq "CHANGED") {
            $nl = $lbl.New_Label
            if (-not $nl -or $nl.Trim() -eq "" -or $nl.Trim() -eq $lbl.Current_Label) { continue }
        }

        # Filter by search
        if ($searchTerm) {
            $matchCurrent = if ($lbl.Current_Label) { $lbl.Current_Label.ToLower().Contains($searchTerm) } else { $false }
            $matchNew = if ($lbl.New_Label) { $lbl.New_Label.ToLower().Contains($searchTerm) } else { $false }
            $matchPort = if ($lbl.Port) { $lbl.Port.ToString().Contains($searchTerm) } else { $false }
            if (-not ($matchCurrent -or $matchNew -or $matchPort)) { continue }
        }

        # Determine status
        $newLabel = $lbl.New_Label
        $status = ""
        $charCount = ""
        if ($newLabel -and $newLabel.Trim() -ne "" -and $newLabel.Trim() -ne $lbl.Current_Label) {
            $status = "Changed"
            $charCount = "$($newLabel.Trim().Length)/50"
        }

        $rowIndex = $dataGrid.Rows.Add($lbl.Port, $lbl.Type, $lbl.Current_Label, $newLabel, $status, $charCount)

        # Color the status
        if ($status -eq "Changed") {
            $dataGrid.Rows[$rowIndex].Cells["Status"].Style.ForeColor = $clrChanged
        }

        # Warn if over character limit
        if ($newLabel -and $newLabel.Trim().Length -gt 50) {
            $dataGrid.Rows[$rowIndex].Cells["Chars"].Style.ForeColor = $clrDanger
            $dataGrid.Rows[$rowIndex].Cells["New_Label"].Style.ForeColor = $clrDanger
        }

        # Color INPUT vs OUTPUT type cells
        if ($lbl.Type -eq "INPUT") {
            $dataGrid.Rows[$rowIndex].Cells["Type"].Style.ForeColor = [System.Drawing.Color]::FromArgb(100, 210, 255)
        } else {
            $dataGrid.Rows[$rowIndex].Cells["Type"].Style.ForeColor = [System.Drawing.Color]::FromArgb(255, 159, 67)
        }
    }

    Update-ChangeCount
}

function Update-ChangeCount {
    $count = 0
    foreach ($lbl in $global:allLabels) {
        $nl = $lbl.New_Label
        if ($nl -and $nl.Trim() -ne "" -and $nl.Trim() -ne $lbl.Current_Label) { $count++ }
    }
    $changesCount.Text = "$count changes pending"
    if ($count -gt 0) {
        $changesCount.ForeColor = $clrChanged
        $btnUpload.Enabled = $global:kumoConnected
    } else {
        $changesCount.ForeColor = $clrDimText
        $btnUpload.Enabled = $false
    }
}

function Sync-GridToData {
    # Save any edits from the grid back to allLabels
    foreach ($row in $dataGrid.Rows) {
        $port = $row.Cells["Port"].Value
        $type = $row.Cells["Type"].Value
        $newVal = $row.Cells["New_Label"].Value

        foreach ($lbl in $global:allLabels) {
            if ($lbl.Port -eq $port -and $lbl.Type -eq $type) {
                $lbl.New_Label = if ($newVal) { $newVal.ToString() } else { "" }
                break
            }
        }
    }
}

function Create-DefaultLabels {
    param([int]$PortCount = 32)
    $global:allLabels.Clear()
    for ($i = 1; $i -le $PortCount; $i++) {
        $global:allLabels.Add([PSCustomObject]@{
            Port = $i; Type = "INPUT"; Current_Label = "Input $i"; New_Label = ""; Notes = ""
        }) | Out-Null
    }
    for ($i = 1; $i -le $PortCount; $i++) {
        $global:allLabels.Add([PSCustomObject]@{
            Port = $i; Type = "OUTPUT"; Current_Label = "Output $i"; New_Label = ""; Notes = ""
        }) | Out-Null
    }
}

function Set-ActiveTab {
    param($activeButton)
    foreach ($btn in @($tabAll, $tabInputs, $tabOutputs, $tabChanged)) {
        $btn.BackColor = $clrField
    }
    $activeButton.BackColor = $clrAccent
    $global:currentFilter = $activeButton.Tag
    Sync-GridToData
    Populate-Grid
}

# ─── Connection ───────────────────────────────────────────────────────────────

$connectButton.Add_Click({
    $ip = $ipTextBox.Text.Trim()
    if (-not $ip) { return }

    $statusText.Text = "Connecting..."
    $statusText.ForeColor = $clrWarning
    $statusDot.ForeColor = $clrWarning
    $form.Refresh()

    try {
        # Test with actual KUMO REST API call (get system name)
        $testUri = "http://$ip/config?action=get&configid=0&paramid=eParamID_SysName"
        $response = Invoke-SecureWebRequest -Uri $testUri -TimeoutSec 8 -UseBasicParsing
        $json = $response.Content | ConvertFrom-Json

        $global:kumoConnected = $true
        $global:routerName = if ($json.value -and $json.value -ne "") { $json.value } else { "KUMO" }

        # Try to detect port count (check if source 33 exists = 64-port router)
        $global:routerPortCount = 32
        try {
            $test64 = Get-KumoParam -IP $ip -ParamId "eParamID_XPT_Source33_Line_1"
            if ($test64 -ne $null) { $global:routerPortCount = 64 }
        } catch { }
        # Check 16-port: if source 17 doesn't exist
        if ($global:routerPortCount -eq 32) {
            try {
                $test17 = Get-KumoParam -IP $ip -ParamId "eParamID_XPT_Source17_Line_1"
                if ($test17 -eq $null) { $global:routerPortCount = 16 }
            } catch { $global:routerPortCount = 16 }
        }

        $statusText.Text = "$($global:routerName) ($($global:routerPortCount)x$($global:routerPortCount)) at $ip"
        $statusText.ForeColor = $clrSuccess
        $statusDot.ForeColor = $clrSuccess
        $btnDownload.Enabled = $true
        $connectButton.Text = "Reconnect"
        $form.Text = "KUMO Label Manager - $($global:routerName)"
        Update-ChangeCount
    } catch {
        $global:kumoConnected = $false
        $statusText.Text = "Connection failed"
        $statusText.ForeColor = $clrDanger
        $statusDot.ForeColor = $clrDanger
        $btnDownload.Enabled = $false
        [System.Windows.Forms.MessageBox]::Show(
            "Cannot connect to KUMO at $ip`n`nCheck that:`n- The IP address is correct`n- The router is powered on`n- You're on the same network`n- Port 80 (HTTP) is accessible",
            "Connection Failed", "OK", "Error"
        )
    }
})

# ─── Download Labels ──────────────────────────────────────────────────────────

$btnDownload.Add_Click({
    $ip = $ipTextBox.Text.Trim()
    $portCount = $global:routerPortCount
    $totalPorts = $portCount * 2
    $global:allLabels.Clear()
    $progressBar.Value = 0
    $progressBar.Maximum = $totalPorts
    $progressLabel.Text = "Downloading via REST API..."
    $form.Refresh()

    # ── Method 1: AJA KUMO REST API (correct method) ──
    # Uses: /config?action=get&configid=0&paramid=eParamID_XPT_Source{N}_Line_1
    $restSuccess = $true

    for ($i = 1; $i -le $portCount; $i++) {
        $label = Get-KumoParam -IP $ip -ParamId "eParamID_XPT_Source${i}_Line_1"
        if (-not $label -or $label -eq "") {
            $label = "Source $i"
            if ($i -eq 1) { $restSuccess = $false }  # First port failed = API not working
        }
        $global:allLabels.Add([PSCustomObject]@{
            Port = $i; Type = "INPUT"; Current_Label = $label; New_Label = ""; Notes = "From KUMO REST API"
        }) | Out-Null
        $progressBar.Value = $i
        $progressLabel.Text = "Source $i/$portCount..."
        $form.Refresh()

        if (-not $restSuccess -and $i -eq 1) { break }  # Don't waste time if API is dead
    }

    if ($restSuccess) {
        for ($i = 1; $i -le $portCount; $i++) {
            $label = Get-KumoParam -IP $ip -ParamId "eParamID_XPT_Destination${i}_Line_1"
            if (-not $label -or $label -eq "") { $label = "Dest $i" }
            $global:allLabels.Add([PSCustomObject]@{
                Port = $i; Type = "OUTPUT"; Current_Label = $label; New_Label = ""; Notes = "From KUMO REST API"
            }) | Out-Null
            $progressBar.Value = $portCount + $i
            $progressLabel.Text = "Dest $i/$portCount..."
            $form.Refresh()
        }
    }

    # ── Method 2: Telnet fallback (only if REST completely failed) ──
    if (-not $restSuccess) {
        $global:allLabels.Clear()
        $progressBar.Value = 0
        $progressLabel.Text = "REST API failed, trying Telnet..."
        $form.Refresh()

        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $tcp.Connect($ip, 23)
            $stream = $tcp.GetStream()
            $writer = New-Object System.IO.StreamWriter($stream)
            $reader = New-Object System.IO.StreamReader($stream)
            Start-Sleep -Seconds 1

            # Clear initial prompt
            while ($stream.DataAvailable) { $reader.ReadLine() | Out-Null }

            for ($i = 1; $i -le $portCount; $i++) {
                try {
                    $writer.WriteLine("LABEL INPUT $i ?"); $writer.Flush()
                    Start-Sleep -Milliseconds 150
                    $resp = if ($stream.DataAvailable) { $reader.ReadLine() } else { "" }
                    $label = if ($resp -and $resp -match '"([^"]+)"') { $matches[1] } else { "Input $i" }
                } catch { $label = "Input $i" }
                $global:allLabels.Add([PSCustomObject]@{
                    Port = $i; Type = "INPUT"; Current_Label = $label; New_Label = ""; Notes = "Via Telnet"
                }) | Out-Null
                $progressBar.Value = $i
                $progressLabel.Text = "Telnet: Input $i/$portCount..."
                $form.Refresh()
            }
            for ($i = 1; $i -le $portCount; $i++) {
                try {
                    $writer.WriteLine("LABEL OUTPUT $i ?"); $writer.Flush()
                    Start-Sleep -Milliseconds 150
                    $resp = if ($stream.DataAvailable) { $reader.ReadLine() } else { "" }
                    $label = if ($resp -and $resp -match '"([^"]+)"') { $matches[1] } else { "Output $i" }
                } catch { $label = "Output $i" }
                $global:allLabels.Add([PSCustomObject]@{
                    Port = $i; Type = "OUTPUT"; Current_Label = $label; New_Label = ""; Notes = "Via Telnet"
                }) | Out-Null
                $progressBar.Value = $portCount + $i
                $progressLabel.Text = "Telnet: Output $i/$portCount..."
                $form.Refresh()
            }
            $writer.Close(); $reader.Close(); $tcp.Close()
        } catch {
            Create-DefaultLabels -PortCount $portCount
        }
    }

    if ($global:allLabels.Count -eq 0) { Create-DefaultLabels -PortCount $portCount }

    $progressBar.Value = $progressBar.Maximum
    $progressLabel.Text = "Downloaded $($global:allLabels.Count) labels from $($global:routerName)"

    # Auto-save to Documents folder with router name
    try {
        $docsPath = Get-DocumentsPath
        $safeName = $global:routerName -replace '[^\w\-]', '_'
        $autoSavePath = Join-Path $docsPath "${safeName}_Labels_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"
        $global:allLabels | Select-Object Port, Type, Current_Label, New_Label, Notes |
            Export-Csv -Path $autoSavePath -NoTypeInformation
        $progressLabel.Text = "Downloaded $($global:allLabels.Count) labels - saved to Documents\KUMO_Labels"
    } catch { }

    Populate-Grid
})

# ─── Open File (CSV or Excel) ────────────────────────────────────────────────

$btnOpenFile.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "Label Files (*.csv;*.xlsx)|*.csv;*.xlsx|CSV files (*.csv)|*.csv|Excel files (*.xlsx)|*.xlsx|All files (*.*)|*.*"
    $dlg.Title = "Open Label File"

    if ($dlg.ShowDialog() -eq "OK") {
        try {
            $global:allLabels.Clear()
            $data = $null

            if ($dlg.FileName -match "\.csv$") {
                $data = Import-Csv -Path $dlg.FileName
            } else {
                if (Get-Module -ListAvailable -Name ImportExcel) {
                    Import-Module ImportExcel
                    $data = Import-Excel -Path $dlg.FileName -WorksheetName "KUMO_Labels"
                } else {
                    $excel = New-Object -ComObject Excel.Application
                    $excel.Visible = $false
                    $wb = $excel.Workbooks.Open($dlg.FileName)
                    $ws = $wb.Worksheets.Item("KUMO_Labels")
                    $data = @()
                    $lastRow = $ws.UsedRange.Rows.Count
                    for ($row = 2; $row -le $lastRow; $row++) {
                        $data += [PSCustomObject]@{
                            Port = $ws.Cells.Item($row,1).Value2
                            Type = $ws.Cells.Item($row,2).Value2
                            Current_Label = $ws.Cells.Item($row,3).Value2
                            New_Label = $ws.Cells.Item($row,4).Value2
                        }
                    }
                    $wb.Close(); $excel.Quit()
                    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
                }
            }

            if ($data) {
                foreach ($row in $data) {
                    if (-not $row.Port -or -not $row.Type) { continue }
                    $nl = if ($row.New_Label) { $row.New_Label.ToString() } else { "" }
                    $cl = if ($row.Current_Label) { $row.Current_Label.ToString() } else { "" }
                    $global:allLabels.Add([PSCustomObject]@{
                        Port = [int]$row.Port
                        Type = $row.Type.ToString().ToUpper().Trim()
                        Current_Label = $cl
                        New_Label = $nl
                        Notes = if ($row.Notes) { $row.Notes.ToString() } else { "" }
                    }) | Out-Null
                }
                Populate-Grid
                $progressLabel.Text = "Loaded $($global:allLabels.Count) labels from file"
            }
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Error loading file: $($_.Exception.Message)", "Load Error", "OK", "Error")
        }
    }
})

# ─── Save File ────────────────────────────────────────────────────────────────

$btnSaveFile.Add_Click({
    Sync-GridToData

    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter = "CSV files (*.csv)|*.csv|Excel files (*.xlsx)|*.xlsx"
    $dlg.DefaultExt = "csv"
    $safeName = if ($global:routerName) { $global:routerName -replace '[^\w\-]', '_' } else { "KUMO" }
    $dlg.FileName = "${safeName}_Labels_$(Get-Date -Format 'yyyyMMdd_HHmm')"
    $dlg.InitialDirectory = Get-DocumentsPath
    $dlg.Title = "Save Label File"

    if ($dlg.ShowDialog() -eq "OK") {
        try {
            if ($dlg.FileName -match "\.xlsx$") {
                if (Get-Module -ListAvailable -Name ImportExcel) {
                    Import-Module ImportExcel
                    $global:allLabels | Select-Object Port, Type, Current_Label, New_Label, Notes |
                        Export-Excel -Path $dlg.FileName -WorksheetName "KUMO_Labels" -AutoSize -TableStyle Medium6 -FreezeTopRow
                } else {
                    $csvPath = $dlg.FileName -replace "\.xlsx$", ".csv"
                    $global:allLabels | Select-Object Port, Type, Current_Label, New_Label, Notes |
                        Export-Csv -Path $csvPath -NoTypeInformation
                    $dlg.FileName = $csvPath
                }
            } else {
                $global:allLabels | Select-Object Port, Type, Current_Label, New_Label, Notes |
                    Export-Csv -Path $dlg.FileName -NoTypeInformation
            }
            $progressLabel.Text = "Saved to $([System.IO.Path]::GetFileName($dlg.FileName))"
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Error saving file: $($_.Exception.Message)", "Save Error", "OK", "Error")
        }
    }
})

# ─── Find & Replace ──────────────────────────────────────────────────────────

$btnFindReplace.Add_Click({
    Sync-GridToData

    $frForm = New-Object System.Windows.Forms.Form
    $frForm.Text = "Find && Replace in Labels"
    $frForm.Size = New-Object System.Drawing.Size(420, 260)
    $frForm.StartPosition = "CenterParent"
    $frForm.BackColor = $clrPanel
    $frForm.ForeColor = $clrText
    $frForm.FormBorderStyle = "FixedDialog"
    $frForm.MaximizeBox = $false
    $frForm.MinimizeBox = $false

    $frForm.Controls.Add((New-Object System.Windows.Forms.Label -Property @{
        Text="Find:"; Location="20,20"; Size="60,20"; ForeColor=$clrText
    }))
    $findBox = New-Object System.Windows.Forms.TextBox -Property @{
        Location="90,18"; Size="290,24"; BackColor=$clrField; ForeColor=$clrText; BorderStyle="FixedSingle"
    }
    $frForm.Controls.Add($findBox)

    $frForm.Controls.Add((New-Object System.Windows.Forms.Label -Property @{
        Text="Replace:"; Location="20,55"; Size="60,20"; ForeColor=$clrText
    }))
    $replaceBox = New-Object System.Windows.Forms.TextBox -Property @{
        Location="90,53"; Size="290,24"; BackColor=$clrField; ForeColor=$clrText; BorderStyle="FixedSingle"
    }
    $frForm.Controls.Add($replaceBox)

    $scopeGroup = New-Object System.Windows.Forms.GroupBox -Property @{
        Text="Apply to"; Location="20,90"; Size="360,55"; ForeColor=$clrDimText
    }
    $rbNewLabels = New-Object System.Windows.Forms.RadioButton -Property @{
        Text="New_Label column"; Location="15,22"; Size="150,20"; Checked=$true; ForeColor=$clrText
    }
    $rbCurrentToNew = New-Object System.Windows.Forms.RadioButton -Property @{
        Text="Copy Current -> New, then replace"; Location="170,22"; Size="180,20"; ForeColor=$clrText
    }
    $scopeGroup.Controls.Add($rbNewLabels)
    $scopeGroup.Controls.Add($rbCurrentToNew)
    $frForm.Controls.Add($scopeGroup)

    $typeGroup = New-Object System.Windows.Forms.GroupBox -Property @{
        Text="Port type"; Location="20,150"; Size="360,40"; ForeColor=$clrDimText
    }
    $rbAll = New-Object System.Windows.Forms.RadioButton -Property @{
        Text="All"; Location="15,15"; Size="50,20"; Checked=$true; ForeColor=$clrText
    }
    $rbInputOnly = New-Object System.Windows.Forms.RadioButton -Property @{
        Text="Inputs only"; Location="75,15"; Size="90,20"; ForeColor=$clrText
    }
    $rbOutputOnly = New-Object System.Windows.Forms.RadioButton -Property @{
        Text="Outputs only"; Location="175,15"; Size="100,20"; ForeColor=$clrText
    }
    $typeGroup.Controls.Add($rbAll)
    $typeGroup.Controls.Add($rbInputOnly)
    $typeGroup.Controls.Add($rbOutputOnly)
    $frForm.Controls.Add($typeGroup)

    $btnDoReplace = New-Object System.Windows.Forms.Button -Property @{
        Text="Replace All"; Location="240,200"; Size="80,28"
        BackColor=$clrAccent; ForeColor=$clrText; FlatStyle="Flat"
    }
    $btnDoReplace.FlatAppearance.BorderSize = 0
    $btnCancel = New-Object System.Windows.Forms.Button -Property @{
        Text="Cancel"; Location="330,200"; Size="60,28"
        BackColor=$clrField; ForeColor=$clrText; FlatStyle="Flat"
    }
    $btnCancel.FlatAppearance.BorderColor = $clrBorder

    $btnDoReplace.Add_Click({
        $find = $findBox.Text
        $replace = $replaceBox.Text
        if (-not $find) { return }

        $count = 0
        foreach ($lbl in $global:allLabels) {
            if ($rbInputOnly.Checked -and $lbl.Type -ne "INPUT") { continue }
            if ($rbOutputOnly.Checked -and $lbl.Type -ne "OUTPUT") { continue }

            if ($rbCurrentToNew.Checked) {
                $newVal = $lbl.Current_Label.Replace($find, $replace)
                if ($newVal -ne $lbl.Current_Label) {
                    $lbl.New_Label = $newVal
                    $count++
                }
            } else {
                if ($lbl.New_Label -and $lbl.New_Label.Contains($find)) {
                    $lbl.New_Label = $lbl.New_Label.Replace($find, $replace)
                    $count++
                }
            }
        }
        $frForm.Close()
        Populate-Grid
        $progressLabel.Text = "Replaced in $count labels"
    })
    $btnCancel.Add_Click({ $frForm.Close() })
    $frForm.Controls.Add($btnDoReplace)
    $frForm.Controls.Add($btnCancel)
    $frForm.ShowDialog() | Out-Null
})

# ─── Auto-Number ──────────────────────────────────────────────────────────────

$btnAutoNumber.Add_Click({
    Sync-GridToData

    $anForm = New-Object System.Windows.Forms.Form
    $anForm.Text = "Auto-Number Labels"
    $anForm.Size = New-Object System.Drawing.Size(400, 230)
    $anForm.StartPosition = "CenterParent"
    $anForm.BackColor = $clrPanel
    $anForm.ForeColor = $clrText
    $anForm.FormBorderStyle = "FixedDialog"
    $anForm.MaximizeBox = $false
    $anForm.MinimizeBox = $false

    $anForm.Controls.Add((New-Object System.Windows.Forms.Label -Property @{
        Text="Prefix:"; Location="20,20"; Size="60,20"; ForeColor=$clrText
    }))
    $prefixBox = New-Object System.Windows.Forms.TextBox -Property @{
        Location="90,18"; Size="270,24"; BackColor=$clrField; ForeColor=$clrText; BorderStyle="FixedSingle"; Text="Camera "
    }
    $anForm.Controls.Add($prefixBox)

    $anForm.Controls.Add((New-Object System.Windows.Forms.Label -Property @{
        Text="Start #:"; Location="20,55"; Size="60,20"; ForeColor=$clrText
    }))
    $startNumBox = New-Object System.Windows.Forms.NumericUpDown -Property @{
        Location="90,53"; Size="80,24"; BackColor=$clrField; ForeColor=$clrText; Value=1; Minimum=1; Maximum=999
    }
    $anForm.Controls.Add($startNumBox)

    $anForm.Controls.Add((New-Object System.Windows.Forms.Label -Property @{
        Text="Preview:"; Location="20,90"; Size="60,20"; ForeColor=$clrDimText
    }))
    $previewLbl = New-Object System.Windows.Forms.Label -Property @{
        Location="90,90"; Size="270,20"; ForeColor=$clrChanged; Text="Camera 1, Camera 2, Camera 3..."
    }
    $anForm.Controls.Add($previewLbl)

    # Update preview on changes
    $updatePreview = {
        $p = $prefixBox.Text
        $s = [int]$startNumBox.Value
        $previewLbl.Text = "$p$s, $p$($s+1), $p$($s+2)..."
    }
    $prefixBox.Add_TextChanged($updatePreview)
    $startNumBox.Add_ValueChanged($updatePreview)

    $typeGroup2 = New-Object System.Windows.Forms.GroupBox -Property @{
        Text="Apply to"; Location="20,115"; Size="340,45"; ForeColor=$clrDimText
    }
    $rbInputs2 = New-Object System.Windows.Forms.RadioButton -Property @{
        Text="Inputs"; Location="15,18"; Size="70,20"; Checked=$true; ForeColor=$clrText
    }
    $rbOutputs2 = New-Object System.Windows.Forms.RadioButton -Property @{
        Text="Outputs"; Location="95,18"; Size="80,20"; ForeColor=$clrText
    }
    $rbBoth2 = New-Object System.Windows.Forms.RadioButton -Property @{
        Text="Both"; Location="185,18"; Size="60,20"; ForeColor=$clrText
    }
    $rbSelected2 = New-Object System.Windows.Forms.RadioButton -Property @{
        Text="Selected rows"; Location="255,18"; Size="100,20"; ForeColor=$clrText
    }
    $typeGroup2.Controls.Add($rbInputs2)
    $typeGroup2.Controls.Add($rbOutputs2)
    $typeGroup2.Controls.Add($rbBoth2)
    $typeGroup2.Controls.Add($rbSelected2)
    $anForm.Controls.Add($typeGroup2)

    $btnApply = New-Object System.Windows.Forms.Button -Property @{
        Text="Apply"; Location="240,170"; Size="60,28"; BackColor=$clrAccent; ForeColor=$clrText; FlatStyle="Flat"
    }
    $btnApply.FlatAppearance.BorderSize = 0
    $btnCancelAN = New-Object System.Windows.Forms.Button -Property @{
        Text="Cancel"; Location="310,170"; Size="60,28"; BackColor=$clrField; ForeColor=$clrText; FlatStyle="Flat"
    }
    $btnCancelAN.FlatAppearance.BorderColor = $clrBorder

    $btnApply.Add_Click({
        $prefix = $prefixBox.Text
        $num = [int]$startNumBox.Value

        if ($rbSelected2.Checked) {
            # Sort selected rows by index (SelectedRows returns in reverse selection order)
            $sortedRows = $dataGrid.SelectedRows | Sort-Object { $_.Index }
            foreach ($row in $sortedRows) {
                $port = $row.Cells["Port"].Value
                $type = $row.Cells["Type"].Value
                foreach ($lbl in $global:allLabels) {
                    if ($lbl.Port -eq $port -and $lbl.Type -eq $type) {
                        $lbl.New_Label = "$prefix$num"
                        $num++
                        break
                    }
                }
            }
        } else {
            foreach ($lbl in $global:allLabels) {
                if ($rbInputs2.Checked -and $lbl.Type -ne "INPUT") { continue }
                if ($rbOutputs2.Checked -and $lbl.Type -ne "OUTPUT") { continue }
                $lbl.New_Label = "$prefix$num"
                $num++
            }
        }
        $anForm.Close()
        Populate-Grid
        $progressLabel.Text = "Auto-numbered labels"
    })
    $btnCancelAN.Add_Click({ $anForm.Close() })
    $anForm.Controls.Add($btnApply)
    $anForm.Controls.Add($btnCancelAN)
    $anForm.ShowDialog() | Out-Null
})

# ─── Clear All New Labels ────────────────────────────────────────────────────

$btnClearNew.Add_Click({
    $result = [System.Windows.Forms.MessageBox]::Show(
        "Clear all New Label values?", "Confirm Clear", "YesNo", "Question"
    )
    if ($result -eq "Yes") {
        foreach ($lbl in $global:allLabels) { $lbl.New_Label = "" }
        Populate-Grid
        $progressLabel.Text = "All new labels cleared"
    }
})

# ─── Tab Filters ──────────────────────────────────────────────────────────────

$tabAll.Add_Click({ Set-ActiveTab $tabAll })
$tabInputs.Add_Click({ Set-ActiveTab $tabInputs })
$tabOutputs.Add_Click({ Set-ActiveTab $tabOutputs })
$tabChanged.Add_Click({ Set-ActiveTab $tabChanged })

# ─── Search ───────────────────────────────────────────────────────────────────

$searchBox.Add_GotFocus({
    if ($searchBox.Text -eq $searchWatermark) {
        $searchBox.Text = ""
        $searchBox.ForeColor = $clrText
    }
})

$searchBox.Add_LostFocus({
    if ($searchBox.Text -eq "") {
        $searchBox.Text = $searchWatermark
        $searchBox.ForeColor = $clrDimText
    }
})

$searchBox.Add_TextChanged({
    if ($searchBox.Text -ne $searchWatermark) {
        Sync-GridToData
        Populate-Grid
    }
})

# ─── Grid Cell Editing ────────────────────────────────────────────────────────

$dataGrid.Add_CellEndEdit({
    param($sender, $e)
    if ($e.ColumnIndex -eq 3) {  # New_Label column
        $port = $sender.Rows[$e.RowIndex].Cells["Port"].Value
        $type = $sender.Rows[$e.RowIndex].Cells["Type"].Value
        $newVal = $sender.Rows[$e.RowIndex].Cells["New_Label"].Value

        # Update the backing data
        foreach ($lbl in $global:allLabels) {
            if ($lbl.Port -eq $port -and $lbl.Type -eq $type) {
                $lbl.New_Label = if ($newVal) { $newVal.ToString() } else { "" }
                break
            }
        }

        # Update status cell inline
        $currentLabel = $sender.Rows[$e.RowIndex].Cells["Current_Label"].Value
        if ($newVal -and $newVal.ToString().Trim() -ne "" -and $newVal.ToString().Trim() -ne $currentLabel) {
            $sender.Rows[$e.RowIndex].Cells["Status"].Value = "Changed"
            $sender.Rows[$e.RowIndex].Cells["Status"].Style.ForeColor = $clrChanged
            $len = $newVal.ToString().Trim().Length
            $sender.Rows[$e.RowIndex].Cells["Chars"].Value = "$len/50"
            if ($len -gt 50) {
                $sender.Rows[$e.RowIndex].Cells["Chars"].Style.ForeColor = $clrDanger
                $sender.Rows[$e.RowIndex].Cells["New_Label"].Style.ForeColor = $clrDanger
            } else {
                $sender.Rows[$e.RowIndex].Cells["Chars"].Style.ForeColor = $clrText
                $sender.Rows[$e.RowIndex].Cells["New_Label"].Style.ForeColor = $clrChanged
            }
        } else {
            $sender.Rows[$e.RowIndex].Cells["Status"].Value = ""
            $sender.Rows[$e.RowIndex].Cells["Chars"].Value = ""
        }

        Update-ChangeCount
    }
})

# ─── Upload to Router ─────────────────────────────────────────────────────────

$btnUpload.Add_Click({
    Sync-GridToData

    if (-not $global:kumoConnected) {
        [System.Windows.Forms.MessageBox]::Show("Please connect to a KUMO router first.", "Not Connected", "OK", "Warning")
        return
    }

    # Collect changes
    $changes = @()
    foreach ($lbl in $global:allLabels) {
        $nl = $lbl.New_Label
        if ($nl -and $nl.Trim() -ne "" -and $nl.Trim() -ne $lbl.Current_Label) {
            $changes += $lbl
        }
    }

    if ($changes.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No label changes to upload.", "No Changes", "OK", "Information")
        return
    }

    # Validate character limits
    $tooLong = @($changes | Where-Object { $_.New_Label.Trim().Length -gt 50 })
    if ($tooLong.Count -gt 0) {
        $result = [System.Windows.Forms.MessageBox]::Show(
            "$($tooLong.Count) label(s) exceed the 50-character limit. They may be truncated by the router.`n`nContinue anyway?",
            "Character Limit Warning", "YesNo", "Warning"
        )
        if ($result -ne "Yes") { return }
    }

    # Confirm
    $result = [System.Windows.Forms.MessageBox]::Show(
        "Upload $($changes.Count) label changes to KUMO at $($ipTextBox.Text)?`n`nThis will modify the router's port names immediately.`n`nA backup of current labels will be saved automatically.",
        "Confirm Upload", "YesNo", "Question"
    )
    if ($result -ne "Yes") { return }

    # Backup current labels
    $global:backupLabels = @()
    foreach ($lbl in $global:allLabels) {
        $global:backupLabels += [PSCustomObject]@{
            Port = $lbl.Port; Type = $lbl.Type; Current_Label = $lbl.Current_Label; New_Label = ""; Notes = "Backup"
        }
    }

    # Save backup to Documents/KUMO_Labels folder
    try {
        $docsPath = Get-DocumentsPath
        $safeName = $global:routerName -replace '[^\w\-]', '_'
        $backupPath = Join-Path $docsPath "${safeName}_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $global:backupLabels | Export-Csv -Path $backupPath -NoTypeInformation
        $progressLabel.Text = "Backup saved to Documents\KUMO_Labels"
    } catch { }

    # Upload via real AJA KUMO REST API
    $ip = $ipTextBox.Text.Trim()
    $progressBar.Value = 0
    $progressBar.Maximum = $changes.Count
    $successCount = 0
    $errorCount = 0

    foreach ($item in $changes) {
        try {
            $progressLabel.Text = "Uploading $($item.Type) $($item.Port): $($item.New_Label)"
            $form.Refresh()

            # Build the correct eParamID for this port
            $paramId = if ($item.Type -eq "INPUT") {
                "eParamID_XPT_Source$($item.Port)_Line_1"
            } else {
                "eParamID_XPT_Destination$($item.Port)_Line_1"
            }

            $ok = Set-KumoParam -IP $ip -ParamId $paramId -Value $item.New_Label.Trim()
            if ($ok) {
                $successCount++
            } else {
                # Telnet fallback for this port
                try {
                    $tcp = New-Object System.Net.Sockets.TcpClient
                    $tcp.Connect($ip, 23)
                    $s = $tcp.GetStream()
                    $w = New-Object System.IO.StreamWriter($s)
                    Start-Sleep -Milliseconds 300
                    $w.WriteLine("LABEL $($item.Type) $($item.Port) `"$($item.New_Label.Trim())`"")
                    $w.Flush()
                    Start-Sleep -Milliseconds 200
                    $w.Close(); $tcp.Close()
                    $successCount++
                } catch {
                    $errorCount++
                }
            }
        } catch {
            $errorCount++
        }
        $progressBar.Value++
    }

    $progressBar.Value = $progressBar.Maximum
    $progressLabel.Text = "Done: $successCount OK, $errorCount failed"

    # Update current labels for successful uploads
    if ($successCount -gt 0) {
        foreach ($lbl in $global:allLabels) {
            $nl = $lbl.New_Label
            if ($nl -and $nl.Trim() -ne "" -and $nl.Trim() -ne $lbl.Current_Label) {
                $lbl.Current_Label = $nl.Trim()
                $lbl.New_Label = ""
            }
        }
        Populate-Grid
    }

    $icon = if ($errorCount -eq 0) { "Information" } else { "Warning" }
    [System.Windows.Forms.MessageBox]::Show(
        "Upload complete!`n`nSuccessful: $successCount`nFailed: $errorCount`n`nBackup saved to Documents\KUMO_Labels folder.",
        "Upload Results", "OK", $icon
    )
})

# ─── Initialize with default empty grid ───────────────────────────────────────

Create-DefaultLabels
Populate-Grid

# ─── Show Form ────────────────────────────────────────────────────────────────

$form.ShowDialog() | Out-Null
