<#
    Exercises Test-KumoPortPresent from Helix-Label-Manager.ps1 without launching
    the WinForms GUI: the function is extracted from the script text and defined
    in this session.

    Background: some KUMO firmware answers XPT parameter reads for ports the
    chassis does not have. Detection used to treat any reply as proof the port
    existed, so a 3232 reporting a value for Source33 was sized as a 6464.

    Exit code 0 = all cases pass.
#>
[CmdletBinding()]
param(
    [string]$ScriptPath
)

$ErrorActionPreference = "Stop"

# $PSScriptRoot is not reliably populated inside a param default under Windows
# PowerShell 5.1, so the fallback is resolved here in the script body instead.
if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
    $root = Split-Path -Parent $MyInvocation.MyCommand.Path
    $ScriptPath = Join-Path $root "..\..\Helix-Label-Manager.ps1"
}

$resolved = (Resolve-Path $ScriptPath).Path
$src = Get-Content $resolved -Raw
$match = [regex]::Match($src, '(?ms)^function Test-KumoPortPresent \{.*?^\}')
if (-not $match.Success) {
    Write-Host "FAIL: Test-KumoPortPresent not found in $resolved"
    exit 1
}
Invoke-Expression $match.Value

# p = reply for the port under test, c = reply for the port-100 canary,
# e = whether the port should be treated as present.
$cases = @(
    @{ n="firmware refuses phantom ports / 6464 Source33 has a label"; p="CAM A";          c=$null;             pre="Source";      port=33; e=$true  }
    @{ n="firmware refuses phantom ports / 3232 Source33 no reply";    p=$null;            c=$null;             pre="Source";      port=33; e=$false }
    @{ n="fixed-filler firmware / 3232 Source33 returns the filler";   p="---";            c="---";             pre="Source";      port=33; e=$false }
    @{ n="fixed-filler firmware / 6464 Source33 has a real label";     p="CAM A";          c="---";             pre="Source";      port=33; e=$true  }
    @{ n="auto-naming firmware / 3232 Source33 is auto-named";         p="Source 33";      c="Source 100";      pre="Source";      port=33; e=$false }
    @{ n="auto-naming firmware / 6464 Source33 has a user label";      p="CAM A";          c="Source 100";      pre="Source";      port=33; e=$true  }
    @{ n="auto-naming firmware / destination side phantom";            p="Destination 33"; c="Destination 100"; pre="Destination"; port=33; e=$false }
    @{ n="a reply carrying no value is not proof of existence";        p="";               c=$null;             pre="Source";      port=33; e=$false }
    @{ n="an empty canary counts as the router refusing";              p="CAM A";          c="";                pre="Source";      port=33; e=$true  }
    @{ n="auto-name match tolerates zero padding";                     p="Source 033";     c="Source 100";      pre="Source";      port=33; e=$false }
    @{ n="a real label that merely contains the prefix word";          p="Source Feed A";  c="Source 100";      pre="Source";      port=33; e=$true  }
    @{ n="1604 has no Destination5";                                   p=$null;            c=$null;             pre="Destination"; port=5;  e=$false }
    @{ n="3232 Source17 is present";                                   p="IN 17";          c=$null;             pre="Source";      port=17; e=$true  }
    @{ n="1616 Source17 is an auto-named phantom";                     p="Source 17";      c="Source 100";      pre="Source";      port=17; e=$false }
)

$pass = 0
$fail = 0
foreach ($c in $cases) {
    $got = Test-KumoPortPresent -ProbeValue $c.p -PhantomValue $c.c -Prefix $c.pre -PortNumber $c.port
    if ($got -eq $c.e) {
        $pass++
        Write-Host "  PASS  $($c.n)"
    } else {
        $fail++
        Write-Host "  FAIL  $($c.n)  expected=$($c.e) got=$got"
    }
}

Write-Host ""
Write-Host "Test-KumoPortPresent: $pass passed, $fail failed"
if ($fail -gt 0) { exit 1 }
exit 0
