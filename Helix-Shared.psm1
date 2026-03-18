# KUMO-Shared.psm1 - Shared functions for KUMO Router Label Manager tools
# Version: 5.5.0

function Get-ButtonSettingsIndex {
    param([int]$Port, [string]$PortType)
    # KUMO interleaves sources and destinations in blocks of 16:
    #   Src 1-16 -> 1-16,  Dst 1-16 -> 17-32,
    #   Src 17-32 -> 33-48, Dst 17-32 -> 49-64, etc.
    $block = [math]::Floor(($Port - 1) / 16)   # 0, 1, 2, 3
    $offset = ($Port - 1) % 16                   # 0..15
    $idx = $block * 32 + $offset + 1
    if ($PortType.ToUpper() -eq "OUTPUT") { $idx += 16 }
    return $idx
}

Export-ModuleMember -Function Get-ButtonSettingsIndex
