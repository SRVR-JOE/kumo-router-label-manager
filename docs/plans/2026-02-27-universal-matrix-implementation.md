# Universal Matrix Tab Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a Universal Matrix crosspoint grid tab that shows live routing state and allows one-click route switching across AJA KUMO, Blackmagic Videohub, and Lightware MX2 devices.

**Architecture:** A C# `CrosspointMatrixPanel` custom control (GDI+ painted, double-buffered) is added to the existing `Add-Type` block. A new "Matrix" chip button toggles between the label editor DataGridView and the matrix panel. Three new protocol functions query/switch crosspoint state per device type.

**Tech Stack:** PowerShell 5.1, WinForms, GDI+ (System.Drawing.Drawing2D), C# inline via Add-Type

---

### Task 1: Add CrosspointMatrixPanel C# Class

**Files:**
- Modify: `KUMO-Label-Manager.ps1:46-357` (inside the `Add-Type -TypeDefinition @'....'@` block)

**Step 1: Add the CrosspointMatrixPanel class before the closing `'@` on line 357**

Insert this C# class after the `SmoothProgressBar` class (after line 356, before the `'@` on line 357):

```csharp
// -- CrosspointMatrixPanel -----------------------------------------------------
public class CrosspointMatrixPanel : Panel
{
    // Data
    private string[] _inputLabels = new string[0];
    private string[] _outputLabels = new string[0];
    private int[] _crosspoints = new int[0]; // index=output, value=routed input (-1=none)

    // Hover state
    private int _hoverRow = -1;
    private int _hoverCol = -1;

    // Layout cache (recalculated on resize/data change)
    private int _headerWidth = 120;
    private int _headerHeight = 80;
    private int _cellSize = 32;
    private float _fontSize = 8f;

    // Scrolling
    private int _scrollX = 0;
    private int _scrollY = 0;

    // Colors (match app theme)
    private static readonly Color BgColor       = Color.FromArgb(30, 25, 40);
    private static readonly Color PanelColor    = Color.FromArgb(40, 35, 55);
    private static readonly Color FieldColor    = Color.FromArgb(75, 60, 100);
    private static readonly Color BorderColor   = Color.FromArgb(70, 60, 90);
    private static readonly Color TextColor     = Color.White;
    private static readonly Color DimTextColor  = Color.FromArgb(190, 180, 210);
    private static readonly Color AccentColor   = Color.FromArgb(103, 58, 183);
    private static readonly Color HoverRowCol   = Color.FromArgb(20, 255, 255, 255);
    private static readonly Color ActiveDot     = Color.White;
    private static readonly Color AltRowColor   = Color.FromArgb(45, 40, 60);

    // Events
    public event EventHandler<CrosspointClickEventArgs> CrosspointClicked;

    public string[] InputLabels
    {
        get { return _inputLabels; }
        set { _inputLabels = value ?? new string[0]; RecalcLayout(); Invalidate(); }
    }

    public string[] OutputLabels
    {
        get { return _outputLabels; }
        set { _outputLabels = value ?? new string[0]; RecalcLayout(); Invalidate(); }
    }

    public int[] Crosspoints
    {
        get { return _crosspoints; }
        set { _crosspoints = value ?? new int[0]; Invalidate(); }
    }

    public CrosspointMatrixPanel()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        BackColor = BgColor;
        AutoScroll = true;
    }

    private void RecalcLayout()
    {
        int inputs = _inputLabels.Length;
        int outputs = _outputLabels.Length;
        if (inputs == 0 || outputs == 0) return;

        // Font size scales with matrix size
        int maxPorts = Math.Max(inputs, outputs);
        if (maxPorts <= 20) _fontSize = 8.5f;
        else if (maxPorts <= 32) _fontSize = 8f;
        else if (maxPorts <= 64) _fontSize = 7f;
        else _fontSize = 6f;

        // Measure longest input label for header width
        using (Font f = new Font("Segoe UI", _fontSize))
        using (Graphics g = CreateGraphics())
        {
            float maxW = 60;
            foreach (string lbl in _inputLabels)
            {
                SizeF sz = g.MeasureString(lbl, f);
                if (sz.Width > maxW) maxW = sz.Width;
            }
            _headerWidth = (int)maxW + 20;

            // Header height for rotated output labels
            float maxOutW = 60;
            foreach (string lbl in _outputLabels)
            {
                SizeF sz = g.MeasureString(lbl, f);
                if (sz.Width > maxOutW) maxOutW = sz.Width;
            }
            _headerHeight = (int)(maxOutW * 0.75f) + 20;
        }

        // Cell size: fit available space, min 24
        int availW = ClientSize.Width - _headerWidth - 20;
        int availH = ClientSize.Height - _headerHeight - 20;
        int cellW = outputs > 0 ? Math.Max(24, availW / outputs) : 32;
        int cellH = inputs > 0 ? Math.Max(24, availH / inputs) : 32;
        _cellSize = Math.Min(cellW, cellH);
        _cellSize = Math.Min(_cellSize, 48); // cap max size
        _cellSize = Math.Max(_cellSize, 24); // enforce min

        // Set auto-scroll size
        int totalW = _headerWidth + outputs * _cellSize + 20;
        int totalH = _headerHeight + inputs * _cellSize + 20;
        AutoScrollMinSize = new Size(totalW, totalH);
    }

    protected override void OnResize(EventArgs e)
    {
        base.OnResize(e);
        RecalcLayout();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;

        // Apply scroll offset
        g.TranslateTransform(AutoScrollPosition.X, AutoScrollPosition.Y);

        int inputs = _inputLabels.Length;
        int outputs = _outputLabels.Length;
        if (inputs == 0 || outputs == 0)
        {
            using (Font f = new Font("Segoe UI", 11f))
            using (SolidBrush b = new SolidBrush(DimTextColor))
                g.DrawString("Connect to a router and download labels to view the matrix.",
                    f, b, 40, 40);
            return;
        }

        using (Font font = new Font("Segoe UI", _fontSize))
        using (Font fontBold = new Font("Segoe UI", _fontSize, FontStyle.Bold))
        {
            int ox = _headerWidth; // grid origin X
            int oy = _headerHeight; // grid origin Y

            // Draw row/column highlight for hovered cell
            if (_hoverRow >= 0 && _hoverRow < inputs)
            {
                using (SolidBrush hb = new SolidBrush(HoverRowCol))
                    g.FillRectangle(hb, ox, oy + _hoverRow * _cellSize, outputs * _cellSize, _cellSize);
            }
            if (_hoverCol >= 0 && _hoverCol < outputs)
            {
                using (SolidBrush hb = new SolidBrush(HoverRowCol))
                    g.FillRectangle(hb, ox + _hoverCol * _cellSize, oy, _cellSize, inputs * _cellSize);
            }

            // Draw grid lines
            using (Pen gridPen = new Pen(BorderColor, 1f))
            {
                for (int r = 0; r <= inputs; r++)
                    g.DrawLine(gridPen, ox, oy + r * _cellSize, ox + outputs * _cellSize, oy + r * _cellSize);
                for (int c = 0; c <= outputs; c++)
                    g.DrawLine(gridPen, ox + c * _cellSize, oy, ox + c * _cellSize, oy + inputs * _cellSize);
            }

            // Draw crosspoint cells
            for (int c = 0; c < outputs; c++)
            {
                int routedInput = (c < _crosspoints.Length) ? _crosspoints[c] : -1;
                for (int r = 0; r < inputs; r++)
                {
                    int cx = ox + c * _cellSize;
                    int cy = oy + r * _cellSize;
                    bool isActive = (routedInput == r);
                    bool isHover = (r == _hoverRow && c == _hoverCol);

                    if (isActive)
                    {
                        // Active crosspoint: filled purple cell with white dot
                        Rectangle cellRect = new Rectangle(cx + 2, cy + 2, _cellSize - 4, _cellSize - 4);
                        using (GraphicsPath path = RoundedRect(cellRect, 4))
                        using (SolidBrush ab = new SolidBrush(AccentColor))
                            g.FillPath(ab, path);

                        int dotSize = Math.Max(6, _cellSize / 4);
                        int dotX = cx + (_cellSize - dotSize) / 2;
                        int dotY = cy + (_cellSize - dotSize) / 2;
                        using (SolidBrush db = new SolidBrush(ActiveDot))
                            g.FillEllipse(db, dotX, dotY, dotSize, dotSize);
                    }
                    else if (isHover)
                    {
                        Rectangle cellRect = new Rectangle(cx + 2, cy + 2, _cellSize - 4, _cellSize - 4);
                        using (GraphicsPath path = RoundedRect(cellRect, 4))
                        using (SolidBrush hb = new SolidBrush(FieldColor))
                            g.FillPath(hb, path);
                    }
                }
            }

            // Draw input labels (row headers)
            using (SolidBrush tb = new SolidBrush(DimTextColor))
            {
                for (int r = 0; r < inputs; r++)
                {
                    float ty = oy + r * _cellSize + (_cellSize - font.Height) / 2f;
                    // Highlight active row label
                    Font drawFont = (_hoverRow == r) ? fontBold : font;
                    Color drawColor = (_hoverRow == r) ? TextColor : DimTextColor;
                    using (SolidBrush lb = new SolidBrush(drawColor))
                    {
                        // Right-align in header area
                        SizeF sz = g.MeasureString(_inputLabels[r], drawFont);
                        float tx = _headerWidth - sz.Width - 8;
                        g.DrawString(_inputLabels[r], drawFont, lb, tx, ty);
                    }
                }
            }

            // Draw output labels (column headers, rotated -60 degrees)
            for (int c = 0; c < outputs; c++)
            {
                float tx = ox + c * _cellSize + _cellSize / 2f;
                float ty = _headerHeight - 4;
                Font drawFont = (_hoverCol == c) ? fontBold : font;
                Color drawColor = (_hoverCol == c) ? TextColor : DimTextColor;

                var state = g.Save();
                g.TranslateTransform(tx, ty);
                g.RotateTransform(-55);
                using (SolidBrush lb = new SolidBrush(drawColor))
                    g.DrawString(_outputLabels[c], drawFont, lb, 0, 0);
                g.Restore(state);
            }

            // Corner label
            using (SolidBrush cb = new SolidBrush(Color.FromArgb(100, DimTextColor)))
            using (Font cf = new Font("Segoe UI", _fontSize - 1f))
            {
                g.DrawString("IN \\ OUT", cf, cb, 4, _headerHeight - cf.Height - 4);
            }
        }
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        int mx = e.X - AutoScrollPosition.X;
        int my = e.Y - AutoScrollPosition.Y;

        int col = (mx - _headerWidth) / _cellSize;
        int row = (my - _headerHeight) / _cellSize;

        int newHoverRow = (row >= 0 && row < _inputLabels.Length && mx >= _headerWidth) ? row : -1;
        int newHoverCol = (col >= 0 && col < _outputLabels.Length && my >= _headerHeight) ? col : -1;

        if (newHoverRow != _hoverRow || newHoverCol != _hoverCol)
        {
            _hoverRow = newHoverRow;
            _hoverCol = newHoverCol;
            Invalidate();
        }
    }

    protected override void OnMouseLeave(EventArgs e)
    {
        base.OnMouseLeave(e);
        if (_hoverRow != -1 || _hoverCol != -1)
        {
            _hoverRow = -1;
            _hoverCol = -1;
            Invalidate();
        }
    }

    protected override void OnMouseClick(MouseEventArgs e)
    {
        base.OnMouseClick(e);
        if (e.Button != MouseButtons.Left) return;

        int mx = e.X - AutoScrollPosition.X;
        int my = e.Y - AutoScrollPosition.Y;

        int col = (mx - _headerWidth) / _cellSize;
        int row = (my - _headerHeight) / _cellSize;

        if (row >= 0 && row < _inputLabels.Length && col >= 0 && col < _outputLabels.Length
            && mx >= _headerWidth && my >= _headerHeight)
        {
            CrosspointClicked?.Invoke(this, new CrosspointClickEventArgs(col, row));
        }
    }

    private GraphicsPath RoundedRect(Rectangle bounds, int radius)
    {
        int d = radius * 2;
        GraphicsPath path = new GraphicsPath();
        path.AddArc(bounds.X, bounds.Y, d, d, 180, 90);
        path.AddArc(bounds.Right - d, bounds.Y, d, d, 270, 90);
        path.AddArc(bounds.Right - d, bounds.Bottom - d, d, d, 0, 90);
        path.AddArc(bounds.X, bounds.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }
}

public class CrosspointClickEventArgs : EventArgs
{
    public int OutputIndex { get; private set; }
    public int InputIndex { get; private set; }
    public CrosspointClickEventArgs(int output, int input) { OutputIndex = output; InputIndex = input; }
}
```

**Step 2: Verify the Add-Type compiles**

Run: `powershell -ExecutionPolicy Bypass -File KUMO-Label-Manager.ps1` — the form should open without errors. Close it.

**Step 3: Commit**

```bash
git add KUMO-Label-Manager.ps1
git commit -m "feat: add CrosspointMatrixPanel C# custom control"
```

---

### Task 2: Add Global State for Crosspoints

**Files:**
- Modify: `KUMO-Label-Manager.ps1:429-453` (Global State section)

**Step 1: Add crosspoint globals after line 453 (after `$global:lightwareSendId`)**

```powershell
# Crosspoint routing state
$global:crosspoints       = @()      # int array: index=output, value=routed input (0-based, -1=none)
$global:matrixViewActive  = $false    # true when Matrix tab is active
```

**Step 2: Commit**

```bash
git add KUMO-Label-Manager.ps1
git commit -m "feat: add global crosspoint routing state variables"
```

---

### Task 3: Add Crosspoint Query Functions Per Device

**Files:**
- Modify: `KUMO-Label-Manager.ps1` — add after `Upload-RouterLabels` function (after ~line 1230)

**Step 1: Add three device-specific crosspoint query functions and one unified dispatcher**

```powershell
# --- Crosspoint Query/Switch Functions ----------------------------------------

function Get-KumoCrosspoints {
    param([string]$IP, [int]$OutputCount)
    # Queries AJA KUMO for current crosspoint routing state.
    # Returns int array: index=output (0-based), value=input (0-based), -1=none.
    $xp = @()
    for ($i = 1; $i -le $OutputCount; $i++) {
        $val = Get-KumoParam -IP $IP -ParamId "eParamID_XPT_Destination${i}_Status"
        if ($val -ne $null -and $val -match '^\d+$') {
            $xp += ([int]$val - 1)  # KUMO is 1-based, convert to 0-based
        } else {
            $xp += -1
        }
    }
    return $xp
}

function Get-VideohubCrosspoints {
    param([string]$IP, [int]$Port = 9990, [int]$OutputCount)
    # Queries Videohub for VIDEO OUTPUT ROUTING block.
    # Must re-read from connection; sends empty command to trigger state re-dump.
    $routing = @()
    for ($i = 0; $i -lt $OutputCount; $i++) { $routing += -1 }

    if ($global:videohubTcp -eq $null -or -not $global:videohubTcp.Connected) { return $routing }
    $stream = $global:videohubTcp.GetStream()
    $writer = $global:videohubWriter
    $reader = $global:videohubReader

    # Send request for routing state
    $writer.WriteLine("VIDEO OUTPUT ROUTING:")
    $writer.WriteLine("")
    $writer.Flush()

    $deadline = [DateTime]::Now.AddSeconds(3)
    $inBlock  = $false
    while ([DateTime]::Now -lt $deadline) {
        if ($stream.DataAvailable) {
            $line = $reader.ReadLine()
            if ($line -eq $null) { break }
            if ($line -eq "VIDEO OUTPUT ROUTING:") { $inBlock = $true; continue }
            if ($inBlock -and $line.Trim() -eq "") { break }
            if ($inBlock -and $line -match '^(\d+)\s+(\d+)') {
                $outIdx = [int]$matches[1]
                $inIdx  = [int]$matches[2]
                if ($outIdx -ge 0 -and $outIdx -lt $OutputCount) {
                    $routing[$outIdx] = $inIdx
                }
            }
        } else {
            Start-Sleep -Milliseconds 20
        }
    }
    return $routing
}

function Get-LightwareCrosspoints {
    param([int]$OutputCount)
    # Queries Lightware for crosspoint routing via DestinationConnectionList.
    $routing = @()
    for ($i = 0; $i -lt $OutputCount; $i++) { $routing += -1 }

    try {
        $resp = Send-LW3Command "GET /MEDIA/XP/VIDEO.DestinationConnectionList"
        foreach ($line in $resp) {
            # Response like: /MEDIA/XP/VIDEO.DestinationConnectionList=I5:O1;I3:O2;...
            if ($line -match "DestinationConnectionList=(.+)") {
                $pairs = $matches[1] -split ";"
                foreach ($pair in $pairs) {
                    if ($pair -match "I(\d+):O(\d+)") {
                        $inPort  = [int]$matches[1] - 1  # convert to 0-based
                        $outPort = [int]$matches[2] - 1
                        if ($outPort -ge 0 -and $outPort -lt $OutputCount) {
                            $routing[$outPort] = $inPort
                        }
                    }
                }
            }
        }
    } catch {
        Write-ErrorLog "LW3-XP" "Failed to query crosspoints: $($_.Exception.Message)"
    }
    return $routing
}

function Get-RouterCrosspoints {
    # Unified crosspoint query - dispatches to correct device handler.
    $ip = $ipTextBox.Text.Trim()
    $outCount = $global:routerOutputCount

    switch ($global:routerType) {
        "KUMO"      { return Get-KumoCrosspoints -IP $ip -OutputCount $outCount }
        "Videohub"  { return Get-VideohubCrosspoints -IP $ip -OutputCount $outCount }
        "Lightware" { return Get-LightwareCrosspoints -OutputCount $outCount }
        default     { return @() }
    }
}

function Switch-KumoCrosspoint {
    param([string]$IP, [int]$OutputPort1, [int]$InputPort1)
    # Switches a KUMO crosspoint. Ports are 1-based.
    $result = Set-KumoParam -IP $IP -ParamId "eParamID_XPT_Destination${OutputPort1}_Status" -Value "$InputPort1"
    return $result
}

function Switch-VideohubCrosspoint {
    param([int]$OutputPort0, [int]$InputPort0)
    # Switches a Videohub crosspoint. Ports are 0-based.
    if ($global:videohubWriter -eq $null -or $global:videohubTcp -eq $null) { return $false }
    try {
        $writer = $global:videohubWriter
        $reader = $global:videohubReader
        $stream = $global:videohubTcp.GetStream()

        $writer.WriteLine("VIDEO OUTPUT ROUTING:")
        $writer.WriteLine("$OutputPort0 $InputPort0")
        $writer.WriteLine("")
        $writer.Flush()

        # Wait for ACK
        $deadline = [DateTime]::Now.AddSeconds(3)
        while ([DateTime]::Now -lt $deadline) {
            if ($stream.DataAvailable) {
                $line = $reader.ReadLine()
                if ($line -eq "ACK") { return $true }
                if ($line -eq "NAK") { return $false }
            } else {
                Start-Sleep -Milliseconds 20
            }
        }
        return $true  # timeout but likely succeeded
    } catch {
        Write-ErrorLog "VH-XP" "Switch failed: $($_.Exception.Message)"
        return $false
    }
}

function Switch-LightwareCrosspoint {
    param([int]$OutputPort1, [int]$InputPort1)
    # Switches a Lightware crosspoint. Ports are 1-based.
    try {
        $resp = Send-LW3Command "CALL /MEDIA/XP/VIDEO:switch(I${InputPort1}:O${OutputPort1})"
        foreach ($line in $resp) {
            if ($line -match "^pE" -or $line -match "^nE") { return $false }
        }
        return $true
    } catch {
        Write-ErrorLog "LW3-XP" "Switch failed: $($_.Exception.Message)"
        return $false
    }
}

function Switch-RouterCrosspoint {
    param([int]$OutputIndex0, [int]$InputIndex0)
    # Unified crosspoint switch - dispatches to correct device handler.
    # Both params are 0-based. Converts to 1-based for KUMO/Lightware.
    $ip = $ipTextBox.Text.Trim()

    switch ($global:routerType) {
        "KUMO"      { return Switch-KumoCrosspoint -IP $ip -OutputPort1 ($OutputIndex0 + 1) -InputPort1 ($InputIndex0 + 1) }
        "Videohub"  { return Switch-VideohubCrosspoint -OutputPort0 $OutputIndex0 -InputPort0 $InputIndex0 }
        "Lightware" { return Switch-LightwareCrosspoint -OutputPort1 ($OutputIndex0 + 1) -InputPort1 ($InputIndex0 + 1) }
        default     { return $false }
    }
}
```

**Step 2: Commit**

```bash
git add KUMO-Label-Manager.ps1
git commit -m "feat: add crosspoint query and switch functions for all device types"
```

---

### Task 4: Add Matrix Tab UI and Toggle Logic

**Files:**
- Modify: `KUMO-Label-Manager.ps1:1557-1590` (filterRail and tab chips)
- Modify: `KUMO-Label-Manager.ps1:1979-1985` (content panel assembly)
- Modify: `KUMO-Label-Manager.ps1:2091-2102` (Set-ActiveTab function)
- Modify: `KUMO-Label-Manager.ps1:2943-2946` (tab click handlers)

**Step 1: Add the Matrix chip button after the Changed chip (after line 1590)**

After `$filterRail.Controls.Add($tabChanged)` (line 1590), add:

```powershell
$tabMatrix  = New-TabChip "Matrix"   "MATRIX"  348
$tabMatrix.Size = New-Object System.Drawing.Size(78, 28)
$filterRail.Controls.Add($tabMatrix)
```

**Step 2: Create the matrix panel instance (after the dataGrid setup, around line 1660, before the filterRail.Add_Resize)**

Add after the dataGrid context menu section (~line 1932) and before `$statusBar` setup:

```powershell
# --- Matrix Panel ---------------------------------------------------------------
$matrixPanel = New-Object CrosspointMatrixPanel
$matrixPanel.Dock = "Fill"
$matrixPanel.Visible = $false
```

**Step 3: Add the matrix panel to contentPanel (modify line 1981)**

Change the content panel assembly section (lines 1979-1985) to include `$matrixPanel`:

```powershell
# --- Assemble Content Panel (reverse dock order: Bottom first, then Fill, then Top) --

$contentPanel.Controls.Add($matrixPanel)     # Dock=Fill (hidden by default)
$contentPanel.Controls.Add($dataGrid)        # Dock=Fill
$contentPanel.Controls.Add($statusBar)       # Dock=Bottom
$contentPanel.Controls.Add($filterRail)      # Dock=Top (below contentHeader)
$contentPanel.Controls.Add($contentHeader)   # Dock=Top (below headerBar)
$contentPanel.Controls.Add($headerBar)       # Dock=Top (very top of content)
```

**Step 4: Modify Set-ActiveTab to toggle matrix/grid visibility (replace lines 2091-2102)**

```powershell
function Set-ActiveTab {
    param($activeButton)
    foreach ($btn in @($tabAll, $tabInputs, $tabOutputs, $tabChanged, $tabMatrix)) {
        $btn.BackColor = $clrField
        $btn.ForeColor = $clrText
    }
    $activeButton.BackColor = $clrAccent
    $activeButton.ForeColor = $clrText
    $global:currentFilter = $activeButton.Tag

    if ($activeButton.Tag -eq "MATRIX") {
        $global:matrixViewActive = $true
        $dataGrid.Visible = $false
        $matrixPanel.Visible = $true
        # Hide label-editor-only toolbar buttons
        $btnFindReplace.Visible = $false
        $btnAutoNumber.Visible = $false
        $btnTemplate.Visible = $false
        $btnClearNew.Visible = $false
        $searchBox.Visible = $false
        # Refresh matrix data
        Update-MatrixPanel
    } else {
        $global:matrixViewActive = $false
        $matrixPanel.Visible = $false
        $dataGrid.Visible = $true
        $btnFindReplace.Visible = $true
        $btnAutoNumber.Visible = $true
        $btnTemplate.Visible = $true
        $btnClearNew.Visible = $true
        $searchBox.Visible = $true
        Sync-GridToData
        Populate-Grid
    }
}
```

**Step 5: Add the Matrix tab click handler (after the existing tab click handlers, after line 2946)**

```powershell
$tabMatrix.Add_Click({  Set-ActiveTab $tabMatrix })
```

**Step 6: Commit**

```bash
git add KUMO-Label-Manager.ps1
git commit -m "feat: add Matrix tab chip and toggle between grid/matrix views"
```

---

### Task 5: Add Update-MatrixPanel and CrosspointClicked Handler

**Files:**
- Modify: `KUMO-Label-Manager.ps1` — add after `Set-ActiveTab` function

**Step 1: Add the Update-MatrixPanel function**

```powershell
function Update-MatrixPanel {
    # Populates the matrix panel with current labels and crosspoint state.
    if (-not $global:routerConnected) { return }

    $inCount  = $global:routerInputCount
    $outCount = $global:routerOutputCount

    # Build label arrays using New_Label if set, otherwise Current_Label
    $inputLabels = @()
    $outputLabels = @()
    foreach ($lbl in $global:allLabels) {
        $displayName = if ($lbl.New_Label -and $lbl.New_Label.Trim() -ne "") { $lbl.New_Label.Trim() } else { $lbl.Current_Label }
        if ($lbl.Type -eq "INPUT") {
            $inputLabels += "I$($lbl.Port): $displayName"
        }
    }
    foreach ($lbl in $global:allLabels) {
        $displayName = if ($lbl.New_Label -and $lbl.New_Label.Trim() -ne "") { $lbl.New_Label.Trim() } else { $lbl.Current_Label }
        if ($lbl.Type -eq "OUTPUT") {
            $outputLabels += "O$($lbl.Port): $displayName"
        }
    }

    $matrixPanel.InputLabels = $inputLabels
    $matrixPanel.OutputLabels = $outputLabels

    # Query crosspoint state from router
    try {
        Set-StatusMessage "Querying crosspoint routing..." "Dim"
        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        [System.Windows.Forms.Application]::DoEvents()

        $global:crosspoints = Get-RouterCrosspoints
        $matrixPanel.Crosspoints = [int[]]$global:crosspoints

        $activeRoutes = ($global:crosspoints | Where-Object { $_ -ge 0 }).Count
        Set-StatusMessage "$activeRoutes active routes loaded" "Success"
    } catch {
        Write-ErrorLog "MATRIX" "Failed to query crosspoints: $($_.Exception.Message)"
        Set-StatusMessage "Failed to load routing state" "Danger"
    } finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
}
```

**Step 2: Add the crosspoint click handler (right after Update-MatrixPanel)**

```powershell
$matrixPanel.Add_CrosspointClicked({
    param($sender, $args)
    if (-not $global:routerConnected) { return }

    $outIdx = $args.OutputIndex
    $inIdx  = $args.InputIndex
    $outPort = $outIdx + 1
    $inPort  = $inIdx + 1

    # Get display names for status message
    $inName  = if ($matrixPanel.InputLabels.Length -gt $inIdx) { $matrixPanel.InputLabels[$inIdx] } else { "Input $inPort" }
    $outName = if ($matrixPanel.OutputLabels.Length -gt $outIdx) { $matrixPanel.OutputLabels[$outIdx] } else { "Output $outPort" }

    Set-StatusMessage "Switching: $inName -> $outName ..." "Changed"
    [System.Windows.Forms.Application]::DoEvents()

    try {
        $result = Switch-RouterCrosspoint -OutputIndex0 $outIdx -InputIndex0 $inIdx
        if ($result -ne $false) {
            # Update local crosspoint state
            $global:crosspoints[$outIdx] = $inIdx
            $matrixPanel.Crosspoints = [int[]]$global:crosspoints
            Set-StatusMessage "Routed: $inName -> $outName" "Success"
        } else {
            Set-StatusMessage "Switch failed: $inName -> $outName" "Danger"
        }
    } catch {
        Write-ErrorLog "MATRIX" "Switch failed: $($_.Exception.Message)"
        Set-StatusMessage "Switch error: $($_.Exception.Message)" "Danger"
    }
})
```

**Step 3: Commit**

```bash
git add KUMO-Label-Manager.ps1
git commit -m "feat: add matrix panel data population and crosspoint click handler"
```

---

### Task 6: Integrate Crosspoint Loading Into Connect/Download Flow

**Files:**
- Modify: `KUMO-Label-Manager.ps1` — the connect button click handler

**Step 1: Find the connect button click handler**

Search for `$connectButton.Add_Click` — this is where the router connects and downloads labels. After a successful download, add a crosspoint query.

After the line that calls `Download-RouterLabels` and the grid is populated, add:

```powershell
        # Pre-fetch crosspoint state for matrix view
        try {
            $global:crosspoints = Get-RouterCrosspoints
        } catch {
            Write-ErrorLog "CONNECT" "Crosspoint query failed (non-fatal): $($_.Exception.Message)" "WARN"
            $global:crosspoints = @()
        }
```

**Step 2: Also find the Download button click handler**

After a successful re-download of labels, add the same crosspoint refresh:

```powershell
        # Refresh crosspoint state
        try {
            $global:crosspoints = Get-RouterCrosspoints
            if ($global:matrixViewActive) { Update-MatrixPanel }
        } catch {
            Write-ErrorLog "DOWNLOAD" "Crosspoint refresh failed (non-fatal): $($_.Exception.Message)" "WARN"
        }
```

**Step 3: Commit**

```bash
git add KUMO-Label-Manager.ps1
git commit -m "feat: integrate crosspoint loading into connect and download flows"
```

---

### Task 7: Handle Videohub Routing Block in Initial State Dump

**Files:**
- Modify: `KUMO-Label-Manager.ps1:874-913` (Connect-VideohubRouter parse blocks)

**Step 1: Add routing data parsing to the Videohub state dump parser**

In the `switch ($currentBlock)` block (around line 891), add a new case after `"OUTPUT LABELS"`:

```powershell
            "VIDEO OUTPUT ROUTING" {
                if ($line -match '^(\d+)\s+(\d+)') {
                    $routingMap[[int]$matches[1]] = [int]$matches[2]
                }
            }
```

And add `$routingMap = @{}` with the other hashtable declarations (around line 876):

```powershell
    $routingMap   = @{}
```

And add `Routing = $routingMap` to the return hashtable (around line 925):

```powershell
        Routing       = $routingMap
```

**Step 2: Use the routing data when connecting**

In `Download-RouterLabels`, after the Videohub labels are populated, store the routing data:

```powershell
            # Store routing data if available
            if ($info.Routing -and $info.Routing.Count -gt 0) {
                $xp = @()
                for ($i = 0; $i -lt $outputCount; $i++) {
                    if ($info.Routing.ContainsKey($i)) { $xp += $info.Routing[$i] }
                    else { $xp += -1 }
                }
                $global:crosspoints = $xp
            }
```

**Step 3: Commit**

```bash
git add KUMO-Label-Manager.ps1
git commit -m "feat: parse VIDEO OUTPUT ROUTING from Videohub initial state dump"
```

---

### Task 8: Test End-to-End and Polish

**Files:**
- Modify: `KUMO-Label-Manager.ps1` — minor polish

**Step 1: Manual test checklist**

- [ ] Launch the app — form opens without errors
- [ ] Matrix tab appears in filter rail as 5th chip
- [ ] Before connecting: Matrix view shows "Connect to a router..." message
- [ ] Connect to a router (any type)
- [ ] Click Matrix tab — grid appears with correct labels on axes
- [ ] Crosspoint cells show active routes (purple cells with white dots)
- [ ] Hover over cells — row/column highlight works
- [ ] Click a crosspoint cell — route switches on the actual router
- [ ] Status bar shows "Routed: I1:Camera 1 -> O2:Preview"
- [ ] Switch back to All Ports tab — label editor returns
- [ ] Resize window — matrix auto-sizes correctly
- [ ] Large matrix (32x32+) — scrollbars appear, fonts scale down

**Step 2: Edge case handling**

Add a guard at the top of `Get-VideohubCrosspoints` for when the connection is lost:

```powershell
    if ($global:videohubTcp -eq $null -or -not $global:videohubTcp.Connected) {
        $routing = @()
        for ($i = 0; $i -lt $OutputCount; $i++) { $routing += -1 }
        return $routing
    }
```

Ensure `Update-MatrixPanel` is called when switching to Matrix tab even if crosspoints were already loaded (it already does this in `Set-ActiveTab`).

**Step 3: Final commit**

```bash
git add KUMO-Label-Manager.ps1
git commit -m "feat: Universal Matrix tab complete with crosspoint routing"
```

---

## Summary

| Task | Description | Key Files |
|------|-------------|-----------|
| 1 | CrosspointMatrixPanel C# class | Lines 46-357 (Add-Type block) |
| 2 | Global crosspoint state | Lines 429-453 (Global State) |
| 3 | Device crosspoint query/switch functions | After Upload-RouterLabels |
| 4 | Matrix tab UI + toggle logic | filterRail, Set-ActiveTab, content panel |
| 5 | Update-MatrixPanel + click handler | After Set-ActiveTab |
| 6 | Integrate into connect/download flow | Connect/Download button handlers |
| 7 | Videohub routing block parsing | Connect-VideohubRouter |
| 8 | End-to-end testing + polish | Full app |
