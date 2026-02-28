# Universal Matrix Tab Design

## Summary

Add a Universal Matrix crosspoint grid as a 5th chip button in the filter rail. Works identically across AJA KUMO, Blackmagic Videohub, and Lightware MX2 devices. Displays an NxN grid with input labels on rows, output labels on columns, active crosspoints highlighted, and live route switching on click.

## Navigation

- New chip button `[Matrix]` added after `[Changed]` in the filter rail
- Clicking Matrix hides the DataGridView and shows the CrosspointMatrixPanel
- Clicking any other chip hides the matrix and restores the DataGridView

## CrosspointMatrixPanel (C# Custom Control)

Inherits `Panel`, double-buffered. Added to the existing `Add-Type` C# block.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| InputLabels | string[] | Input port labels ("I1:Camera 1") |
| OutputLabels | string[] | Output port labels ("O1:Program") |
| Crosspoints | int[] | Index = output port, value = routed input port (-1 = none) |
| InputCount | int | Number of inputs |
| OutputCount | int | Number of outputs |

### Events

| Event | Args | Description |
|-------|------|-------------|
| CrosspointClicked | (int output, int input) | Fired when user clicks a crosspoint cell |

### Rendering (OnPaint)

- **Column headers** (top): Output labels, rotated 45 degrees for space efficiency
- **Row headers** (left): Input labels, left-aligned
- **Active crosspoint**: Filled rounded rect in `$clrAccent` (RGB 103,58,183) with centered dot
- **Inactive cell**: Subtle border rect in `$clrBorder` (RGB 70,60,90)
- **Hovered cell**: Lighter fill in `$clrField` (RGB 75,60,100)
- **Row/column highlight**: When hovering, entire row and column get a subtle tint
- **Font**: Segoe UI, scales by matrix size (8pt for <=32, 7pt for <=64, 6pt for >64)

### Auto-Sizing

```
headerWidth  = max label text width + padding
headerHeight = max label text width (rotated) + padding
cellSize     = min(maxCellSize, (panelWidth - headerWidth) / outputCount,
                                (panelHeight - headerHeight) / inputCount)
minCellSize  = 24x24px (scrollbars appear if matrix exceeds available space)
```

Recalculated on panel Resize event.

### Mouse Interaction

- **OnMouseMove**: Hit-test to find hovered cell, set row/col highlight, show tooltip with full label
- **OnMouseClick**: Hit-test to find clicked cell, fire CrosspointClicked event
- **Tooltip**: Shows "Route Input 3 (Camera 3) to Output 1 (Program)"

## Device Protocol — Crosspoint Operations

### Query Crosspoints

| Device | Command | Response |
|--------|---------|----------|
| AJA KUMO | `GET /config?action=get&paramid=eParamID_XPT_Destination{N}_Status` | `{"value": "3"}` (input 3 routed to dest N) |
| Blackmagic | Read `VIDEO OUTPUT ROUTING:` block from TCP 9990 state dump | `0 2\n1 0\n` (output 0 <- input 2) |
| Lightware | `GET /MEDIA/XP/VIDEO.DestinationConnectionList` | Connection map per output |

### Switch Route

| Device | Command | Format |
|--------|---------|--------|
| AJA KUMO | REST: `set paramid=eParamID_XPT_Destination{out}_Status&value={in}` or Telnet: `XPT D{out}:S{in}` | Per-crosspoint |
| Blackmagic | `VIDEO OUTPUT ROUTING:\n{out} {in}\n\n` (0-based) | Block + ACK wait |
| Lightware | `CALL /MEDIA/XP/VIDEO:switch(I{in}:O{out})` | Per-crosspoint |

## Integration Points

### Tab System

- `$tabMatrix = New-TabChip "Matrix" "MATRIX" 348` added to filter rail
- `Set-ActiveTab` modified: MATRIX active hides `$dataGrid`, shows `$matrixPanel`; other tabs reverse
- `$matrixPanel` is `Dock=Fill`, added to `$contentPanel` alongside `$dataGrid`

### Data Flow

1. On connect/download: fetch labels (existing) AND query crosspoint state (new)
2. Populate `$matrixPanel.InputLabels`, `$matrixPanel.OutputLabels`, `$matrixPanel.Crosspoints`
3. On crosspoint click: dispatch protocol-specific route command, update Crosspoints array, repaint affected cells only
4. Uses labels from `$global:allLabels` — either New_Label (if set) or Current_Label

### Refresh

- Crosspoints fetched once on connect/download
- After each route switch, only the affected output column updates
- Refresh button in matrix view re-queries all crosspoints from the device

## Visual Design

Follows existing dark-purple theme exactly:
- Background: `$clrBg` (RGB 30,25,40)
- Grid lines: `$clrBorder` (RGB 70,60,90)
- Active route: `$clrAccent` (RGB 103,58,183)
- Hover: `$clrField` (RGB 75,60,100)
- Header text: `$clrDimText` (RGB 190,180,210)
- Active route indicator: White dot on purple cell

## Supported Matrix Sizes

| Device | Sizes | Max Grid |
|--------|-------|----------|
| AJA KUMO | 16x4, 16x16, 32x32, 64x64 | 64x64 |
| Blackmagic Videohub | 10x10 to 120x120+ | 120x120 |
| Lightware MX2 | 4x4 to 48x48 | 48x48 |

All sizes auto-handled by the cell sizing algorithm.
