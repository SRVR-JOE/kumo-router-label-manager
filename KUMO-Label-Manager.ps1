# Router Label Manager v5.0
# Supports AJA KUMO, Blackmagic Videohub, and Lightware MX2 matrix routers.

# --- Error Logging -----------------------------------------------------------
# Captures all errors and warnings to error-log.txt in the script directory.
# This file can be shared for remote debugging.

$global:scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $global:scriptDir) { $global:scriptDir = (Get-Location).Path }
$global:errorLogPath = Join-Path $global:scriptDir "error-log.txt"

# Clear previous log and write header
try {
    "=== Router Label Manager Error Log ===" | Out-File $global:errorLogPath -Encoding ascii
    "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File $global:errorLogPath -Append -Encoding ascii
    "PowerShell: $($PSVersionTable.PSVersion)" | Out-File $global:errorLogPath -Append -Encoding ascii
    "OS: $([System.Environment]::OSVersion.VersionString)" | Out-File $global:errorLogPath -Append -Encoding ascii
    "" | Out-File $global:errorLogPath -Append -Encoding ascii
} catch {
    # If we cannot write the log, continue without logging
}

function Write-ErrorLog {
    param([string]$Source, [string]$Message, [string]$Level = "ERROR")
    try {
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "[$ts] [$Level] [$Source] $Message" | Out-File $global:errorLogPath -Append -Encoding ascii
    } catch { }
}

# Global trap: catch any unhandled terminating error and log it
trap {
    $errMsg = "$($_.Exception.GetType().Name): $($_.Exception.Message)"
    $errLoc = "at line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())"
    Write-ErrorLog "UNHANDLED" "$errMsg`n  $errLoc"
    Write-Host "ERROR: $errMsg" -ForegroundColor Red
    Write-Host "  $errLoc" -ForegroundColor Yellow
    continue
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- Custom Controls (C#) ----------------------------------------------------

Add-Type -ReferencedAssemblies @('System.Windows.Forms', 'System.Drawing') -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

// -- ModernButton --------------------------------------------------------------
public class ModernButton : Button
{
    public enum ButtonStyle { Primary, Secondary, Success, Warning, Danger }

    private ButtonStyle _style = ButtonStyle.Primary;
    private bool _hovered = false;
    private bool _pressed = false;

    private static readonly Color PrimaryBase    = Color.FromArgb(103, 58, 183);
    private static readonly Color SecondaryBase  = Color.FromArgb(75, 60, 100);
    private static readonly Color SuccessBase    = Color.FromArgb(0, 133, 117);
    private static readonly Color WarningBase    = Color.FromArgb(247, 99, 12);
    private static readonly Color DangerBase     = Color.FromArgb(232, 17, 35);

    public ButtonStyle Style
    {
        get { return _style; }
        set { _style = value; Invalidate(); }
    }

    public ModernButton()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        FlatStyle = FlatStyle.Flat;
        FlatAppearance.BorderSize = 0;
        Cursor = Cursors.Hand;
        ForeColor = Color.White;
        Font = new Font("Segoe UI", 9f, FontStyle.Bold);
        Padding = new Padding(4, 0, 4, 0);
    }

    private Color GetBaseColor()
    {
        switch (_style)
        {
            case ButtonStyle.Secondary: return SecondaryBase;
            case ButtonStyle.Success:   return SuccessBase;
            case ButtonStyle.Warning:   return WarningBase;
            case ButtonStyle.Danger:    return DangerBase;
            default:                    return PrimaryBase;
        }
    }

    private Color AdjustBrightness(Color color, float factor)
    {
        int r = (int)Math.Min(255, Math.Max(0, color.R * factor));
        int g = (int)Math.Min(255, Math.Max(0, color.G * factor));
        int b = (int)Math.Min(255, Math.Max(0, color.B * factor));
        return Color.FromArgb(color.A, r, g, b);
    }

    protected override void OnMouseEnter(EventArgs e) { _hovered = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { _hovered = false; _pressed = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnMouseDown(MouseEventArgs e) { _pressed = true; Invalidate(); base.OnMouseDown(e); }
    protected override void OnMouseUp(MouseEventArgs e) { _pressed = false; Invalidate(); base.OnMouseUp(e); }

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        Color baseColor = GetBaseColor();
        Color fillColor;

        if (!Enabled)
            fillColor = AdjustBrightness(baseColor, 0.5f);
        else if (_pressed)
            fillColor = AdjustBrightness(baseColor, 0.7f);
        else if (_hovered)
            fillColor = AdjustBrightness(baseColor, 1.15f);
        else
            fillColor = baseColor;

        Rectangle rc = new Rectangle(0, 0, Width - 1, Height - 1);
        int radius = 6;
        using (GraphicsPath path = RoundedRect(rc, radius))
        using (SolidBrush brush = new SolidBrush(fillColor))
        {
            e.Graphics.FillPath(brush, path);
        }

        Color textColor = Enabled ? ForeColor : Color.FromArgb(120, ForeColor);
        TextRenderer.DrawText(e.Graphics, Text, Font, rc, textColor,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter |
            TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis);
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

// -- RoundedPanel -------------------------------------------------------------
public class RoundedPanel : Panel
{
    private int _cornerRadius = 8;
    private Color _borderColor = Color.Transparent;

    public int CornerRadius { get { return _cornerRadius; } set { _cornerRadius = value; Invalidate(); } }
    public Color BorderColor { get { return _borderColor; } set { _borderColor = value; Invalidate(); } }

    public RoundedPanel()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        Rectangle rc = new Rectangle(0, 0, Width - 1, Height - 1);
        int d = _cornerRadius * 2;
        using (GraphicsPath path = new GraphicsPath())
        {
            path.AddArc(rc.X, rc.Y, d, d, 180, 90);
            path.AddArc(rc.Right - d, rc.Y, d, d, 270, 90);
            path.AddArc(rc.Right - d, rc.Bottom - d, d, d, 0, 90);
            path.AddArc(rc.X, rc.Bottom - d, d, d, 90, 90);
            path.CloseFigure();

            using (SolidBrush brush = new SolidBrush(BackColor))
                e.Graphics.FillPath(brush, path);

            if (_borderColor != Color.Transparent)
                using (Pen pen = new Pen(_borderColor, 1f))
                    e.Graphics.DrawPath(pen, path);
        }
    }
}

// -- ConnectionIndicator ------------------------------------------------------
public class ConnectionIndicator : Control
{
    public enum ConnectionState { Disconnected, Connecting, Connected }

    private ConnectionState _state = ConnectionState.Disconnected;
    private Timer _pulseTimer;
    private float _pulseAlpha = 1.0f;
    private bool _pulseFading = true;
    private string _statusText = "Not connected";

    private static readonly Color ColorDisconnected = Color.FromArgb(232, 17, 35);
    private static readonly Color ColorConnecting    = Color.FromArgb(247, 99, 12);
    private static readonly Color ColorConnected     = Color.FromArgb(0, 133, 117);

    public ConnectionState State
    {
        get { return _state; }
        set
        {
            _state = value;
            if (_pulseTimer == null) { Invalidate(); return; }
            if (value == ConnectionState.Connecting)
            {
                if (!_pulseTimer.Enabled) _pulseTimer.Start();
            }
            else
            {
                _pulseTimer.Stop();
                _pulseAlpha = 1.0f;
            }
            Invalidate();
        }
    }

    public string StatusText
    {
        get { return _statusText; }
        set { _statusText = value; Invalidate(); }
    }

    public ConnectionIndicator()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        Height = 20;
        ForeColor = Color.FromArgb(190, 180, 210);
        Font = new Font("Segoe UI", 8.5f);

        _pulseTimer = new Timer();
        _pulseTimer.Interval = 50;
        _pulseTimer.Tick += (s, e) =>
        {
            if (_pulseFading) { _pulseAlpha -= 0.05f; if (_pulseAlpha <= 0.3f) _pulseFading = false; }
            else              { _pulseAlpha += 0.05f; if (_pulseAlpha >= 1.0f) _pulseFading = true;  }
            Invalidate();
        };
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        Color dotColor;
        switch (_state)
        {
            case ConnectionState.Connecting:
                dotColor = Color.FromArgb((int)(255 * _pulseAlpha), ColorConnecting);
                break;
            case ConnectionState.Connected:
                dotColor = ColorConnected;
                break;
            default:
                dotColor = ColorDisconnected;
                break;
        }

        using (SolidBrush dotBrush = new SolidBrush(dotColor))
            e.Graphics.FillEllipse(dotBrush, 0, (Height - 10) / 2, 10, 10);

        using (SolidBrush textBrush = new SolidBrush(ForeColor))
            e.Graphics.DrawString(_statusText, Font, textBrush, 16, (Height - Font.Height) / 2f);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) _pulseTimer.Dispose();
        base.Dispose(disposing);
    }
}

// -- SmoothProgressBar ---------------------------------------------------------
public class SmoothProgressBar : Control
{
    private int _maximum = 100;
    private int _value = 0;
    private float _displayValue = 0f;
    private Timer _animTimer;
    private Color _fillColor = Color.FromArgb(103, 58, 183);

    public int Maximum { get { return _maximum; } set { _maximum = value; Invalidate(); } }
    public Color FillColor { get { return _fillColor; } set { _fillColor = value; Invalidate(); } }

    public int Value
    {
        get { return _value; }
        set
        {
            _value = Math.Max(0, Math.Min(_maximum, value));
            _animTimer.Start();
        }
    }

    public SmoothProgressBar()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                 ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        Height = 4;
        BackColor = Color.FromArgb(70, 60, 90);

        _animTimer = new Timer();
        _animTimer.Interval = 16;
        _animTimer.Tick += (s, e) =>
        {
            float target = _maximum > 0 ? (float)_value / _maximum * Width : 0;
            float delta = target - _displayValue;
            if (Math.Abs(delta) < 0.5f) { _displayValue = target; _animTimer.Stop(); }
            else { _displayValue += delta * 0.18f; }
            Invalidate();
        };
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        if (Width <= 0 || Height <= 0) return;

        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using (SolidBrush bgBrush = new SolidBrush(BackColor))
            e.Graphics.FillRectangle(bgBrush, 0, 0, Width, Height);

        if (_displayValue > 1)
        {
            Rectangle fillRect = new Rectangle(0, 0, (int)_displayValue, Height);
            if (!fillRect.IsEmpty)
            {
                using (LinearGradientBrush gb = new LinearGradientBrush(fillRect,
                    AdjustBrightness(_fillColor, 1.3f), _fillColor, LinearGradientMode.Horizontal))
                {
                    e.Graphics.FillRectangle(gb, fillRect);
                }
            }
        }
    }

    private Color AdjustBrightness(Color c, float f)
    {
        return Color.FromArgb(c.A,
            Math.Min(255, (int)(c.R * f)),
            Math.Min(255, (int)(c.G * f)),
            Math.Min(255, (int)(c.B * f)));
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) _animTimer.Dispose();
        base.Dispose(disposing);
    }
}

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

    // Colors (match app theme)
    private static readonly Color BgColor       = Color.FromArgb(30, 25, 40);
    private static readonly Color FieldColor    = Color.FromArgb(75, 60, 100);
    private static readonly Color BorderColor   = Color.FromArgb(70, 60, 90);
    private static readonly Color TextColor     = Color.White;
    private static readonly Color DimTextColor  = Color.FromArgb(190, 180, 210);
    private static readonly Color AccentColor   = Color.FromArgb(103, 58, 183);
    private static readonly Color HoverRowCol   = Color.FromArgb(20, 255, 255, 255);
    private static readonly Color ActiveDot     = Color.White;

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
            var handler = CrosspointClicked;
            if (handler != null)
                handler(this, new CrosspointClickEventArgs(col, row));
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
'@ -ErrorAction Stop

# --- HTTPS Helper Functions --------------------------------------------------

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
    # KUMO routers only use HTTP/80 on local networks -- go straight to HTTP
    $httpUri = $Uri -replace "^https://", "http://"
    $p = @{ Uri=$httpUri; Method=$Method; TimeoutSec=$TimeoutSec; UseBasicParsing=$UseBasicParsing; ErrorAction="Stop" }
    if ($Body) { $p.Body = $Body }
    if ($Headers.Count -gt 0) { $p.Headers = $Headers }
    return Invoke-WebRequest @p
}

# --- Color Theme -------------------------------------------------------------

$clrBg       = [System.Drawing.Color]::FromArgb(30, 25, 40)
$clrPanel    = [System.Drawing.Color]::FromArgb(40, 35, 55)
$clrField    = [System.Drawing.Color]::FromArgb(75, 60, 100)
$clrBorder   = [System.Drawing.Color]::FromArgb(70, 60, 90)
$clrText     = [System.Drawing.Color]::White
$clrDimText  = [System.Drawing.Color]::FromArgb(190, 180, 210)
$clrAccent   = [System.Drawing.Color]::FromArgb(103, 58, 183)
$clrSuccess  = [System.Drawing.Color]::FromArgb(0, 133, 117)
$clrWarning  = [System.Drawing.Color]::FromArgb(247, 99, 12)
$clrDanger   = [System.Drawing.Color]::FromArgb(232, 17, 35)
$clrChanged  = [System.Drawing.Color]::FromArgb(179, 136, 255)

$clrSidebarBg     = [System.Drawing.Color]::FromArgb(25, 20, 35)
$clrStatusBar     = [System.Drawing.Color]::FromArgb(25, 20, 35)
$clrSelectedRow   = [System.Drawing.Color]::FromArgb(103, 58, 183)
$clrAltRow        = [System.Drawing.Color]::FromArgb(45, 40, 60)

# --- AJA KUMO REST API Helpers -----------------------------------------------

function Get-KumoParam {
    param([string]$IP, [string]$ParamId)
    $uri = "http://$IP/config?action=get&configid=0&paramid=$ParamId"
    try {
        $r = Invoke-SecureWebRequest -Uri $uri -TimeoutSec 5 -UseBasicParsing
        $json = $r.Content | ConvertFrom-Json
        if ($json.value_name -and $json.value_name -ne "") { return $json.value_name }
        if ($json.value -and $json.value -ne "") { return $json.value }
        return ""
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

# --- Global State ------------------------------------------------------------

$global:routerConnected     = $false
$global:allLabels         = [System.Collections.ArrayList]::new()
$global:backupLabels      = $null
$global:currentFilter     = "ALL"
$global:routerName        = ""
$global:routerModel       = ""
$global:routerFirmware    = ""
$global:routerInputCount  = 32
$global:routerOutputCount = 32
$global:undoStack         = [System.Collections.Generic.Stack[hashtable]]::new()
$global:redoStack         = [System.Collections.Generic.Stack[hashtable]]::new()
$global:cellEditOldValue  = ""

# New globals for multi-router support
$global:routerType        = ""       # "KUMO" or "Videohub"
$global:maxLabelLength    = 50       # 50 for KUMO, 255 for Videohub
$global:videohubTcp       = $null    # persistent TCP connection for Videohub
$global:videohubWriter    = $null
$global:videohubReader    = $null
$global:lightwareTcp      = $null    # persistent TCP connection for Lightware
$global:lightwareWriter   = $null
$global:lightwareReader   = $null
$global:lightwareSendId   = 0

# Crosspoint routing state
$global:crosspoints       = @()      # int array: index=output, value=routed input (0-based, -1=none)
$global:matrixViewActive  = $false    # true when Matrix tab is active

# --- Router Adapter Functions -------------------------------------------------

function Connect-KumoRouter {
    param([string]$IP)
    # Returns a hashtable with connection info or throws on failure.
    $testUri  = "http://$IP/config?action=get&configid=0&paramid=eParamID_SysName"
    $response = Invoke-SecureWebRequest -Uri $testUri -TimeoutSec 8 -UseBasicParsing -ErrorAction Stop
    $json     = $response.Content | ConvertFrom-Json

    $routerName = if ($json.value -and $json.value -ne "") { $json.value } else { "KUMO" }

    $firmware = ""
    try {
        $fw = Get-KumoParam -IP $IP -ParamId "eParamID_SWVersion"
        if ($fw) { $firmware = $fw }
    } catch { }

    # Detect port count (retry once on failure to avoid misdetection from network glitch)
    $inputCount = 32
    $test64 = Get-KumoParam -IP $IP -ParamId "eParamID_XPT_Source33_Line_1"
    if ($test64 -eq $null) {
        Start-Sleep -Milliseconds 200
        $test64 = Get-KumoParam -IP $IP -ParamId "eParamID_XPT_Source33_Line_1"
    }
    if ($test64 -ne $null) { $inputCount = 64 }

    if ($inputCount -eq 32) {
        $test17 = Get-KumoParam -IP $IP -ParamId "eParamID_XPT_Source17_Line_1"
        if ($test17 -eq $null) {
            Start-Sleep -Milliseconds 200
            $test17 = Get-KumoParam -IP $IP -ParamId "eParamID_XPT_Source17_Line_1"
        }
        if ($test17 -eq $null) { $inputCount = 16 }
    }

    $outputCount = $inputCount
    if ($inputCount -eq 16) {
        $testDest5 = Get-KumoParam -IP $IP -ParamId "eParamID_XPT_Destination5_Line_1"
        if ($testDest5 -eq $null) {
            Start-Sleep -Milliseconds 200
            $testDest5 = Get-KumoParam -IP $IP -ParamId "eParamID_XPT_Destination5_Line_1"
        }
        if ($testDest5 -eq $null) { $outputCount = 4 }
    }

    $modelName = switch ("$inputCount`x$outputCount") {
        "16x4"  { "KUMO 1604" }
        "16x16" { "KUMO 1616" }
        "32x32" { "KUMO 3232" }
        "64x64" { "KUMO 6464" }
        default { "KUMO ${inputCount}x${outputCount}" }
    }

    return @{
        RouterType   = "KUMO"
        RouterName   = $routerName
        RouterModel  = $modelName
        Firmware     = $firmware
        InputCount   = $inputCount
        OutputCount  = $outputCount
    }
}

function Download-KumoLabels {
    param([string]$IP, [int]$InputCount, [int]$OutputCount, [scriptblock]$ProgressCallback = $null)
    # Returns an ArrayList of PSCustomObjects compatible with $global:allLabels format.
    $labels = [System.Collections.ArrayList]::new()
    $restSuccess = $true
    $consecutiveFailures = 0

    for ($i = 1; $i -le $InputCount; $i++) {
        $label = Get-KumoParam -IP $IP -ParamId "eParamID_XPT_Source${i}_Line_1"
        if ($label -eq $null) {
            $label = "Source $i"
            $consecutiveFailures++
            if ($consecutiveFailures -ge 3) { $restSuccess = $false; break }
        } else {
            $consecutiveFailures = 0
            if ($label -eq "") { $label = "Source $i" }
        }
        $labels.Add([PSCustomObject]@{
            Port = $i; Type = "INPUT"; Current_Label = $label; New_Label = ""; Notes = "From KUMO"
        }) | Out-Null
        if ($ProgressCallback) { & $ProgressCallback $i }
    }

    if ($restSuccess) {
        $consecutiveFailures = 0
        for ($i = 1; $i -le $OutputCount; $i++) {
            $label = Get-KumoParam -IP $IP -ParamId "eParamID_XPT_Destination${i}_Line_1"
            if ($label -eq $null) {
                $label = "Dest $i"
                $consecutiveFailures++
                if ($consecutiveFailures -ge 3) { break }
            } else {
                $consecutiveFailures = 0
                if ($label -eq "") { $label = "Dest $i" }
            }
            $labels.Add([PSCustomObject]@{
                Port = $i; Type = "OUTPUT"; Current_Label = $label; New_Label = ""; Notes = "From KUMO"
            }) | Out-Null
            if ($ProgressCallback) { & $ProgressCallback ($InputCount + $i) }
        }
    }

    if (-not $restSuccess) {
        # Telnet fallback
        $labels.Clear()
        $tcp = $null
        try {
            $tcp    = New-Object System.Net.Sockets.TcpClient
            $tcp.Connect($IP, 23)
            $stream = $tcp.GetStream()
            $writer = New-Object System.IO.StreamWriter($stream)
            $reader = New-Object System.IO.StreamReader($stream)
            Start-Sleep -Seconds 1
            while ($stream.DataAvailable) { $reader.ReadLine() | Out-Null }

            for ($i = 1; $i -le $InputCount; $i++) {
                try {
                    $writer.WriteLine("LABEL INPUT $i ?"); $writer.Flush()
                    Start-Sleep -Milliseconds 150
                    $resp  = if ($stream.DataAvailable) { $reader.ReadLine() } else { "" }
                    $label = if ($resp -and $resp -match '"([^"]+)"') { $matches[1] } else { "Input $i" }
                } catch { $label = "Input $i" }
                $labels.Add([PSCustomObject]@{
                    Port = $i; Type = "INPUT"; Current_Label = $label; New_Label = ""; Notes = "Via Telnet"
                }) | Out-Null
                if ($ProgressCallback) { & $ProgressCallback $i }
            }
            for ($i = 1; $i -le $OutputCount; $i++) {
                try {
                    $writer.WriteLine("LABEL OUTPUT $i ?"); $writer.Flush()
                    Start-Sleep -Milliseconds 150
                    $resp  = if ($stream.DataAvailable) { $reader.ReadLine() } else { "" }
                    $label = if ($resp -and $resp -match '"([^"]+)"') { $matches[1] } else { "Output $i" }
                } catch { $label = "Output $i" }
                $labels.Add([PSCustomObject]@{
                    Port = $i; Type = "OUTPUT"; Current_Label = $label; New_Label = ""; Notes = "Via Telnet"
                }) | Out-Null
                if ($ProgressCallback) { & $ProgressCallback ($InputCount + $i) }
            }
        } finally {
            try { if ($writer) { $writer.Close() } } catch { }
            try { if ($reader) { $reader.Close() } } catch { }
            try { if ($tcp)    { $tcp.Close() } } catch { }
        }
    }

    return $labels
}

function Upload-KumoLabel {
    param([string]$IP, [string]$Type, [int]$Port, [string]$Label)
    # Returns $true on success via REST, $false on failure.
    $paramId = if ($Type -eq "INPUT") {
        "eParamID_XPT_Source${Port}_Line_1"
    } else {
        "eParamID_XPT_Destination${Port}_Line_1"
    }
    return (Set-KumoParam -IP $IP -ParamId $paramId -Value $Label)
}

function Upload-KumoLabels-Telnet {
    param([string]$IP, [array]$Items)
    # Sends all items over a single Telnet connection. Returns list of succeeded items.
    $succeeded = [System.Collections.Generic.List[object]]::new()
    $tcp = $null
    $w = $null
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.Connect($IP, 23)
        $s = $tcp.GetStream()
        $w = New-Object System.IO.StreamWriter($s)
        Start-Sleep -Milliseconds 300
        foreach ($item in $Items) {
            try {
                $w.WriteLine("LABEL $($item.Type) $($item.Port) `"$($item.New_Label.Trim())`"")
                $w.Flush()
                Start-Sleep -Milliseconds 150
                $succeeded.Add($item)
            } catch {
                # Per-label write failed -- skip this label but continue with the rest
            }
        }
    } catch {
        # Connection failed -- return whatever succeeded so far
    } finally {
        try { if ($w)   { $w.Close() } } catch { }
        try { if ($tcp) { $tcp.Close() } } catch { }
    }
    return $succeeded
}

function Send-LW3Command {
    param([string]$Command)
    # Frames a command with the current request ID, sends it, reads the response block.
    # Returns an array of response lines (without the wrapper braces).
    $global:lightwareSendId = ($global:lightwareSendId % 9999) + 1
    $idStr = "{0:D4}" -f $global:lightwareSendId
    $framed = "$idStr#$Command`r`n"

    $global:lightwareWriter.Write($framed)
    $global:lightwareWriter.Flush()

    $lines    = [System.Collections.Generic.List[string]]::new()
    $deadline = [DateTime]::Now.AddSeconds(5)
    $inBlock  = $false

    while ([DateTime]::Now -lt $deadline) {
        if ($global:lightwareTcp -eq $null -or -not $global:lightwareTcp.Connected) { break }
        $stream = $global:lightwareTcp.GetStream()
        if ($stream.DataAvailable) {
            $line = $global:lightwareReader.ReadLine()
            if ($line -eq $null) { break }
            $trimmed = $line.Trim()
            if ($trimmed -match "^\{$idStr") {
                $inBlock = $true
                continue
            }
            if ($inBlock -and $trimmed -eq "}") { break }
            if ($inBlock) { $lines.Add($trimmed) }
        } else {
            Start-Sleep -Milliseconds 20
        }
    }

    return $lines.ToArray()
}

function Connect-LightwareRouter {
    param([string]$IP, [int]$Port = 6107)
    # Opens a persistent TCP connection to the Lightware MX2 and queries device info.
    # Stores connection objects in globals. Returns info hashtable or throws on failure.

    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.ReceiveTimeout = 5000
    $tcp.SendTimeout    = 5000
    $tcp.Connect($IP, $Port)

    $stream = $tcp.GetStream()
    $encoding = [System.Text.Encoding]::ASCII
    $reader = New-Object System.IO.StreamReader($stream, $encoding)
    $writer = New-Object System.IO.StreamWriter($stream, $encoding)
    $writer.AutoFlush = $false
    $writer.NewLine   = "`r`n"

    $global:lightwareTcp    = $tcp
    $global:lightwareWriter = $writer
    $global:lightwareReader = $reader
    $global:lightwareSendId = 0

    try {
        # Drain any welcome banner (up to 500ms)
        $drainDeadline = [DateTime]::Now.AddMilliseconds(500)
        while ([DateTime]::Now -lt $drainDeadline -and $stream.DataAvailable) {
            $reader.ReadLine() | Out-Null
            Start-Sleep -Milliseconds 10
        }

        # Get product name
        $productName = "MX2"
        try {
            $resp = Send-LW3Command "GET /.ProductName"
            foreach ($line in $resp) {
                if ($line -match "\.ProductName=(.+)") {
                    $productName = $matches[1].Trim()
                }
            }
        } catch { }

        # Get port counts
        $inputCount  = 0
        $outputCount = 0
        try {
            $resp = Send-LW3Command "GET /MEDIA/XP/VIDEO.SourcePortCount"
            foreach ($line in $resp) {
                if ($line -match "SourcePortCount=(\d+)") {
                    $inputCount = [int]$matches[1]
                }
            }
        } catch {
            Write-ErrorLog "LW3-CONNECT" "Failed to query SourcePortCount: $($_.Exception.Message)"
        }
        try {
            $resp = Send-LW3Command "GET /MEDIA/XP/VIDEO.DestinationPortCount"
            foreach ($line in $resp) {
                if ($line -match "DestinationPortCount=(\d+)") {
                    $outputCount = [int]$matches[1]
                }
            }
        } catch {
            Write-ErrorLog "LW3-CONNECT" "Failed to query DestinationPortCount: $($_.Exception.Message)"
        }

        if ($inputCount -eq 0)  { $inputCount  = 8 }
        if ($outputCount -eq 0) { $outputCount = 8 }

        return @{
            RouterType   = "Lightware"
            RouterName   = $productName
            RouterModel  = "Lightware $productName"
            Firmware     = ""
            InputCount   = $inputCount
            OutputCount  = $outputCount
        }
    } catch {
        try { $writer.Dispose() } catch { }
        try { $reader.Dispose() } catch { }
        try { $tcp.Close() } catch { }
        $global:lightwareTcp    = $null
        $global:lightwareWriter = $null
        $global:lightwareReader = $null
        throw
    }
}

function Download-LightwareLabels {
    param([string]$IP)
    # Closes any existing Lightware TCP session, reconnects, fetches all port labels.
    # Returns hashtable with InputLabels, OutputLabels, InputCount, OutputCount.

    if ($global:lightwareTcp -ne $null) {
        try { $global:lightwareWriter.Dispose() } catch { }
        try { $global:lightwareReader.Dispose() } catch { }
        try { $global:lightwareTcp.Close() }       catch { }
        $global:lightwareTcp    = $null
        $global:lightwareWriter = $null
        $global:lightwareReader = $null
    }

    $info = Connect-LightwareRouter -IP $IP -Port 6107

    $inputLabels  = @{}
    $outputLabels = @{}

    $resp = Send-LW3Command "GET /MEDIA/NAMES/VIDEO.*"
    foreach ($line in $resp) {
        # Lines look like:  pw /MEDIA/NAMES/VIDEO.I3=2;Label Text
        if ($line -match "MEDIA/NAMES/VIDEO\.(I|O)(\d+)=\d+;(.*)") {
            $portType = $matches[1]
            $portNum  = [int]$matches[2]
            $label    = $matches[3].Trim()
            if ($portType -eq "I") {
                $inputLabels[$portNum] = $label
            } else {
                $outputLabels[$portNum] = $label
            }
        }
    }

    return @{
        InputLabels  = $inputLabels
        OutputLabels = $outputLabels
        InputCount   = $info.InputCount
        OutputCount  = $info.OutputCount
    }
}

function Upload-LightwareLabel {
    param([string]$Type, [int]$Port, [string]$Label)
    # Sends a SET command to update a single port label.
    # Returns $true on success, $false on error.

    $prefix = if ($Type -eq "INPUT") { "I" } else { "O" }
    try {
        $resp = Send-LW3Command "SET /MEDIA/NAMES/VIDEO.$prefix${Port}=$Port;$Label"
        foreach ($line in $resp) {
            if ($line -match "^(pE|nE)") { return $false }
        }
        return $true
    } catch {
        return $false
    }
}

function Connect-VideohubRouter {
    param([string]$IP, [int]$Port = 9990)
    # Opens a persistent TCP connection to the Videohub and parses the initial state dump.
    # Stores connection objects in globals. Returns info hashtable or throws on failure.

    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.ReceiveTimeout = 5000
    $tcp.SendTimeout    = 5000
    $tcp.Connect($IP, $Port)

    $stream = $tcp.GetStream()
    $reader = New-Object System.IO.StreamReader($stream)
    $writer = New-Object System.IO.StreamWriter($stream)
    $writer.AutoFlush = $true

    # Read the initial state dump until END PRELUDE or 300ms of silence
    $allLines    = [System.Collections.Generic.List[string]]::new()
    $deadline    = [DateTime]::Now.AddSeconds(8)
    $sawPrelude  = $false
    $silenceStart = $null

    while ([DateTime]::Now -lt $deadline) {
        if ($stream.DataAvailable) {
            $line = $reader.ReadLine()
            if ($line -eq $null) { break }
            $allLines.Add($line)
            $silenceStart = $null  # reset silence timer
            if ($line -eq "PROTOCOL PREAMBLE:") { $sawPrelude = $true }
            if ($line -eq "END PRELUDE:") { break }
        } else {
            if ($allLines.Count -gt 0) {
                if ($silenceStart -eq $null) { $silenceStart = [DateTime]::Now }
                elseif (([DateTime]::Now - $silenceStart).TotalMilliseconds -ge 300) { break }
            }
            Start-Sleep -Milliseconds 20
        }
    }

    if (-not $sawPrelude) {
        try { $tcp.Close() } catch { }
        throw "Device at ${IP}:${Port} did not respond with a Videohub protocol preamble."
    }

    # Parse blocks
    $deviceInfo   = @{}
    $inputLabels  = @{}
    $outputLabels = @{}
    $routingMap   = @{}
    $protocolVersion = "Unknown"

    $currentBlock = ""
    foreach ($line in $allLines) {
        if ($line -match '^([A-Z][A-Z0-9 ]+):$') {
            $currentBlock = $matches[1]
            continue
        }
        if ($line.Trim() -eq "") {
            $currentBlock = ""
            continue
        }

        switch ($currentBlock) {
            "PROTOCOL PREAMBLE" {
                if ($line -match '^Version:\s*(.+)$') {
                    $protocolVersion = $matches[1].Trim()
                }
            }
            "VIDEOHUB DEVICE" {
                if ($line -match '^([^:]+):\s*(.+)$') {
                    $deviceInfo[$matches[1].Trim()] = $matches[2].Trim()
                }
            }
            "INPUT LABELS" {
                if ($line -match '^(\d+)\s+(.*)$') {
                    $inputLabels[[int]$matches[1]] = $matches[2]
                }
            }
            "OUTPUT LABELS" {
                if ($line -match '^(\d+)\s+(.*)$') {
                    $outputLabels[[int]$matches[1]] = $matches[2]
                }
            }
            "VIDEO OUTPUT ROUTING" {
                if ($line -match '^(\d+)\s+(\d+)') {
                    $routingMap[[int]$matches[1]] = [int]$matches[2]
                }
            }
        }
    }

    $modelName    = if ($deviceInfo["Model name"])    { $deviceInfo["Model name"] }    else { "Blackmagic Videohub" }
    $friendlyName = if ($deviceInfo["Friendly name"]) { $deviceInfo["Friendly name"] } else { $modelName }
    $inputCount   = if ($deviceInfo["Video inputs"])  { [int]$deviceInfo["Video inputs"] }  else { $inputLabels.Count }
    $outputCount  = if ($deviceInfo["Video outputs"]) { [int]$deviceInfo["Video outputs"] } else { $outputLabels.Count }

    # Store persistent connection
    $global:videohubTcp    = $tcp
    $global:videohubWriter = $writer
    $global:videohubReader = $reader

    return @{
        RouterType    = "Videohub"
        RouterName    = $friendlyName
        RouterModel   = "Blackmagic $modelName"
        Firmware      = "Protocol $protocolVersion"
        InputCount    = $inputCount
        OutputCount   = $outputCount
        InputLabels   = $inputLabels
        OutputLabels  = $outputLabels
        Routing       = $routingMap
    }
}

function Download-VideohubLabels {
    param([string]$IP, [int]$Port = 9990)
    # If a persistent connection exists, reads current labels from it via re-connect.
    # For simplicity, re-connects to get a fresh state dump each time.
    # Closes the old connection first.
    if ($global:videohubTcp -ne $null) {
        try { $global:videohubWriter.Dispose() } catch { }
        try { $global:videohubReader.Dispose() } catch { }
        try { $global:videohubTcp.Close() } catch { }
        $global:videohubTcp    = $null
        $global:videohubWriter = $null
        $global:videohubReader = $null
    }

    $info = Connect-VideohubRouter -IP $IP -Port $Port
    return $info
}


function Connect-Router {
    param([string]$IP, [string]$RouterType = "Auto")
    # Auto-detects or uses the specified router type.
    # Returns a hashtable with connection info.

    if ($RouterType -eq "Lightware" -or $RouterType -eq "Auto") {
        # Try Lightware TCP 6107 first
        try {
            $testTcp = New-Object System.Net.Sockets.TcpClient
            $connectResult = $testTcp.BeginConnect($IP, 6107, $null, $null)
            $waited = $connectResult.AsyncWaitHandle.WaitOne(2000)
            if ($waited) {
                try {
                    $testTcp.EndConnect($connectResult)
                    if ($testTcp.Connected) {
                        $testTcp.Close()
                        # Port is open -- try full Lightware connect
                        $info = Connect-LightwareRouter -IP $IP -Port 6107
                        return $info
                    }
                } catch {
                    Write-ErrorLog "AUTO-DETECT" "Lightware connect failed: $($_.Exception.Message)"
                    $global:lightwareTcp = $null; $global:lightwareWriter = $null; $global:lightwareReader = $null
                }
                try { $testTcp.Close() } catch { }
            } else {
                try { $testTcp.EndConnect($connectResult) } catch { }
                try { $testTcp.Close() } catch { }
            }
        } catch {
            Write-ErrorLog "AUTO-DETECT" "Lightware probe error: $($_.Exception.Message)" "DEBUG"
        }

        if ($RouterType -eq "Lightware") {
            throw "Cannot connect to Lightware MX2 at $IP on port 6107."
        }
    }

    if ($RouterType -eq "Videohub" -or $RouterType -eq "Auto") {
        # Try Videohub TCP 9990
        try {
            $testTcp = New-Object System.Net.Sockets.TcpClient
            $connectResult = $testTcp.BeginConnect($IP, 9990, $null, $null)
            $waited = $connectResult.AsyncWaitHandle.WaitOne(2000)
            if ($waited) {
                try {
                    $testTcp.EndConnect($connectResult)
                    if ($testTcp.Connected) {
                        $testTcp.Close()
                        # Port is open -- try full Videohub connect
                        $info = Connect-VideohubRouter -IP $IP -Port 9990
                        return $info
                    }
                } catch {
                    $global:videohubTcp = $null; $global:videohubWriter = $null; $global:videohubReader = $null
                }
                try { $testTcp.Close() } catch { }
            } else {
                try { $testTcp.EndConnect($connectResult) } catch { }
                try { $testTcp.Close() } catch { }
            }
        } catch {
            # Videohub not available
        }

        if ($RouterType -eq "Videohub") {
            throw "Cannot connect to Blackmagic Videohub at $IP on port 9990."
        }
    }

    if ($RouterType -eq "KUMO" -or $RouterType -eq "Auto") {
        try {
            return Connect-KumoRouter -IP $IP
        } catch {
            throw "Could not connect to $IP -- no Lightware (TCP/6107), Videohub (TCP/9990), or KUMO (HTTP/80) response detected. Verify the IP address and that the router is powered on."
        }
    }

    throw "Unknown router type: $RouterType"
}

function Download-RouterLabels {
    param([string]$IP, [scriptblock]$ProgressCallback = $null)
    # Downloads labels from whatever router type is currently connected.
    # Populates $global:allLabels directly. Returns count of labels loaded.

    # Snapshot existing labels so we can restore on failure
    $snapshot = [System.Collections.ArrayList]::new($global:allLabels)
    $global:allLabels.Clear()

    try {
        if ($global:routerType -eq "Videohub") {
            if ($ProgressCallback) { & $ProgressCallback 50 }
            $info = Download-VideohubLabels -IP $IP -Port 9990

            $inputLabels  = $info.InputLabels
            $outputLabels = $info.OutputLabels
            $inputCount   = $info.InputCount
            $outputCount  = $info.OutputCount
            $global:routerInputCount  = $inputCount
            $global:routerOutputCount = $outputCount

            for ($i = 1; $i -le $inputCount; $i++) {
                $zeroIdx = $i - 1
                $label = if ($inputLabels.ContainsKey($zeroIdx)) { $inputLabels[$zeroIdx] } else { "Input $i" }
                $global:allLabels.Add([PSCustomObject]@{
                    Port = $i; Type = "INPUT"; Current_Label = $label; New_Label = ""; Notes = "From Videohub"
                }) | Out-Null
            }
            for ($i = 1; $i -le $outputCount; $i++) {
                $zeroIdx = $i - 1
                $label = if ($outputLabels.ContainsKey($zeroIdx)) { $outputLabels[$zeroIdx] } else { "Output $i" }
                $global:allLabels.Add([PSCustomObject]@{
                    Port = $i; Type = "OUTPUT"; Current_Label = $label; New_Label = ""; Notes = "From Videohub"
                }) | Out-Null
            }
            if ($ProgressCallback) { & $ProgressCallback 100 }
            # Store routing data if available
            if ($info.Routing -and $info.Routing.Count -gt 0) {
                $xp = @()
                for ($i = 0; $i -lt $outputCount; $i++) {
                    if ($info.Routing.ContainsKey($i)) { $xp += $info.Routing[$i] }
                    else { $xp += -1 }
                }
                $global:crosspoints = $xp
            }
        } elseif ($global:routerType -eq "Lightware") {
            if ($ProgressCallback) { & $ProgressCallback 50 }
            $info = Download-LightwareLabels -IP $IP

            $inputLabels  = $info.InputLabels
            $outputLabels = $info.OutputLabels
            $inputCount   = $info.InputCount
            $outputCount  = $info.OutputCount
            $global:routerInputCount  = $inputCount
            $global:routerOutputCount = $outputCount

            # Lightware uses 1-based port numbering -- no index translation needed
            for ($i = 1; $i -le $inputCount; $i++) {
                $label = if ($inputLabels.ContainsKey($i)) { $inputLabels[$i] } else { "Input $i" }
                $global:allLabels.Add([PSCustomObject]@{
                    Port = $i; Type = "INPUT"; Current_Label = $label; New_Label = ""; Notes = "From Lightware"
                }) | Out-Null
            }
            for ($i = 1; $i -le $outputCount; $i++) {
                $label = if ($outputLabels.ContainsKey($i)) { $outputLabels[$i] } else { "Output $i" }
                $global:allLabels.Add([PSCustomObject]@{
                    Port = $i; Type = "OUTPUT"; Current_Label = $label; New_Label = ""; Notes = "From Lightware"
                }) | Out-Null
            }
            if ($ProgressCallback) { & $ProgressCallback 100 }
        } else {
            # KUMO
            $downloaded = Download-KumoLabels -IP $IP -InputCount $global:routerInputCount -OutputCount $global:routerOutputCount -ProgressCallback $ProgressCallback
            foreach ($lbl in $downloaded) {
                $global:allLabels.Add($lbl) | Out-Null
            }
            if ($global:allLabels.Count -eq 0) {
                Create-DefaultLabels -InputCount $global:routerInputCount -OutputCount $global:routerOutputCount
            }
        }
    } catch {
        # Restore snapshot on failure so the grid isn't left empty
        $global:allLabels.Clear()
        foreach ($item in $snapshot) { $global:allLabels.Add($item) | Out-Null }
        # If TCP globals were destroyed during the failed attempt, mark disconnected
        if ($global:routerType -eq "Videohub" -and $global:videohubTcp -eq $null) {
            $global:routerConnected = $false
        }
        if ($global:routerType -eq "Lightware" -and $global:lightwareTcp -eq $null) {
            $global:routerConnected = $false
        }
        throw
    }

    return $global:allLabels.Count
}

function Upload-RouterLabels {
    param([string]$IP, [array]$Changes, [scriptblock]$ProgressCallback = $null)
    # Uploads an array of changed label objects to the connected router.
    # Returns hashtable with SuccessCount, ErrorCount, and SuccessLabels.

    if ($global:routerType -eq "Videohub") {
        $inputChanges  = @($Changes | Where-Object { $_.Type -eq "INPUT" })
        $outputChanges = @($Changes | Where-Object { $_.Type -eq "OUTPUT" })
        $successLabels = [System.Collections.Generic.List[object]]::new()

        # Upload in two blocks; track which blocks succeed
        $script:vhSuccessCount = 0
        $script:vhErrorCount   = 0

        if ($global:videohubWriter -eq $null -or $global:videohubTcp -eq $null -or -not $global:videohubTcp.Connected) {
            try { Connect-VideohubRouter -IP $IP -Port 9990 | Out-Null } catch {
                return @{ SuccessCount = 0; ErrorCount = $Changes.Count; SuccessLabels = $successLabels }
            }
        }

        $writer = $global:videohubWriter
        $reader = $global:videohubReader
        $stream = $global:videohubTcp.GetStream()

        $sendBlock = {
            param([string]$BlockHeader, [array]$Items)
            if ($Items.Count -eq 0) { return $true }
            # Always read current globals in case of reconnect
            $writer = $global:videohubWriter
            $reader = $global:videohubReader
            $stream = $global:videohubTcp.GetStream()
            $sb = New-Object System.Text.StringBuilder
            $sb.Append("$BlockHeader`n") | Out-Null
            foreach ($item in $Items) {
                $zeroIndex = $item.Port - 1
                $sb.Append("$zeroIndex $($item.New_Label.Trim())`n") | Out-Null
            }
            $sb.Append("`n") | Out-Null
            try {
                $writer.Write($sb.ToString()); $writer.Flush()
                $deadline = [DateTime]::Now.AddSeconds(5)
                $response = ""
                while ([DateTime]::Now -lt $deadline) {
                    if ($stream.DataAvailable) {
                        $line = $reader.ReadLine()
                        if ($line -eq "ACK") { $response = "ACK"; break }
                        if ($line -eq "NAK") { $response = "NAK"; break }
                    } else { Start-Sleep -Milliseconds 50 }
                }
                return ($response -eq "ACK")
            } catch { return $false }
        }

        $blockNum = 0
        if ($inputChanges.Count -gt 0) {
            $ok = & $sendBlock "INPUT LABELS:" $inputChanges
            $blockNum++
            if ($ok) { foreach ($item in $inputChanges) { $successLabels.Add($item) } ; $script:vhSuccessCount += $inputChanges.Count }
            else     { $script:vhErrorCount += $inputChanges.Count }
            if ($ProgressCallback) { & $ProgressCallback ($blockNum * [int]($Changes.Count / [Math]::Max(($inputChanges.Count -gt 0) + ($outputChanges.Count -gt 0), 1))) }
        }
        if ($outputChanges.Count -gt 0) {
            $ok = & $sendBlock "OUTPUT LABELS:" $outputChanges
            $blockNum++
            if ($ok) { foreach ($item in $outputChanges) { $successLabels.Add($item) } ; $script:vhSuccessCount += $outputChanges.Count }
            else     { $script:vhErrorCount += $outputChanges.Count }
            if ($ProgressCallback) { & $ProgressCallback $Changes.Count }
        }

        return @{ SuccessCount = $script:vhSuccessCount; ErrorCount = $script:vhErrorCount; SuccessLabels = $successLabels }
    } elseif ($global:routerType -eq "Lightware") {
        # Lightware: per-label LW3 SET command via persistent TCP
        $successLabels = [System.Collections.Generic.List[object]]::new()
        $lwSuccessCount = 0
        $lwErrorCount   = 0
        $doneCount      = 0

        # Reconnect if TCP is gone or disconnected
        if ($global:lightwareTcp -eq $null -or -not $global:lightwareTcp.Connected) {
            try { Connect-LightwareRouter -IP $IP -Port 6107 | Out-Null } catch {
                return @{ SuccessCount = 0; ErrorCount = $Changes.Count; SuccessLabels = $successLabels }
            }
        }

        foreach ($item in $Changes) {
            $ok = Upload-LightwareLabel -Type $item.Type -Port $item.Port -Label $item.New_Label.Trim()
            if ($ok) { $successLabels.Add($item); $lwSuccessCount++ } else { $lwErrorCount++ }
            $doneCount++
            if ($ProgressCallback) { & $ProgressCallback $doneCount }
        }

        return @{ SuccessCount = $lwSuccessCount; ErrorCount = $lwErrorCount; SuccessLabels = $successLabels }
    } else {
        # KUMO: per-label REST upload, then bulk Telnet for any REST failures
        $successLabels = [System.Collections.Generic.List[object]]::new()
        $restFailed    = [System.Collections.Generic.List[object]]::new()
        $doneCount     = 0

        foreach ($item in $Changes) {
            $ok = Upload-KumoLabel -IP $IP -Type $item.Type -Port $item.Port -Label $item.New_Label.Trim()
            if ($ok) { $successLabels.Add($item) } else { $restFailed.Add($item) }
            $doneCount++
            if ($ProgressCallback) { & $ProgressCallback $doneCount }
        }

        if ($restFailed.Count -gt 0) {
            $telnetSucceeded = Upload-KumoLabels-Telnet -IP $IP -Items $restFailed
            foreach ($item in $telnetSucceeded) { $successLabels.Add($item) }
            $errorCount = $restFailed.Count - $telnetSucceeded.Count
        } else {
            $errorCount = 0
        }

        return @{ SuccessCount = $successLabels.Count; ErrorCount = $errorCount; SuccessLabels = $successLabels }
    }
}

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

# --- Main Form ---------------------------------------------------------------

$form = New-Object System.Windows.Forms.Form
$form.Text = "Router Label Manager v5.0"
$form.Size = New-Object System.Drawing.Size(1100, 750)
$form.MinimumSize = New-Object System.Drawing.Size(900, 650)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "Sizable"
$form.BackColor = $clrBg
$form.ForeColor = $clrText
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.KeyPreview = $true
$form.SuspendLayout()

# --- Enable double-buffering on the form --------------------------------------

$form.GetType().GetProperty(
    "DoubleBuffered",
    [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic
).SetValue($form, $true)

# --- Sidebar Panel -----------------------------------------------------------

$sidebarPanel = New-Object System.Windows.Forms.Panel
$sidebarPanel.Dock = "Left"
$sidebarPanel.Width = 200
$sidebarPanel.BackColor = $clrSidebarBg
$sidebarPanel.Padding = New-Object System.Windows.Forms.Padding(0)

# App title area
$appTitlePanel = New-Object System.Windows.Forms.Panel
$appTitlePanel.Dock = "Top"
$appTitlePanel.Height = 72
$appTitlePanel.BackColor = $clrSidebarBg
$appTitlePanel.Padding = New-Object System.Windows.Forms.Padding(16, 14, 16, 8)

$lblAppTitle = New-Object System.Windows.Forms.Label
$lblAppTitle.Text = "Router"
$lblAppTitle.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
$lblAppTitle.ForeColor = $clrAccent
$lblAppTitle.Location = New-Object System.Drawing.Point(16, 12)
$lblAppTitle.AutoSize = $true
$appTitlePanel.Controls.Add($lblAppTitle)

$lblAppSubtitle = New-Object System.Windows.Forms.Label
$lblAppSubtitle.Text = "Label Manager"
$lblAppSubtitle.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$lblAppSubtitle.ForeColor = $clrDimText
$lblAppSubtitle.Location = New-Object System.Drawing.Point(18, 46)
$lblAppSubtitle.AutoSize = $true
$appTitlePanel.Controls.Add($lblAppSubtitle)

# Sidebar thin accent line under title
$sidebarAccentLine = New-Object System.Windows.Forms.Label
$sidebarAccentLine.Dock = "Top"
$sidebarAccentLine.Height = 2
$sidebarAccentLine.BackColor = $clrAccent

# Connection section label
$lblConnSection = New-Object System.Windows.Forms.Label
$lblConnSection.Text = "CONNECTION"
$lblConnSection.Font = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Bold)
$lblConnSection.ForeColor = [System.Drawing.Color]::FromArgb(100, 90, 130)
$lblConnSection.Location = New-Object System.Drawing.Point(16, 6)
$lblConnSection.Size = New-Object System.Drawing.Size(168, 16)

$connSectionPanel = New-Object System.Windows.Forms.Panel
$connSectionPanel.Height = 210
$connSectionPanel.BackColor = $clrSidebarBg
$connSectionPanel.Padding = New-Object System.Windows.Forms.Padding(12, 4, 12, 8)
$connSectionPanel.Controls.Add($lblConnSection)

# Router type selector label
$lblRouterType = New-Object System.Windows.Forms.Label
$lblRouterType.Text = "Router Type"
$lblRouterType.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$lblRouterType.ForeColor = $clrDimText
$lblRouterType.Location = New-Object System.Drawing.Point(14, 26)
$lblRouterType.Size = New-Object System.Drawing.Size(80, 16)
$connSectionPanel.Controls.Add($lblRouterType)

# Router type ComboBox
$cboRouterType = New-Object System.Windows.Forms.ComboBox
$cboRouterType.Location = New-Object System.Drawing.Point(14, 44)
$cboRouterType.Size = New-Object System.Drawing.Size(172, 24)
$cboRouterType.BackColor = $clrField
$cboRouterType.ForeColor = $clrText
$cboRouterType.FlatStyle = "Flat"
$cboRouterType.DropDownStyle = "DropDownList"
$cboRouterType.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$cboRouterType.Items.AddRange(@("Auto-detect", "AJA KUMO", "BMD Videohub", "Lightware MX2"))
$cboRouterType.SelectedIndex = 0
$connSectionPanel.Controls.Add($cboRouterType)

# IP label
$lblIp = New-Object System.Windows.Forms.Label
$lblIp.Text = "Router IP"
$lblIp.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$lblIp.ForeColor = $clrDimText
$lblIp.Location = New-Object System.Drawing.Point(14, 74)
$lblIp.Size = New-Object System.Drawing.Size(80, 16)
$connSectionPanel.Controls.Add($lblIp)

# IP textbox
$ipTextBox = New-Object System.Windows.Forms.TextBox
$ipTextBox.Text = "192.168.1.100"
$ipTextBox.Location = New-Object System.Drawing.Point(14, 92)
$ipTextBox.Size = New-Object System.Drawing.Size(172, 24)
$ipTextBox.BackColor = $clrField
$ipTextBox.ForeColor = $clrText
$ipTextBox.BorderStyle = "FixedSingle"
$ipTextBox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$connSectionPanel.Controls.Add($ipTextBox)

# Connect button (ModernButton)
$connectButton = New-Object ModernButton
$connectButton.Text = "Connect"
$connectButton.Style = [ModernButton+ButtonStyle]::Primary
$connectButton.Location = New-Object System.Drawing.Point(14, 124)
$connectButton.Size = New-Object System.Drawing.Size(172, 30)
$connSectionPanel.Controls.Add($connectButton)

# Connection indicator
$connIndicator = New-Object ConnectionIndicator
$connIndicator.Location = New-Object System.Drawing.Point(14, 164)
$connIndicator.Size = New-Object System.Drawing.Size(172, 20)
$connIndicator.BackColor = $clrSidebarBg
$connSectionPanel.Controls.Add($connIndicator)

# Separator line in sidebar
$sidebarSep1 = New-Object System.Windows.Forms.Label
$sidebarSep1.Height = 1
$sidebarSep1.BackColor = [System.Drawing.Color]::FromArgb(50, 45, 65)

# Router info card (RoundedPanel, hidden until connected)
$routerInfoCard = New-Object RoundedPanel
$routerInfoCard.Height = 88
$routerInfoCard.BackColor = $clrPanel
$routerInfoCard.CornerRadius = 8
$routerInfoCard.BorderColor = $clrBorder
$routerInfoCard.Margin = New-Object System.Windows.Forms.Padding(12, 6, 12, 6)
$routerInfoCard.Visible = $false
$routerInfoCard.Padding = New-Object System.Windows.Forms.Padding(10, 8, 10, 8)

$routerInfoWrapper = New-Object System.Windows.Forms.Panel
$routerInfoWrapper.Height = 100
$routerInfoWrapper.BackColor = $clrSidebarBg
$routerInfoWrapper.Padding = New-Object System.Windows.Forms.Padding(12, 6, 12, 6)
$routerInfoWrapper.Visible = $false

$lblRouterModel = New-Object System.Windows.Forms.Label
$lblRouterModel.Text = ""
$lblRouterModel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblRouterModel.ForeColor = $clrText
$lblRouterModel.Location = New-Object System.Drawing.Point(10, 10)
$lblRouterModel.Size = New-Object System.Drawing.Size(160, 18)
$routerInfoCard.Controls.Add($lblRouterModel)

$lblRouterPorts = New-Object System.Windows.Forms.Label
$lblRouterPorts.Text = ""
$lblRouterPorts.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$lblRouterPorts.ForeColor = $clrDimText
$lblRouterPorts.Location = New-Object System.Drawing.Point(10, 30)
$lblRouterPorts.Size = New-Object System.Drawing.Size(160, 16)
$routerInfoCard.Controls.Add($lblRouterPorts)

$lblRouterFw = New-Object System.Windows.Forms.Label
$lblRouterFw.Text = ""
$lblRouterFw.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$lblRouterFw.ForeColor = $clrDimText
$lblRouterFw.Location = New-Object System.Drawing.Point(10, 48)
$lblRouterFw.Size = New-Object System.Drawing.Size(160, 16)
$routerInfoCard.Controls.Add($lblRouterFw)

$lblRouterName = New-Object System.Windows.Forms.Label
$lblRouterName.Text = ""
$lblRouterName.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$lblRouterName.ForeColor = [System.Drawing.Color]::FromArgb(140, 130, 160)
$lblRouterName.Location = New-Object System.Drawing.Point(10, 66)
$lblRouterName.Size = New-Object System.Drawing.Size(160, 14)
$routerInfoCard.Controls.Add($lblRouterName)

$routerInfoWrapper.Controls.Add($routerInfoCard)

# Actions section label
$lblActSection = New-Object System.Windows.Forms.Label
$lblActSection.Text = "ACTIONS"
$lblActSection.Font = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Bold)
$lblActSection.ForeColor = [System.Drawing.Color]::FromArgb(100, 90, 130)
$lblActSection.Location = New-Object System.Drawing.Point(16, 6)
$lblActSection.Size = New-Object System.Drawing.Size(168, 16)

$actionSectionPanel = New-Object System.Windows.Forms.Panel
$actionSectionPanel.Height = 210
$actionSectionPanel.BackColor = $clrSidebarBg
$actionSectionPanel.Controls.Add($lblActSection)

# Download button
$btnDownload = New-Object ModernButton
$btnDownload.Text = "Download from Router"
$btnDownload.Style = [ModernButton+ButtonStyle]::Primary
$btnDownload.Location = New-Object System.Drawing.Point(14, 28)
$btnDownload.Size = New-Object System.Drawing.Size(172, 30)
$btnDownload.Enabled = $false
$actionSectionPanel.Controls.Add($btnDownload)

# Open File button
$btnOpenFile = New-Object ModernButton
$btnOpenFile.Text = "Open File..."
$btnOpenFile.Style = [ModernButton+ButtonStyle]::Secondary
$btnOpenFile.Location = New-Object System.Drawing.Point(14, 66)
$btnOpenFile.Size = New-Object System.Drawing.Size(172, 30)
$actionSectionPanel.Controls.Add($btnOpenFile)

# Save File button
$btnSaveFile = New-Object ModernButton
$btnSaveFile.Text = "Save File..."
$btnSaveFile.Style = [ModernButton+ButtonStyle]::Secondary
$btnSaveFile.Location = New-Object System.Drawing.Point(14, 104)
$btnSaveFile.Size = New-Object System.Drawing.Size(172, 30)
$actionSectionPanel.Controls.Add($btnSaveFile)

# Action separator
$actionSep = New-Object System.Windows.Forms.Label
$actionSep.Location = New-Object System.Drawing.Point(14, 142)
$actionSep.Size = New-Object System.Drawing.Size(172, 1)
$actionSep.BackColor = [System.Drawing.Color]::FromArgb(50, 45, 65)
$actionSectionPanel.Controls.Add($actionSep)

# Upload button
$btnUpload = New-Object ModernButton
$btnUpload.Text = "Upload Changes"
$btnUpload.Style = [ModernButton+ButtonStyle]::Danger
$btnUpload.Location = New-Object System.Drawing.Point(14, 152)
$btnUpload.Size = New-Object System.Drawing.Size(172, 34)
$btnUpload.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnUpload.Enabled = $false
$actionSectionPanel.Controls.Add($btnUpload)

# Assemble sidebar inner panel with manual layout
$sidebarInner = New-Object System.Windows.Forms.Panel
$sidebarInner.Dock = "Fill"
$sidebarInner.BackColor = $clrSidebarBg
$sidebarInner.AutoScroll = $false

$sidebarPanel.Controls.Add($sidebarInner)
$sidebarPanel.Controls.Add($sidebarAccentLine)
$sidebarPanel.Controls.Add($appTitlePanel)

function Update-SidebarLayout {
    $y = 0
    $connSectionPanel.Location = New-Object System.Drawing.Point(0, $y)
    $connSectionPanel.Width = $sidebarInner.Width
    $y += $connSectionPanel.Height

    $sidebarSep1.Location = New-Object System.Drawing.Point(0, $y)
    $sidebarSep1.Width = $sidebarInner.Width
    $y += 1

    if ($routerInfoWrapper.Visible) {
        $routerInfoWrapper.Location = New-Object System.Drawing.Point(0, $y)
        $routerInfoWrapper.Width = $sidebarInner.Width
        $y += $routerInfoWrapper.Height
    }

    # Push actions to bottom with spacer
    $actionsY = $sidebarInner.Height - $actionSectionPanel.Height - 10
    if ($actionsY -lt $y) { $actionsY = $y }
    $actionSectionPanel.Location = New-Object System.Drawing.Point(0, $actionsY)
    $actionSectionPanel.Width = $sidebarInner.Width
}

$sidebarInner.Controls.Add($connSectionPanel)
$sidebarInner.Controls.Add($sidebarSep1)
$sidebarInner.Controls.Add($routerInfoWrapper)
$sidebarInner.Controls.Add($actionSectionPanel)

$sidebarInner.Add_Resize({ Update-SidebarLayout })

# --- Content Panel (right side of sidebar) -----------------------------------

$contentPanel = New-Object System.Windows.Forms.Panel
$contentPanel.Dock = "Fill"
$contentPanel.BackColor = $clrBg

# Accent header stripe (8px purple bar at top of content)
$headerBar = New-Object System.Windows.Forms.Label
$headerBar.Dock = "Top"
$headerBar.Height = 8
$headerBar.BackColor = $clrAccent

# Content header (router info + change count)
$contentHeader = New-Object System.Windows.Forms.Panel
$contentHeader.Dock = "Top"
$contentHeader.Height = 50
$contentHeader.BackColor = $clrPanel
$contentHeader.Padding = New-Object System.Windows.Forms.Padding(16, 0, 16, 0)

$lblContentTitle = New-Object System.Windows.Forms.Label
$lblContentTitle.Text = "No router connected"
$lblContentTitle.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$lblContentTitle.ForeColor = $clrText
$lblContentTitle.Location = New-Object System.Drawing.Point(16, 8)
$lblContentTitle.Size = New-Object System.Drawing.Size(500, 22)
$contentHeader.Controls.Add($lblContentTitle)

$changesCount = New-Object System.Windows.Forms.Label
$changesCount.Text = "0 changes pending"
$changesCount.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$changesCount.ForeColor = $clrDimText
$changesCount.Location = New-Object System.Drawing.Point(16, 30)
$changesCount.Size = New-Object System.Drawing.Size(300, 16)
$contentHeader.Controls.Add($changesCount)

# Filter rail (tab chips + search box)
$filterRail = New-Object System.Windows.Forms.Panel
$filterRail.Dock = "Top"
$filterRail.Height = 44
$filterRail.BackColor = $clrBg
$filterRail.Padding = New-Object System.Windows.Forms.Padding(12, 7, 12, 7)

# Tab chip style buttons
function New-TabChip {
    param([string]$Text, [string]$Tag, [int]$X)
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Tag = $Tag
    $btn.Location = New-Object System.Drawing.Point($X, 7)
    $btn.Size = New-Object System.Drawing.Size(78, 28)
    $btn.BackColor = $clrField
    $btn.ForeColor = $clrText
    $btn.FlatStyle = "Flat"
    $btn.FlatAppearance.BorderSize = 0
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btn.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
    return $btn
}

$tabAll     = New-TabChip "All Ports" "ALL"     12
$tabInputs  = New-TabChip "Inputs"   "INPUT"   96
$tabOutputs = New-TabChip "Outputs"  "OUTPUT"  180
$tabChanged = New-TabChip "Changed"  "CHANGED" 264
$tabAll.Size = New-Object System.Drawing.Size(80, 28)
$tabAll.BackColor = $clrAccent

$filterRail.Controls.Add($tabAll)
$filterRail.Controls.Add($tabInputs)
$filterRail.Controls.Add($tabOutputs)
$filterRail.Controls.Add($tabChanged)
$tabMatrix  = New-TabChip "Matrix"   "MATRIX"  348
$tabMatrix.Size = New-Object System.Drawing.Size(84, 28)
$tabMatrix.FlatAppearance.BorderSize = 1
$tabMatrix.FlatAppearance.BorderColor = $clrAccent
$filterRail.Controls.Add($tabMatrix)

# Batch tools
$btnFindReplace = New-Object System.Windows.Forms.Button
$btnFindReplace.Text = "Find && Replace"
$btnFindReplace.Location = New-Object System.Drawing.Point(440, 7)
$btnFindReplace.Size = New-Object System.Drawing.Size(110, 28)
$btnFindReplace.BackColor = $clrField
$btnFindReplace.ForeColor = $clrText
$btnFindReplace.FlatStyle = "Flat"
$btnFindReplace.FlatAppearance.BorderColor = $clrBorder
$btnFindReplace.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnFindReplace.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$filterRail.Controls.Add($btnFindReplace)

$btnAutoNumber = New-Object System.Windows.Forms.Button
$btnAutoNumber.Text = "Auto-Number"
$btnAutoNumber.Location = New-Object System.Drawing.Point(558, 7)
$btnAutoNumber.Size = New-Object System.Drawing.Size(98, 28)
$btnAutoNumber.BackColor = $clrField
$btnAutoNumber.ForeColor = $clrText
$btnAutoNumber.FlatStyle = "Flat"
$btnAutoNumber.FlatAppearance.BorderColor = $clrBorder
$btnAutoNumber.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnAutoNumber.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$filterRail.Controls.Add($btnAutoNumber)

$btnTemplate = New-Object System.Windows.Forms.Button
$btnTemplate.Text = "Create Template"
$btnTemplate.Location = New-Object System.Drawing.Point(664, 7)
$btnTemplate.Size = New-Object System.Drawing.Size(108, 28)
$btnTemplate.BackColor = $clrField
$btnTemplate.ForeColor = $clrText
$btnTemplate.FlatStyle = "Flat"
$btnTemplate.FlatAppearance.BorderColor = $clrBorder
$btnTemplate.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnTemplate.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$filterRail.Controls.Add($btnTemplate)

$btnClearNew = New-Object System.Windows.Forms.Button
$btnClearNew.Text = "Clear All New"
$btnClearNew.Location = New-Object System.Drawing.Point(780, 7)
$btnClearNew.Size = New-Object System.Drawing.Size(96, 28)
$btnClearNew.BackColor = $clrField
$btnClearNew.ForeColor = $clrText
$btnClearNew.FlatStyle = "Flat"
$btnClearNew.FlatAppearance.BorderColor = $clrBorder
$btnClearNew.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnClearNew.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$filterRail.Controls.Add($btnClearNew)

# Search box (right-aligned in filter rail)
$searchBox = New-Object System.Windows.Forms.TextBox
$searchBox.Size = New-Object System.Drawing.Size(170, 24)
$searchBox.BackColor = $clrField
$searchBox.ForeColor = $clrDimText
$searchBox.BorderStyle = "FixedSingle"
$searchBox.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)

$searchWatermark = "Search labels..."
$searchBox.Text = $searchWatermark

$filterRail.Add_Resize({
    # Clamp search box so it never overlaps the Clear All New button (right edge ~800px)
    $searchX = [Math]::Max($filterRail.Width - 182, 0)
    $searchBox.Location = New-Object System.Drawing.Point($searchX, 9)
})

$filterRail.Controls.Add($searchBox)

# --- DataGridView -------------------------------------------------------------

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
$dataGrid.ColumnHeadersHeight = 36
$dataGrid.RowTemplate.Height = 32
$dataGrid.DefaultCellStyle.BackColor = $clrBg
$dataGrid.DefaultCellStyle.ForeColor = $clrText
$dataGrid.DefaultCellStyle.SelectionBackColor = $clrSelectedRow
$dataGrid.DefaultCellStyle.SelectionForeColor = $clrText
$dataGrid.DefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(6, 0, 4, 0)
$dataGrid.AlternatingRowsDefaultCellStyle.BackColor = $clrAltRow
$dataGrid.AlternatingRowsDefaultCellStyle.SelectionBackColor = $clrSelectedRow
$dataGrid.ColumnHeadersDefaultCellStyle.BackColor = $clrPanel
$dataGrid.ColumnHeadersDefaultCellStyle.ForeColor = $clrDimText
$dataGrid.ColumnHeadersDefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$dataGrid.ColumnHeadersDefaultCellStyle.Alignment = "MiddleLeft"
$dataGrid.ColumnHeadersDefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(6, 0, 0, 0)

# Enable double-buffering on DataGridView via reflection
$dgType = $dataGrid.GetType()
$dgProp = $dgType.GetProperty(
    "DoubleBuffered",
    [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic
)
if ($dgProp) { $dgProp.SetValue($dataGrid, $true) }

# Columns
$colPort = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colPort.Name = "Port"
$colPort.HeaderText = "Port"
$colPort.ReadOnly = $true
$colPort.FillWeight = 6
$colPort.MinimumWidth = 45

$colType = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colType.Name = "Type"
$colType.HeaderText = "Type"
$colType.ReadOnly = $true
$colType.FillWeight = 8
$colType.MinimumWidth = 55

$colCurrent = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colCurrent.Name = "Current_Label"
$colCurrent.HeaderText = "Current Label"
$colCurrent.ReadOnly = $true
$colCurrent.FillWeight = 28
$colCurrent.MinimumWidth = 120
$colCurrent.DefaultCellStyle.ForeColor = $clrDimText

$colNew = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colNew.Name = "New_Label"
$colNew.HeaderText = "New Label (click to edit)"
$colNew.ReadOnly = $false
$colNew.FillWeight = 28
$colNew.MinimumWidth = 120
$colNew.DefaultCellStyle.ForeColor = $clrChanged
$colNew.DefaultCellStyle.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)

$colStatus = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colStatus.Name = "Status"
$colStatus.HeaderText = "Status"
$colStatus.ReadOnly = $true
$colStatus.FillWeight = 10
$colStatus.MinimumWidth = 60

$colCharCount = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colCharCount.Name = "Chars"
$colCharCount.HeaderText = "Chars"
$colCharCount.ReadOnly = $true
$colCharCount.FillWeight = 6
$colCharCount.MinimumWidth = 40
$colCharCount.DefaultCellStyle.Alignment = "MiddleCenter"

$dataGrid.Columns.Add($colPort)     | Out-Null
$dataGrid.Columns.Add($colType)     | Out-Null
$dataGrid.Columns.Add($colCurrent)  | Out-Null
$dataGrid.Columns.Add($colNew)      | Out-Null
$dataGrid.Columns.Add($colStatus)   | Out-Null
$dataGrid.Columns.Add($colCharCount) | Out-Null

# CellPainting: Type column badge + Status column dot
$dataGrid.Add_CellPainting({
    param($sender, $e)
    if ($e.RowIndex -lt 0) { return }

    # -- Type column: colored badge --
    if ($e.ColumnIndex -eq 1) {
        $e.PaintBackground($e.ClipBounds, $true)
        $val = if ($e.Value) { $e.Value.ToString() } else { "" }

        if ($val -eq "INPUT" -or $val -eq "OUTPUT") {
            $isInput = ($val -eq "INPUT")
            $badgeColor = if ($isInput) {
                [System.Drawing.Color]::FromArgb(30, 100, 210, 255)
            } else {
                [System.Drawing.Color]::FromArgb(30, 255, 159, 67)
            }
            $textColor = if ($isInput) {
                [System.Drawing.Color]::FromArgb(100, 210, 255)
            } else {
                [System.Drawing.Color]::FromArgb(255, 159, 67)
            }

            $badgeRect = New-Object System.Drawing.RectangleF(
                ($e.CellBounds.X + 5),
                ($e.CellBounds.Y + ($e.CellBounds.Height - 18) / 2),
                ($e.CellBounds.Width - 10),
                18
            )

            $g = $e.Graphics
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

            $badgePath = New-Object System.Drawing.Drawing2D.GraphicsPath
            $r = [int]$badgeRect.X
            $t = [int]$badgeRect.Y
            $w2 = [int]$badgeRect.Width
            $h2 = [int]$badgeRect.Height
            $rad = 4

            $badgePath.AddArc($r, $t, $rad*2, $rad*2, 180, 90)
            $badgePath.AddArc($r+$w2-$rad*2, $t, $rad*2, $rad*2, 270, 90)
            $badgePath.AddArc($r+$w2-$rad*2, $t+$h2-$rad*2, $rad*2, $rad*2, 0, 90)
            $badgePath.AddArc($r, $t+$h2-$rad*2, $rad*2, $rad*2, 90, 90)
            $badgePath.CloseFigure()

            $bgBrush = $null; $txtBrush = $null; $textFont = $null; $fmt = $null
            try {
                $bgBrush = New-Object System.Drawing.SolidBrush($badgeColor)
                $g.FillPath($bgBrush, $badgePath)

                $txtBrush = New-Object System.Drawing.SolidBrush($textColor)
                $fmt = New-Object System.Drawing.StringFormat
                $fmt.Alignment = [System.Drawing.StringAlignment]::Center
                $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
                $textFont = New-Object System.Drawing.Font("Segoe UI", 7.5, [System.Drawing.FontStyle]::Bold)
                $g.DrawString($val, $textFont, $txtBrush, $badgeRect, $fmt)
            } finally {
                if ($bgBrush)   { $bgBrush.Dispose() }
                if ($badgePath) { $badgePath.Dispose() }
                if ($txtBrush)  { $txtBrush.Dispose() }
                if ($textFont)  { $textFont.Dispose() }
                if ($fmt)       { $fmt.Dispose() }
            }
        }

        $e.Handled = $true
        return
    }

    # -- Status column: colored dot --
    if ($e.ColumnIndex -eq 4) {
        $e.PaintBackground($e.ClipBounds, $true)
        $val = if ($e.Value) { $e.Value.ToString() } else { "" }

        if ($val -eq "Changed") {
            $g = $e.Graphics
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

            $dotX = $e.CellBounds.X + 8
            $dotY = $e.CellBounds.Y + ($e.CellBounds.Height - 8) / 2
            $dotBrush = New-Object System.Drawing.SolidBrush($clrChanged)
            $g.FillEllipse($dotBrush, $dotX, $dotY, 8, 8)
            $dotBrush.Dispose()

            $txtBrush = New-Object System.Drawing.SolidBrush($clrChanged)
            $textRect = New-Object System.Drawing.RectangleF(
                ($e.CellBounds.X + 20),
                $e.CellBounds.Y,
                ($e.CellBounds.Width - 22),
                $e.CellBounds.Height
            )
            $fmt = New-Object System.Drawing.StringFormat
            $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
            $g.DrawString($val, $e.CellStyle.Font, $txtBrush, $textRect, $fmt)
            $txtBrush.Dispose()
            $fmt.Dispose()
        }

        $e.Handled = $true
        return
    }
})

# --- Context Menu for DataGridView -------------------------------------------

$gridContextMenu = New-Object System.Windows.Forms.ContextMenuStrip
$gridContextMenu.BackColor = $clrPanel
$gridContextMenu.ForeColor = $clrText
$gridContextMenu.Font = New-Object System.Drawing.Font("Segoe UI", 9)

$ctxCopyCurrentToNew = $gridContextMenu.Items.Add("Copy Current Label to New Label")
$ctxClearNew         = $gridContextMenu.Items.Add("Clear New Label")
$ctxCopyClipboard    = $gridContextMenu.Items.Add("Copy to Clipboard")
$gridContextMenu.Items.Add("-") | Out-Null
$ctxSelectInputs     = $gridContextMenu.Items.Add("Select All Inputs")
$ctxSelectOutputs    = $gridContextMenu.Items.Add("Select All Outputs")

$ctxCopyCurrentToNew.Add_Click({
    foreach ($row in $dataGrid.SelectedRows) {
        $port = $row.Cells["Port"].Value
        $type = $row.Cells["Type"].Value
        $currentVal = $row.Cells["Current_Label"].Value
        foreach ($lbl in $global:allLabels) {
            if ($lbl.Port -eq $port -and $lbl.Type -eq $type) {
                $newVal = if ($currentVal) { $currentVal.ToString() } else { "" }
                Push-UndoCommand @{ Port=$lbl.Port; Type=$lbl.Type; OldValue=$lbl.New_Label; NewValue=$newVal }
                $lbl.New_Label = $newVal
                break
            }
        }
    }
    Populate-Grid
})

$ctxClearNew.Add_Click({
    foreach ($row in $dataGrid.SelectedRows) {
        $port = $row.Cells["Port"].Value
        $type = $row.Cells["Type"].Value
        foreach ($lbl in $global:allLabels) {
            if ($lbl.Port -eq $port -and $lbl.Type -eq $type) {
                Push-UndoCommand @{ Port=$lbl.Port; Type=$lbl.Type; OldValue=$lbl.New_Label; NewValue="" }
                $lbl.New_Label = ""
                break
            }
        }
    }
    Populate-Grid
})

$ctxCopyClipboard.Add_Click({
    $lines = @()
    foreach ($row in $dataGrid.SelectedRows | Sort-Object { $_.Index }) {
        $port    = $row.Cells["Port"].Value
        $type    = $row.Cells["Type"].Value
        $current = $row.Cells["Current_Label"].Value
        $newLbl  = $row.Cells["New_Label"].Value
        $lines += "$type $port`t$current`t$newLbl"
    }
    if ($lines.Count -gt 0) {
        [System.Windows.Forms.Clipboard]::SetText(($lines -join [Environment]::NewLine))
    }
})

$ctxSelectInputs.Add_Click({
    $dataGrid.ClearSelection()
    foreach ($row in $dataGrid.Rows) {
        if ($row.Cells["Type"].Value -eq "INPUT") { $row.Selected = $true }
    }
})

$ctxSelectOutputs.Add_Click({
    $dataGrid.ClearSelection()
    foreach ($row in $dataGrid.Rows) {
        if ($row.Cells["Type"].Value -eq "OUTPUT") { $row.Selected = $true }
    }
})

$dataGrid.ContextMenuStrip = $gridContextMenu

$gridContextMenu.Add_Opening({
    param($sender, $e)
    $pt = $dataGrid.PointToClient([System.Windows.Forms.Control]::MousePosition)
    $hit = $dataGrid.HitTest($pt.X, $pt.Y)
    if ($hit.RowIndex -lt 0) { $e.Cancel = $true }
})

# --- Status Bar --------------------------------------------------------------

$statusBar = New-Object System.Windows.Forms.Panel
$statusBar.Dock = "Bottom"
$statusBar.Height = 32
$statusBar.BackColor = $clrStatusBar
$statusBar.Padding = New-Object System.Windows.Forms.Padding(12, 0, 12, 0)

$progressBar = New-Object SmoothProgressBar
$progressBar.Location = New-Object System.Drawing.Point(0, 0)
$progressBar.Size = New-Object System.Drawing.Size(200, 4)
$progressBar.BackColor = [System.Drawing.Color]::FromArgb(50, 45, 65)
$progressBar.FillColor = $clrAccent
$progressBar.Maximum = 100
$progressBar.Value = 0
$statusBar.Controls.Add($progressBar)

$progressLabel = New-Object System.Windows.Forms.Label
$progressLabel.Text = "Ready"
$progressLabel.ForeColor = $clrDimText
$progressLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$progressLabel.Location = New-Object System.Drawing.Point(12, 8)
$progressLabel.AutoSize = $true
$statusBar.Controls.Add($progressLabel)

$lblStatusRight = New-Object System.Windows.Forms.Label
$lblStatusRight.Text = ""
$lblStatusRight.ForeColor = $clrDimText
$lblStatusRight.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblStatusRight.TextAlign = "MiddleRight"
$statusBar.Controls.Add($lblStatusRight)

$statusBar.Add_Resize({
    $progressBar.Width = $statusBar.Width
    $lblStatusRight.Location = New-Object System.Drawing.Point(($statusBar.Width - 300), 8)
    $lblStatusRight.Size = New-Object System.Drawing.Size(285, 16)
})

# --- Matrix Panel ---------------------------------------------------------------
$matrixPanel = New-Object CrosspointMatrixPanel
$matrixPanel.Dock = "Fill"
$matrixPanel.Visible = $false

# --- Assemble Content Panel (reverse dock order: Bottom first, then Fill, then Top) --

$contentPanel.Controls.Add($matrixPanel)     # Dock=Fill (hidden by default)
$contentPanel.Controls.Add($dataGrid)       # Dock=Fill
$contentPanel.Controls.Add($statusBar)      # Dock=Bottom
$contentPanel.Controls.Add($filterRail)     # Dock=Top (below contentHeader)
$contentPanel.Controls.Add($contentHeader)  # Dock=Top (below headerBar)
$contentPanel.Controls.Add($headerBar)      # Dock=Top (very top of content)

# --- Add Sidebar + Content to Form -------------------------------------------

$form.Controls.Add($contentPanel)  # Dock=Fill
$form.Controls.Add($sidebarPanel)  # Dock=Left

# --- Helper Functions ---------------------------------------------------------

function Populate-Grid {
    $dataGrid.SuspendLayout()
    $dataGrid.Rows.Clear()

    $searchTerm = ""
    if ($searchBox.Text -ne $searchWatermark) { $searchTerm = $searchBox.Text.Trim().ToLower() }

    $maxLen = $global:maxLabelLength

    foreach ($lbl in $global:allLabels) {
        if ($global:currentFilter -eq "INPUT"  -and $lbl.Type -ne "INPUT")  { continue }
        if ($global:currentFilter -eq "OUTPUT" -and $lbl.Type -ne "OUTPUT") { continue }
        if ($global:currentFilter -eq "CHANGED") {
            $nl = $lbl.New_Label
            if (-not $nl -or $nl.Trim() -eq "" -or $nl.Trim() -eq $lbl.Current_Label) { continue }
        }

        if ($searchTerm) {
            $matchCurrent = if ($lbl.Current_Label) { $lbl.Current_Label.ToLower().Contains($searchTerm) } else { $false }
            $matchNew     = if ($lbl.New_Label)     { $lbl.New_Label.ToLower().Contains($searchTerm) }     else { $false }
            $matchPort    = if ($lbl.Port)           { $lbl.Port.ToString().Contains($searchTerm) }         else { $false }
            if (-not ($matchCurrent -or $matchNew -or $matchPort)) { continue }
        }

        $newLabel  = $lbl.New_Label
        $status    = ""
        $charCount = ""
        if ($newLabel -and $newLabel.Trim() -ne "" -and $newLabel.Trim() -ne $lbl.Current_Label) {
            $status    = "Changed"
            $charCount = "$($newLabel.Trim().Length)/$maxLen"
        }

        $rowIndex = $dataGrid.Rows.Add($lbl.Port, $lbl.Type, $lbl.Current_Label, $newLabel, $status, $charCount)

        if ($newLabel -and $newLabel.Trim().Length -gt $maxLen) {
            $dataGrid.Rows[$rowIndex].Cells["Chars"].Style.ForeColor     = $clrDanger
            $dataGrid.Rows[$rowIndex].Cells["New_Label"].Style.ForeColor = $clrDanger
        }
    }

    $dataGrid.ResumeLayout()
    Update-ChangeCount
}

function Update-ChangeCount {
    $count = 0
    foreach ($lbl in $global:allLabels) {
        $nl = $lbl.New_Label
        if ($nl -and $nl.Trim() -ne "" -and $nl.Trim() -ne $lbl.Current_Label) { $count++ }
    }

    if ($count -gt 0) {
        $changesCount.Text      = "$count change$(if($count -ne 1){'s'}) pending"
        $changesCount.ForeColor = $clrChanged
        $btnUpload.Enabled      = $global:routerConnected
        $btnUpload.Text         = "Upload Changes ($count)"
    } else {
        $changesCount.Text      = "No changes pending"
        $changesCount.ForeColor = $clrDimText
        $btnUpload.Enabled      = $false
        $btnUpload.Text         = "Upload Changes"
    }

    $totalLabels = $global:allLabels.Count
    $lblStatusRight.Text = "$totalLabels labels | $count changed"
}

function Sync-GridToData {
    foreach ($row in $dataGrid.Rows) {
        $port   = $row.Cells["Port"].Value
        $type   = $row.Cells["Type"].Value
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
    param([int]$InputCount = 32, [int]$OutputCount = 32)
    $global:allLabels.Clear()
    for ($i = 1; $i -le $InputCount; $i++) {
        $global:allLabels.Add([PSCustomObject]@{
            Port = $i; Type = "INPUT"; Current_Label = "Input $i"; New_Label = ""; Notes = ""
        }) | Out-Null
    }
    for ($i = 1; $i -le $OutputCount; $i++) {
        $global:allLabels.Add([PSCustomObject]@{
            Port = $i; Type = "OUTPUT"; Current_Label = "Output $i"; New_Label = ""; Notes = ""
        }) | Out-Null
    }
}

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

function Set-StatusMessage {
    param([string]$Message, [string]$Color = "Dim")
    $progressLabel.Text = $Message
    $progressLabel.ForeColor = switch ($Color) {
        "Success" { $clrSuccess }
        "Warning" { $clrWarning }
        "Danger"  { $clrDanger }
        "Changed" { $clrChanged }
        default   { $clrDimText }
    }
}

function Push-UndoCommand {
    param([hashtable]$Command)
    $global:undoStack.Push($Command)
    $global:redoStack.Clear()
}

# --- Keyboard Shortcuts --------------------------------------------------------

$form.Add_KeyDown({
    param($sender, $e)

    if ($dataGrid.IsCurrentCellInEditMode) {
        if ($e.KeyCode -ne "Escape") { return }
    }

    if ($e.Control -and $e.Shift -and $e.KeyCode -eq "Z") {
        if ($global:redoStack.Count -gt 0) {
            $cmd = $global:redoStack.Pop()
            foreach ($lbl in $global:allLabels) {
                if ($lbl.Port -eq $cmd.Port -and $lbl.Type -eq $cmd.Type) {
                    $global:undoStack.Push(@{ Port=$lbl.Port; Type=$lbl.Type; OldValue=$lbl.New_Label; NewValue=$cmd.NewValue })
                    $lbl.New_Label = $cmd.NewValue
                    break
                }
            }
            Populate-Grid
        }
        $e.Handled = $true
        $e.SuppressKeyPress = $true
        return
    }

    if ($e.Control -and $e.KeyCode -eq "Y") {
        if ($global:redoStack.Count -gt 0) {
            $cmd = $global:redoStack.Pop()
            foreach ($lbl in $global:allLabels) {
                if ($lbl.Port -eq $cmd.Port -and $lbl.Type -eq $cmd.Type) {
                    $global:undoStack.Push(@{ Port=$lbl.Port; Type=$lbl.Type; OldValue=$lbl.New_Label; NewValue=$cmd.NewValue })
                    $lbl.New_Label = $cmd.NewValue
                    break
                }
            }
            Populate-Grid
        }
        $e.Handled = $true
        $e.SuppressKeyPress = $true
        return
    }

    if ($e.Control -and -not $e.Shift -and $e.KeyCode -eq "Z") {
        if ($global:undoStack.Count -gt 0) {
            $cmd = $global:undoStack.Pop()
            foreach ($lbl in $global:allLabels) {
                if ($lbl.Port -eq $cmd.Port -and $lbl.Type -eq $cmd.Type) {
                    $global:redoStack.Push(@{ Port=$lbl.Port; Type=$lbl.Type; OldValue=$lbl.New_Label; NewValue=$cmd.NewValue })
                    $lbl.New_Label = $cmd.OldValue
                    break
                }
            }
            Populate-Grid
        }
        $e.Handled = $true
        return
    }

    if ($e.Control -and $e.KeyCode -eq "S") {
        $btnSaveFile.PerformClick()
        $e.Handled = $true
        return
    }

    if ($e.Control -and $e.KeyCode -eq "O") {
        $btnOpenFile.PerformClick()
        $e.Handled = $true
        return
    }

    if ($e.Control -and $e.KeyCode -eq "H") {
        $btnFindReplace.PerformClick()
        $e.Handled = $true
        return
    }

    if ($e.Control -and $e.KeyCode -eq "K") {
        Set-StatusMessage "Command palette coming soon (Ctrl+K)" "Dim"
        $e.Handled = $true
        return
    }

    if ($e.KeyCode -eq "F5") {
        if ($btnDownload.Enabled) { $btnDownload.PerformClick() }
        $e.Handled = $true
        return
    }

    if ($e.Control -and $e.KeyCode -eq "Return") {
        if ($btnUpload.Enabled) { $btnUpload.PerformClick() }
        $e.Handled = $true
        return
    }

    if ($e.Control -and $e.KeyCode -eq "A") {
        $dataGrid.SelectAll()
        $e.Handled = $true
        $e.SuppressKeyPress = $true
        return
    }

    if ($e.KeyCode -eq "Delete") {
        foreach ($row in $dataGrid.SelectedRows) {
            $port = $row.Cells["Port"].Value
            $type = $row.Cells["Type"].Value
            foreach ($lbl in $global:allLabels) {
                if ($lbl.Port -eq $port -and $lbl.Type -eq $type -and $lbl.New_Label) {
                    Push-UndoCommand @{ Port=$lbl.Port; Type=$lbl.Type; OldValue=$lbl.New_Label; NewValue="" }
                    $lbl.New_Label = ""
                }
            }
        }
        Populate-Grid
        $e.Handled = $true
        $e.SuppressKeyPress = $true
        return
    }
})

# --- Connection ----------------------------------------------------------------

$connectButton.Add_Click({
    $ip = $ipTextBox.Text.Trim()
    if (-not $ip) { return }

    $connectButton.Enabled = $false

    # Map ComboBox selection to RouterType parameter
    $selectedType = switch ($cboRouterType.SelectedIndex) {
        1 { "KUMO" }
        2 { "Videohub" }
        3 { "Lightware" }
        default { "Auto" }
    }

    $connIndicator.State      = [ConnectionIndicator+ConnectionState]::Connecting
    $connIndicator.StatusText = "Connecting..."
    $form.Refresh()

    if ($keepaliveTimer -ne $null) { $keepaliveTimer.Stop() }
    if ($global:videohubTcp -ne $null) {
        try { $global:videohubWriter.Dispose() } catch { }
        try { $global:videohubReader.Dispose() } catch { }
        try { $global:videohubTcp.Close() } catch { }
        $global:videohubTcp    = $null
        $global:videohubWriter = $null
        $global:videohubReader = $null
    }
    if ($global:lightwareTcp -ne $null) {
        try { $global:lightwareWriter.Dispose() } catch { }
        try { $global:lightwareReader.Dispose() } catch { }
        try { $global:lightwareTcp.Close() } catch { }
        $global:lightwareTcp    = $null
        $global:lightwareWriter = $null
        $global:lightwareReader = $null
    }

    try {
        $info = Connect-Router -IP $ip -RouterType $selectedType

        $global:routerConnected     = $true
        $global:routerType        = $info.RouterType
        $global:routerName        = $info.RouterName
        $global:routerModel       = $info.RouterModel
        $global:routerFirmware    = $info.Firmware
        $global:routerInputCount  = $info.InputCount
        $global:routerOutputCount = $info.OutputCount
        $global:maxLabelLength    = if ($info.RouterType -eq "Videohub" -or $info.RouterType -eq "Lightware") { 255 } else { 50 }

        $fwText = if ($global:routerFirmware) { " | $($global:routerFirmware)" } else { "" }

        $connIndicator.State      = [ConnectionIndicator+ConnectionState]::Connected
        $connIndicator.StatusText = "Connected"
        $connIndicator.ForeColor  = $clrSuccess

        $connectButton.Text  = "Reconnect"
        $btnDownload.Enabled = $true

        # Update router info card
        $lblRouterModel.Text = $global:routerModel
        $lblRouterPorts.Text = "$($info.InputCount) inputs / $($info.OutputCount) outputs"
        $lblRouterFw.Text    = if ($global:routerFirmware) { $global:routerFirmware } else { "" }
        $lblRouterName.Text  = "`"$($global:routerName)`""
        $routerInfoWrapper.Visible = $true
        $routerInfoCard.Visible    = $true
        Update-SidebarLayout

        $lblContentTitle.Text = "$($global:routerModel)  `"$($global:routerName)`""
        $form.Text = "Router Label Manager - $($global:routerModel) `"$($global:routerName)`""

        Update-ChangeCount
        Set-StatusMessage "Connected to $($global:routerModel) at $ip$fwText" "Success"

        # Pre-fetch crosspoint state for matrix view (skip if already loaded from Videohub state dump)
        if ($global:crosspoints.Count -eq 0) {
            try {
                $global:crosspoints = Get-RouterCrosspoints
            } catch {
                Write-ErrorLog "CONNECT" "Crosspoint query failed (non-fatal): $($_.Exception.Message)" "WARN"
                $global:crosspoints = @()
            }
        }

        $connectButton.Enabled = $true
        if (($global:routerType -eq "Videohub" -or $global:routerType -eq "Lightware") -and $keepaliveTimer -ne $null) { $keepaliveTimer.Start() }

    } catch {
        Write-ErrorLog "CONNECT" "Connection to $ip failed: $($_.Exception.GetType().Name): $($_.Exception.Message)"
        $global:routerConnected = $false
        $connIndicator.State      = [ConnectionIndicator+ConnectionState]::Disconnected
        $connIndicator.StatusText = "Connection failed"
        $connIndicator.ForeColor  = $clrDimText
        $btnDownload.Enabled = $false
        $progressBar.Value = 0
        Set-StatusMessage "Connection failed" "Danger"
        $connectButton.Enabled = $true

        [System.Windows.Forms.MessageBox]::Show(
            "Cannot connect to router at $ip`n`nCheck that:`n- The IP address is correct`n- The router is powered on`n- You're on the same network`n- Port 6107 (Lightware), 80 (KUMO) or 9990 (Videohub) is accessible`n`nError: $($_.Exception.Message)",
            "Connection Failed", "OK", "Error"
        )
    }
})

# --- Download Labels ----------------------------------------------------------

$btnDownload.Add_Click({
    $ip      = $ipTextBox.Text.Trim()
    $total   = $global:routerInputCount + $global:routerOutputCount

    if ($global:routerType -eq "Videohub" -or $global:routerType -eq "Lightware") {
        $progressBar.Maximum = 100
    } else {
        $progressBar.Maximum = [Math]::Max($total, 1)
    }
    $progressBar.Value = 0
    Set-StatusMessage "Downloading from $($global:routerModel)..." "Dim"
    $form.Refresh()

    $dlProgressCallback = {
        param([int]$val)
        $progressBar.Value = [Math]::Min($val, $progressBar.Maximum)
        $form.Refresh()
    }

    try {
        $count = Download-RouterLabels -IP $ip -ProgressCallback $dlProgressCallback

        if ($count -eq 0) {
            Create-DefaultLabels -InputCount $global:routerInputCount -OutputCount $global:routerOutputCount
        }

        $progressBar.Value = $progressBar.Maximum

        # Auto-save
        try {
            $docsPath     = Get-DocumentsPath
            $safeName     = $global:routerName -replace '[^\w\-]', '_'
            $autoSavePath = Join-Path $docsPath "${safeName}_Labels_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"
            $global:allLabels | Select-Object Port, Type, Current_Label, New_Label, Notes |
                Export-Csv -Path $autoSavePath -NoTypeInformation
            Set-StatusMessage "Downloaded $($global:allLabels.Count) labels - saved to Documents\KUMO_Labels" "Success"
        } catch {
            Set-StatusMessage "Downloaded $($global:allLabels.Count) labels (auto-save failed)" "Warning"
        }

        Populate-Grid

        # Refresh crosspoint state
        try {
            $global:crosspoints = Get-RouterCrosspoints
            if ($global:matrixViewActive) { Update-MatrixPanel }
        } catch {
            Write-ErrorLog "DOWNLOAD" "Crosspoint refresh failed (non-fatal): $($_.Exception.Message)" "WARN"
        }

    } catch {
        Write-ErrorLog "DOWNLOAD" "Download from $ip failed: $($_.Exception.GetType().Name): $($_.Exception.Message)"
        $progressBar.Value = 0
        Set-StatusMessage "Download failed: $($_.Exception.Message)" "Danger"
        [System.Windows.Forms.MessageBox]::Show(
            "Error downloading labels: $($_.Exception.Message)",
            "Download Error", "OK", "Error"
        )
    }
})

# --- Open File ----------------------------------------------------------------

$btnOpenFile.Add_Click({
    $dlg        = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "Label Files (*.csv;*.xlsx)|*.csv;*.xlsx|CSV files (*.csv)|*.csv|Excel files (*.xlsx)|*.xlsx|All files (*.*)|*.*"
    $dlg.Title  = "Open Label File"

    if ($dlg.ShowDialog() -eq "OK") {
        try {
            $global:allLabels.Clear()
            $data = $null

            if ($dlg.FileName -match "\.csv$") {
                $data = Import-Csv -Path $dlg.FileName
            } else {
                if (Get-Module -ListAvailable -Name ImportExcel) {
                    Import-Module ImportExcel
                    # Try each worksheet name in priority order
                    $data = $null
                    foreach ($wsName in @("Lightware_Labels", "Videohub_Labels", "KUMO_Labels")) {
                        try {
                            $data = Import-Excel -Path $dlg.FileName -WorksheetName $wsName
                            if ($data) { break }
                        } catch { }
                    }
                    if (-not $data) { throw "No compatible worksheet found." }
                } else {
                    $excel = $null; $wb = $null
                    try {
                        $excel = New-Object -ComObject Excel.Application
                        $excel.Visible = $false
                        $wb  = $excel.Workbooks.Open($dlg.FileName)
                        $ws = $null
                        try { $ws = $wb.Worksheets.Item("Lightware_Labels") } catch {}
                        if (-not $ws) { try { $ws = $wb.Worksheets.Item("Videohub_Labels") } catch {} }
                        if (-not $ws) { try { $ws = $wb.Worksheets.Item("KUMO_Labels") } catch {} }
                        if (-not $ws) { throw "No compatible worksheet found (expected 'Lightware_Labels', 'Videohub_Labels' or 'KUMO_Labels')." }
                        $data = @()
                        $lastRow = $ws.UsedRange.Rows.Count
                        for ($row = 2; $row -le $lastRow; $row++) {
                            $data += [PSCustomObject]@{
                                Port          = $ws.Cells.Item($row,1).Value2
                                Type          = $ws.Cells.Item($row,2).Value2
                                Current_Label = $ws.Cells.Item($row,3).Value2
                                New_Label     = $ws.Cells.Item($row,4).Value2
                            }
                        }
                    } finally {
                        if ($wb)    { try { $wb.Close($false); [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wb) | Out-Null } catch {} }
                        if ($excel) { try { $excel.Quit(); [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null } catch {} }
                        $wb = $null; $excel = $null
                    }
                }
            }

            if ($data) {
                foreach ($row in $data) {
                    if (-not $row.Port -or -not $row.Type) { continue }
                    $nl = if ($row.New_Label)     { $row.New_Label.ToString() }     else { "" }
                    $cl = if ($row.Current_Label) { $row.Current_Label.ToString() } else { "" }
                    $global:allLabels.Add([PSCustomObject]@{
                        Port          = [int]$row.Port
                        Type          = $row.Type.ToString().ToUpper().Trim()
                        Current_Label = $cl
                        New_Label     = $nl
                        Notes         = if ($row.Notes) { $row.Notes.ToString() } else { "" }
                    }) | Out-Null
                }
                if (-not $global:routerConnected) {
                    $maxLen = ($global:allLabels | ForEach-Object {
                        $len1 = if ($_.Current_Label) { $_.Current_Label.Length } else { 0 }
                        $len2 = if ($_.New_Label) { $_.New_Label.Length } else { 0 }
                        [Math]::Max($len1, $len2)
                    } | Measure-Object -Maximum).Maximum
                    $global:maxLabelLength = if ($maxLen -gt 50) { 255 } else { 50 }
                }
                Populate-Grid
                Set-StatusMessage "Loaded $($global:allLabels.Count) labels from $([System.IO.Path]::GetFileName($dlg.FileName))" "Success"
            }
        } catch {
            Write-ErrorLog "FILE-OPEN" "Error loading file: $($_.Exception.GetType().Name): $($_.Exception.Message)"
            [System.Windows.Forms.MessageBox]::Show("Error loading file: $($_.Exception.Message)", "Load Error", "OK", "Error")
        }
    }
})

# --- Save File ----------------------------------------------------------------

$btnSaveFile.Add_Click({
    Sync-GridToData

    $dlg            = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter     = "CSV files (*.csv)|*.csv|Excel files (*.xlsx)|*.xlsx"
    $dlg.DefaultExt = "csv"
    $safeName        = if ($global:routerName) { $global:routerName -replace '[^\w\-]', '_' } else { "Router" }
    $dlg.FileName   = "${safeName}_Labels_$(Get-Date -Format 'yyyyMMdd_HHmm')"
    $dlg.InitialDirectory = Get-DocumentsPath
    $dlg.Title      = "Save Label File"

    if ($dlg.ShowDialog() -eq "OK") {
        try {
            if ($dlg.FileName -match "\.xlsx$") {
                if (Get-Module -ListAvailable -Name ImportExcel) {
                    Import-Module ImportExcel
                    $saveWsName = switch ($global:routerType) {
                        "Videohub"  { "Videohub_Labels" }
                        "Lightware" { "Lightware_Labels" }
                        default     { "KUMO_Labels" }
                    }
                    $global:allLabels | Select-Object Port, Type, Current_Label, New_Label, Notes |
                        Export-Excel -Path $dlg.FileName -WorksheetName $saveWsName -AutoSize -TableStyle Medium6 -FreezeTopRow
                } else {
                    $csvPath = $dlg.FileName -replace "\.xlsx$", ".csv"
                    $global:allLabels | Select-Object Port, Type, Current_Label, New_Label, Notes |
                        Export-Csv -Path $csvPath -NoTypeInformation
                    $dlg.FileName = $csvPath
                    Set-StatusMessage "ImportExcel module not found -- saved as CSV instead" "Warning"
                }
            } else {
                $global:allLabels | Select-Object Port, Type, Current_Label, New_Label, Notes |
                    Export-Csv -Path $dlg.FileName -NoTypeInformation
            }
            Set-StatusMessage "Saved to $([System.IO.Path]::GetFileName($dlg.FileName))" "Success"
        } catch {
            Write-ErrorLog "FILE-SAVE" "Error saving file: $($_.Exception.GetType().Name): $($_.Exception.Message)"
            [System.Windows.Forms.MessageBox]::Show("Error saving file: $($_.Exception.Message)", "Save Error", "OK", "Error")
        }
    }
})

# --- Find and Replace --------------------------------------------------------

$btnFindReplace.Add_Click({
    Sync-GridToData

    $frForm = New-Object System.Windows.Forms.Form
    $frForm.Text = "Find && Replace in Labels"
    $frForm.Size = New-Object System.Drawing.Size(440, 310)
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
        Location="90,18"; Size="320,24"; BackColor=$clrField; ForeColor=$clrText; BorderStyle="FixedSingle"
    }
    $frForm.Controls.Add($findBox)

    $frForm.Controls.Add((New-Object System.Windows.Forms.Label -Property @{
        Text="Replace:"; Location="20,55"; Size="60,20"; ForeColor=$clrText
    }))
    $replaceBox = New-Object System.Windows.Forms.TextBox -Property @{
        Location="90,53"; Size="320,24"; BackColor=$clrField; ForeColor=$clrText; BorderStyle="FixedSingle"
    }
    $frForm.Controls.Add($replaceBox)

    $chkCaseSensitive = New-Object System.Windows.Forms.CheckBox -Property @{
        Text="Case sensitive"; Location="90,85"; Size="130,20"; Checked=$false; ForeColor=$clrText
    }
    $frForm.Controls.Add($chkCaseSensitive)

    $scopeGroup = New-Object System.Windows.Forms.GroupBox -Property @{
        Text="Apply to"; Location="20,112"; Size="380,55"; ForeColor=$clrDimText
    }
    $rbNewLabels = New-Object System.Windows.Forms.RadioButton -Property @{
        Text="New Label column"; Location="15,22"; Size="150,20"; Checked=$true; ForeColor=$clrText
    }
    $rbCurrentToNew = New-Object System.Windows.Forms.RadioButton -Property @{
        Text="Copy Current to New, then replace"; Location="170,22"; Size="200,20"; ForeColor=$clrText
    }
    $scopeGroup.Controls.Add($rbNewLabels)
    $scopeGroup.Controls.Add($rbCurrentToNew)
    $frForm.Controls.Add($scopeGroup)

    $typeGroup = New-Object System.Windows.Forms.GroupBox -Property @{
        Text="Port type"; Location="20,172"; Size="380,45"; ForeColor=$clrDimText
    }
    $rbAll = New-Object System.Windows.Forms.RadioButton -Property @{
        Text="All"; Location="15,15"; Size="55,20"; Checked=$true; ForeColor=$clrText
    }
    $rbInputOnly = New-Object System.Windows.Forms.RadioButton -Property @{
        Text="Inputs only"; Location="80,15"; Size="95,20"; ForeColor=$clrText
    }
    $rbOutputOnly = New-Object System.Windows.Forms.RadioButton -Property @{
        Text="Outputs only"; Location="185,15"; Size="100,20"; ForeColor=$clrText
    }
    $typeGroup.Controls.Add($rbAll)
    $typeGroup.Controls.Add($rbInputOnly)
    $typeGroup.Controls.Add($rbOutputOnly)
    $frForm.Controls.Add($typeGroup)

    $btnDoReplace = New-Object ModernButton -Property @{
        Text="Replace All"; Location="250,232"; Size="90,30"
    }
    $btnDoReplace.Style = [ModernButton+ButtonStyle]::Primary

    $btnCancelFR = New-Object ModernButton -Property @{
        Text="Cancel"; Location="350,232"; Size="70,30"
    }
    $btnCancelFR.Style = [ModernButton+ButtonStyle]::Secondary

    $btnDoReplace.Add_Click({
        $find    = $findBox.Text
        $replace = $replaceBox.Text
        if (-not $find) { return }

        $caseSensitive = $chkCaseSensitive.Checked
        $escapedFind   = [regex]::Escape($find)
        $regexOpts     = if ($caseSensitive) { [System.Text.RegularExpressions.RegexOptions]::None } else { [System.Text.RegularExpressions.RegexOptions]::IgnoreCase }

        $count = 0
        foreach ($lbl in $global:allLabels) {
            if ($rbInputOnly.Checked  -and $lbl.Type -ne "INPUT")  { continue }
            if ($rbOutputOnly.Checked -and $lbl.Type -ne "OUTPUT") { continue }

            if ($rbCurrentToNew.Checked) {
                $src = if ($lbl.Current_Label) { $lbl.Current_Label } else { "" }
                $matched = if ($caseSensitive) { $src -like "*$find*" } else { $src -ilike "*$find*" }
                if ($matched) {
                    $result = [regex]::Replace($src, $escapedFind, $replace, $regexOpts)
                    if ($result.Length -gt $global:maxLabelLength) {
                        $result = $result.Substring(0, $global:maxLabelLength)
                    }
                    $oldVal = $lbl.New_Label
                    Push-UndoCommand @{ Port=$lbl.Port; Type=$lbl.Type; OldValue=$oldVal; NewValue=$result }
                    $lbl.New_Label = $result
                    $count++
                }
            } else {
                if ($lbl.New_Label) {
                    $matched = if ($caseSensitive) { $lbl.New_Label -like "*$find*" } else { $lbl.New_Label -ilike "*$find*" }
                    if ($matched) {
                        $result = [regex]::Replace($lbl.New_Label, $escapedFind, $replace, $regexOpts)
                        if ($result.Length -gt $global:maxLabelLength) {
                            $result = $result.Substring(0, $global:maxLabelLength)
                        }
                        $oldVal = $lbl.New_Label
                        Push-UndoCommand @{ Port=$lbl.Port; Type=$lbl.Type; OldValue=$oldVal; NewValue=$result }
                        $lbl.New_Label = $result
                        $count++
                    }
                }
            }
        }
        $frForm.Close()
        Populate-Grid
        Set-StatusMessage "Replaced in $count labels" "Changed"
    })
    $btnCancelFR.Add_Click({ $frForm.Close() })
    $frForm.Controls.Add($btnDoReplace)
    $frForm.Controls.Add($btnCancelFR)
    $frForm.ShowDialog() | Out-Null
})

# --- Auto-Number --------------------------------------------------------------

$btnAutoNumber.Add_Click({
    Sync-GridToData

    $anForm = New-Object System.Windows.Forms.Form
    $anForm.Text = "Auto-Number Labels"
    $anForm.Size = New-Object System.Drawing.Size(400, 250)
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

    $updatePreview = {
        $p = $prefixBox.Text
        $s = [int]$startNumBox.Value
        $previewLbl.Text = "$p$s, $p$($s+1), $p$($s+2)..."
    }
    $prefixBox.Add_TextChanged($updatePreview)
    $startNumBox.Add_ValueChanged($updatePreview)

    $typeGroup2 = New-Object System.Windows.Forms.GroupBox -Property @{
        Text="Apply to"; Location="20,115"; Size="340,50"; ForeColor=$clrDimText
    }
    $rbInputs2 = New-Object System.Windows.Forms.RadioButton -Property @{
        Text="Inputs"; Location="15,20"; Size="70,20"; Checked=$true; ForeColor=$clrText
    }
    $rbOutputs2 = New-Object System.Windows.Forms.RadioButton -Property @{
        Text="Outputs"; Location="95,20"; Size="80,20"; ForeColor=$clrText
    }
    $rbBoth2 = New-Object System.Windows.Forms.RadioButton -Property @{
        Text="Both"; Location="185,20"; Size="60,20"; ForeColor=$clrText
    }
    $rbSelected2 = New-Object System.Windows.Forms.RadioButton -Property @{
        Text="Selected rows"; Location="255,20"; Size="100,20"; ForeColor=$clrText
    }
    $typeGroup2.Controls.Add($rbInputs2)
    $typeGroup2.Controls.Add($rbOutputs2)
    $typeGroup2.Controls.Add($rbBoth2)
    $typeGroup2.Controls.Add($rbSelected2)
    $anForm.Controls.Add($typeGroup2)

    $btnApply = New-Object ModernButton -Property @{
        Location="240,185"; Size="70,30"; Text="Apply"
    }
    $btnApply.Style = [ModernButton+ButtonStyle]::Primary

    $btnCancelAN = New-Object ModernButton -Property @{
        Location="320,185"; Size="55,30"; Text="Cancel"
    }
    $btnCancelAN.Style = [ModernButton+ButtonStyle]::Secondary

    $btnApply.Add_Click({
        $prefix = $prefixBox.Text
        $num    = [int]$startNumBox.Value

        if ($rbSelected2.Checked) {
            $sortedRows = $dataGrid.SelectedRows | Sort-Object { $_.Index }
            foreach ($row in $sortedRows) {
                $port = $row.Cells["Port"].Value
                $type = $row.Cells["Type"].Value
                foreach ($lbl in $global:allLabels) {
                    if ($lbl.Port -eq $port -and $lbl.Type -eq $type) {
                        $label = "$prefix$num"
                        if ($label.Length -gt $global:maxLabelLength) {
                            $label = $label.Substring(0, $global:maxLabelLength)
                        }
                        Push-UndoCommand @{ Port=$lbl.Port; Type=$lbl.Type; OldValue=$lbl.New_Label; NewValue=$label }
                        $lbl.New_Label = $label
                        $num++
                        break
                    }
                }
            }
        } else {
            foreach ($lbl in $global:allLabels) {
                if ($rbInputs2.Checked  -and $lbl.Type -ne "INPUT")  { continue }
                if ($rbOutputs2.Checked -and $lbl.Type -ne "OUTPUT") { continue }
                $label = "$prefix$num"
                if ($label.Length -gt $global:maxLabelLength) {
                    $label = $label.Substring(0, $global:maxLabelLength)
                }
                Push-UndoCommand @{ Port=$lbl.Port; Type=$lbl.Type; OldValue=$lbl.New_Label; NewValue=$label }
                $lbl.New_Label = $label
                $num++
            }
        }
        $anForm.Close()
        Populate-Grid
        Set-StatusMessage "Auto-numbered labels" "Changed"
    })
    $btnCancelAN.Add_Click({ $anForm.Close() })
    $anForm.Controls.Add($btnApply)
    $anForm.Controls.Add($btnCancelAN)
    $anForm.ShowDialog() | Out-Null
})

# --- Create Template ----------------------------------------------------------

$btnTemplate.Add_Click({
    Sync-GridToData

    $inCount   = $global:routerInputCount
    $outCount  = $global:routerOutputCount
    $modelName = $global:routerModel

    if (-not $global:routerConnected) {
        $pickForm = New-Object System.Windows.Forms.Form
        $pickForm.Text = "Select Router Model"
        $pickForm.Size = New-Object System.Drawing.Size(340, 210)
        $pickForm.StartPosition = "CenterParent"
        $pickForm.BackColor = $clrPanel
        $pickForm.ForeColor = $clrText
        $pickForm.FormBorderStyle = "FixedDialog"
        $pickForm.MaximizeBox = $false
        $pickForm.MinimizeBox = $false

        $pickForm.Controls.Add((New-Object System.Windows.Forms.Label -Property @{
            Text="No router connected. Select your model:"; Location="20,15"; Size="290,20"; ForeColor=$clrText
        }))

        $modelCombo = New-Object System.Windows.Forms.ComboBox -Property @{
            Location="20,45"; Size="290,28"; BackColor=$clrField; ForeColor=$clrText; DropDownStyle="DropDownList"
        }
        $modelCombo.Items.AddRange(@(
            "KUMO 1604 (16 in / 4 out)",
            "KUMO 1616 (16 in / 16 out)",
            "KUMO 3232 (32 in / 32 out)",
            "KUMO 6464 (64 in / 64 out)",
            "Videohub 10x10 (10 in / 10 out)",
            "Videohub 20x20 (20 in / 20 out)",
            "Videohub 40x40 (40 in / 40 out)",
            "Videohub 80x80 (80 in / 80 out)",
            "Videohub 120x120 (120 in / 120 out)",
            "Smart Videohub 12x12 (12 in / 12 out)",
            "Micro Videohub 16x16 (16 in / 16 out)",
            "MX2-4x4 (4 in / 4 out)",
            "MX2-8x4 (8 in / 4 out)",
            "MX2-8x8 (8 in / 8 out)",
            "MX2-16x16 (16 in / 16 out)",
            "MX2-24x24 (24 in / 24 out)",
            "MX2-32x32 (32 in / 32 out)",
            "MX2-48x48 (48 in / 48 out)"
        ))
        $modelCombo.SelectedIndex = 2
        $pickForm.Controls.Add($modelCombo)

        $btnPickOK = New-Object ModernButton -Property @{
            Text="OK"; Location="150,105"; Size="70,28"; DialogResult="OK"
        }
        $btnPickOK.Style = [ModernButton+ButtonStyle]::Primary

        $btnPickCancel = New-Object ModernButton -Property @{
            Text="Cancel"; Location="230,105"; Size="80,28"; DialogResult="Cancel"
        }
        $btnPickCancel.Style = [ModernButton+ButtonStyle]::Secondary

        $pickForm.Controls.Add($btnPickOK)
        $pickForm.Controls.Add($btnPickCancel)
        $pickForm.AcceptButton = $btnPickOK
        $pickForm.CancelButton = $btnPickCancel

        if ($pickForm.ShowDialog() -ne "OK") { return }

        switch ($modelCombo.SelectedIndex) {
            0  { $inCount = 16;  $outCount = 4;   $modelName = "KUMO 1604" }
            1  { $inCount = 16;  $outCount = 16;  $modelName = "KUMO 1616" }
            2  { $inCount = 32;  $outCount = 32;  $modelName = "KUMO 3232" }
            3  { $inCount = 64;  $outCount = 64;  $modelName = "KUMO 6464" }
            4  { $inCount = 10;  $outCount = 10;  $modelName = "Videohub 10x10" }
            5  { $inCount = 20;  $outCount = 20;  $modelName = "Videohub 20x20" }
            6  { $inCount = 40;  $outCount = 40;  $modelName = "Videohub 40x40" }
            7  { $inCount = 80;  $outCount = 80;  $modelName = "Videohub 80x80" }
            8  { $inCount = 120; $outCount = 120; $modelName = "Videohub 120x120" }
            9  { $inCount = 12;  $outCount = 12;  $modelName = "Smart Videohub 12x12" }
            10 { $inCount = 16;  $outCount = 16;  $modelName = "Micro Videohub 16x16" }
            11 { $inCount = 4;   $outCount = 4;   $modelName = "MX2-4x4" }
            12 { $inCount = 8;   $outCount = 4;   $modelName = "MX2-8x4" }
            13 { $inCount = 8;   $outCount = 8;   $modelName = "MX2-8x8" }
            14 { $inCount = 16;  $outCount = 16;  $modelName = "MX2-16x16" }
            15 { $inCount = 24;  $outCount = 24;  $modelName = "MX2-24x24" }
            16 { $inCount = 32;  $outCount = 32;  $modelName = "MX2-32x32" }
            17 { $inCount = 48;  $outCount = 48;  $modelName = "MX2-48x48" }
        }
    }

    $templateData = @()
    $hasLabels    = ($global:allLabels.Count -gt 0)

    for ($i = 1; $i -le $inCount; $i++) {
        $currentLabel = "Input $i"
        if ($hasLabels) {
            $existing = $global:allLabels | Where-Object { $_.Port -eq $i -and $_.Type -eq "INPUT" } | Select-Object -First 1
            if ($existing -and $existing.Current_Label) { $currentLabel = $existing.Current_Label }
        }
        $templateData += [PSCustomObject]@{
            Port = $i; Type = "INPUT"; Current_Label = $currentLabel; New_Label = ""; Notes = "Enter your new label name here"
        }
    }
    for ($i = 1; $i -le $outCount; $i++) {
        $currentLabel = "Output $i"
        if ($hasLabels) {
            $existing = $global:allLabels | Where-Object { $_.Port -eq $i -and $_.Type -eq "OUTPUT" } | Select-Object -First 1
            if ($existing -and $existing.Current_Label) { $currentLabel = $existing.Current_Label }
        }
        $templateData += [PSCustomObject]@{
            Port = $i; Type = "OUTPUT"; Current_Label = $currentLabel; New_Label = ""; Notes = "Enter your new label name here"
        }
    }

    $docsPath        = Get-DocumentsPath
    $safeName        = if ($global:routerName -and $global:routerName -ne "") {
        $global:routerName -replace '[^\w\-]', '_'
    } else { $modelName -replace ' ', '_' }
    $templateFileName = "${safeName}_Template_$(Get-Date -Format 'yyyyMMdd_HHmm')"

    $savedPath = $null
    $hasExcel  = $false
    try { $hasExcel = [bool](Get-Module -ListAvailable -Name ImportExcel) } catch {}

    if ($hasExcel) {
        try {
            Import-Module ImportExcel
            $savedPath = Join-Path $docsPath "$templateFileName.xlsx"
            $worksheetName = switch ($global:routerType) {
                "Videohub"  { "Videohub_Labels" }
                "Lightware" { "Lightware_Labels" }
                default     { "KUMO_Labels" }
            }
            $templateData | Export-Excel -Path $savedPath -WorksheetName $worksheetName -AutoSize -TableStyle Medium6 -FreezeTopRow
        } catch {
            $savedPath = $null
            Set-StatusMessage "Excel export failed -- saving as CSV instead" "Warning"
        }
    }

    if (-not $savedPath) {
        $savedPath = Join-Path $docsPath "$templateFileName.csv"
        $templateData | Export-Csv -Path $savedPath -NoTypeInformation
    }

    Set-StatusMessage "Template saved: $([System.IO.Path]::GetFileName($savedPath))" "Success"
    try { Start-Process $savedPath } catch { }

    [System.Windows.Forms.MessageBox]::Show(
        "Template created for $modelName - $inCount inputs / $outCount outputs`n`nFile: $savedPath`n`nInstructions:`n1. Fill in the 'New_Label' column with your desired names`n2. Save the file`n3. Use 'Open File' to load it back`n4. Click 'Upload Changes' to apply",
        "Template Created", "OK", "Information"
    )
})

# --- Clear All New Labels -----------------------------------------------------

$btnClearNew.Add_Click({
    $result = [System.Windows.Forms.MessageBox]::Show(
        "Clear all New Label values?", "Confirm Clear", "YesNo", "Question"
    )
    if ($result -eq "Yes") {
        foreach ($lbl in $global:allLabels) { $lbl.New_Label = "" }
        $global:undoStack.Clear()
        $global:redoStack.Clear()
        Populate-Grid
        Set-StatusMessage "All new labels cleared" "Dim"
    }
})

# --- Tab Filters --------------------------------------------------------------

$tabAll.Add_Click({     Set-ActiveTab $tabAll })
$tabInputs.Add_Click({  Set-ActiveTab $tabInputs })
$tabOutputs.Add_Click({ Set-ActiveTab $tabOutputs })
$tabChanged.Add_Click({ Set-ActiveTab $tabChanged })
$tabMatrix.Add_Click({  Set-ActiveTab $tabMatrix })

# --- Search -------------------------------------------------------------------

$searchBox.Add_GotFocus({
    if ($searchBox.Text -eq $searchWatermark) {
        $searchBox.Text      = ""
        $searchBox.ForeColor = $clrText
    }
})

$searchBox.Add_LostFocus({
    if ($searchBox.Text -eq "") {
        $searchBox.Text      = $searchWatermark
        $searchBox.ForeColor = $clrDimText
    }
})

$searchBox.Add_TextChanged({
    if ($searchBox.Text -ne $searchWatermark) {
        Sync-GridToData
        Populate-Grid
    }
})

# --- Grid Cell Editing with Undo ---------------------------------------------

$dataGrid.Add_EditingControlShowing({
    param($sender, $e)
    $tb = $e.Control
    if ($tb -is [System.Windows.Forms.TextBox]) {
        $tb.MaxLength = $global:maxLabelLength
    }
})

$dataGrid.Add_CellBeginEdit({
    param($sender, $e)
    if ($e.ColumnIndex -eq 3) {
        $val = $sender.Rows[$e.RowIndex].Cells["New_Label"].Value
        $global:cellEditOldValue = if ($val) { $val.ToString() } else { "" }
    }
})

$dataGrid.Add_CellEndEdit({
    param($sender, $e)
    if ($e.ColumnIndex -eq 3) {
        $port   = $sender.Rows[$e.RowIndex].Cells["Port"].Value
        $type   = $sender.Rows[$e.RowIndex].Cells["Type"].Value
        $newVal = $sender.Rows[$e.RowIndex].Cells["New_Label"].Value
        $newStr = if ($newVal) { $newVal.ToString() } else { "" }

        if ($newStr -ne $global:cellEditOldValue) {
            Push-UndoCommand @{
                Port     = $port
                Type     = $type
                OldValue = $global:cellEditOldValue
                NewValue = $newStr
            }
        }

        foreach ($lbl in $global:allLabels) {
            if ($lbl.Port -eq $port -and $lbl.Type -eq $type) {
                $lbl.New_Label = $newStr
                break
            }
        }

        $maxLen = $global:maxLabelLength
        $currentLabel = $sender.Rows[$e.RowIndex].Cells["Current_Label"].Value
        if ($newStr.Trim() -ne "" -and $newStr.Trim() -ne $currentLabel) {
            $sender.Rows[$e.RowIndex].Cells["Status"].Value = "Changed"
            $len = $newStr.Trim().Length
            $sender.Rows[$e.RowIndex].Cells["Chars"].Value  = "$len/$maxLen"
            if ($len -gt $maxLen) {
                $sender.Rows[$e.RowIndex].Cells["Chars"].Style.ForeColor    = $clrDanger
                $sender.Rows[$e.RowIndex].Cells["New_Label"].Style.ForeColor = $clrDanger
            } else {
                $sender.Rows[$e.RowIndex].Cells["Chars"].Style.ForeColor    = $clrText
                $sender.Rows[$e.RowIndex].Cells["New_Label"].Style.ForeColor = $clrChanged
            }
        } else {
            $sender.Rows[$e.RowIndex].Cells["Status"].Value = ""
            $sender.Rows[$e.RowIndex].Cells["Chars"].Value  = ""
            $sender.Rows[$e.RowIndex].Cells["Chars"].Style.ForeColor    = $clrText
            $sender.Rows[$e.RowIndex].Cells["New_Label"].Style.ForeColor = $clrText
        }

        Update-ChangeCount
    }
})

# --- Upload to Router ---------------------------------------------------------

$btnUpload.Add_Click({
    Sync-GridToData

    if (-not $global:routerConnected) {
        [System.Windows.Forms.MessageBox]::Show("Please connect to a router first.", "Not Connected", "OK", "Warning")
        return
    }

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

    $maxLen = $global:maxLabelLength
    $tooLong = @($changes | Where-Object { $_.New_Label.Trim().Length -gt $maxLen })
    if ($tooLong.Count -gt 0) {
        $result = [System.Windows.Forms.MessageBox]::Show(
            "$($tooLong.Count) labels exceed the $maxLen-character limit. They may be truncated by the router.`n`nContinue anyway?",
            "Character Limit Warning", "YesNo", "Warning"
        )
        if ($result -ne "Yes") { return }
    }

    $routerTypeLabel = switch ($global:routerType) {
        "Videohub"  { "Blackmagic Videohub" }
        "Lightware" { "Lightware MX2" }
        default     { "KUMO" }
    }
    $result = [System.Windows.Forms.MessageBox]::Show(
        "Upload $($changes.Count) label changes to $routerTypeLabel at $($ipTextBox.Text)?`n`nThis will modify the router's port names immediately.`n`nA backup of current labels will be saved automatically.",
        "Confirm Upload", "YesNo", "Question"
    )
    if ($result -ne "Yes") { return }

    # Backup
    $global:backupLabels = @()
    foreach ($lbl in $global:allLabels) {
        $global:backupLabels += [PSCustomObject]@{
            Port = $lbl.Port; Type = $lbl.Type; Current_Label = $lbl.Current_Label; New_Label = ""; Notes = "Backup"
        }
    }
    $backupSaved = $false
    try {
        $docsPath    = Get-DocumentsPath
        $safeName    = $global:routerName -replace '[^\w\-]', '_'
        $backupPath  = Join-Path $docsPath "${safeName}_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $global:backupLabels | Export-Csv -Path $backupPath -NoTypeInformation
        $backupSaved = $true
    } catch { }

    $ip = $ipTextBox.Text.Trim()
    $progressBar.Maximum = [Math]::Max($changes.Count, 1)
    $progressBar.Value   = 0
    Set-StatusMessage "Uploading $($changes.Count) labels to $($global:routerModel)..." "Dim"
    $form.Refresh()

    $btnUpload.Enabled    = $false
    $btnDownload.Enabled  = $false
    $connectButton.Enabled = $false
    if ($keepaliveTimer -ne $null) { $keepaliveTimer.Stop() }

    $ulProgressCallback = {
        param([int]$val)
        $progressBar.Value = [Math]::Min($val, $progressBar.Maximum)
        $form.Refresh()
    }

    try {
        $result       = Upload-RouterLabels -IP $ip -Changes $changes -ProgressCallback $ulProgressCallback
        $successCount = $result.SuccessCount
        $errorCount   = $result.ErrorCount

        $progressBar.Value = $progressBar.Maximum

        if ($result.SuccessLabels -and $result.SuccessLabels.Count -gt 0) {
            foreach ($item in $result.SuccessLabels) {
                $item.Current_Label = $item.New_Label.Trim()
                $item.New_Label     = ""
            }
            Populate-Grid
        }

        $statusColor = if ($errorCount -eq 0) { "Success" } else { "Warning" }
        Set-StatusMessage "Upload complete: $successCount OK, $errorCount failed" $statusColor

        $icon = if ($errorCount -eq 0) { "Information" } else { "Warning" }
        $backupMsg = if ($backupSaved) { "`n`nBackup saved to Documents\KUMO_Labels folder." } else { "`n`nWarning: backup could not be saved." }
        [System.Windows.Forms.MessageBox]::Show(
            "Upload complete!`n`nSuccessful: $successCount`nFailed: $errorCount$backupMsg",
            "Upload Results", "OK", $icon
        )
    } catch {
        Write-ErrorLog "UPLOAD" "Upload failed: $($_.Exception.GetType().Name): $($_.Exception.Message)"
        Set-StatusMessage "Upload failed: $_" "Danger"
        [System.Windows.Forms.MessageBox]::Show("Upload failed:`n`n$($_.Exception.Message)", "Upload Error", "OK", "Error")
    } finally {
        $btnDownload.Enabled   = $global:routerConnected
        $connectButton.Enabled = $true
        $remainingChanges = @($global:allLabels | Where-Object { $_.New_Label -and $_.New_Label.Trim() -ne "" -and $_.New_Label.Trim() -ne $_.Current_Label })
        $btnUpload.Enabled = ($remainingChanges.Count -gt 0)
        if (($global:routerType -eq "Videohub" -or $global:routerType -eq "Lightware") -and $global:routerConnected -and $keepaliveTimer -ne $null) { $keepaliveTimer.Start() }
    }
})

# --- Videohub PING Keepalive --------------------------------------------------

$keepaliveTimer = New-Object System.Windows.Forms.Timer
$keepaliveTimer.Interval = 25000
$keepaliveTimer.Add_Tick({
    if ($global:routerType -eq "Videohub" -and $global:routerConnected -and $global:videohubWriter) {
        try {
            $global:videohubWriter.Write("PING:`n`n")
            $global:videohubWriter.Flush()
        } catch {
            Write-ErrorLog "KEEPALIVE" "Videohub keepalive failed: $($_.Exception.Message)"
            $global:routerConnected = $false
            $keepaliveTimer.Stop()
            $connIndicator.State = [ConnectionIndicator+ConnectionState]::Disconnected
            $connIndicator.StatusText = "Connection lost"
            $connectButton.Text = "Connect"
            $btnDownload.Enabled = $false
            $btnUpload.Enabled = $false
            Set-StatusMessage "Videohub connection lost" "Danger"
        }
    }
    if ($global:routerType -eq "Lightware" -and $global:routerConnected -and $global:lightwareWriter) {
        try {
            Send-LW3Command "GET /.ProductName" | Out-Null
        } catch {
            Write-ErrorLog "KEEPALIVE" "Lightware keepalive failed: $($_.Exception.Message)"
            $global:routerConnected = $false
            $keepaliveTimer.Stop()
            $connIndicator.State = [ConnectionIndicator+ConnectionState]::Disconnected
            $connIndicator.StatusText = "Connection lost"
            $connectButton.Text = "Connect"
            $btnDownload.Enabled = $false
            $btnUpload.Enabled = $false
            Set-StatusMessage "Lightware connection lost" "Danger"
        }
    }
})
# keepaliveTimer is started by the connect handler after a successful Videohub or Lightware connection

# --- Form Close: clean up Videohub TCP connection -----------------------------

$form.Add_FormClosing({
    $keepaliveTimer.Stop()
    $keepaliveTimer.Dispose()
    if ($global:videohubTcp -ne $null) {
        try { $global:videohubWriter.Dispose() } catch { }
        try { $global:videohubReader.Dispose() } catch { }
        try { $global:videohubTcp.Close() } catch { }
        $global:videohubTcp    = $null
        $global:videohubWriter = $null
        $global:videohubReader = $null
    }
    if ($global:lightwareTcp -ne $null) {
        try { $global:lightwareWriter.Dispose() } catch { }
        try { $global:lightwareReader.Dispose() } catch { }
        try { $global:lightwareTcp.Close() } catch { }
        $global:lightwareTcp    = $null
        $global:lightwareWriter = $null
        $global:lightwareReader = $null
    }
})

# --- Form Resize Handler ------------------------------------------------------

$form.Add_Resize({
    Update-SidebarLayout
    $searchX = [Math]::Max($filterRail.Width - 182, 0)
    $searchBox.Location = New-Object System.Drawing.Point($searchX, 9)
    $lblStatusRight.Location = New-Object System.Drawing.Point(($statusBar.Width - 300), 8)
    $lblStatusRight.Size = New-Object System.Drawing.Size(285, 16)
    $progressBar.Width = $statusBar.Width
})

# --- Form Load ----------------------------------------------------------------

$form.Add_Load({
    Update-SidebarLayout
    $searchBox.Location = New-Object System.Drawing.Point(($filterRail.Width - 182), 9)
    $progressBar.Width  = $statusBar.Width
    $lblStatusRight.Location = New-Object System.Drawing.Point(($statusBar.Width - 300), 8)
    $lblStatusRight.Size = New-Object System.Drawing.Size(285, 16)
})

# --- Initialize ---------------------------------------------------------------

Create-DefaultLabels
Populate-Grid

$form.ResumeLayout($false)
$form.PerformLayout()

# --- Show Form ---------------------------------------------------------------

try {
    $form.ShowDialog() | Out-Null
} catch {
    Write-ErrorLog "FORM" "Form crashed: $($_.Exception.GetType().Name): $($_.Exception.Message)`n  Stack: $($_.Exception.StackTrace)"
    Write-Host ""
    Write-Host "=== FORM CRASH ===" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.GetType().Name): $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Stack: $($_.Exception.StackTrace)" -ForegroundColor Yellow
} finally {
    Write-ErrorLog "APP" "Application closed" "INFO"
}

# Show any errors that occurred and pause so the window stays open
if ($Error.Count -gt 0) {
    Write-Host ""
    Write-Host "=== $($Error.Count) error(s) occurred ===" -ForegroundColor Red
    foreach ($err in $Error) {
        Write-Host "  - $($err.Exception.Message)" -ForegroundColor Yellow
        if ($err.InvocationInfo) {
            Write-Host "    at line $($err.InvocationInfo.ScriptLineNumber): $($err.InvocationInfo.Line.Trim())" -ForegroundColor DarkGray
        }
    }
    Write-Host ""
    Write-Host "Error log saved to: $($global:errorLogPath)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Press any key to exit..." -ForegroundColor White
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
} else {
    Write-ErrorLog "APP" "Clean exit with no errors" "INFO"
}
