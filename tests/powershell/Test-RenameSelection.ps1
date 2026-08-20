<#
    Exercises the rename helpers from Helix-Label-Manager.ps1 against a real
    DataGridView, without launching the application window.

    The functions under test are extracted from the script text and defined in
    this session, then pointed at a grid built with the same column names the
    app uses.

    Exit code 0 = all cases pass.
#>
[CmdletBinding()]
param(
    [string]$ScriptPath
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
    $root = Split-Path -Parent $MyInvocation.MyCommand.Path
    $ScriptPath = Join-Path $root "..\..\Helix-Label-Manager.ps1"
}
$resolved = (Resolve-Path $ScriptPath).Path
$src = Get-Content $resolved -Raw

foreach ($fn in @("Get-SelectedGridRows", "Get-SelectedLabelCells", "Set-LabelForTargets", "Select-GridRowCells", "Push-UndoCommand")) {
    $m = [regex]::Match($src, "(?ms)^function $([regex]::Escape($fn)) \{.*?^\}")
    if (-not $m.Success) {
        Write-Host "FAIL: $fn not found in $resolved"
        exit 1
    }
    Invoke-Expression $m.Value
}

# --- Stand-ins for the app's globals -------------------------------------
$global:undoStack = New-Object System.Collections.Stack
$global:redoStack = New-Object System.Collections.Stack
$global:maxLabelLength = 50

$script:PORTS = 6

function New-TestGrid {
    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.AllowUserToAddRows = $false
    $grid.SelectionMode = "CellSelect"
    $grid.MultiSelect = $true
    foreach ($n in @("Port", "Type", "Router", "Current_Label", "New_Label", "Current_Label_2", "New_Label_2", "Color")) {
        $c = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $c.Name = $n
        $c.HeaderText = $n
        [void]$grid.Columns.Add($c)
    }
    for ($i = 1; $i -le $script:PORTS; $i++) {
        [void]$grid.Rows.Add($i, "INPUT", "10.0.0.1", "Input $i", "", "L2-$i", "", "")
    }
    return $grid
}

function Reset-Model {
    $global:allLabels = @()
    for ($i = 1; $i -le $script:PORTS; $i++) {
        $global:allLabels += [PSCustomObject]@{
            Port             = $i
            Type             = "INPUT"
            Router           = "10.0.0.1"
            Current_Label    = "Input $i"
            New_Label        = ""
            Current_Label_2  = "L2-$i"
            New_Label_2      = ""
            Color            = $null
            New_Color        = $null
        }
    }
    $global:undoStack.Clear()
    $global:redoStack.Clear()
}

$pass = 0
$fail = 0
function Check([string]$name, $expected, $actual) {
    $e = ($expected | Out-String).Trim()
    $a = ($actual | Out-String).Trim()
    if ($e -eq $a) { $script:pass++; Write-Host "  PASS  $name" }
    else { $script:fail++; Write-Host "  FAIL  $name`n          expected: $e`n          actual:   $a" }
}

# =========================================================================
# Get-SelectedGridRows
# =========================================================================
$dataGrid = New-TestGrid
$colNewL2 = $dataGrid.Columns["New_Label_2"]

$dataGrid.ClearSelection()
$dataGrid.Rows[0].Cells["New_Label"].Selected = $true
$dataGrid.Rows[2].Cells["New_Label"].Selected = $true
Check "cell selection yields those rows in order" @(0, 2) @((Get-SelectedGridRows) | ForEach-Object { $_.Index })

$dataGrid.ClearSelection()
$dataGrid.Rows[3].Cells["Current_Label"].Selected = $true
$dataGrid.Rows[3].Cells["New_Label"].Selected = $true
$dataGrid.Rows[3].Cells["Port"].Selected = $true
Check "three cells in one row collapse to a single row" @(3) @((Get-SelectedGridRows) | ForEach-Object { $_.Index })

$dataGrid.ClearSelection()
$dataGrid.Rows[4].Cells["New_Label"].Selected = $true
$dataGrid.Rows[1].Cells["New_Label"].Selected = $true
Check "rows come back in display order, not click order" @(1, 4) @((Get-SelectedGridRows) | ForEach-Object { $_.Index })

# Row.Selected is a no-op in CellSelect mode, which is why "Select All Inputs"
# goes through Select-GridRowCells rather than setting Selected on the row.
$dataGrid.ClearSelection()
Select-GridRowCells -Rows @($dataGrid.Rows[2])
Check "Select-GridRowCells selects a whole row" @(2) @((Get-SelectedGridRows) | ForEach-Object { $_.Index })

$dataGrid.ClearSelection()
Select-GridRowCells -Rows @($dataGrid.Rows[1], $dataGrid.Rows[4])
Check "Select-GridRowCells handles several rows" @(1, 4) @((Get-SelectedGridRows) | ForEach-Object { $_.Index })

$dataGrid.ClearSelection()
$dataGrid.Rows[2].Selected = $true
Check "setting Row.Selected alone selects nothing in CellSelect mode" 0 @((Get-SelectedGridRows)).Count

$dataGrid.ClearSelection()
$dataGrid.SelectAll()
Check "SelectAll yields every row once" $script:PORTS @((Get-SelectedGridRows)).Count

# =========================================================================
# Get-SelectedLabelCells -- per-cell rename targets
# =========================================================================
function TargetSig($targets) {
    # "row:line" per target, in the order returned.
    return (@($targets | ForEach-Object { "$($_.RowIndex):$($_.LineNum)" }) -join " ")
}

$colNewL2.Visible = $true

$dataGrid.ClearSelection()
$dataGrid.Rows[0].Cells["New_Label"].Selected = $true
Check "a line-1 cell is one line-1 target" "0:1" (TargetSig (Get-SelectedLabelCells))

$dataGrid.ClearSelection()
$dataGrid.Rows[0].Cells["New_Label_2"].Selected = $true
Check "a line-2 cell is one line-2 target" "0:2" (TargetSig (Get-SelectedLabelCells))

$dataGrid.ClearSelection()
$dataGrid.Rows[0].Cells["Current_Label_2"].Selected = $true
Check "a current-line-2 cell maps to line 2" "0:2" (TargetSig (Get-SelectedLabelCells))

$dataGrid.ClearSelection()
$dataGrid.Rows[2].Cells["Current_Label"].Selected = $true
$dataGrid.Rows[2].Cells["New_Label"].Selected = $true
Check "both sides of one line collapse to a single target" "2:1" (TargetSig (Get-SelectedLabelCells))

# The headline case: one pass covering both lines.
$dataGrid.ClearSelection()
$dataGrid.Rows[1].Cells["New_Label"].Selected = $true
$dataGrid.Rows[1].Cells["New_Label_2"].Selected = $true
Check "line 1 and line 2 of one row are two targets" "1:1 1:2" (TargetSig (Get-SelectedLabelCells))

$dataGrid.ClearSelection()
$dataGrid.Rows[3].Cells["New_Label_2"].Selected = $true
$dataGrid.Rows[1].Cells["New_Label_2"].Selected = $true
$dataGrid.Rows[1].Cells["New_Label"].Selected = $true
$dataGrid.Rows[3].Cells["New_Label"].Selected = $true
Check "targets are ordered by row, then line" "1:1 1:2 3:1 3:2" (TargetSig (Get-SelectedLabelCells))

$colNewL2.Visible = $false
$dataGrid.ClearSelection()
$dataGrid.Rows[0].Cells["New_Label_2"].Selected = $true
$dataGrid.Rows[0].Cells["New_Label"].Selected = $true
Check "a hidden line-2 cell is not a target" "0:1" (TargetSig (Get-SelectedLabelCells))
$colNewL2.Visible = $true

# Non-label cells fall back to a whole-row line-1 rename.
$dataGrid.ClearSelection()
$dataGrid.Rows[2].Cells["Port"].Selected = $true
$dataGrid.Rows[4].Cells["Type"].Selected = $true
Check "a selection with no label cell falls back to line 1 per row" "2:1 4:1" (TargetSig (Get-SelectedLabelCells))

$dataGrid.ClearSelection()
$dataGrid.Rows[1].Cells["Color"].Selected = $true
Check "a colour cell is not a rename target" "1:1" (TargetSig (Get-SelectedLabelCells))

# =========================================================================
# Set-LabelForTargets
# =========================================================================
function Select-Cells($spec) {
    # spec: array of "rowIndex:columnName"
    $dataGrid.ClearSelection()
    foreach ($item in $spec) {
        $parts = $item -split ":"
        $dataGrid.Rows[[int]$parts[0]].Cells[$parts[1]].Selected = $true
    }
}

Reset-Model
Select-Cells @("0:New_Label", "1:New_Label", "2:New_Label")
$targets = Get-SelectedLabelCells
$applied = Set-LabelForTargets -Targets $targets -NameFor { param($i, $t) "CAM A" }
Check "same name applied to three cells" 3 $applied
Check "rows 1-3 renamed" @("CAM A", "CAM A", "CAM A") @($global:allLabels[0..2] | ForEach-Object { $_.New_Label })
Check "untouched row left alone" "" $global:allLabels[3].New_Label
Check "one undo entry per changed cell" 3 $global:undoStack.Count

Reset-Model
$applied = Set-LabelForTargets -Targets $targets -NameFor { param($i, $t) "CAM $($i + 1)" }
Check "numbered rename increments per cell" @("CAM 1", "CAM 2", "CAM 3") @($global:allLabels[0..2] | ForEach-Object { $_.New_Label })

Reset-Model
Select-Cells @("0:New_Label_2", "1:New_Label_2", "2:New_Label_2")
$applied = Set-LabelForTargets -Targets (Get-SelectedLabelCells) -NameFor { param($i, $t) "L2 NEW" }
Check "line-2 rename writes New_Label_2" @("L2 NEW", "L2 NEW", "L2 NEW") @($global:allLabels[0..2] | ForEach-Object { $_.New_Label_2 })
Check "line-2 rename leaves line 1 alone" @("", "", "") @($global:allLabels[0..2] | ForEach-Object { $_.New_Label })

# The point of per-cell targets: both lines written in one pass.
Reset-Model
Select-Cells @("0:New_Label", "1:New_Label_2")
$applied = Set-LabelForTargets -Targets (Get-SelectedLabelCells) -NameFor { param($i, $t) "MIX" }
Check "a mixed selection writes both lines in one pass" 2 $applied
Check "row 1 line 1 written" "MIX" $global:allLabels[0].New_Label
Check "row 1 line 2 untouched" "" $global:allLabels[0].New_Label_2
Check "row 2 line 2 written" "MIX" $global:allLabels[1].New_Label_2
Check "row 2 line 1 untouched" "" $global:allLabels[1].New_Label

Reset-Model
Select-Cells @("0:New_Label", "0:New_Label_2")
$applied = Set-LabelForTargets -Targets (Get-SelectedLabelCells) -NameFor { param($i, $t) "N$($i + 1)" }
Check "both lines of one row number in reading order" @("N1", "N2") @($global:allLabels[0].New_Label, $global:allLabels[0].New_Label_2)

Reset-Model
Select-Cells @("0:New_Label")
$one = Get-SelectedLabelCells
$long = "X" * 80
$applied = Set-LabelForTargets -Targets $one -NameFor { param($i, $t) $long }
Check "over-long label truncated to the router limit" 50 $global:allLabels[0].New_Label.Length

Reset-Model
$global:allLabels[0].New_Label = "ALREADY"
$global:undoStack.Clear()
$applied = Set-LabelForTargets -Targets $one -NameFor { param($i, $t) "ALREADY" }
Check "writing an identical value is not counted as a change" 0 $applied
Check "and records no undo entry" 0 $global:undoStack.Count

Reset-Model
$applied = Set-LabelForTargets -Targets $one -NameFor { param($i, $t) $null }
Check "a null name clears rather than throwing" "" $global:allLabels[0].New_Label

Reset-Model
$applied = Set-LabelForTargets -Targets @() -NameFor { param($i, $t) "NOPE" }
Check "empty selection applies nothing" 0 $applied

# The undo entry has to name the field it wrote, or undo restores the wrong line.
Reset-Model
Select-Cells @("2:New_Label_2")
$applied = Set-LabelForTargets -Targets (Get-SelectedLabelCells) -NameFor { param($i, $t) "UNDOME" }
$cmd = $global:undoStack.Peek()
Check "the undo entry records the line-2 field" "New_Label_2" $cmd.Field
Check "and the row it belongs to" 3 $cmd.Port

# =========================================================================
# CellClick redirect + seeding
#
# The handler is extracted from the script and invoked against the test grid.
# BeginEdit needs a displayed control, so it throws here; everything under test
# (the column redirect and the seed) happens before that call, and the catch
# keeps the throw from masking the result.
# =========================================================================
$clickMatch = [regex]::Match($src, '(?ms)^\$dataGrid\.Add_CellClick\(\{\r?\n(.*?)^\}\)')
if (-not $clickMatch.Success) {
    Write-Host "  FAIL  CellClick handler not found"
    $fail++
} else {
    $clickBody = [scriptblock]::Create($clickMatch.Groups[1].Value)

    function Invoke-CellClick([int]$RowIndex, [string]$ColumnName) {
        $global:pendingSeedText = $null
        $colIndex = $dataGrid.Columns[$ColumnName].Index
        $ea = New-Object System.Windows.Forms.DataGridViewCellEventArgs($colIndex, $RowIndex)
        # BeginEdit returns a bool; a real event handler discards it, so do the same.
        try { & $clickBody $dataGrid $ea | Out-Null } catch { }
    }

    $colNew   = $dataGrid.Columns["New_Label"]
    $colNewL2.Visible = $true
    $colNew.Visible = $true
    $dataGrid.Columns["Current_Label"].ReadOnly = $true
    $dataGrid.Columns["Current_Label_2"].ReadOnly = $true
    $colNew.ReadOnly = $false
    $colNewL2.ReadOnly = $false

    # Blank out the new-label cells so seeding is allowed.
    foreach ($r in $dataGrid.Rows) { $r.Cells["New_Label"].Value = ""; $r.Cells["New_Label_2"].Value = "" }

    Invoke-CellClick 0 "Current_Label"
    Check "clicking Current Label focuses the New Label cell" "New_Label" $dataGrid.CurrentCell.OwningColumn.Name
    Check "and on the row that was clicked" 0 $dataGrid.CurrentCell.RowIndex
    Check "and seeds the editor with the current label" "Input 1" $global:pendingSeedText

    Invoke-CellClick 3 "Current_Label"
    Check "seeding follows the clicked row" "Input 4" $global:pendingSeedText

    Invoke-CellClick 2 "Current_Label_2"
    Check "clicking Current Label 2 focuses New Label 2" "New_Label_2" $dataGrid.CurrentCell.OwningColumn.Name
    Check "and seeds from line 2" "L2-3" $global:pendingSeedText

    # A rename already in progress must not be clobbered by the old name.
    $dataGrid.Rows[1].Cells["New_Label"].Value = "WIP"
    Invoke-CellClick 1 "Current_Label"
    Check "an in-progress new label is not overwritten by the seed" "" ([string]$global:pendingSeedText)
    Check "and the cell keeps the in-progress text" "WIP" $dataGrid.Rows[1].Cells["New_Label"].Value

    # Clicking the editable column directly must not seed anything.
    $dataGrid.Rows[4].Cells["New_Label"].Value = ""
    Invoke-CellClick 4 "New_Label"
    Check "clicking New Label directly does not seed" "" ([string]$global:pendingSeedText)
    Check "but still focuses that cell" 4 $dataGrid.CurrentCell.RowIndex

    # Read-only columns that are not label columns should be inert.
    $before = $dataGrid.CurrentCell.RowIndex
    Invoke-CellClick 5 "Port"
    Check "clicking Port does not start an edit" $before $dataGrid.CurrentCell.RowIndex

    # Line 2 hidden: clicking Current Label 2 must not open a hidden editor.
    $colNewL2.Visible = $false
    $dataGrid.CurrentCell = $dataGrid.Rows[0].Cells["New_Label"]
    Invoke-CellClick 2 "Current_Label_2"
    Check "hidden line-2 column is not opened for edit" 0 $dataGrid.CurrentCell.RowIndex
    $colNewL2.Visible = $true
}

Write-Host ""
Write-Host "Rename selection helpers: $pass passed, $fail failed"
if ($fail -gt 0) { exit 1 }
exit 0
