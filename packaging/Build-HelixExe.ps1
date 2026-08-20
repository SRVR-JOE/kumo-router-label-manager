<#
    Builds Helix.exe: a single standalone launcher with Helix-Label-Manager.ps1
    embedded as a resource.

    Uses the Roslyn compiler shipped with VS2022 Build Tools. The .NET Framework
    csc under C:\Windows\Microsoft.NET is C# 5 only and rejects this source.

    -OutputPath places the finished exe wherever you want it; the default keeps
    it in dist\ next to the repo.
#>
[CmdletBinding()]
param(
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$packaging = Join-Path $repoRoot "packaging"

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repoRoot "dist\Helix.exe"
}

$script = Join-Path $repoRoot "Helix-Label-Manager.ps1"
if (-not (Test-Path $script)) { throw "Cannot find $script" }

# Refuse to embed a script that Windows PowerShell 5.1 cannot parse. Without a
# UTF-8 BOM, 5.1 decodes non-ASCII as ANSI and U+2713 becomes a quote character.
$parseErrors = $null
$tokens = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    throw "$script has $($parseErrors.Count) parse error(s) under PowerShell $($PSVersionTable.PSVersion); refusing to build. First at line $($parseErrors[0].Extent.StartLineNumber)."
}

$csc = Get-ChildItem "C:\Program Files (x86)\Microsoft Visual Studio\2022\*\MSBuild\Current\Bin\Roslyn\csc.exe",
                     "C:\Program Files\Microsoft Visual Studio\2022\*\MSBuild\Current\Bin\Roslyn\csc.exe" `
                     -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $csc) { throw "Roslyn csc.exe not found. Install VS2022 Build Tools." }

$outDir = Split-Path -Parent $OutputPath
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

Write-Host "Compiler: $($csc.FullName)"
Write-Host "Embedding: $script"
Write-Host "Output:    $OutputPath"

$args = @(
    "/nologo"
    "/target:winexe"
    "/platform:anycpu"
    "/optimize+"
    "/langversion:5"
    "/out:$OutputPath"
    "/reference:System.dll"
    "/reference:System.Windows.Forms.dll"
    "/resource:$script,Helix-Label-Manager.ps1"
    (Join-Path $packaging "HelixLauncher.cs")
    (Join-Path $packaging "AssemblyInfo.cs")
)

& $csc.FullName @args
if ($LASTEXITCODE -ne 0) { throw "csc failed with exit code $LASTEXITCODE" }

$built = Get-Item $OutputPath
Write-Host ""
Write-Host "Built $($built.Name) - $([math]::Round($built.Length/1KB,1)) KB" -ForegroundColor Green
$built.VersionInfo | Format-List ProductName, FileDescription, CompanyName, FileVersion
