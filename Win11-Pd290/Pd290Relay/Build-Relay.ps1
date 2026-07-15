[CmdletBinding()]
param(
    [switch] $SkipProbe
)

$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot 'Pd290Relay.cs'
$output = Join-Path $PSScriptRoot 'Pd290Relay.exe'
$compilerCandidates = @(
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
)
$compiler = $compilerCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1
if (-not $compiler) {
    throw 'The .NET Framework C# compiler (csc.exe) was not found.'
}
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw "Source file not found: $source"
}

Write-Host "Building x64 relay with $compiler"
& $compiler /nologo /target:exe /platform:x64 /optimize+ "/out:$output" `
    /reference:System.ServiceProcess.dll $source
if ($LASTEXITCODE -ne 0) {
    throw "C# compiler failed with exit code $LASTEXITCODE"
}

if (-not $SkipProbe) {
    Write-Host 'Probing the PL2305 WinUSB interface...'
    & $output --probe
    if ($LASTEXITCODE -ne 0) {
        throw "Relay probe failed with exit code $LASTEXITCODE"
    }
}

Get-Item -LiteralPath $output | Format-List FullName, Length, LastWriteTime
